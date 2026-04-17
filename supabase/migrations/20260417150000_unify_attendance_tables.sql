-- ═══════════════════════════════════════
-- Unify attendance: eliminate mentor_attendance, use only attendance table
--
-- Before: mentor_attendance (mentor_id UUID, class_id UUID, session_date, status)
--         attendance (course TEXT, teacher_name TEXT, lesson_date DATE, status)
-- After:  attendance only (single source of truth for grid + report + zoom pipeline)
--
-- Steps:
--   1. Migrate any mentor_attendance records not in attendance
--   2. Rewrite sync_staff_attendance_from_zoom → inserts into attendance
--   3. Rewrite get_staff_not_found_in_zoom → checks attendance
--   4. Drop mentor_attendance
-- ═══════════════════════════════════════

-- ─── 1. Migrate existing mentor_attendance records into attendance ───
INSERT INTO attendance (course, teacher_name, role, lesson_date, status, notes)
SELECT
  c.name AS course,
  m.name AS teacher_name,
  COALESCE(
    (SELECT cm.role FROM class_mentors cm
     WHERE cm.mentor_id = ma.mentor_id AND cm.class_id = ma.class_id
     LIMIT 1),
    'Staff'
  ) AS role,
  ma.session_date AS lesson_date,
  ma.status,
  ma.comment AS notes
FROM mentor_attendance ma
JOIN mentors m ON m.id = ma.mentor_id
JOIN classes c ON c.id = ma.class_id
WHERE NOT EXISTS (
  SELECT 1 FROM attendance a
  WHERE a.lesson_date = ma.session_date
    AND a.course = c.name
    AND a.teacher_name = m.name
)
ON CONFLICT DO NOTHING;

-- ─── 2. Rewrite sync_staff_attendance_from_zoom → attendance table ───
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
  v_class_id   UUID;
  v_class_name TEXT;
  v_class_role TEXT;
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
    -- 1. classes.zoom_meeting_id (direct match)
    SELECT c.id, c.name INTO v_class_id, v_class_name
    FROM classes c
    WHERE c.zoom_meeting_id = rec.zoom_meeting_id
      AND c.active = true
      AND (c.start_date IS NULL OR c.start_date <= rec.session_date)
      AND (c.end_date IS NULL OR c.end_date >= rec.session_date)
    LIMIT 1;

    -- 2. class_cohort_access (cohort → class mapping)
    IF v_class_id IS NULL AND rec.cohort_id IS NOT NULL THEN
      SELECT c.id, c.name INTO v_class_id, v_class_name
      FROM classes c
      JOIN class_cohort_access cca ON cca.class_id = c.id AND cca.cohort_id = rec.cohort_id
      WHERE c.active = true
        AND (c.start_date IS NULL OR c.start_date <= rec.session_date)
        AND (c.end_date IS NULL OR c.end_date >= rec.session_date)
      LIMIT 1;
    END IF;

    -- 3. zoom_meetings.class_id (legacy fallback)
    IF v_class_id IS NULL THEN
      SELECT c.id, c.name INTO v_class_id, v_class_name
      FROM zoom_meetings zm
      JOIN classes c ON c.id = zm.class_id
      WHERE zm.id = rec.meeting_id AND zm.class_id IS NOT NULL
      LIMIT 1;
    END IF;

    IF v_class_id IS NULL THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    -- Resolve role from class_mentors
    SELECT cm.role INTO v_class_role
    FROM class_mentors cm
    WHERE cm.mentor_id = rec.mentor_id
      AND cm.class_id = v_class_id
      AND cm.valid_from <= rec.session_date
      AND (cm.valid_until IS NULL OR cm.valid_until >= rec.session_date)
    LIMIT 1;

    -- Insert into attendance (the single source of truth)
    INSERT INTO attendance (course, teacher_name, role, lesson_date, status, notes)
    VALUES (
      v_class_name,
      rec.mentor_name,
      COALESCE(v_class_role, 'Staff'),
      rec.session_date,
      'present',
      'Auto-synced from Zoom (participant: ' || rec.participant_name || ')'
    )
    ON CONFLICT DO NOTHING;

    IF FOUND THEN
      v_inserted := v_inserted + 1;
    END IF;

    UPDATE zoom_participants SET matched = true WHERE id = rec.participant_id AND matched = false;
  END LOOP;

  RETURN QUERY SELECT v_processed, v_inserted, v_skipped;
END;
$$;

GRANT EXECUTE ON FUNCTION public.sync_staff_attendance_from_zoom(INT) TO service_role;

-- ─── 3. Rewrite get_staff_not_found_in_zoom → checks attendance table ───
CREATE OR REPLACE FUNCTION public.get_staff_not_found_in_zoom(
  p_date DATE DEFAULT (NOW() AT TIME ZONE 'America/Sao_Paulo')::date - INTERVAL '1 day'
)
RETURNS TABLE (
  mentor_name TEXT,
  mentor_role TEXT,
  class_name  TEXT,
  class_time  TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_dow      INT;
  v_date_key TEXT;
  v_date     DATE;
BEGIN
  v_date     := p_date::date;
  v_dow      := EXTRACT(DOW FROM v_date)::int;
  v_date_key := to_char(v_date, 'DD/MM');

  RETURN QUERY
  -- PART 1: Regular class_mentors (minus override removes)
  SELECT
    m.name::TEXT       AS mentor_name,
    cm.role::TEXT      AS mentor_role,
    c.name::TEXT       AS class_name,
    COALESCE(c.time_start, '')::TEXT AS class_time
  FROM classes c
  JOIN class_mentors cm ON c.id = cm.class_id
    AND cm.weekday = v_dow
    AND cm.valid_from <= v_date
    AND (cm.valid_until IS NULL OR cm.valid_until >= v_date)
  JOIN mentors m ON cm.mentor_id = m.id
    AND m.active = true
  WHERE c.active = true
    AND (c.start_date IS NULL OR c.start_date <= v_date)
    AND (c.end_date   IS NULL OR c.end_date   >= v_date)
    -- Exclude override removes
    AND NOT EXISTS (
      SELECT 1 FROM schedule_overrides so
      WHERE so.lesson_date  = v_date_key
        AND so.course       = c.name
        AND so.teacher_name = m.name
        AND so.action       = 'remove'
    )
    -- NOT in attendance for this date+class+teacher
    AND NOT EXISTS (
      SELECT 1 FROM attendance a
      WHERE a.teacher_name = m.name
        AND a.course       = c.name
        AND a.lesson_date  = v_date
    )

  UNION ALL

  -- PART 2: Override-added mentors NOT in attendance
  SELECT
    m.name::TEXT       AS mentor_name,
    so.role::TEXT      AS mentor_role,
    c.name::TEXT       AS class_name,
    COALESCE(c.time_start, '')::TEXT AS class_time
  FROM schedule_overrides so
  JOIN classes c ON c.name = so.course AND c.active = true
  JOIN mentors m ON m.name = so.teacher_name AND m.active = true
  WHERE so.lesson_date = v_date_key
    AND so.action = 'add'
    -- Not already covered by class_mentors
    AND NOT EXISTS (
      SELECT 1 FROM class_mentors cm
      WHERE cm.class_id = c.id
        AND cm.mentor_id = m.id
        AND cm.weekday = v_dow
        AND cm.valid_from <= p_date
        AND (cm.valid_until IS NULL OR cm.valid_until >= p_date)
    )
    -- NOT in attendance
    AND NOT EXISTS (
      SELECT 1 FROM attendance a
      WHERE a.teacher_name = m.name
        AND a.course       = c.name
        AND a.lesson_date  = v_date
    )

  ORDER BY class_time, mentor_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_not_found_in_zoom(DATE) TO service_role;

-- ─── 4. Add unique constraint on attendance for upsert support ───
-- Needed so zoom pipeline and slack-interact can upsert without duplicates
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_unique_record
  ON attendance (lesson_date, course, teacher_name);

-- ─── 5. Drop mentor_attendance table ───
DROP TABLE IF EXISTS mentor_attendance CASCADE;
