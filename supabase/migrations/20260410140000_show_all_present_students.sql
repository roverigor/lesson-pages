-- Show ALL matched students in presence list, not just those with valid phones.
-- Phone filtering should happen only at dispatch time, not at presence display.

CREATE OR REPLACE FUNCTION public.get_present_students(
  p_class_date DATE,
  p_cohort_id UUID DEFAULT NULL,
  p_meeting_id UUID DEFAULT NULL
)
RETURNS TABLE (
  student_id UUID,
  student_name TEXT,
  phone TEXT,
  cohort_name TEXT,
  cohort_id UUID,
  duration_minutes INT,
  source TEXT,
  zoom_meeting_id UUID
)
LANGUAGE sql
STABLE
AS $$
  SELECT DISTINCT ON (s.id)
    sa.student_id,
    s.name AS student_name,
    CASE
      WHEN s.phone IS NOT NULL AND s.phone NOT LIKE 'pending_%' AND s.phone <> ''
      THEN s.phone
      ELSE NULL
    END AS phone,
    c.name AS cohort_name,
    sa.cohort_id,
    sa.duration_minutes,
    sa.source,
    sa.zoom_meeting_id
  FROM student_attendance sa
  JOIN students s ON s.id = sa.student_id
  LEFT JOIN cohorts c ON c.id = COALESCE(sa.cohort_id, s.cohort_id)
  WHERE sa.class_date = p_class_date
    AND (p_cohort_id IS NULL OR sa.cohort_id = p_cohort_id OR s.cohort_id = p_cohort_id)
    AND (p_meeting_id IS NULL OR sa.zoom_meeting_id = p_meeting_id)
    AND s.active = true
  ORDER BY s.id, sa.duration_minutes DESC NULLS LAST
$$;

GRANT EXECUTE ON FUNCTION public.get_present_students(DATE, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_present_students(DATE, UUID, UUID) TO service_role;

-- Update get_class_dates to count all present students (not just those with phones)
CREATE OR REPLACE FUNCTION public.get_class_dates(p_cohort_id UUID)
RETURNS TABLE (
  class_date DATE,
  present_count BIGINT,
  zoom_topic TEXT
)
LANGUAGE sql
STABLE
AS $$
  SELECT
    sa.class_date,
    COUNT(DISTINCT sa.student_id) AS present_count,
    MAX(zm.topic) AS zoom_topic
  FROM student_attendance sa
  JOIN students s ON s.id = sa.student_id
  LEFT JOIN zoom_meetings zm ON zm.id = sa.zoom_meeting_id
  WHERE sa.cohort_id = p_cohort_id
    AND s.active = true
  GROUP BY sa.class_date
  ORDER BY sa.class_date DESC
$$;

GRANT EXECUTE ON FUNCTION public.get_class_dates(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_class_dates(UUID) TO service_role;
