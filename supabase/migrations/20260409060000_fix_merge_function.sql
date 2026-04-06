-- ═══════════════════════════════════════
-- Fix merge_duplicate_student — remove ambiguous column references
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
  -- ── zoom_participants: simple reassign (no unique constraint issues) ──
  UPDATE public.zoom_participants
  SET student_id = p_keep_id
  WHERE student_id = p_delete_id;

  -- ── student_attendance: delete conflicting rows first, then reassign ──
  -- A conflict exists when the keeper already has attendance for the same
  -- (class_date, zoom_meeting_id) as the duplicate.
  DELETE FROM public.student_attendance del_sa
  WHERE del_sa.student_id = p_delete_id
    AND EXISTS (
      SELECT 1
      FROM public.student_attendance keep_sa
      WHERE keep_sa.student_id     = p_keep_id
        AND keep_sa.class_date     = del_sa.class_date
        AND keep_sa.zoom_meeting_id IS NOT DISTINCT FROM del_sa.zoom_meeting_id
    );

  -- Reassign the non-conflicting ones
  UPDATE public.student_attendance
  SET student_id = p_keep_id
  WHERE student_id = p_delete_id;

  -- ── student_cohorts: delete conflicts, then reassign ──
  DELETE FROM public.student_cohorts del_sc
  WHERE del_sc.student_id = p_delete_id
    AND EXISTS (
      SELECT 1
      FROM public.student_cohorts keep_sc
      WHERE keep_sc.student_id = p_keep_id
        AND keep_sc.cohort_id  = del_sc.cohort_id
    );

  UPDATE public.student_cohorts
  SET student_id = p_keep_id
  WHERE student_id = p_delete_id;

  -- ── Soft-delete the duplicate ──
  UPDATE public.students
  SET active      = false,
      phone_issue = '*merged_into_' || p_keep_id::TEXT
  WHERE id = p_delete_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.merge_duplicate_student(UUID, UUID) TO service_role;
