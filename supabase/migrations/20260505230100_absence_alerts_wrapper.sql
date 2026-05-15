-- ═══════════════════════════════════════════════════════════════════════════
-- Wrapper function send_absence_alerts_now()
--
-- Bug original: cron job zoom-absence-alert dependia de GUCs
-- (app.zoom_attendance_url + app.supabase_service_key) que Supabase não permite
-- setar via ALTER DATABASE pra namespace `app.*` (permission denied 42501).
--
-- Fix: wrapper function lê service_role_key de private.config (já criada pra
-- alerts EPIC-015) + URL hardcoded da edge function zoom-attendance.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.send_absence_alerts_now()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_url TEXT := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/zoom-attendance';
  v_service_key TEXT;
  v_request_id BIGINT;
  v_alert_count INT;
BEGIN
  -- Lê service_role_key de private.config (mesmo padrão de send_slack_alert EPIC-015)
  SELECT value INTO v_service_key FROM private.config WHERE key = 'service_role_key';

  IF v_service_key IS NULL OR v_service_key = '' THEN
    RAISE NOTICE 'send_absence_alerts_now: service_role_key não configurado em private.config';
    RETURN jsonb_build_object('error', 'service_role_key not configured');
  END IF;

  -- Verifica quantos alertas seriam enviados
  SELECT COUNT(*) INTO v_alert_count FROM public.get_consecutive_absences_needing_alert();

  IF v_alert_count = 0 THEN
    RETURN jsonb_build_object('alerts_pending', 0, 'message', 'no alerts to send');
  END IF;

  -- Dispara edge function via pg_net
  SELECT net.http_post(
    url     := v_url,
    body    := '{"action":"send_absence_alerts"}'::jsonb,
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'Content-Type',  'application/json'
    )
  ) INTO v_request_id;

  RETURN jsonb_build_object(
    'alerts_pending', v_alert_count,
    'request_id', v_request_id,
    'dispatched_at', now()
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.send_absence_alerts_now() TO service_role;

COMMENT ON FUNCTION public.send_absence_alerts_now() IS
  'Wrapper que dispara edge function zoom-attendance pra envio de absence alerts. Lê service_role_key de private.config (não depende GUC).';

-- ═══════════════════════════════════════════════════════════════════════════
-- Atualizar cron job pra chamar wrapper (em vez de http_post inline com GUC)
-- ═══════════════════════════════════════════════════════════════════════════

SELECT cron.unschedule('zoom-absence-alert');

SELECT cron.schedule(
  'zoom-absence-alert',
  '0 21 * * *',  -- 21:00 UTC = 18:00 BRT
  $$ SELECT public.send_absence_alerts_now(); $$
);
