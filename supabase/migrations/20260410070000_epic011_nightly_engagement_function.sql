-- ═══════════════════════════════════════
-- EPIC-011: Fix nightly_engagement_sync cron
-- Uses app_config table (same as process_zoom_import_queue)
-- instead of current_setting('app.*') which doesn't work in Supabase
-- ═══════════════════════════════════════

-- Wrapper function that reads from app_config and calls the edge function
CREATE OR REPLACE FUNCTION public.trigger_nightly_engagement_sync()
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
    RAISE WARNING 'nightly_engagement_sync: zoom_attendance_url not set in app_config';
    RETURN;
  END IF;

  IF svc_key IS NULL OR svc_key = '' THEN
    RAISE WARNING 'nightly_engagement_sync: supabase_service_key not set in app_config';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := fn_url,
    body    := '{"action":"nightly_engagement_sync"}'::jsonb,
    headers := json_build_object(
      'Authorization', 'Bearer ' || svc_key,
      'Content-Type',  'application/json'
    )::jsonb
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.trigger_nightly_engagement_sync() TO service_role;

-- Remove old cron job created by 20260410040000 (used current_setting)
SELECT cron.unschedule('nightly-engagement-sync');

-- Create corrected cron job calling the function
SELECT cron.schedule(
  'nightly-engagement-sync',
  '0 2 * * *',
  $$ SELECT public.trigger_nightly_engagement_sync(); $$
);
