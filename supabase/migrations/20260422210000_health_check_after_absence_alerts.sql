-- ═══════════════════════════════════════════════════════════════════════
-- Fix pipeline-health-check timing bug
-- ═══════════════════════════════════════════════════════════════════════
-- Previous schedule: 0 9 * * * (06:00 BRT) — rodava ANTES do zoom-absence-alert
-- (21:00 UTC / 18:00 BRT), causando falso positivo "Alerta de Ausência NÃO executou hoje"
-- todos os dias úteis.
--
-- New schedule: 0 22 * * * (22:00 UTC / 19:00 BRT) — 1h após absence_alerts,
-- e após todos os outros jobs monitorados (daily_pipeline 06 UTC, wa_sync 07 UTC).
-- ═══════════════════════════════════════════════════════════════════════

SELECT cron.unschedule('pipeline-health-check')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'pipeline-health-check');

SELECT cron.schedule(
  'pipeline-health-check',
  '0 22 * * *',
  $$ SELECT public.trigger_pipeline_health_check(); $$
);
