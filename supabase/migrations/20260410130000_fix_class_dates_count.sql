-- Fix: get_class_dates count must match get_present_students count
-- Previously counted all student_ids, now applies same filters:
-- - active students only
-- - valid phone (not pending_*)
-- - deduplicates by phone (same as get_present_students)

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
    COUNT(DISTINCT COALESCE(NULLIF(s.phone, ''), s.id::text)) AS present_count,
    MAX(zm.topic) AS zoom_topic
  FROM student_attendance sa
  JOIN students s ON s.id = sa.student_id
  LEFT JOIN zoom_meetings zm ON zm.id = sa.zoom_meeting_id
  WHERE sa.cohort_id = p_cohort_id
    AND s.active = true
    AND s.phone IS NOT NULL
    AND s.phone NOT LIKE 'pending_%'
  GROUP BY sa.class_date
  ORDER BY sa.class_date DESC
$$;

GRANT EXECUTE ON FUNCTION public.get_class_dates(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_class_dates(UUID) TO service_role;
