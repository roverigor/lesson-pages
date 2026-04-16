-- ═══════════════════════════════════════
-- Fix class resolution: use classes.zoom_meeting_id as primary lookup
-- Problem: PS Advanced/Fundamentals meetings had no cohort_id in zoom_meetings,
-- so sync_staff_attendance couldn't resolve class_id.
-- Fix: classes table already has zoom_meeting_id matching the Zoom room ID.
-- ═══════════════════════════════════════

-- 1. Update sync_staff_attendance_from_zoom to resolve class via classes.zoom_meeting_id
CREATE OR REPLACE FUNCTION public.sync_staff_attendance_from_zoom(
  p_days_back INT DEFAULT 2
)
RETURNS TABLE (processed BIGINT, inserted BIGINT, skipped BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_processed BIGINT := 0;
  v_inserted  BIGINT := 0;
  v_skipped   BIGINT := 0;
  rec RECORD;
  v_class_id  UUID;
BEGIN
  FOR rec IN
    WITH mentor_norms AS (
      SELECT
        id AS mentor_id,
        name,
        LOWER(TRANSLATE(UNACCENT(TRIM(name)), '_', ' ')) AS norm_name
      FROM mentors
      WHERE active = true
    ),
    participant_mentor_match AS (
      SELECT DISTINCT ON (zp.id)
        zp.id AS participant_id,
        zp.participant_name,
        mn.mentor_id,
        mn.name AS mentor_name,
        zm.id AS meeting_id,
        zm.cohort_id,
        zm.zoom_meeting_id,
        (zm.start_time AT TIME ZONE 'America/Sao_Paulo')::date AS session_date,
        zp.duration_minutes
      FROM zoom_participants zp
      JOIN zoom_meetings zm ON zp.meeting_id = zm.id
      JOIN mentor_norms mn ON (
        LOWER(TRANSLATE(UNACCENT(TRIM(zp.participant_name)), '_', ' ')) = mn.norm_name
        OR LOWER(TRANSLATE(UNACCENT(TRIM(zp.participant_name)), '_', ' ')) LIKE mn.norm_name || ' %'
        OR mn.norm_name LIKE LOWER(TRANSLATE(UNACCENT(TRIM(zp.participant_name)), '_', ' ')) || ' %'
      )
      WHERE zm.start_time >= (NOW() AT TIME ZONE 'America/Sao_Paulo' - (p_days_back || ' days')::interval)
        AND zp.participant_name IS NOT NULL
        AND TRIM(zp.participant_name) != ''
        AND LOWER(zp.participant_name) NOT LIKE '%notetaker%'
        AND LOWER(zp.participant_name) NOT LIKE '%note taker%'
        AND LOWER(zp.participant_name) NOT LIKE '%otter%'
        AND LOWER(zp.participant_name) NOT LIKE '%bot%'
      ORDER BY zp.id, LENGTH(mn.norm_name) DESC
    )
    SELECT * FROM participant_mentor_match
  LOOP
    v_processed := v_processed + 1;

    -- Resolution priority:
    -- 1. classes.zoom_meeting_id (direct match — works for PS Advanced/Fundamentals)
    SELECT c.id INTO v_class_id
    FROM classes c
    WHERE c.zoom_meeting_id = rec.zoom_meeting_id
      AND c.active = true
      AND (c.start_date IS NULL OR c.start_date <= rec.session_date)
      AND (c.end_date IS NULL OR c.end_date >= rec.session_date)
    LIMIT 1;

    -- 2. class_cohort_access (cohort → class mapping)
    IF v_class_id IS NULL AND rec.cohort_id IS NOT NULL THEN
      SELECT c.id INTO v_class_id
      FROM classes c
      JOIN class_cohort_access cca ON cca.class_id = c.id AND cca.cohort_id = rec.cohort_id
      WHERE c.active = true
        AND (c.start_date IS NULL OR c.start_date <= rec.session_date)
        AND (c.end_date IS NULL OR c.end_date >= rec.session_date)
      LIMIT 1;
    END IF;

    -- 3. zoom_meetings.class_id (legacy fallback)
    IF v_class_id IS NULL THEN
      SELECT zm.class_id INTO v_class_id
      FROM zoom_meetings zm
      WHERE zm.id = rec.meeting_id AND zm.class_id IS NOT NULL;
    END IF;

    IF v_class_id IS NULL THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    INSERT INTO mentor_attendance (mentor_id, class_id, session_date, status, comment)
    VALUES (
      rec.mentor_id,
      v_class_id,
      rec.session_date,
      'present',
      'Auto-synced from Zoom (participant: ' || rec.participant_name || ')'
    )
    ON CONFLICT (mentor_id, class_id, session_date) DO NOTHING;

    IF FOUND THEN
      v_inserted := v_inserted + 1;
    END IF;

    UPDATE zoom_participants SET matched = true WHERE id = rec.participant_id AND matched = false;
  END LOOP;

  RETURN QUERY SELECT v_processed, v_inserted, v_skipped;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_staff_attendance_from_zoom(INT) TO service_role;

-- 2. Update get_staff_not_found_in_zoom to also resolve via classes.zoom_meeting_id
-- The absence check needs to know which classes had Zoom meetings on a given date.
-- Add: check mentor_attendance for classes that match the zoom_meeting sessions that day.
-- (The existing function already checks correctly — it uses class_mentors to find scheduled staff
--  and mentor_attendance to check if they were synced. Since we now resolve class_id correctly
--  in sync_staff_attendance, the absence check will automatically work.)

-- 3. Backfill: set class_id on existing zoom_meetings that match classes.zoom_meeting_id
UPDATE zoom_meetings zm
SET class_id = c.id
FROM classes c
WHERE c.zoom_meeting_id = zm.zoom_meeting_id
  AND c.active = true
  AND zm.class_id IS NULL;
