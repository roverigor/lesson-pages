-- ═══════════════════════════════════════
-- Function: get_staff_not_found_in_zoom
-- Returns scheduled mentors who do NOT have a mentor_attendance record
-- for the given date. Used by daily_pipeline Step 8 to alert coordinator.
-- Respects: class_mentors cycles, schedule_overrides (add/remove), class active status.
-- ═══════════════════════════════════════

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
    -- NOT in mentor_attendance for this date
    AND NOT EXISTS (
      SELECT 1 FROM mentor_attendance ma
      WHERE ma.mentor_id    = m.id
        AND ma.class_id     = c.id
        AND ma.session_date = v_date
    )

  UNION ALL

  -- PART 2: Override-added mentors NOT in mentor_attendance
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
    -- NOT in mentor_attendance
    AND NOT EXISTS (
      SELECT 1 FROM mentor_attendance ma
      WHERE ma.mentor_id    = m.id
        AND ma.class_id     = c.id
        AND ma.session_date = v_date
    )

  ORDER BY class_time, mentor_name;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_staff_not_found_in_zoom(DATE) TO service_role;
