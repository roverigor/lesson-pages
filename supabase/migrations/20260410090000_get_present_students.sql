-- ═══════════════════════════════════════
-- RPC: get_present_students
-- Returns deduplicated list of students present on a given date
-- Deduplicates by phone (same student in 2+ cohorts = 1 row)
-- Used by Presença tab and WhatsApp dispatch
-- ═══════════════════════════════════════

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
  SELECT DISTINCT ON (COALESCE(NULLIF(s.phone, ''), s.id::text))
    sa.student_id,
    s.name AS student_name,
    s.phone,
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
    AND s.phone IS NOT NULL
    AND s.phone NOT LIKE 'pending_%'
  ORDER BY COALESCE(NULLIF(s.phone, ''), s.id::text), sa.duration_minutes DESC NULLS LAST
$$;

GRANT EXECUTE ON FUNCTION public.get_present_students(DATE, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_present_students(DATE, UUID, UUID) TO service_role;

-- ═══════════════════════════════════════
-- RPC: get_class_dates
-- Returns distinct dates with attendance for a cohort (for dropdown)
-- ═══════════════════════════════════════

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
