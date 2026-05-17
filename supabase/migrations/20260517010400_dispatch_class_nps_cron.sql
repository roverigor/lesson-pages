-- ═══════════════════════════════════════════════════════════════════════════
-- P3 — Cron tick (*/5 min) for dispatch-class-nps
-- Function is internally gated by nps_dispatch_enabled flag (safe when off).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- Register endpoint URL (override if needed)
INSERT INTO public.app_config (key, value)
VALUES ('dispatch_class_nps_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/dispatch-class-nps')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Unschedule any prior version (idempotent)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dispatch-class-nps-tick') THEN
    PERFORM cron.unschedule('dispatch-class-nps-tick');
  END IF;
END $$;

-- Schedule every 5 min
SELECT cron.schedule(
  'dispatch-class-nps-tick',
  '*/5 * * * *',
  $$
  DO $inner$
  DECLARE
    fn_url  TEXT;
    svc_key TEXT;
  BEGIN
    SELECT value INTO fn_url  FROM public.app_config WHERE key = 'dispatch_class_nps_url';
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
