-- ═══════════════════════════════════════════════════════════
-- Story 12.6 — Pipeline Health Alerts
-- pg_cron at 06:00 AM UTC-3 (09:00 UTC) → health_check action
-- ═══════════════════════════════════════════════════════════

-- Wrapper function: reads URL/key from app_config, calls edge function
CREATE OR REPLACE FUNCTION public.trigger_pipeline_health_check()
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
    RAISE WARNING 'pipeline_health_check: zoom_attendance_url not set in app_config';
    RETURN;
  END IF;

  IF svc_key IS NULL OR svc_key = '' THEN
    RAISE WARNING 'pipeline_health_check: supabase_service_key not set in app_config';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := fn_url,
    body    := '{"action":"health_check"}'::jsonb,
    headers := json_build_object(
      'Authorization', 'Bearer ' || svc_key,
      'Content-Type',  'application/json'
    )::jsonb
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.trigger_pipeline_health_check() TO service_role;

-- Schedule: 06:00 AM BRT = 09:00 UTC
SELECT cron.schedule(
  'pipeline-health-check',
  '0 9 * * *',
  $$ SELECT public.trigger_pipeline_health_check(); $$
);
