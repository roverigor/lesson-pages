-- ============================================================================
-- Class Reminders Cron — Tick job a cada 5min
-- Date: 2026-05-15
-- ============================================================================
-- Calls dispatch-class-reminders edge function.
-- Holiday detection acontece NA prepare-class-reminders (preview time), não no cron.
-- ============================================================================

BEGIN;

-- Ensure app_config has our function URL
INSERT INTO public.app_config (key, value)
VALUES ('class_reminders_dispatch_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/dispatch-class-reminders')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Schedule cron tick every 5 minutes
SELECT cron.schedule(
  'class-reminders-tick',
  '*/5 * * * *',
  $$
  DO $inner$
  DECLARE
    fn_url  TEXT;
    svc_key TEXT;
  BEGIN
    SELECT value INTO fn_url  FROM public.app_config WHERE key = 'class_reminders_dispatch_url';
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
