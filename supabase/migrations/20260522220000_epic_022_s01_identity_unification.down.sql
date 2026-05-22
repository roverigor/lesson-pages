-- ============================================================
-- Story 22.1 — Identity Unification ROLLBACK (EPIC-022 S.022.1)
-- ============================================================
-- Migration up: 20260522220000_epic_022_s01_identity_unification.sql
-- ADR: docs/architecture/ADR-021-student-identity-unification.md
--
-- DECISÃO ROLLBACK:
--   - DROP VIEW + DROP TRIGGER + DROP COLUMN normalized_phone
--   - PRESERVA coluna `phone` original (out-of-scope drop legacy)
--   - PRESERVA dados row-level (sem DELETE)
--   - Audit log mantém append-only (não desfaz inserts)
--   - is_dashboard_admin não tocada (load-bearing pra outras migrations)
-- ============================================================
-- Autor: @dev (Dex) — 2026-05-22
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
        'identity_unification_rollback',
        jsonb_build_object(
          'story_id', '22.1',
          'migration', '20260522220000_epic_022_s01_identity_unification.down',
          'started_at', now()
        )
      )
    $insert$;
  END IF;
END
$audit_rb$;


-- ============================================================
-- DROP VIEW v_students_unified
-- ============================================================

DROP VIEW IF EXISTS public.v_students_unified;


-- ============================================================
-- DROP triggers
-- ============================================================

DROP TRIGGER IF EXISTS trg_wa_group_members_normalize_phone ON public.wa_group_members;
DROP TRIGGER IF EXISTS trg_student_imports_normalize_phone  ON public.student_imports;
DROP TRIGGER IF EXISTS trg_students_normalize_phone         ON public.students;


-- ============================================================
-- DROP indexes
-- ============================================================

DROP INDEX IF EXISTS public.idx_wa_group_members_normalized_phone;
DROP INDEX IF EXISTS public.idx_student_imports_normalized_phone;
DROP INDEX IF EXISTS public.idx_students_normalized_phone;


-- ============================================================
-- DROP columns
-- ============================================================
-- PRESERVA coluna `phone` original (não dropa).
-- Só dropa coluna nova `normalized_phone`.
-- ============================================================

BEGIN;
ALTER TABLE public.wa_group_members  DROP COLUMN IF EXISTS normalized_phone;
ALTER TABLE public.student_imports   DROP COLUMN IF EXISTS normalized_phone;
ALTER TABLE public.students          DROP COLUMN IF EXISTS normalized_phone;
COMMIT;


-- ============================================================
-- DROP functions
-- ============================================================

DROP FUNCTION IF EXISTS public.backfill_normalized_phones();
DROP FUNCTION IF EXISTS public.trigger_normalize_phone();
DROP FUNCTION IF EXISTS public.normalize_phone_e164(text);


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
        'identity_unification_rollback',
        jsonb_build_object(
          'story_id', '22.1',
          'migration', '20260522220000_epic_022_s01_identity_unification.down',
          'completed_at', now(),
          'status', 'rollback_complete',
          'note', 'VIEW + triggers + indexes + columns + functions removidos. Coluna phone original preservada.'
        )
      )
    $insert$;
  END IF;
END
$audit_rb_final$;
