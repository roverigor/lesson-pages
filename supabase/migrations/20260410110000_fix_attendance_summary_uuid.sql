-- Fix get_attendance_summary: use zm.id (UUID) instead of zm.zoom_meeting_id (TEXT)
-- student_attendance.zoom_meeting_id is UUID referencing zoom_meetings.id,
-- but the RPC was comparing against zoom_meetings.zoom_meeting_id (TEXT) → always 0 results

CREATE OR REPLACE FUNCTION public.get_attendance_summary(p_cohort_id UUID)
RETURNS TABLE (
  student_id         UUID,
  student_name       TEXT,
  phone              TEXT,
  total_present      BIGINT,
  total_classes      BIGINT,
  presence_pct       NUMERIC,
  last_3             JSONB,
  consecutive_abs    INT
)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total_classes BIGINT;
BEGIN
  SELECT COUNT(DISTINCT sa.class_date)
  INTO v_total_classes
  FROM public.student_attendance sa
  WHERE sa.zoom_meeting_id IN (
    SELECT zm.id FROM public.zoom_meetings zm WHERE zm.cohort_id = p_cohort_id
  );

  IF v_total_classes = 0 THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH cohort_students AS (
    SELECT s.id, s.name, s.phone
    FROM public.students s
    WHERE s.cohort_id = p_cohort_id
      AND (s.active IS NULL OR s.active = true)
  ),
  cohort_dates AS (
    SELECT DISTINCT sa.class_date
    FROM public.student_attendance sa
    WHERE sa.zoom_meeting_id IN (
      SELECT zm.id FROM public.zoom_meetings zm WHERE zm.cohort_id = p_cohort_id
    )
    ORDER BY sa.class_date DESC
  ),
  present AS (
    SELECT
      sa.student_id,
      sa.class_date,
      sa.duration_minutes
    FROM public.student_attendance sa
    WHERE sa.zoom_meeting_id IN (
      SELECT zm.id FROM public.zoom_meetings zm WHERE zm.cohort_id = p_cohort_id
    )
  ),
  last_3_dates AS (
    SELECT class_date FROM cohort_dates LIMIT 3
  ),
  student_last3 AS (
    SELECT
      cs.id AS student_id,
      jsonb_agg(
        jsonb_build_object(
          'date',             cd.class_date,
          'present',          CASE WHEN p.student_id IS NOT NULL THEN true ELSE false END,
          'duration_minutes', COALESCE(p.duration_minutes, 0)
        ) ORDER BY cd.class_date DESC
      ) AS last_3
    FROM cohort_students cs
    CROSS JOIN last_3_dates cd
    LEFT JOIN present p ON p.student_id = cs.id AND p.class_date = cd.class_date
    GROUP BY cs.id
  ),
  consecutive AS (
    SELECT
      cs.id AS student_id,
      (
        SELECT COUNT(*)
        FROM (
          SELECT cd2.class_date,
                 CASE WHEN p2.student_id IS NOT NULL THEN 1 ELSE 0 END AS was_present,
                 ROW_NUMBER() OVER (ORDER BY cd2.class_date DESC) AS rn
          FROM cohort_dates cd2
          LEFT JOIN present p2 ON p2.student_id = cs.id AND p2.class_date = cd2.class_date
        ) seq
        WHERE rn <= (
          SELECT MIN(rn2) - 1
          FROM (
            SELECT ROW_NUMBER() OVER (ORDER BY cd3.class_date DESC) AS rn2,
                   CASE WHEN p3.student_id IS NOT NULL THEN 1 ELSE 0 END AS was_present
            FROM cohort_dates cd3
            LEFT JOIN present p3 ON p3.student_id = cs.id AND p3.class_date = cd3.class_date
          ) inner_seq
          WHERE was_present = 1
        )
        AND was_present = 0
      )::INT AS consecutive_abs
    FROM cohort_students cs
  )
  SELECT
    cs.id,
    cs.name,
    cs.phone,
    COUNT(p.class_date)                                               AS total_present,
    v_total_classes                                                   AS total_classes,
    ROUND(COUNT(p.class_date)::NUMERIC / v_total_classes * 100, 1)  AS presence_pct,
    COALESCE(sl3.last_3, '[]'::jsonb)                                AS last_3,
    COALESCE(con.consecutive_abs, 0)                                 AS consecutive_abs
  FROM cohort_students cs
  LEFT JOIN present p ON p.student_id = cs.id
  LEFT JOIN student_last3 sl3 ON sl3.student_id = cs.id
  LEFT JOIN consecutive con ON con.student_id = cs.id
  GROUP BY cs.id, cs.name, cs.phone, sl3.last_3, con.consecutive_abs
  ORDER BY presence_pct ASC;
END;
$$;
