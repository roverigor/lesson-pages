-- ═══════════════════════════════════════
-- pg_cron: Evolution API Health Ping (every 2 hours, 8h-22h BRT)
-- Calls evolution-health-ping edge function to verify WhatsApp connectivity.
-- Alerts Igor via Slack if Evolution API is unreachable or disconnected.
-- ═══════════════════════════════════════

-- ─── 1. Store the edge function URL in app_config ───
INSERT INTO app_config (key, value)
VALUES ('evolution_health_ping_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/evolution-health-ping')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- ─── 2. Remove old job if exists ───
SELECT cron.unschedule('evolution-health-ping')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'evolution-health-ping'
);

-- ─── 3. Schedule: every 2 hours between 11:00-01:00 UTC (8h-22h BRT) ───
-- 11,13,15,17,19,21,23,01 UTC = 8,10,12,14,16,18,20,22 BRT
SELECT cron.schedule(
  'evolution-health-ping',
  '0 11,13,15,17,19,21,23,1 * * *',
  $$
  DO $inner$
  DECLARE
    fn_url  TEXT;
    svc_key TEXT;
  BEGIN
    SELECT value INTO fn_url  FROM public.app_config WHERE key = 'evolution_health_ping_url';
    SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';
    IF fn_url IS NOT NULL THEN
      PERFORM net.http_post(
        url     := fn_url,
        body    := '{}'::jsonb,
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
