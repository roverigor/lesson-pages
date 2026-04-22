-- ═══════════════════════════════════════════════════════════════════════
-- Class Reminders — expand Slack to all weekdays + add WhatsApp dispatch
-- ═══════════════════════════════════════════════════════════════════════
-- Change 1: slack-class-reminder cron Tue/Fri → Mon-Fri (1-5)
-- Change 2: register whatsapp-class-reminder cron (Mon-Fri) via Evolution API
--
-- Both edge functions internally filter by class_mentors.weekday,
-- so dias sem escalação não geram mensagens (custo adicional nulo).
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Store edge function URLs in app_config ───
INSERT INTO app_config (key, value)
VALUES ('slack_reminder_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/send-slack-reminder')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

INSERT INTO app_config (key, value)
VALUES ('whatsapp_reminder_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/send-whatsapp-reminder')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- ─── 2. Reschedule Slack reminder: Mon-Fri at 10:00 BRT (13:00 UTC) ───
SELECT cron.unschedule('slack-class-reminder')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'slack-class-reminder');

SELECT cron.schedule(
  'slack-class-reminder',
  '0 13 * * 1-5',
  $$
  DO $inner$
  DECLARE
    fn_url  TEXT;
    svc_key TEXT;
  BEGIN
    SELECT value INTO fn_url  FROM public.app_config WHERE key = 'slack_reminder_url';
    SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';
    IF fn_url IS NOT NULL THEN
      PERFORM net.http_post(
        url     := fn_url,
        body    := '{"dry_run": false}'::jsonb,
        headers := json_build_object(
          'Authorization', 'Bearer ' || COALESCE(svc_key,''),
          'Content-Type',  'application/json'
        )::jsonb
      );
    END IF;
  END;
  $inner$;
  $$
);

-- ─── 3. Schedule WhatsApp reminder: Mon-Fri at 10:00 BRT (13:00 UTC) ───
SELECT cron.unschedule('whatsapp-class-reminder')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'whatsapp-class-reminder');

SELECT cron.schedule(
  'whatsapp-class-reminder',
  '0 13 * * 1-5',
  $$
  DO $inner$
  DECLARE
    fn_url  TEXT;
    svc_key TEXT;
  BEGIN
    SELECT value INTO fn_url  FROM public.app_config WHERE key = 'whatsapp_reminder_url';
    SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';
    IF fn_url IS NOT NULL THEN
      PERFORM net.http_post(
        url     := fn_url,
        body    := '{"dry_run": false}'::jsonb,
        headers := json_build_object(
          'Authorization', 'Bearer ' || COALESCE(svc_key,''),
          'Content-Type',  'application/json'
        )::jsonb
      );
    END IF;
  END;
  $inner$;
  $$
);
