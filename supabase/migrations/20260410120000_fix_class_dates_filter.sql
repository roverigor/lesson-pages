-- Fix: get_class_dates was showing classes from OTHER cohorts
-- because the OR clause matched any attendance for students in this cohort
-- regardless of which meeting they attended.
-- Now strictly filters by sa.cohort_id only.

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
  LEFT JOIN zoom_meetings zm ON zm.id = sa.zoom_meeting_id
  WHERE sa.cohort_id = p_cohort_id
  GROUP BY sa.class_date
  ORDER BY sa.class_date DESC
$$;

GRANT EXECUTE ON FUNCTION public.get_class_dates(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_class_dates(UUID) TO service_role;
