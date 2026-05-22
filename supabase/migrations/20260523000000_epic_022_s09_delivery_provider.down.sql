-- ============================================================
-- Story 22.9 — Delivery Provider ROLLBACK (EPIC-022 S.022.9)
-- ============================================================
-- Migration up: 20260523000000_epic_022_s09_delivery_provider.sql
-- ADR: docs/architecture/ADR-027-delivery-routing-provider.md
--
-- DECISÃO ROLLBACK:
--   - DROP NOT NULL (se foi aplicado via STEP 2)
--   - DROP INDEX provider + meta_message_id
--   - DROP CONSTRAINT chk_notifications_provider
--   - DROP COLUMN provider + meta_message_id
--   - DROP FUNCTION backfill_notifications_provider
--   - PRESERVA evolution_message_ids (introduzida em 20260402200000)
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
        'delivery_provider_routing_rollback',
        jsonb_build_object(
          'story_id', '22.9',
          'migration', '20260523000000_epic_022_s09_delivery_provider.down',
          'started_at', now()
        )
      )
    $insert$;
  END IF;
END
$audit_rb$;


-- ============================================================
-- DROP NOT NULL constraint (se foi aplicado)
-- ============================================================
BEGIN;
ALTER TABLE public.notifications
  ALTER COLUMN provider DROP NOT NULL;
COMMIT;


-- ============================================================
-- DROP indexes
-- ============================================================
DROP INDEX IF EXISTS public.idx_notifications_provider;
DROP INDEX IF EXISTS public.idx_notifications_meta_message;


-- ============================================================
-- DROP constraints + columns
-- ============================================================
BEGIN;
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS chk_notifications_provider;

ALTER TABLE public.notifications
  DROP COLUMN IF EXISTS provider;

ALTER TABLE public.notifications
  DROP COLUMN IF EXISTS meta_message_id;
COMMIT;


-- ============================================================
-- DROP function backfill
-- ============================================================
DROP FUNCTION IF EXISTS public.backfill_notifications_provider();


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
        'delivery_provider_routing_rollback',
        jsonb_build_object(
          'story_id', '22.9',
          'migration', '20260523000000_epic_022_s09_delivery_provider.down',
          'completed_at', now(),
          'status', 'rollback_complete',
          'note', 'provider + meta_message_id columns + index + constraint + function removidos. evolution_message_ids preservado.'
        )
      )
    $insert$;
  END IF;
END
$audit_rb_final$;
