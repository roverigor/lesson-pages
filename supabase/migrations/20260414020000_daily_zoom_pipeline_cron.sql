-- ═══════════════════════════════════════════════════════════
-- Story 12.2 — Daily Zoom Pipeline Cron
-- pg_cron at 03:00 AM UTC-3 (06:00 UTC) → daily_pipeline action
-- ═══════════════════════════════════════════════════════════

-- Wrapper function: reads URL/key from app_config, calls edge function
CREATE OR REPLACE FUNCTION public.trigger_daily_zoom_pipeline()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  fn_url   TEXT;
  svc_key  TEXT;
BEGIN
  SELECT value INTO fn_url  FROM public.app_config WHERE key = 'zoom_attendance_url';
  SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';

  IF fn_url IS NULL OR fn_url = '' THEN
    RAISE WARNING 'daily_zoom_pipeline: zoom_attendance_url not set in app_config';
    RETURN;
  END IF;

  IF svc_key IS NULL OR svc_key = '' THEN
    RAISE WARNING 'daily_zoom_pipeline: supabase_service_key not set in app_config';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := fn_url,
    body    := '{"action":"daily_pipeline"}'::jsonb,
    headers := json_build_object(
      'Authorization', 'Bearer ' || svc_key,
      'Content-Type',  'application/json'
    )::jsonb
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.trigger_daily_zoom_pipeline() TO service_role;

-- Schedule: 03:00 AM BRT = 06:00 UTC
SELECT cron.schedule(
  'daily-zoom-pipeline',
  '0 6 * * *',
  $$ SELECT public.trigger_daily_zoom_pipeline(); $$
);
