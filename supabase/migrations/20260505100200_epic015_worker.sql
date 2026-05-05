-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-015 Story 15.A — Worker Function + pg_cron Jobs + Views (Migration 3/4)
-- Refs: ADR-016 §3 (worker function), §6 (observabilidade)
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. WORKER FUNCTION — process_ac_purchase_events_batch()
-- ═══════════════════════════════════════════════════════════════════════════
-- Pg_cron chama esta função a cada 30s. Processa até 50 eventos por batch.
-- SKIP LOCKED permite múltiplos workers paralelos no futuro sem deadlock.

CREATE OR REPLACE FUNCTION process_ac_purchase_events_batch()
RETURNS TABLE(processed_count INTEGER, failed_count INTEGER) AS $$
DECLARE
  evt RECORD;
  v_proc_count INTEGER := 0;
  v_fail_count INTEGER := 0;
  v_email TEXT;
  v_phone TEXT;
  v_full_name TEXT;
  v_ac_contact_id TEXT;
  v_ac_product_id TEXT;
  v_student_id UUID;
  v_mapping RECORD;
  v_link_id UUID;
  v_token UUID;
BEGIN
  FOR evt IN
    SELECT id, payload
    FROM ac_purchase_events
    WHERE status = 'received'
      AND retry_count < 3
    ORDER BY created_at
    LIMIT 50
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      -- Mark processing
      UPDATE ac_purchase_events
        SET status = 'processing', processing_started_at = now()
        WHERE id = evt.id;

      -- Extract fields from payload (defensive: tolera campos ausentes)
      v_email         := evt.payload->>'email';
      v_phone         := evt.payload->>'phone';
      v_full_name     := COALESCE(evt.payload->>'full_name', evt.payload->>'name', '');
      v_ac_contact_id := evt.payload->>'contact_id';
      v_ac_product_id := evt.payload->>'product_id';

      -- Validar payload mínimo
      IF v_email IS NULL OR v_email = '' THEN
        UPDATE ac_purchase_events
          SET status = 'failed', last_error = 'invalid_payload: email missing', retry_count = retry_count + 1
          WHERE id = evt.id;
        v_fail_count := v_fail_count + 1;
        CONTINUE;
      END IF;

      -- Resolve student: lookup by ac_contact_id ou email
      SELECT id INTO v_student_id FROM students
       WHERE ac_contact_id = v_ac_contact_id
       LIMIT 1;

      IF v_student_id IS NULL AND v_email IS NOT NULL THEN
        -- Tenta por email (fallback)
        SELECT s.id INTO v_student_id FROM students s
         WHERE EXISTS (SELECT 1 FROM students s2 WHERE LOWER(s2.name) = LOWER(v_email))
         LIMIT 1;
      END IF;

      IF v_student_id IS NULL THEN
        -- Cria student novo
        INSERT INTO students (name, phone, ac_contact_id, active, is_mentor)
        VALUES (
          COALESCE(v_full_name, v_email),
          COALESCE(v_phone, ''),
          v_ac_contact_id,
          true,
          false
        )
        RETURNING id INTO v_student_id;
      ELSE
        -- Atualiza ac_contact_id se necessário (idempotente)
        UPDATE students SET ac_contact_id = v_ac_contact_id
         WHERE id = v_student_id AND ac_contact_id IS DISTINCT FROM v_ac_contact_id;
      END IF;

      -- Lookup mapping (HIT path)
      SELECT * INTO v_mapping FROM ac_product_mappings
       WHERE ac_product_id = v_ac_product_id
         AND active = true
       LIMIT 1;

      IF v_mapping.id IS NOT NULL THEN
        -- HIT — vincula cohort + cria survey_link + enfileira dispatch
        INSERT INTO student_cohorts (student_id, cohort_id)
        VALUES (v_student_id, v_mapping.cohort_id)
        ON CONFLICT DO NOTHING;

        -- Cria survey_link com cohort_snapshot + version atual
        v_token := gen_random_uuid();
        INSERT INTO survey_links (
          survey_id, student_id, token, version_id, cohort_snapshot_name, send_status
        )
        SELECT
          v_mapping.survey_id,
          v_student_id,
          v_token,
          s.current_version_id,
          c.name,
          'pending'
        FROM surveys s
        JOIN cohorts c ON c.id = v_mapping.cohort_id
        WHERE s.id = v_mapping.survey_id
        ON CONFLICT (survey_id, student_id) DO NOTHING
        RETURNING id INTO v_link_id;

        -- Dispatch real fica para edge function dispatch-survey (15.B/15.4)
        -- Worker apenas marca como "ready to dispatch"

      ELSE
        -- MISS — fila pendente
        INSERT INTO pending_student_assignments (
          student_id, ac_event_id, reason, ac_payload
        ) VALUES (
          v_student_id,
          evt.id,
          'unknown_product:' || COALESCE(v_ac_product_id, 'null'),
          evt.payload
        );

        -- Slack alert via send_slack_alert (Story 15.E impl)
        BEGIN
          PERFORM send_slack_alert(
            'pending_new_' || evt.id::text,
            format('🆕 Novo aluno pendente: %s (produto AC %s sem mapping)',
                   COALESCE(v_full_name, v_email),
                   COALESCE(v_ac_product_id, 'null'))
          );
        EXCEPTION WHEN OTHERS THEN
          -- send_slack_alert ainda placeholder em 15.E — não falha worker se não existe
          NULL;
        END;
      END IF;

      -- Mark processed
      UPDATE ac_purchase_events
        SET status = 'processed', processed_at = now()
        WHERE id = evt.id;

      v_proc_count := v_proc_count + 1;

    EXCEPTION WHEN OTHERS THEN
      UPDATE ac_purchase_events
        SET status = 'received',
            retry_count = retry_count + 1,
            last_error = LEFT(SQLERRM, 500)
        WHERE id = evt.id;
      v_fail_count := v_fail_count + 1;
    END;
  END LOOP;

  RETURN QUERY SELECT v_proc_count, v_fail_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION process_ac_purchase_events_batch() IS
  'EPIC-015 ADR-016 §3: worker async que processa ac_purchase_events. Resolve student/mapping/cohort + cria survey_link. Chamado por pg_cron a cada 30s.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. PLACEHOLDER FUNCTIONS — recently_alerted() + send_slack_alert()
-- Implementação real em Story 15.E. Placeholder permite worker rodar sem falhar.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION recently_alerted(p_key TEXT, p_within INTERVAL DEFAULT INTERVAL '1 hour')
RETURNS BOOLEAN
LANGUAGE sql
AS $$
  SELECT EXISTS (
    SELECT 1 FROM alert_history
    WHERE alert_key = p_key AND last_sent_at > now() - p_within
  );
$$;

CREATE OR REPLACE FUNCTION send_slack_alert(p_key TEXT, p_message TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Story 15.E implementa chamada HTTP real via pg_net.
  -- V1 placeholder: apenas registra em alert_history para throttle funcionar.
  INSERT INTO alert_history (alert_key, last_sent_at)
  VALUES (p_key, now())
  ON CONFLICT (alert_key) DO UPDATE SET last_sent_at = now();

  -- Log para visibilidade
  RAISE NOTICE 'EPIC-015 alert [%]: %', p_key, p_message;
END;
$$;

CREATE OR REPLACE FUNCTION alert_slack_if_unhealthy()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Placeholder: implementação real em Story 15.E.
  -- V1 NO-OP para que pg_cron não falhe se chamado antes de 15.E.
  RAISE NOTICE 'alert_slack_if_unhealthy() placeholder — Story 15.E implementa lógica real';
END;
$$;

COMMENT ON FUNCTION alert_slack_if_unhealthy() IS
  'EPIC-015 Story 15.A placeholder; Story 15.E implementa detecção de anomalias.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. VIEWS — observabilidade + drill-down aluno
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── ac_integration_health — métricas últimas 24h por hora/status ─────────

CREATE OR REPLACE VIEW ac_integration_health AS
SELECT
  date_trunc('hour', created_at) AS hour,
  status,
  COUNT(*) AS count,
  AVG(EXTRACT(EPOCH FROM (processed_at - created_at))) AS avg_latency_seconds,
  MAX(retry_count) AS max_retries
FROM ac_purchase_events
WHERE created_at > now() - INTERVAL '24 hours'
GROUP BY hour, status
ORDER BY hour DESC;

COMMENT ON VIEW ac_integration_health IS
  'EPIC-015 NFR-10: métricas agregadas eventos AC últimas 24h. Usado em /cs/integrations dashboard + alerts.';

-- ─── student_dispatch_timeline — drill-down aluno (NFR-18) ────────────────

CREATE OR REPLACE VIEW student_dispatch_timeline AS
SELECT
  sl.id                      AS link_id,
  sl.student_id,
  st.name                    AS student_name,
  st.phone                   AS student_phone,
  sv.id                      AS survey_id,
  sv.name                    AS survey_name,
  sv.category                AS survey_category,
  sl.cohort_snapshot_name,
  sl.version_id,
  svv.version_number,
  sl.token,
  sl.meta_message_id,
  sl.send_status,
  sl.sent_at,
  sl.delivered_at,
  sl.read_at,
  sl.used_at,
  sr.submitted_at,
  sl.created_at
FROM survey_links sl
JOIN students st ON st.id = sl.student_id
JOIN surveys sv ON sv.id = sl.survey_id
LEFT JOIN survey_versions svv ON svv.id = sl.version_id
LEFT JOIN survey_responses sr ON sr.link_id = sl.id
ORDER BY sl.sent_at DESC NULLS LAST, sl.created_at DESC;

COMMENT ON VIEW student_dispatch_timeline IS
  'EPIC-015 FR-12/FR-17 NFR-18: timeline aluno-centric com 4 timestamps. Usado em /cs/history drill-down.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. PG_CRON JOBS (4 jobs)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 4.1. process-ac-events — worker a cada 30s ───────────────────────────
-- Usa schedule de 6 campos para suportar segundos (pg_cron 1.4+)

SELECT cron.unschedule('epic015-process-ac-events') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'epic015-process-ac-events'
);

SELECT cron.schedule(
  'epic015-process-ac-events',
  '30 seconds',
  $$ SELECT process_ac_purchase_events_batch(); $$
);

-- ─── 4.2. warmup-edge-functions — a cada 4 minutos ───────────────────────
-- Mantém edge functions quentes (anti-cold-start)

SELECT cron.unschedule('epic015-warmup-edge-functions') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'epic015-warmup-edge-functions'
);

SELECT cron.schedule(
  'epic015-warmup-edge-functions',
  '*/4 * * * *',
  $$
    SELECT net.http_get(url := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/ac-purchase-webhook?warmup=1');
    SELECT net.http_get(url := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/ac-report-dispatch?warmup=1');
    SELECT net.http_get(url := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/meta-delivery-webhook?warmup=1');
  $$
);

-- ─── 4.3. alert-ac-health — a cada 15 minutos ────────────────────────────

SELECT cron.unschedule('epic015-alert-ac-health') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'epic015-alert-ac-health'
);

SELECT cron.schedule(
  'epic015-alert-ac-health',
  '*/15 * * * *',
  $$ SELECT alert_slack_if_unhealthy(); $$
);

-- ─── 4.4. purge-old-ac-events — diário 3am UTC ───────────────────────────
-- LGPD CON-7: retenção 90 dias

SELECT cron.unschedule('epic015-purge-old-ac-events') WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'epic015-purge-old-ac-events'
);

SELECT cron.schedule(
  'epic015-purge-old-ac-events',
  '0 3 * * *',
  $$
    DELETE FROM ac_purchase_events
    WHERE created_at < now() - INTERVAL '90 days'
      AND status IN ('processed','duplicate','failed');
  $$
);

-- ═══════════════════════════════════════════════════════════════════════════
-- Fim Migration 3/4 — Workers + Crons + Views
-- Próxima: 20260505100300_epic015_backfill.sql
-- ═══════════════════════════════════════════════════════════════════════════
