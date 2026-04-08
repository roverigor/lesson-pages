-- ═══════════════════════════════════════
-- EPIC-011 Story 11.7: engagement_daily_ranking
-- Daily composite score per student per cohort
-- Score: attendance × 3 + wa_messages + zoom_chat_messages
-- ═══════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.engagement_daily_ranking (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id           UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  cohort_id            UUID NOT NULL REFERENCES public.cohorts(id) ON DELETE CASCADE,
  ref_date             DATE NOT NULL,
  wa_messages          INT NOT NULL DEFAULT 0,
  zoom_chat_messages   INT NOT NULL DEFAULT 0,
  attendance_count     INT NOT NULL DEFAULT 0,
  engagement_score     INT NOT NULL DEFAULT 0,
  UNIQUE (student_id, cohort_id, ref_date)
);

CREATE INDEX IF NOT EXISTS idx_engagement_ranking_cohort_date
  ON public.engagement_daily_ranking (cohort_id, ref_date DESC);

CREATE INDEX IF NOT EXISTS idx_engagement_ranking_student_date
  ON public.engagement_daily_ranking (student_id, ref_date DESC);

-- RLS
ALTER TABLE public.engagement_daily_ranking ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role_all_engagement_ranking"
  ON public.engagement_daily_ranking
  FOR ALL
  USING (true)
  WITH CHECK (true);

GRANT ALL ON public.engagement_daily_ranking TO service_role;
GRANT SELECT ON public.engagement_daily_ranking TO authenticated;

-- pg_cron: nightly engagement sync at 02:00 AM UTC
-- This calls zoom-attendance with action=nightly_engagement_sync
-- Requires app.zoom_attendance_url and app.supabase_service_key to be set
-- (run manually via Supabase SQL editor if not already set)
SELECT cron.schedule(
  'nightly-engagement-sync',
  '0 2 * * *',
  $$
    SELECT net.http_post(
      url     := current_setting('app.zoom_attendance_url', true),
      body    := '{"action":"nightly_engagement_sync"}'::jsonb,
      headers := json_build_object(
        'Authorization', 'Bearer ' || current_setting('app.supabase_service_key', true),
        'Content-Type',  'application/json'
      )::jsonb
    );
  $$
);
