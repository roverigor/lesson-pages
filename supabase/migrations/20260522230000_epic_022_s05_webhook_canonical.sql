-- ============================================================
-- Story 22.5 — Webhook Purchase Canonical (EPIC-022 S.022.5)
-- ============================================================
-- ESCOPO:
--   - ADD COLUMN source enum ('ac'|'hotmart'|'generic') em ac_purchase_events
--   - ADD COLUMN purchase_dedup_key (derivada por source)
--   - Trigger BEFORE INSERT extrai dedup_key conforme source
--   - UNIQUE constraint (source, purchase_dedup_key) — intra-source dedup
-- ROLLBACK: ver .down.sql pareada
-- ADR: docs/architecture/ADR-023-webhook-purchase-precedence.md
-- GATE PROD: NON-NEGOTIABLE — autorização literal user antes apply
-- ============================================================
-- Autor: @dev (Dex via aiox-master) — 2026-05-22
-- Pattern reference: 20260522155830_epic_022_s04_rls_hardening.sql
-- Deps: 22.4 RLS Hardening (ac_purchase_events é exceção RLS — sem POLICY)
-- PG version: 15
-- Idempotência: ADD COLUMN IF NOT EXISTS + DROP TRIGGER IF EXISTS
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
        'webhook_canonical',
        jsonb_build_object(
          'story_id', '22.5',
          'epic_id', 'EPIC-022',
          'migration', '20260522230000_epic_022_s05_webhook_canonical',
          'started_at', now(),
          'tables_affected', jsonb_build_array('ac_purchase_events')
        )
      )
    $insert$;
  END IF;
END
$audit$;


-- ============================================================
-- T2 — ADD COLUMN source + CHECK constraint
-- ============================================================

BEGIN;
ALTER TABLE public.ac_purchase_events
  ADD COLUMN IF NOT EXISTS source text DEFAULT 'ac';

-- Backfill rows existentes (assume default 'ac' — origem mais comum legacy)
UPDATE public.ac_purchase_events
   SET source = 'ac'
 WHERE source IS NULL;

ALTER TABLE public.ac_purchase_events
  ALTER COLUMN source SET NOT NULL;

-- Drop constraint se já existe (idempotência rerun)
ALTER TABLE public.ac_purchase_events
  DROP CONSTRAINT IF EXISTS chk_ac_purchase_source;

ALTER TABLE public.ac_purchase_events
  ADD CONSTRAINT chk_ac_purchase_source
  CHECK (source IN ('ac','hotmart','generic'));

CREATE INDEX IF NOT EXISTS idx_ac_purchase_events_source
  ON public.ac_purchase_events (source);
COMMIT;


-- ============================================================
-- T3 — ADD COLUMN purchase_dedup_key (derivada por source)
-- ============================================================

BEGIN;
ALTER TABLE public.ac_purchase_events
  ADD COLUMN IF NOT EXISTS purchase_dedup_key text;
COMMIT;


-- ============================================================
-- T4 — Function extract_purchase_dedup_key
-- ============================================================
-- IMMUTABLE: extrai dedup key normalizado conforme source.
-- AC:      payload->>'contact'->>'email' || '|' || payload->>'product_id' || '|' || payload->>'date'
-- Hotmart: payload->>'buyer'->>'email' || '|' || payload->>'product'->>'id' || '|' || payload->>'purchase'->>'order_date'
-- Generic: payload->>'email' || '|' || payload->>'product_id' || '|' || payload->>'purchase_date'
--
-- Returns NULL se payload não contém keys esperadas (caller decide tratar).
-- ============================================================

CREATE OR REPLACE FUNCTION public.extract_purchase_dedup_key(
  p_source  text,
  p_payload jsonb
)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_email text;
  v_product_id text;
  v_purchase_date text;
BEGIN
  IF p_payload IS NULL THEN
    RETURN NULL;
  END IF;

  CASE p_source
    WHEN 'ac' THEN
      v_email         := lower(trim(p_payload #>> '{contact,email}'));
      v_product_id    := p_payload ->> 'product_id';
      v_purchase_date := p_payload ->> 'date';
    WHEN 'hotmart' THEN
      v_email         := lower(trim(p_payload #>> '{buyer,email}'));
      v_product_id    := p_payload #>> '{product,id}';
      v_purchase_date := p_payload #>> '{purchase,order_date}';
    WHEN 'generic' THEN
      v_email         := lower(trim(p_payload ->> 'email'));
      v_product_id    := p_payload ->> 'product_id';
      v_purchase_date := p_payload ->> 'purchase_date';
    ELSE
      RETURN NULL;
  END CASE;

  -- Se qualquer componente NULL → não pode dedup
  IF v_email IS NULL OR v_email = ''
     OR v_product_id IS NULL OR v_product_id = ''
     OR v_purchase_date IS NULL OR v_purchase_date = '' THEN
    RETURN NULL;
  END IF;

  -- Normalize date: keep only YYYY-MM-DD (strip time se houver)
  v_purchase_date := substring(v_purchase_date from 1 for 10);

  RETURN v_email || '|' || v_product_id || '|' || v_purchase_date;
END;
$$;

GRANT EXECUTE ON FUNCTION public.extract_purchase_dedup_key(text, jsonb) TO authenticated, anon, service_role;

COMMENT ON FUNCTION public.extract_purchase_dedup_key(text, jsonb) IS
  'Extrai chave dedup (email|product_id|purchase_date) do payload conforme source AC/Hotmart/Generic. NULL se incompleto. IMMUTABLE. Ref: ADR-023.';


-- ============================================================
-- T5 — Trigger BEFORE INSERT/UPDATE pra popular dedup_key
-- ============================================================

CREATE OR REPLACE FUNCTION public.trigger_set_purchase_dedup_key()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.purchase_dedup_key := public.extract_purchase_dedup_key(NEW.source, NEW.payload);
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ac_purchase_events_dedup_key ON public.ac_purchase_events;
CREATE TRIGGER trg_ac_purchase_events_dedup_key
  BEFORE INSERT OR UPDATE OF source, payload
  ON public.ac_purchase_events
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_set_purchase_dedup_key();


-- ============================================================
-- T6 — Backfill dedup_key em rows existentes
-- ============================================================

DO $backfill$
DECLARE
  v_updated bigint;
BEGIN
  UPDATE public.ac_purchase_events
     SET purchase_dedup_key = public.extract_purchase_dedup_key(source, payload)
   WHERE purchase_dedup_key IS NULL;
  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RAISE NOTICE 'Backfilled purchase_dedup_key in % rows', v_updated;
END
$backfill$;


-- ============================================================
-- T7 — Detectar duplicates pre-UNIQUE (gate)
-- ============================================================
-- Se duplicates > 0 → POLICY/process manual ANTES de adicionar UNIQUE.
-- Aqui só logamos warning. Migration follow-up adiciona UNIQUE quando
-- duplicates resolvidos.
-- ============================================================

DO $duplicates$
DECLARE
  v_dup_count bigint;
BEGIN
  SELECT count(*) INTO v_dup_count
    FROM (
      SELECT source, purchase_dedup_key, count(*) c
        FROM public.ac_purchase_events
       WHERE purchase_dedup_key IS NOT NULL
       GROUP BY 1, 2
      HAVING count(*) > 1
    ) dups;

  IF v_dup_count > 0 THEN
    RAISE WARNING 'Found % duplicate (source, purchase_dedup_key) tuples — UNIQUE constraint deferred. Resolve manually via merge', v_dup_count;
    -- Audit
    INSERT INTO public.audit_log (event_type, payload)
    VALUES (
      'webhook_canonical_duplicates_detected',
      jsonb_build_object(
        'story_id', '22.5',
        'duplicate_groups', v_dup_count,
        'action_required', 'manual_merge_before_unique_constraint'
      )
    );
  ELSE
    RAISE NOTICE 'No duplicates detected — UNIQUE constraint safe to apply';
  END IF;
END
$duplicates$;


-- ============================================================
-- T8 — UNIQUE constraint (DEFERRED — bloco comentado)
-- ============================================================
-- PRE-APPLY GATE: T7 deve reportar 0 duplicates.
-- Se houver duplicates, resolver via manual merge + re-run T7 = 0,
-- THEN descomentar este bloco em migration follow-up separada.
--
-- Migration follow-up sugerida:
-- supabase/migrations/{ts}_epic_022_s05_webhook_dedup_unique.sql
--
-- BEGIN;
-- ALTER TABLE public.ac_purchase_events
--   ADD CONSTRAINT IF NOT EXISTS ac_purchase_events_dedup_unique
--   UNIQUE (source, purchase_dedup_key);
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
        'webhook_canonical',
        jsonb_build_object(
          'story_id', '22.5',
          'migration', '20260522230000_epic_022_s05_webhook_canonical',
          'completed_at', now(),
          'status', 'source_column_dedup_key_trigger_applied',
          'unique_constraint_pending', true,
          'note', 'UNIQUE constraint bloco comentado — aguarda gate duplicates=0 + migration follow-up'
        )
      )
    $insert$;
  END IF;
END
$audit_final$;
