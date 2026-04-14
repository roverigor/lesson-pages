-- ═══════════════════════════════════════════════════════════
-- Story 12.1 — Automation Tracking Infrastructure
-- Creates automation_runs table + log_automation_step helper
-- ═══════════════════════════════════════════════════════════

-- ─── ENUM TYPES ──────────────────────────────────────────
DO $$ BEGIN
  CREATE TYPE automation_run_type AS ENUM ('daily_pipeline', 'wa_sync', 'recording_notification', 'health_check');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE TYPE automation_run_status AS ENUM ('running', 'success', 'error');
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- ─── TABLE ───────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS automation_runs (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  run_type          automation_run_type NOT NULL,
  step_name         TEXT NOT NULL,
  started_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  finished_at       TIMESTAMPTZ,
  status            automation_run_status NOT NULL DEFAULT 'running',
  records_processed INT DEFAULT 0,
  records_created   INT DEFAULT 0,
  records_failed    INT DEFAULT 0,
  error_message     TEXT,
  metadata          JSONB DEFAULT '{}'::jsonb
);

-- ─── INDEXES ─────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_automation_runs_type_started
  ON automation_runs (run_type, started_at DESC);

CREATE INDEX IF NOT EXISTS idx_automation_runs_status
  ON automation_runs (status) WHERE status = 'error';

-- ─── RLS ─────────────────────────────────────────────────
ALTER TABLE automation_runs ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read (for dashboard)
CREATE POLICY "Authenticated read automation_runs"
  ON automation_runs FOR SELECT TO authenticated USING (true);

-- Only service_role can write (edge functions / pg_cron)
CREATE POLICY "Service role write automation_runs"
  ON automation_runs FOR ALL TO service_role USING (true) WITH CHECK (true);

-- ─── HELPER FUNCTION ─────────────────────────────────────
CREATE OR REPLACE FUNCTION log_automation_step(
  p_run_type       automation_run_type,
  p_step_name      TEXT,
  p_status         automation_run_status,
  p_processed      INT DEFAULT 0,
  p_created        INT DEFAULT 0,
  p_failed         INT DEFAULT 0,
  p_error          TEXT DEFAULT NULL,
  p_metadata       JSONB DEFAULT '{}'::jsonb
) RETURNS UUID
LANGUAGE plpgsql SECURITY DEFINER
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO automation_runs (
    run_type, step_name, status,
    started_at, finished_at,
    records_processed, records_created, records_failed,
    error_message, metadata
  ) VALUES (
    p_run_type, p_step_name, p_status,
    now(),
    CASE WHEN p_status IN ('success', 'error') THEN now() ELSE NULL END,
    p_processed, p_created, p_failed,
    p_error, p_metadata
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

-- Grant execute to authenticated (edge functions run as authenticated + service_role)
GRANT EXECUTE ON FUNCTION log_automation_step TO authenticated;
GRANT EXECUTE ON FUNCTION log_automation_step TO service_role;

-- ─── COMMENT ─────────────────────────────────────────────
COMMENT ON TABLE automation_runs IS 'Tracks all automation pipeline executions (EPIC-012)';
COMMENT ON FUNCTION log_automation_step IS 'Helper to log a pipeline step result into automation_runs';
