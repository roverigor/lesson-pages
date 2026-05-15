-- ============================================================================
-- Class Reminders Healthcheck — Daily 08:00 BRT (11:00 UTC)
-- Date: 2026-05-15
-- ============================================================================

BEGIN;

INSERT INTO public.app_config (key, value)
VALUES ('class_reminders_healthcheck_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/class-reminders-healthcheck')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

SELECT cron.schedule(
  'class-reminders-healthcheck',
  '0 11 * * *',  -- 08:00 BRT
  $$
  DO $inner$
  DECLARE
    fn_url  TEXT;
    svc_key TEXT;
  BEGIN
    SELECT value INTO fn_url  FROM public.app_config WHERE key = 'class_reminders_healthcheck_url';
    SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';
    IF fn_url IS NOT NULL AND svc_key IS NOT NULL THEN
      PERFORM net.http_post(
        url     := fn_url,
        body    := '{}'::jsonb,
        headers := json_build_object(
          'Authorization', 'Bearer ' || svc_key,
          'Content-Type',  'application/json'
        )::jsonb
      );
    END IF;
  END;
  $inner$;
  $$
);

COMMIT;
