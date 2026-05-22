-- ============================================================
-- Story 22.2 — Dispatch Unification ROLLBACK (EPIC-022 S.022.2)
-- ============================================================
-- Migration up: 20260523010000_epic_022_s02_dispatch_unification.sql
-- ADR: docs/architecture/ADR-022-dispatch-unification.md
--
-- DECISÃO ROLLBACK:
--   - DROP dispatch_type column + index + constraint em dispatch_history
--   - DROP RPC set_nps_dispatch_engine + get_nps_dispatch_engine
--   - DELETE app_config row nps_dispatch_engine
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
        'dispatch_unification_rollback',
        jsonb_build_object(
          'story_id', '22.2',
          'migration', '20260523010000_epic_022_s02_dispatch_unification.down',
          'started_at', now()
        )
      )
    $insert$;
  END IF;
END
$audit_rb$;


-- ============================================================
-- DROP dispatch_type column + index + constraint
-- ============================================================
BEGIN;
DROP INDEX IF EXISTS public.idx_dispatch_history_type;
ALTER TABLE public.dispatch_history
  DROP CONSTRAINT IF EXISTS chk_dispatch_history_type;
ALTER TABLE public.dispatch_history
  DROP COLUMN IF EXISTS dispatch_type;
COMMIT;


-- ============================================================
-- DROP RPCs
-- ============================================================
DROP FUNCTION IF EXISTS public.set_nps_dispatch_engine(text);
DROP FUNCTION IF EXISTS public.get_nps_dispatch_engine();


-- ============================================================
-- DELETE feature flag row
-- ============================================================
DELETE FROM public.app_config WHERE key = 'nps_dispatch_engine';


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
        'dispatch_unification_rollback',
        jsonb_build_object(
          'story_id', '22.2',
          'migration', '20260523010000_epic_022_s02_dispatch_unification.down',
          'completed_at', now(),
          'status', 'rollback_complete',
          'note', 'flag + RPCs + dispatch_type column removidos. dispatch_history rows preservados.'
        )
      )
    $insert$;
  END IF;
END
$audit_rb_final$;
