-- ═══════════════════════════════════════
-- Fix column ambiguity: rename RETURNS TABLE 'student_id' → 'record_id'
-- The name 'student_id' in RETURNS TABLE shadowed same-named columns in queries
-- ═══════════════════════════════════════

-- Must drop first because return type is changing
DROP FUNCTION IF EXISTS public.fix_student_phones();

CREATE OR REPLACE FUNCTION public.fix_student_phones()
RETURNS TABLE (
  action       TEXT,
  record_id    UUID,    -- renamed from student_id to avoid column shadowing
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
      -- Find duplicate in same cohort with the normalized phone
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
        -- Which has more zoom links?
        SELECT COUNT(*) INTO keep_links
        FROM public.zoom_participants zp
        WHERE zp.student_id = conflict_id;

        SELECT COUNT(*) INTO del_links
        FROM public.zoom_participants zp2
        WHERE zp2.student_id = rec.sid;

        IF keep_links >= del_links THEN
          keep_id := conflict_id;
          del_id  := rec.sid;
        ELSE
          keep_id := rec.sid;
          del_id  := conflict_id;
        END IF;

        PERFORM public.merge_duplicate_student(keep_id, del_id);

        UPDATE public.students
        SET phone = norm, phone_issue = NULL
        WHERE id = keep_id AND phone != norm;

        RETURN QUERY SELECT 'merged'::TEXT, del_id, rec.sname, rec.sphone, norm,
          'Merged into ' || keep_id::TEXT;

      ELSE
        -- No conflict — just normalize
        UPDATE public.students
        SET phone = norm, phone_issue = NULL
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

GRANT EXECUTE ON FUNCTION public.fix_student_phones() TO service_role;
