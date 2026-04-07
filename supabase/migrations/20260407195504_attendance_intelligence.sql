-- ═══════════════════════════════════════
-- Stories 6.2, 6.3, 6.4: Attendance Intelligence
-- Functions: get_attendance_summary, get_weekly_attendance,
--            get_consecutive_absences_needing_alert
-- Table: zoom_absence_alerts
-- ═══════════════════════════════════════

-- ─── zoom_absence_alerts (Story 6.4) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.zoom_absence_alerts (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id        UUID NOT NULL REFERENCES public.students(id),
  cohort_id         UUID NOT NULL,
  consecutive_count INT NOT NULL,
  message_text      TEXT,
  whatsapp_status   TEXT DEFAULT 'pending',
  error_message     TEXT,
  sent_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_zoom_absence_alerts_student
  ON public.zoom_absence_alerts (student_id, cohort_id, sent_at DESC);

GRANT ALL ON public.zoom_absence_alerts TO service_role;

-- ─── whatsapp_alerts_enabled column on students (Story 6.4) ──────────────
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS whatsapp_alerts_enabled BOOLEAN NOT NULL DEFAULT true;

-- ─── get_attendance_summary(cohort_id) (Stories 6.2, 6.3) ────────────────
-- Returns per-student attendance rate for a given cohort.
-- Crosses student_attendance (present records) with the full set of class dates
-- derived from zoom_meetings for that cohort.

CREATE OR REPLACE FUNCTION public.get_attendance_summary(p_cohort_id UUID)
RETURNS TABLE (
  student_id         UUID,
  student_name       TEXT,
  phone              TEXT,
  total_present      BIGINT,
  total_classes      BIGINT,
  presence_pct       NUMERIC,
  last_3             JSONB,   -- [{ date, present, duration_minutes }]
  consecutive_abs    INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_total_classes BIGINT;
BEGIN
  -- Count distinct class dates for this cohort
  SELECT COUNT(DISTINCT sa.class_date)
  INTO v_total_classes
  FROM public.student_attendance sa
  WHERE sa.zoom_meeting_id IN (
    SELECT zm.zoom_meeting_id FROM public.zoom_meetings zm WHERE zm.cohort_id = p_cohort_id
  );

  IF v_total_classes = 0 THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH cohort_students AS (
    -- Students enrolled in this cohort
    SELECT s.id, s.name, s.phone
    FROM public.students s
    WHERE s.cohort_id = p_cohort_id
      AND (s.active IS NULL OR s.active = true)
  ),
  cohort_dates AS (
    -- All class dates for this cohort
    SELECT DISTINCT sa.class_date
    FROM public.student_attendance sa
    WHERE sa.zoom_meeting_id IN (
      SELECT zm.zoom_meeting_id FROM public.zoom_meetings zm WHERE zm.cohort_id = p_cohort_id
    )
    ORDER BY sa.class_date DESC
  ),
  present AS (
    -- Presence records per student in this cohort
    SELECT
      sa.student_id,
      sa.class_date,
      sa.duration_minutes
    FROM public.student_attendance sa
    WHERE sa.zoom_meeting_id IN (
      SELECT zm.zoom_meeting_id FROM public.zoom_meetings zm WHERE zm.cohort_id = p_cohort_id
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
    -- Count consecutive absences from most recent date backwards
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

GRANT EXECUTE ON FUNCTION public.get_attendance_summary(UUID) TO service_role, authenticated;

-- ─── get_weekly_attendance(cohort_id, weeks) (Story 6.2) ─────────────────
-- Returns weekly attendance rate for a cohort over the last N weeks.

CREATE OR REPLACE FUNCTION public.get_weekly_attendance(p_cohort_id UUID, p_weeks INT DEFAULT 8)
RETURNS TABLE (
  week_start    DATE,
  week_label    TEXT,
  total_present BIGINT,
  total_slots   BIGINT,
  presence_pct  NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH cohort_students AS (
    SELECT id FROM public.students
    WHERE cohort_id = p_cohort_id AND (active IS NULL OR active = true)
  ),
  cohort_meetings AS (
    SELECT zoom_meeting_id, start_time::DATE AS class_date
    FROM public.zoom_meetings
    WHERE cohort_id = p_cohort_id
  ),
  weekly AS (
    SELECT
      date_trunc('week', cm.class_date)::DATE AS week_start,
      COUNT(DISTINCT sa.student_id)           AS total_present,
      (SELECT COUNT(*) FROM cohort_students) *
        COUNT(DISTINCT cm.class_date)         AS total_slots
    FROM cohort_meetings cm
    LEFT JOIN public.student_attendance sa
      ON sa.zoom_meeting_id = cm.zoom_meeting_id
     AND sa.student_id IN (SELECT id FROM cohort_students)
    WHERE cm.class_date >= CURRENT_DATE - (p_weeks * 7)
    GROUP BY date_trunc('week', cm.class_date)::DATE
  )
  SELECT
    w.week_start,
    TO_CHAR(w.week_start, 'DD/MM') || '–' || TO_CHAR(w.week_start + 6, 'DD/MM') AS week_label,
    w.total_present,
    w.total_slots,
    CASE WHEN w.total_slots > 0
         THEN ROUND(w.total_present::NUMERIC / w.total_slots * 100, 1)
         ELSE 0
    END AS presence_pct
  FROM weekly w
  ORDER BY w.week_start DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_weekly_attendance(UUID, INT) TO service_role, authenticated;

-- ─── get_consecutive_absences_needing_alert() (Story 6.4) ────────────────
-- Returns students with 2+ consecutive absences who haven't been alerted yet
-- for this cycle (no alert in last 7 days for same consecutive_count).

CREATE OR REPLACE FUNCTION public.get_consecutive_absences_needing_alert()
RETURNS TABLE (
  student_id        UUID,
  student_name      TEXT,
  phone             TEXT,
  cohort_id         UUID,
  cohort_name       TEXT,
  consecutive_count INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
BEGIN
  RETURN QUERY
  WITH cohorts AS (
    SELECT DISTINCT cohort_id FROM public.zoom_meetings WHERE cohort_id IS NOT NULL
  ),
  summaries AS (
    SELECT
      s.student_id,
      s.student_name,
      s.phone,
      c.cohort_id,
      COALESCE(co.name, 'Turma') AS cohort_name,
      s.consecutive_abs
    FROM cohorts c
    CROSS JOIN LATERAL public.get_attendance_summary(c.cohort_id) s
    LEFT JOIN public.cohorts co ON co.id = c.cohort_id
    WHERE s.consecutive_abs >= 2
      AND s.phone IS NOT NULL
      AND s.phone != ''
  )
  SELECT
    su.student_id,
    su.student_name,
    su.phone,
    su.cohort_id,
    su.cohort_name,
    su.consecutive_abs
  FROM summaries su
  WHERE NOT EXISTS (
    SELECT 1 FROM public.zoom_absence_alerts a
    WHERE a.student_id = su.student_id
      AND a.cohort_id  = su.cohort_id
      AND a.sent_at    > now() - INTERVAL '7 days'
  )
  AND EXISTS (
    SELECT 1 FROM public.students st
    WHERE st.id = su.student_id
      AND st.whatsapp_alerts_enabled = true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_consecutive_absences_needing_alert() TO service_role;

-- ─── pg_cron: daily absence alerts at 18:00 BRT (21:00 UTC) ──────────────
SELECT cron.schedule(
  'zoom-absence-alert',
  '0 21 * * *',
  $$ SELECT net.http_post(
    url     := current_setting('app.zoom_attendance_url', true),
    body    := '{"action":"send_absence_alerts"}'::jsonb,
    headers := json_build_object(
      'Authorization', 'Bearer ' || current_setting('app.supabase_service_key', true),
      'Content-Type',  'application/json'
    )::jsonb
  ); $$
);
