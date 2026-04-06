-- ═══════════════════════════════════════
-- LESSON PAGES — Normalize student phone numbers
-- Problems solved:
--   1. Phones without Brazil country code (55) — add it
--   2. Duplicate students caused by same phone ± 55 prefix
--   3. Invalid phones flagged with phone_issue = '*invalid'
-- ═══════════════════════════════════════

-- ── 1. Add phone_issue flag column ─────────────────────────────────────────
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS phone_issue TEXT DEFAULT NULL;

-- ── 2. Pure normalization helper (no side effects) ─────────────────────────
-- Input: any phone string  →  Output: canonical '55DDDDDDDDDD[D]' (12-13 digits)
-- Returns the input unchanged if it cannot be safely normalized.
CREATE OR REPLACE FUNCTION public.normalize_phone_br(raw_phone TEXT)
RETURNS TEXT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  digits TEXT;
BEGIN
  -- Strip all non-digit characters
  digits := REGEXP_REPLACE(COALESCE(raw_phone, ''), '[^0-9]', '', 'g');

  -- Remove leading 0 (old Brazilian trunk prefix)
  IF digits LIKE '0%' THEN
    digits := SUBSTRING(digits FROM 2);
  END IF;

  -- 10-11 digits → Brazilian without country code → prepend 55
  IF LENGTH(digits) IN (10, 11) THEN
    RETURN '55' || digits;
  END IF;

  -- Already 12-13 digits starting with 55 → valid as-is
  IF LENGTH(digits) IN (12, 13) AND digits LIKE '55%' THEN
    RETURN digits;
  END IF;

  -- Cannot normalize
  RETURN digits;
END;
$$;

-- ── 3. Merge helper — reassigns all FKs from source to target ──────────────
-- Called internally when two students are detected as duplicates.
CREATE OR REPLACE FUNCTION public.merge_duplicate_student(
  p_keep_id   UUID,  -- student to keep
  p_delete_id UUID   -- student to remove (FKs reassigned to keep)
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Reassign zoom_participants
  UPDATE public.zoom_participants
  SET student_id = p_keep_id
  WHERE student_id = p_delete_id;

  -- Reassign student_attendance
  UPDATE public.student_attendance
  SET student_id = p_keep_id
  WHERE student_id = p_delete_id
    -- Skip if the same class_date+zoom_meeting_id already exists for keep (would violate unique)
    AND NOT EXISTS (
      SELECT 1 FROM public.student_attendance sa
      WHERE sa.student_id  = p_keep_id
        AND sa.class_date  = (SELECT class_date FROM public.student_attendance WHERE student_id = p_delete_id LIMIT 1)
        AND sa.zoom_meeting_id = (SELECT zoom_meeting_id FROM public.student_attendance WHERE student_id = p_delete_id LIMIT 1)
    );

  -- Reassign student_cohorts
  UPDATE public.student_cohorts
  SET student_id = p_keep_id
  WHERE student_id = p_delete_id
    AND NOT EXISTS (
      SELECT 1 FROM public.student_cohorts sc2
      WHERE sc2.student_id = p_keep_id
        AND sc2.cohort_id  = (SELECT cohort_id FROM public.student_cohorts WHERE student_id = p_delete_id LIMIT 1)
    );

  -- Deactivate (soft delete) the duplicate student
  UPDATE public.students
  SET active     = false,
      phone_issue = '*merged_into_' || p_keep_id::TEXT
  WHERE id = p_delete_id;
END;
$$;

-- ── 4. Main procedure: normalize + merge duplicates ─────────────────────────
CREATE OR REPLACE FUNCTION public.fix_student_phones()
RETURNS TABLE (
  action      TEXT,
  student_id  UUID,
  student_name TEXT,
  old_phone   TEXT,
  new_phone   TEXT,
  note        TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  rec         RECORD;
  norm        TEXT;
  conflict_id UUID;
  keep_id     UUID;
  del_id      UUID;
BEGIN
  FOR rec IN
    SELECT s.id, s.name, s.phone, s.cohort_id
    FROM public.students s
    WHERE s.active = true
      AND s.phone_issue IS DISTINCT FROM '*merged'
    ORDER BY s.id
  LOOP
    norm := public.normalize_phone_br(rec.phone);

    -- ── Case 1: Phone is already in correct format ─────────────────────
    IF norm = rec.phone THEN
      -- Check if norm matches valid pattern
      IF norm !~ '^55\d{10,11}$' THEN
        -- Valid-looking 55 prefix but wrong length — flag
        UPDATE public.students SET phone_issue = '*invalid' WHERE id = rec.id;
        RETURN QUERY SELECT 'flagged'::TEXT, rec.id, rec.name, rec.phone, norm, 'Does not match 55+10-11 digits pattern'::TEXT;
      END IF;
      -- Phone is fine, clear any existing flag
      UPDATE public.students SET phone_issue = NULL WHERE id = rec.id AND phone_issue IS NOT NULL;
      CONTINUE;
    END IF;

    -- ── Case 2: Phone can be normalized ───────────────────────────────
    IF norm ~ '^55\d{10,11}$' THEN
      -- Check if another ACTIVE student has this normalized phone in the same cohort
      SELECT id INTO conflict_id
      FROM public.students
      WHERE phone      = norm
        AND active     = true
        AND id        != rec.id
        AND (
          cohort_id = rec.cohort_id
          OR (cohort_id IS NULL AND rec.cohort_id IS NULL)
        )
      LIMIT 1;

      IF conflict_id IS NOT NULL THEN
        -- Merge: keep whichever has more zoom_participants links
        SELECT
          CASE WHEN a.linked >= b.linked THEN conflict_id ELSE rec.id END,
          CASE WHEN a.linked >= b.linked THEN rec.id      ELSE conflict_id END
        INTO keep_id, del_id
        FROM
          (SELECT COUNT(*) AS linked FROM public.zoom_participants WHERE student_id = conflict_id) a,
          (SELECT COUNT(*) AS linked FROM public.zoom_participants WHERE student_id = rec.id)      b;

        PERFORM public.merge_duplicate_student(keep_id, del_id);
        -- Update phone on keeper to normalized if needed
        UPDATE public.students SET phone = norm, phone_issue = NULL WHERE id = keep_id AND phone != norm;

        RETURN QUERY SELECT 'merged'::TEXT, del_id, rec.name, rec.phone, norm,
          'Merged into ' || keep_id::TEXT;
      ELSE
        -- No conflict — just normalize the phone
        UPDATE public.students
        SET phone = norm, phone_issue = NULL
        WHERE id = rec.id;

        RETURN QUERY SELECT 'normalized'::TEXT, rec.id, rec.name, rec.phone, norm, NULL::TEXT;
      END IF;

    ELSE
      -- ── Case 3: Cannot normalize ──────────────────────────────────────
      UPDATE public.students SET phone_issue = '*invalid' WHERE id = rec.id;
      RETURN QUERY SELECT 'flagged'::TEXT, rec.id, rec.name, rec.phone, norm,
        'Cannot normalize to 55+10-11 digits'::TEXT;
    END IF;
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.normalize_phone_br(TEXT)           TO service_role;
GRANT EXECUTE ON FUNCTION public.merge_duplicate_student(UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.fix_student_phones()               TO service_role;
