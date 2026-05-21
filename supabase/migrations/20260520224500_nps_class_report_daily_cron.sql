-- ═══════════════════════════════════════════════════════════════════════════
-- NPS Class Report Daily — cron + schema
--
-- Adiciona:
--   1. Columns report_sent_at + report_evolution_message_id em jobs
--   2. Cron diário 12:00 UTC (09:00 BRT) chamando nps-class-report-daily
--   3. App_config URL da function
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.nps_class_dispatch_jobs
  ADD COLUMN IF NOT EXISTS report_sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS report_evolution_message_id TEXT;

CREATE INDEX IF NOT EXISTS idx_nps_jobs_report_pending
  ON public.nps_class_dispatch_jobs (finished_at)
  WHERE report_sent_at IS NULL AND status IN ('sent','partial');

COMMENT ON COLUMN public.nps_class_dispatch_jobs.report_sent_at IS
  'When daily MD report was sent to WA group. NULL = pending report.';

-- Insert URL config
INSERT INTO public.app_config (key, value)
VALUES ('nps_class_report_daily_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/nps-class-report-daily')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Schedule daily 12:00 UTC (09:00 BRT)
SELECT cron.schedule(
  'nps-class-report-daily',
  '0 12 * * *',
  $$
  DO $inner$
  DECLARE
    fn_url  TEXT;
    svc_key TEXT;
  BEGIN
    SELECT value INTO fn_url  FROM public.app_config WHERE key = 'nps_class_report_daily_url';
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
