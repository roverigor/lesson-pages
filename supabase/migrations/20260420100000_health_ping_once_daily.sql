-- ═══════════════════════════════════════
-- Reduce Evolution health ping from every 2h to once daily at 09:00 BRT (12:00 UTC)
-- Remove excessive alerting — health check already runs at 06:00 BRT via zoom-attendance.
-- ═══════════════════════════════════════

-- ─── 1. Remove old job ───
SELECT cron.unschedule('evolution-health-ping')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'evolution-health-ping'
);

-- ─── 2. Reschedule: once daily at 12:00 UTC (09:00 BRT) ───
SELECT cron.schedule(
  'evolution-health-ping',
  '0 12 * * *',
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
