-- ═══════════════════════════════════════
-- Story 14.1: Auto sync staff attendance from Zoom to mentor_attendance
-- Uses same name-matching logic as mark_mentor_participants()
-- but ALSO identifies which mentor matched and writes to mentor_attendance.
-- Called as Step 7 of daily_pipeline after transfer_to_attendance.
-- ═══════════════════════════════════════

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
  -- For each zoom_participant in recent meetings that matches a mentor name,
  -- resolve the class and insert into mentor_attendance
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
        (zm.start_time AT TIME ZONE 'America/Sao_Paulo')::date AS session_date,
        zp.duration_minutes
      FROM zoom_participants zp
      JOIN zoom_meetings zm ON zp.meeting_id = zm.id
      JOIN mentor_norms mn ON (
        -- Exact match
        LOWER(TRANSLATE(UNACCENT(TRIM(zp.participant_name)), '_', ' ')) = mn.norm_name
        -- Participant starts with mentor name
        OR LOWER(TRANSLATE(UNACCENT(TRIM(zp.participant_name)), '_', ' ')) LIKE mn.norm_name || ' %'
        -- Mentor name starts with participant
        OR mn.norm_name LIKE LOWER(TRANSLATE(UNACCENT(TRIM(zp.participant_name)), '_', ' ')) || ' %'
      )
      WHERE zm.start_time >= (NOW() AT TIME ZONE 'America/Sao_Paulo' - (p_days_back || ' days')::interval)
        AND zp.participant_name IS NOT NULL
        AND TRIM(zp.participant_name) != ''
        -- Exclude known bot/notetaker patterns
        AND LOWER(zp.participant_name) NOT LIKE '%notetaker%'
        AND LOWER(zp.participant_name) NOT LIKE '%note taker%'
        AND LOWER(zp.participant_name) NOT LIKE '%otter%'
        AND LOWER(zp.participant_name) NOT LIKE '%bot%'
      ORDER BY zp.id, LENGTH(mn.norm_name) DESC  -- prefer longest (most specific) match
    )
    SELECT * FROM participant_mentor_match
  LOOP
    v_processed := v_processed + 1;

    -- Resolve class_id from cohort_id
    -- A cohort may map to multiple classes; pick the one active on this session_date
    SELECT c.id INTO v_class_id
    FROM classes c
    JOIN class_cohort_access cca ON cca.class_id = c.id AND cca.cohort_id = rec.cohort_id
    WHERE c.active = true
      AND (c.start_date IS NULL OR c.start_date <= rec.session_date)
      AND (c.end_date IS NULL OR c.end_date >= rec.session_date)
    LIMIT 1;

    -- Fallback: try via zoom_meetings.class_id (legacy field)
    IF v_class_id IS NULL THEN
      SELECT zm.class_id INTO v_class_id
      FROM zoom_meetings zm
      WHERE zm.id = rec.meeting_id AND zm.class_id IS NOT NULL;
    END IF;

    -- If we can't resolve a class, skip
    IF v_class_id IS NULL THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- UPSERT into mentor_attendance
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

    -- Also mark the zoom_participant as matched (if not already)
    UPDATE zoom_participants SET matched = true WHERE id = rec.participant_id AND matched = false;
  END LOOP;

  RETURN QUERY SELECT v_processed, v_inserted, v_skipped;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_staff_attendance_from_zoom(INT) TO service_role;
