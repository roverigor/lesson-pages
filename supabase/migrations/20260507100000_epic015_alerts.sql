-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-015 Story 15.E — Alerts SQL Functions (impl real)
--
-- Substitui placeholder de alert_slack_if_unhealthy() criado em 15.A worker.sql.
-- Detecta 4 condições e envia Slack alerts via pg_net → send-slack-alert edge function.
--
-- Refs: NFR-10, NFR-12, AC-18 spec.md
-- ═══════════════════════════════════════════════════════════════════════════

-- Helper: send_slack_alert via edge function send-slack-alert
CREATE OR REPLACE FUNCTION send_slack_alert(p_key TEXT, p_message TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_url TEXT := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/send-slack-alert';
  v_service_key TEXT;
BEGIN
  -- Obtém service role key do GUC (configurado via supabase secrets ou ALTER DATABASE SET)
  v_service_key := current_setting('app.service_role_key', true);

  IF v_service_key IS NULL OR v_service_key = '' THEN
    -- Fallback: registra em alert_history mesmo assim (throttle funciona) + log
    RAISE NOTICE 'EPIC-015 alert [%] (service_role_key não configurado): %', p_key, p_message;
  ELSE
    -- HTTP call via pg_net
    PERFORM net.http_post(
      url := v_url,
      body := jsonb_build_object('message', p_message, 'key', p_key),
      headers := jsonb_build_object(
        'Authorization', 'Bearer ' || v_service_key,
        'Content-Type', 'application/json'
      )
    );
  END IF;

  -- Sempre registra em alert_history (throttle)
  INSERT INTO alert_history (alert_key, last_sent_at)
  VALUES (p_key, now())
  ON CONFLICT (alert_key) DO UPDATE SET last_sent_at = now();
END;
$$;

COMMENT ON FUNCTION send_slack_alert(TEXT, TEXT) IS
  'EPIC-015 Story 15.E: dispara alert via pg_net → send-slack-alert edge function. Throttle via alert_history.';

-- ═══════════════════════════════════════════════════════════════════════════
-- alert_slack_if_unhealthy — implementação real (substitui placeholder 15.A)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION alert_slack_if_unhealthy()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_total            INTEGER;
  v_failed           INTEGER;
  v_fail_rate        NUMERIC;
  v_pending_old      INTEGER;
  v_callback_failures INTEGER;
  v_last_processed   TIMESTAMPTZ;
  v_received_count   INTEGER;
  v_message          TEXT;
BEGIN
  -- ─── 1. Webhook AC fail rate últimas 24h ───────────────────────────────
  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE status = 'failed')
  INTO v_total, v_failed
  FROM ac_purchase_events
  WHERE created_at > now() - INTERVAL '24 hours';

  v_fail_rate := CASE WHEN v_total > 0 THEN v_failed::NUMERIC / v_total * 100 ELSE 0 END;

  IF v_fail_rate > 10 AND v_total >= 5 AND NOT recently_alerted('webhook_fail_rate', INTERVAL '1 hour') THEN
    v_message := format(
      '⚠️ AC Webhook fail rate %s%% últimas 24h (%s/%s falharam)',
      round(v_fail_rate, 1), v_failed, v_total
    );
    PERFORM send_slack_alert('webhook_fail_rate', v_message);
  END IF;

  -- ─── 2. Pendentes não resolvidos > 24h (NFR-12 SLA) ────────────────────
  SELECT COUNT(*) INTO v_pending_old
  FROM pending_student_assignments
  WHERE resolved_at IS NULL
    AND created_at < now() - INTERVAL '24 hours';

  IF v_pending_old > 0 AND NOT recently_alerted('pending_overdue', INTERVAL '6 hours') THEN
    v_message := format(
      '⏰ %s aluno(s) pendente(s) há mais de 24h aguardando resolução CS — verificar /cs/pending',
      v_pending_old
    );
    PERFORM send_slack_alert('pending_overdue', v_message);
  END IF;

  -- ─── 3. Worker pg_cron travado (eventos received não processados) ──────
  SELECT MAX(processed_at) INTO v_last_processed
  FROM ac_purchase_events
  WHERE status = 'processed';

  SELECT COUNT(*) INTO v_received_count
  FROM ac_purchase_events
  WHERE status = 'received';

  IF v_received_count > 0
     AND (v_last_processed IS NULL OR v_last_processed < now() - INTERVAL '5 minutes')
     AND NOT recently_alerted('worker_stuck', INTERVAL '30 minutes') THEN
    v_message := format(
      '🚨 Worker pg_cron parece travado — %s eventos received não processados (último processed: %s)',
      v_received_count,
      COALESCE(v_last_processed::TEXT, 'never')
    );
    PERFORM send_slack_alert('worker_stuck', v_message);
  END IF;

  -- ─── 4. Callback AC failures (>5 falhas última 1h) ─────────────────────
  SELECT COUNT(*) INTO v_callback_failures
  FROM ac_dispatch_callbacks
  WHERE status = 'failed'
    AND last_attempt_at > now() - INTERVAL '1 hour';

  IF v_callback_failures > 5 AND NOT recently_alerted('callback_failures', INTERVAL '1 hour') THEN
    v_message := format(
      '❌ %s callbacks AC falharam última hora (3 retries esgotados — verificar /cs/integrations Eventos)',
      v_callback_failures
    );
    PERFORM send_slack_alert('callback_failures', v_message);
  END IF;
END;
$$;

COMMENT ON FUNCTION alert_slack_if_unhealthy() IS
  'EPIC-015 Story 15.E: detecta 4 condições de saúde (webhook fail rate / pending overdue / worker stuck / callback failures) e envia alert Slack throttled.';

-- ═══════════════════════════════════════════════════════════════════════════
-- recently_alerted — atualiza versão para aceitar interval custom
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION recently_alerted(p_key TEXT, p_within INTERVAL DEFAULT INTERVAL '1 hour')
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM alert_history
    WHERE alert_key = p_key
      AND last_sent_at > now() - p_within
  );
$$;

-- ═══════════════════════════════════════════════════════════════════════════
-- Setup app.service_role_key (ONE-TIME ALTER DATABASE)
-- ═══════════════════════════════════════════════════════════════════════════
-- IMPORTANTE: rodar manualmente após migration:
--
--   ALTER DATABASE postgres SET app.service_role_key = '<service_role_jwt>';
--
-- OU configurar via Supabase Dashboard → Database → Configuration → Custom Settings.
-- Sem isso, send_slack_alert() apenas registra em alert_history (sem chamada HTTP).
-- ═══════════════════════════════════════════════════════════════════════════
