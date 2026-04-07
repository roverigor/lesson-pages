-- ═══════════════════════════════════════
-- App config table — replaces ALTER DATABASE SET app.*
-- Supabase doesn't allow custom database parameters via Management API
-- so we use a config table instead.
-- ═══════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.app_config (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

GRANT ALL ON public.app_config TO service_role;

-- Disable RLS so the pg_cron function (running as superuser) can read it
ALTER TABLE public.app_config DISABLE ROW LEVEL SECURITY;

-- Rewrite process_zoom_import_queue() to read from app_config table
CREATE OR REPLACE FUNCTION public.process_zoom_import_queue()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  r        RECORD;
  fn_url   TEXT;
  svc_key  TEXT;
BEGIN
  SELECT value INTO fn_url  FROM public.app_config WHERE key = 'zoom_attendance_url';
  SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';

  IF fn_url IS NULL OR fn_url = '' THEN
    RAISE WARNING 'zoom_import_queue: zoom_attendance_url not set in app_config';
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
    UPDATE public.zoom_import_queue
    SET status = 'processing', attempt_count = attempt_count + 1
    WHERE id = r.id;

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

-- Rewrite get_consecutive_absences_needing_alert() to also use app_config
-- (no change needed — it doesn't use settings)

GRANT EXECUTE ON FUNCTION public.process_zoom_import_queue() TO service_role;

-- Also rewrite the pg_cron absence alert to use app_config
-- First drop and recreate with config table approach
SELECT cron.unschedule('zoom-absence-alert') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'zoom-absence-alert'
);

SELECT cron.schedule(
  'zoom-absence-alert',
  '0 21 * * *',
  $cron$
  DO $inner$
  DECLARE
    fn_url  TEXT;
    svc_key TEXT;
  BEGIN
    SELECT value INTO fn_url  FROM public.app_config WHERE key = 'zoom_attendance_url';
    SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';
    IF fn_url IS NOT NULL THEN
      PERFORM net.http_post(
        url     := fn_url,
        body    := '{"action":"send_absence_alerts"}'::jsonb,
        headers := json_build_object(
          'Authorization', 'Bearer ' || COALESCE(svc_key,''),
          'Content-Type',  'application/json'
        )::jsonb
      );
    END IF;
  END;
  $inner$;
  $cron$
);
