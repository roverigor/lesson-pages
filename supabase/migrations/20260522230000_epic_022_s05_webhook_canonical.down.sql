-- ============================================================
-- Story 22.5 — Webhook Canonical ROLLBACK (EPIC-022 S.022.5)
-- ============================================================
-- Migration up: 20260522230000_epic_022_s05_webhook_canonical.sql
-- ADR: docs/architecture/ADR-023-webhook-purchase-precedence.md
--
-- DECISÃO ROLLBACK:
--   - DROP TRIGGER + DROP COLUMN purchase_dedup_key
--   - DROP CHECK constraint + DROP INDEX source + DROP COLUMN source
--   - DROP FUNCTION extract_purchase_dedup_key + trigger_set_purchase_dedup_key
--   - PRESERVA payload JSONB (nunca tocado)
--   - Audit log mantém append-only
-- ============================================================
-- Autor: @dev (Dex via aiox-master) — 2026-05-22
-- ============================================================


-- ============================================================
-- AUDIT TRAIL — registrar rollback
-- ============================================================

DO $audit_rb$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'webhook_canonical_rollback',
        jsonb_build_object(
          'story_id', '22.5',
          'migration', '20260522230000_epic_022_s05_webhook_canonical.down',
          'started_at', now()
        )
      )
    $insert$;
  END IF;
END
$audit_rb$;


-- ============================================================
-- DROP UNIQUE constraint (se foi aplicada via migration follow-up)
-- ============================================================
BEGIN;
ALTER TABLE public.ac_purchase_events
  DROP CONSTRAINT IF EXISTS ac_purchase_events_dedup_unique;
COMMIT;


-- ============================================================
-- DROP trigger
-- ============================================================
DROP TRIGGER IF EXISTS trg_ac_purchase_events_dedup_key ON public.ac_purchase_events;


-- ============================================================
-- DROP column purchase_dedup_key
-- ============================================================
BEGIN;
ALTER TABLE public.ac_purchase_events
  DROP COLUMN IF EXISTS purchase_dedup_key;
COMMIT;


-- ============================================================
-- DROP source column + constraints + index
-- ============================================================
BEGIN;
DROP INDEX IF EXISTS public.idx_ac_purchase_events_source;
ALTER TABLE public.ac_purchase_events
  DROP CONSTRAINT IF EXISTS chk_ac_purchase_source;
ALTER TABLE public.ac_purchase_events
  DROP COLUMN IF EXISTS source;
COMMIT;


-- ============================================================
-- DROP functions
-- ============================================================
DROP FUNCTION IF EXISTS public.trigger_set_purchase_dedup_key();
DROP FUNCTION IF EXISTS public.extract_purchase_dedup_key(text, jsonb);


-- ============================================================
-- AUDIT TRAIL — final
-- ============================================================

DO $audit_rb_final$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'webhook_canonical_rollback',
        jsonb_build_object(
          'story_id', '22.5',
          'migration', '20260522230000_epic_022_s05_webhook_canonical.down',
          'completed_at', now(),
          'status', 'rollback_complete',
          'note', 'source + purchase_dedup_key columns + trigger + functions removidos. payload JSONB preservado.'
        )
      )
    $insert$;
  END IF;
END
$audit_rb_final$;
