-- ═══════════════════════════════════════════════════════════════════════════
-- P3 — NPS post-class dispatch jobs queue
-- Idempotent. One job per (cohort, class_id, session_date).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.nps_class_dispatch_jobs (
  id                          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id                    UUID REFERENCES public.classes(id) ON DELETE SET NULL,
  cohort_id                   UUID NOT NULL REFERENCES public.cohorts(id) ON DELETE CASCADE,
  session_date                DATE NOT NULL,
  zoom_meeting_id             TEXT,
  status                      TEXT NOT NULL DEFAULT 'pending'
                              CHECK (status IN ('pending','in_progress','sent','partial','skipped','failed')),
  scheduled_at                TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  started_at                  TIMESTAMPTZ,
  finished_at                 TIMESTAMPTZ,
  group_send_status           TEXT CHECK (group_send_status IN ('sent','skipped','failed','not_applicable')),
  group_send_error            TEXT,
  group_evolution_message_id  TEXT,
  dm_sent_count               INT NOT NULL DEFAULT 0,
  dm_failed_count             INT NOT NULL DEFAULT 0,
  dm_skipped_count            INT NOT NULL DEFAULT 0,
  total_eligible_students     INT,
  error_detail                TEXT,
  variant_group_id            TEXT,
  variant_dm_id               TEXT,
  metadata                    JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at                  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Idempotency: never duplicate active jobs for same triple
CREATE UNIQUE INDEX IF NOT EXISTS uq_nps_job_per_class_session_active
  ON public.nps_class_dispatch_jobs (cohort_id, COALESCE(class_id, '00000000-0000-0000-0000-000000000000'::uuid), session_date)
  WHERE status NOT IN ('skipped','failed');

-- Cron tick lookup
CREATE INDEX IF NOT EXISTS idx_nps_job_pending_due
  ON public.nps_class_dispatch_jobs (scheduled_at)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_nps_job_cohort_date
  ON public.nps_class_dispatch_jobs (cohort_id, session_date DESC);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.set_nps_job_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_nps_job_updated_at ON public.nps_class_dispatch_jobs;
CREATE TRIGGER trg_nps_job_updated_at
  BEFORE UPDATE ON public.nps_class_dispatch_jobs
  FOR EACH ROW EXECUTE FUNCTION public.set_nps_job_updated_at();

-- RLS: service role full, admin read
ALTER TABLE public.nps_class_dispatch_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS nps_jobs_service_all ON public.nps_class_dispatch_jobs;
CREATE POLICY nps_jobs_service_all ON public.nps_class_dispatch_jobs
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS nps_jobs_admin_read ON public.nps_class_dispatch_jobs;
CREATE POLICY nps_jobs_admin_read ON public.nps_class_dispatch_jobs
  FOR SELECT TO authenticated
  USING ((auth.jwt() ->> 'user_metadata')::jsonb ->> 'role' = 'admin');

COMMENT ON TABLE public.nps_class_dispatch_jobs IS
  'P3: queue of post-class NPS dispatches. Inserted by enqueue_nps_class_dispatch after Zoom meeting.ended.';
