-- ═══════════════════════════════════════
-- Fix merge_duplicate_student: clear phone on soft-deleted record
-- Prevents unique constraint (phone, cohort_id) violation after merge
-- ═══════════════════════════════════════

CREATE OR REPLACE FUNCTION public.merge_duplicate_student(
  p_keep_id   UUID,
  p_delete_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Reassign zoom_participants
  UPDATE public.zoom_participants zp
  SET student_id = p_keep_id
  WHERE zp.student_id = p_delete_id;

  -- Remove student_attendance rows that would conflict with keeper
  DELETE FROM public.student_attendance
  WHERE student_id = p_delete_id
    AND (class_date, COALESCE(zoom_meeting_id::TEXT, ''))
      IN (
        SELECT sa_keep.class_date, COALESCE(sa_keep.zoom_meeting_id::TEXT, '')
        FROM public.student_attendance sa_keep
        WHERE sa_keep.student_id = p_keep_id
      );

  -- Reassign remaining student_attendance rows
  UPDATE public.student_attendance sa
  SET student_id = p_keep_id
  WHERE sa.student_id = p_delete_id;

  -- Remove student_cohorts rows that would conflict with keeper
  DELETE FROM public.student_cohorts
  WHERE student_id = p_delete_id
    AND cohort_id IN (
      SELECT sc_keep.cohort_id
      FROM public.student_cohorts sc_keep
      WHERE sc_keep.student_id = p_keep_id
    );

  -- Reassign remaining student_cohorts rows
  UPDATE public.student_cohorts sc
  SET student_id = p_keep_id
  WHERE sc.student_id = p_delete_id;

  -- Soft-delete: clear phone to avoid unique constraint conflict,
  -- store merged_into info in phone_issue
  UPDATE public.students
  SET active      = false,
      phone       = 'merged_' || p_delete_id::TEXT,
      phone_issue = '*merged_into_' || p_keep_id::TEXT
  WHERE id = p_delete_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.merge_duplicate_student(UUID, UUID) TO service_role;
