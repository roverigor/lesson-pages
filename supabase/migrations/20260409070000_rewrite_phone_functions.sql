-- ═══════════════════════════════════════
-- Rewrite fix_student_phones — avoid all column ambiguity
-- Simpler approach: separate normalization from merge logic
-- ═══════════════════════════════════════

-- ── Drop and recreate merge function with no aliases in DELETE ──────────────
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

  -- Remove student_attendance rows for the duplicate that would conflict with keeper
  DELETE FROM public.student_attendance
  WHERE student_id = p_delete_id
    AND (class_date, COALESCE(zoom_meeting_id::TEXT, ''))
      IN (
        SELECT class_date, COALESCE(zoom_meeting_id::TEXT, '')
        FROM public.student_attendance
        WHERE student_id = p_keep_id
      );

  -- Reassign remaining student_attendance rows
  UPDATE public.student_attendance sa
  SET student_id = p_keep_id
  WHERE sa.student_id = p_delete_id;

  -- Remove student_cohorts rows for the duplicate that would conflict with keeper
  DELETE FROM public.student_cohorts
  WHERE student_id = p_delete_id
    AND cohort_id IN (
      SELECT cohort_id FROM public.student_cohorts WHERE student_id = p_keep_id
    );

  -- Reassign remaining student_cohorts rows
  UPDATE public.student_cohorts sc
  SET student_id = p_keep_id
  WHERE sc.student_id = p_delete_id;

  -- Soft-delete the duplicate
  UPDATE public.students
  SET active      = false,
      phone_issue = '*merged_into_' || p_keep_id::TEXT
  WHERE id = p_delete_id;
END;
$$;

-- ── Rewrite fix_student_phones with explicit table references everywhere ─────
CREATE OR REPLACE FUNCTION public.fix_student_phones()
RETURNS TABLE (
  action       TEXT,
  student_id   UUID,
  student_name TEXT,
  old_phone    TEXT,
  new_phone    TEXT,
  note         TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  rec          RECORD;
  norm         TEXT;
  conflict_id  UUID;
  keep_id      UUID;
  del_id       UUID;
  keep_links   BIGINT;
  del_links    BIGINT;
BEGIN
  FOR rec IN
    SELECT s.id AS sid, s.name AS sname, s.phone AS sphone, s.cohort_id AS scohort
    FROM public.students s
    WHERE s.active = true
      AND (s.phone_issue IS NULL OR s.phone_issue NOT LIKE '*merged%')
    ORDER BY s.id
  LOOP
    norm := public.normalize_phone_br(rec.sphone);

    -- ── Phone already correct ──────────────────────────────────────────
    IF norm = rec.sphone THEN
      IF norm !~ '^55\d{10,11}$' THEN
        UPDATE public.students SET phone_issue = '*invalid' WHERE id = rec.sid;
        RETURN QUERY SELECT 'flagged'::TEXT, rec.sid, rec.sname, rec.sphone, norm,
          'Format does not match 55+DDD+number'::TEXT;
      ELSE
        UPDATE public.students SET phone_issue = NULL
        WHERE id = rec.sid AND phone_issue IS NOT NULL;
      END IF;
      CONTINUE;
    END IF;

    -- ── Phone can be normalized ────────────────────────────────────────
    IF norm ~ '^55\d{10,11}$' THEN
      -- Find duplicate (another student with the normalized phone in same cohort)
      SELECT s2.id INTO conflict_id
      FROM public.students s2
      WHERE s2.phone    = norm
        AND s2.active   = true
        AND s2.id      != rec.sid
        AND (
          (s2.cohort_id  = rec.scohort)
          OR (s2.cohort_id IS NULL AND rec.scohort IS NULL)
        )
      LIMIT 1;

      IF conflict_id IS NOT NULL THEN
        -- Determine which to keep (more zoom links wins)
        SELECT COUNT(*) INTO keep_links FROM public.zoom_participants WHERE student_id = conflict_id;
        SELECT COUNT(*) INTO del_links  FROM public.zoom_participants WHERE student_id = rec.sid;

        IF keep_links >= del_links THEN
          keep_id := conflict_id;
          del_id  := rec.sid;
        ELSE
          keep_id := rec.sid;
          del_id  := conflict_id;
        END IF;

        PERFORM public.merge_duplicate_student(keep_id, del_id);
        -- Ensure keeper has the normalized phone
        UPDATE public.students SET phone = norm, phone_issue = NULL
        WHERE id = keep_id AND phone != norm;

        RETURN QUERY SELECT 'merged'::TEXT, del_id, rec.sname, rec.sphone, norm,
          'Merged into ' || keep_id::TEXT;

      ELSE
        -- No conflict — just normalize
        UPDATE public.students SET phone = norm, phone_issue = NULL
        WHERE id = rec.sid;

        RETURN QUERY SELECT 'normalized'::TEXT, rec.sid, rec.sname, rec.sphone, norm, NULL::TEXT;
      END IF;

    ELSE
      -- ── Cannot normalize ───────────────────────────────────────────────
      UPDATE public.students SET phone_issue = '*invalid' WHERE id = rec.sid;
      RETURN QUERY SELECT 'flagged'::TEXT, rec.sid, rec.sname, rec.sphone, norm,
        'Cannot normalize to 55+DDD+number'::TEXT;
    END IF;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.merge_duplicate_student(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.fix_student_phones()               TO service_role;
