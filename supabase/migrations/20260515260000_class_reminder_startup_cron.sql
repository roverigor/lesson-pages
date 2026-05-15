-- ============================================================================
-- Class Reminder Startup Alert — Cron diário 09:00 BRT (12:00 UTC)
-- Date: 2026-05-15
-- ============================================================================
-- Chama edge function class-reminder-startup-alert pra detectar classes
-- acontecendo hoje com reminder_enabled=false e pingar Slack.
-- ============================================================================

BEGIN;

INSERT INTO public.app_config (key, value)
VALUES ('class_reminder_startup_alert_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/class-reminder-startup-alert')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

SELECT cron.schedule(
  'class-reminder-startup-alert',
  '0 12 * * *',  -- 09:00 BRT (UTC-3)
  $$
  DO $inner$
  DECLARE
    fn_url  TEXT;
    svc_key TEXT;
  BEGIN
    SELECT value INTO fn_url  FROM public.app_config WHERE key = 'class_reminder_startup_alert_url';
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
