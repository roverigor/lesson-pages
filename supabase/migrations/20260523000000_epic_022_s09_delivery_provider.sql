-- ============================================================
-- Story 22.9 — Delivery Routing Provider Column (EPIC-022 S.022.9)
-- ============================================================
-- ESCOPO (2-step migration):
--   STEP 1 (esta migration):
--     - ADD COLUMN provider text DEFAULT 'evolution' em notifications
--     - ADD COLUMN meta_message_id text em notifications (gap atual)
--     - CHECK constraint provider IN ('evolution','meta')
--     - Backfill heurística (evolution_message_ids populated → 'evolution')
--     - Slack ambíguo warning se backfill encontrar rows sem identificador
--   STEP 2 (migration follow-up): NOT NULL apply após validação manual
-- ROLLBACK: ver .down.sql pareada
-- ADR: docs/architecture/ADR-027-delivery-routing-provider.md
-- GATE PROD: NON-NEGOTIABLE — autorização literal user antes apply
-- ============================================================
-- Autor: @dev (Dex via aiox-master) — 2026-05-22
-- Pattern reference: 20260522230000_epic_022_s05_webhook_canonical.sql
-- Deps: 22.4 RLS Hardening (notifications é Tier 2 — admin read + service write)
-- PG version: 15
-- Idempotência: ADD COLUMN IF NOT EXISTS + DROP CONSTRAINT IF EXISTS
-- ============================================================


-- ============================================================
-- AUDIT TRAIL — INSERT inicial
-- ============================================================

DO $audit$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'delivery_provider_routing',
        jsonb_build_object(
          'story_id', '22.9',
          'epic_id', 'EPIC-022',
          'migration', '20260523000000_epic_022_s09_delivery_provider',
          'started_at', now(),
          'step', 1,
          'tables_affected', jsonb_build_array('notifications')
        )
      )
    $insert$;
  END IF;
END
$audit$;


-- ============================================================
-- T2 — ADD COLUMN provider (STEP 1 — com DEFAULT, sem NOT NULL ainda)
-- ============================================================

BEGIN;
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS provider text DEFAULT 'evolution';

-- CHECK constraint (drop + recreate pra idempotência)
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS chk_notifications_provider;

ALTER TABLE public.notifications
  ADD CONSTRAINT chk_notifications_provider
  CHECK (provider IN ('evolution','meta'));

-- Index pra dispatch-retry router lookup
CREATE INDEX IF NOT EXISTS idx_notifications_provider
  ON public.notifications (provider);
COMMIT;


-- ============================================================
-- T3 — ADD COLUMN meta_message_id (gap atual — pareia evolution_message_ids)
-- ============================================================
-- notifications já tem evolution_message_ids TEXT[] (since 20260402200000).
-- Adiciona meta_message_id text (single — Meta retorna 1 ID por send).
-- Sparse UNIQUE index pra correlação webhook delivery.
-- ============================================================

BEGIN;
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS meta_message_id text;

-- Sparse UNIQUE em meta_message_id (correlação webhook delivery)
CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_meta_message
  ON public.notifications (meta_message_id)
  WHERE meta_message_id IS NOT NULL;

COMMENT ON COLUMN public.notifications.meta_message_id IS
  'wamid retornado por Meta Cloud API. Pareia evolution_message_ids legacy. Ref: ADR-027.';
COMMIT;


-- ============================================================
-- T4 — RPC backfill_notifications_provider (heurística)
-- ============================================================
-- Heurística:
--   1. evolution_message_ids NOT NULL e não-vazio → provider='evolution'
--   2. meta_message_id NOT NULL → provider='meta'
--   3. Senão → ambíguo → DEFAULT 'evolution' + Slack alert + audit log
--
-- SECURITY DEFINER + service_role only (bypassa RLS Tier 2)
-- Idempotente (UPDATE WHERE condições — segundo run retorna 0)
-- ============================================================

CREATE OR REPLACE FUNCTION public.backfill_notifications_provider()
RETURNS TABLE(category text, rows_updated bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_evolution   bigint := 0;
  v_meta        bigint := 0;
  v_ambiguous   bigint := 0;
  v_sample      jsonb;
BEGIN
  -- Evolution: array populated
  UPDATE public.notifications
     SET provider = 'evolution'
   WHERE provider IS NULL
     AND evolution_message_ids IS NOT NULL
     AND array_length(evolution_message_ids, 1) > 0;
  GET DIAGNOSTICS v_evolution = ROW_COUNT;

  -- Meta: meta_message_id populated
  UPDATE public.notifications
     SET provider = 'meta'
   WHERE provider IS NULL
     AND meta_message_id IS NOT NULL;
  GET DIAGNOSTICS v_meta = ROW_COUNT;

  -- Ambíguo: ainda NULL após Evolution/Meta backfill
  SELECT count(*) INTO v_ambiguous
    FROM public.notifications
   WHERE provider IS NULL;

  IF v_ambiguous > 0 THEN
    -- Coletar sample de até 5 rows pra Slack
    SELECT jsonb_agg(jsonb_build_object('id', id, 'type', type, 'status', status, 'created_at', created_at))
      INTO v_sample
      FROM (SELECT id, type, status, created_at FROM public.notifications
             WHERE provider IS NULL LIMIT 5) s;

    -- Audit alert
    INSERT INTO public.audit_log (event_type, payload)
    VALUES (
      'notifications_provider_backfill_ambiguous',
      jsonb_build_object(
        'story_id', '22.9',
        'ambiguous_count', v_ambiguous,
        'sample', v_sample,
        'action', 'default_evolution_applied',
        'requires_review', true
      )
    );

    -- Default fallback (evolution mais comum legacy)
    UPDATE public.notifications
       SET provider = 'evolution'
     WHERE provider IS NULL;
  END IF;

  RETURN QUERY VALUES
    ('evolution',  v_evolution),
    ('meta',       v_meta),
    ('ambiguous_defaulted_evolution', v_ambiguous);
END;
$$;

GRANT EXECUTE ON FUNCTION public.backfill_notifications_provider() TO service_role;
REVOKE EXECUTE ON FUNCTION public.backfill_notifications_provider() FROM authenticated, anon;

COMMENT ON FUNCTION public.backfill_notifications_provider() IS
  'Backfill provider column via heurística (evolution_message_ids, meta_message_id, fallback evolution). Idempotente. service_role only. Ref: ADR-027.';


-- ============================================================
-- T5 — Executar backfill (parte da migration)
-- ============================================================

DO $backfill$
DECLARE
  rec record;
BEGIN
  FOR rec IN SELECT * FROM public.backfill_notifications_provider() LOOP
    RAISE NOTICE 'Backfill % rows: %', rec.category, rec.rows_updated;
  END LOOP;
END
$backfill$;


-- ============================================================
-- T6 — Validation gate (zero NULL após backfill)
-- ============================================================

DO $validate$
DECLARE
  v_null_count bigint;
BEGIN
  SELECT count(*) INTO v_null_count
    FROM public.notifications
   WHERE provider IS NULL;

  IF v_null_count > 0 THEN
    RAISE EXCEPTION 'Backfill failed: % rows still NULL provider. Investigate before STEP 2 NOT NULL apply', v_null_count;
  ELSE
    RAISE NOTICE 'Backfill validation OK — 0 NULL provider rows';
  END IF;
END
$validate$;


-- ============================================================
-- T7 — NOT NULL constraint (STEP 2 — bloco comentado)
-- ============================================================
-- PRE-APPLY GATE: T6 validation = 0 NULL rows.
-- Step 2 fica em migration follow-up separada pra permitir
-- review humano dos rows ambíguos pré NOT NULL.
--
-- Migration follow-up: 20260524000000_epic_022_s09_provider_not_null.sql
--
-- BEGIN;
-- ALTER TABLE public.notifications
--   ALTER COLUMN provider SET NOT NULL;
-- COMMIT;


-- ============================================================
-- AUDIT TRAIL — final
-- ============================================================

DO $audit_final$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'delivery_provider_routing',
        jsonb_build_object(
          'story_id', '22.9',
          'migration', '20260523000000_epic_022_s09_delivery_provider',
          'completed_at', now(),
          'step', 1,
          'status', 'provider_column_meta_message_id_backfill_applied',
          'not_null_pending', true,
          'note', 'STEP 2 (NOT NULL constraint) em migration follow-up após review ambíguos'
        )
      )
    $insert$;
  END IF;
END
$audit_final$;
