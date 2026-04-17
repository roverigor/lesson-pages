-- ═══════════════════════════════════════
-- pg_cron: Auto-dispatch Slack reminders on class days
-- Calls send-slack-reminder edge function at 10:00 BRT (13:00 UTC)
-- on Tuesdays and Fridays.
-- Uses app_config for URL and service key (same pattern as zoom-absence-alert).
-- ═══════════════════════════════════════

-- ─── 1. Store the edge function URL in app_config ───
INSERT INTO app_config (key, value)
VALUES ('slack_reminder_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/send-slack-reminder')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- ─── 2. Remove old job if exists ───
SELECT cron.unschedule('slack-class-reminder')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'slack-class-reminder'
);

-- ─── 3. Schedule: 10:00 BRT = 13:00 UTC, Tuesdays (2) and Fridays (5) ───
SELECT cron.schedule(
  'slack-class-reminder',
  '0 13 * * 2,5',
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
