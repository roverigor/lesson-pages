-- ═══════════════════════════════════════
-- Story 6.1: zoom_import_queue
-- Auto-import Zoom participants after meeting.ended webhook
-- ═══════════════════════════════════════

-- Queue table
CREATE TABLE IF NOT EXISTS public.zoom_import_queue (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  meeting_id     TEXT NOT NULL,
  zoom_uuid      TEXT,
  host_email     TEXT,
  topic          TEXT,
  status         TEXT NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','processing','done','skipped','error','failed')),
  attempt_count  INT NOT NULL DEFAULT 0,
  error_message  TEXT,
  process_after  TIMESTAMPTZ NOT NULL DEFAULT now() + INTERVAL '5 minutes',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  processed_at   TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_zoom_import_queue_status
  ON public.zoom_import_queue (status, process_after)
  WHERE status IN ('pending','error');

-- RLS: admin-only
ALTER TABLE public.zoom_import_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_all_zoom_import_queue"
  ON public.zoom_import_queue
  FOR ALL
  USING ((auth.jwt() ->> 'role') = 'admin');

-- Grant service_role full access (edge functions bypass RLS anyway)
GRANT ALL ON public.zoom_import_queue TO service_role;

-- ─── pg_cron job: auto-process queue every 2 minutes ───
-- Uses pg_net to call the zoom-attendance edge function
-- Requires: pg_net extension enabled (already active in Supabase)
-- Requires: pg_cron extension enabled (already active - used by ghost-session-cleanup)

-- Store edge function URL as a DB setting (set via Supabase SQL editor or migration)
-- ALTER DATABASE postgres SET app.zoom_attendance_url = 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/zoom-attendance';
-- ALTER DATABASE postgres SET app.supabase_service_key = '<SERVICE_ROLE_KEY>';
-- NOTE: the above lines are commented out because they contain secrets.
-- Run them manually via Supabase SQL editor ONCE after deploying this migration.

-- pg_cron worker function
CREATE OR REPLACE FUNCTION public.process_zoom_import_queue()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r RECORD;
  fn_url TEXT;
  svc_key TEXT;
BEGIN
  fn_url  := current_setting('app.zoom_attendance_url', true);
  svc_key := current_setting('app.supabase_service_key', true);

  IF fn_url IS NULL OR fn_url = '' THEN
    RAISE WARNING 'zoom_import_queue: app.zoom_attendance_url not set';
    RETURN;
  END IF;

  FOR r IN
    SELECT id, meeting_id
    FROM public.zoom_import_queue
    WHERE status IN ('pending', 'error')
      AND attempt_count < 3
      AND process_after <= now()
    ORDER BY created_at
    LIMIT 5
  LOOP
    -- Mark as processing to prevent double-processing
    UPDATE public.zoom_import_queue
    SET status = 'processing', attempt_count = attempt_count + 1
    WHERE id = r.id;

    -- Fire HTTP request to edge function (async via pg_net)
    PERFORM net.http_post(
      url     := fn_url,
      body    := json_build_object('meeting_id', r.meeting_id)::jsonb,
      headers := json_build_object(
        'Authorization', 'Bearer ' || COALESCE(svc_key, ''),
        'Content-Type',  'application/json'
      )::jsonb
    );
  END LOOP;
END;
$$;

GRANT EXECUTE ON FUNCTION public.process_zoom_import_queue() TO service_role;

-- Schedule the worker (every 2 minutes)
SELECT cron.schedule(
  'zoom-auto-import',
  '*/2 * * * *',
  $$ SELECT public.process_zoom_import_queue(); $$
);

-- ─── Callback: mark queue item done/error after edge function responds ───
-- The edge function will call this RPC after importing to update queue status

CREATE OR REPLACE FUNCTION public.update_zoom_import_queue(
  p_meeting_id   TEXT,
  p_status       TEXT,  -- 'done' | 'error' | 'skipped'
  p_error_msg    TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.zoom_import_queue
  SET
    status        = CASE
                      WHEN p_status = 'error' AND attempt_count >= 3 THEN 'failed'
                      ELSE p_status
                    END,
    error_message = p_error_msg,
    processed_at  = now()
  WHERE id = (
    SELECT id FROM public.zoom_import_queue
    WHERE meeting_id = p_meeting_id AND status = 'processing'
    ORDER BY created_at DESC
    LIMIT 1
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.update_zoom_import_queue(TEXT, TEXT, TEXT) TO service_role;
