-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-019 Story 19.6 — Anomaly Detection
-- Detecta variações >X% week-over-week em métricas-chave + Slack alert.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.anomaly_alerts (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  metric text NOT NULL,
  current_value numeric NOT NULL,
  previous_value numeric NOT NULL,
  variation_pct numeric NOT NULL,
  threshold_pct numeric NOT NULL,
  direction text CHECK (direction IN ('up', 'down')),
  cohort_id uuid REFERENCES public.cohorts(id),
  alerted_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_anomaly_alerts_recent
  ON public.anomaly_alerts (alerted_at DESC);

ALTER TABLE public.anomaly_alerts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cs_admin_read_anomalies" ON public.anomaly_alerts FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));
GRANT SELECT ON public.anomaly_alerts TO authenticated;

-- ─── Detecção: comparar metric atual (7d) vs previous (7d antes) ─────────
CREATE OR REPLACE FUNCTION public.detect_anomalies()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_threshold numeric := 25.0;  -- 25% variação dispara alerta
  v_alerts integer := 0;
  v_metric RECORD;
BEGIN
  -- Metric 1: respostas survey 7d vs 7d anterior
  WITH
    current_period AS (SELECT COUNT(*) AS n FROM public.survey_responses
                       WHERE submitted_at > now() - interval '7 days'),
    previous_period AS (SELECT COUNT(*) AS n FROM public.survey_responses
                        WHERE submitted_at > now() - interval '14 days'
                          AND submitted_at <= now() - interval '7 days')
  SELECT cp.n AS curr, pp.n AS prev,
         CASE WHEN pp.n > 0 THEN ((cp.n - pp.n)::numeric / pp.n) * 100 ELSE 0 END AS variation
  INTO v_metric FROM current_period cp, previous_period pp;

  IF v_metric.prev >= 5 AND ABS(v_metric.variation) >= v_threshold THEN
    INSERT INTO public.anomaly_alerts (metric, current_value, previous_value, variation_pct, threshold_pct, direction)
    VALUES ('survey_responses_7d', v_metric.curr, v_metric.prev, v_metric.variation, v_threshold,
            CASE WHEN v_metric.variation > 0 THEN 'up' ELSE 'down' END);

    PERFORM public.send_slack_alert(
      'anomaly_responses_' || to_char(now(), 'YYYYMMDD'),
      format('📊 Anomalia respostas survey: %s últimos 7d (vs %s anterior). Variação %s%%.',
             v_metric.curr, v_metric.prev, ROUND(v_metric.variation, 1))
    );
    v_alerts := v_alerts + 1;
  END IF;

  -- Metric 2: dispatches 7d vs 7d anterior
  WITH
    current_period AS (SELECT COUNT(*) AS n FROM public.survey_links WHERE created_at > now() - interval '7 days'),
    previous_period AS (SELECT COUNT(*) AS n FROM public.survey_links
                        WHERE created_at > now() - interval '14 days' AND created_at <= now() - interval '7 days')
  SELECT cp.n AS curr, pp.n AS prev,
         CASE WHEN pp.n > 0 THEN ((cp.n - pp.n)::numeric / pp.n) * 100 ELSE 0 END AS variation
  INTO v_metric FROM current_period cp, previous_period pp;

  IF v_metric.prev >= 5 AND ABS(v_metric.variation) >= v_threshold THEN
    INSERT INTO public.anomaly_alerts (metric, current_value, previous_value, variation_pct, threshold_pct, direction)
    VALUES ('dispatches_7d', v_metric.curr, v_metric.prev, v_metric.variation, v_threshold,
            CASE WHEN v_metric.variation > 0 THEN 'up' ELSE 'down' END);

    PERFORM public.send_slack_alert(
      'anomaly_dispatches_' || to_char(now(), 'YYYYMMDD'),
      format('📤 Anomalia dispatches: %s últimos 7d (vs %s anterior). Variação %s%%.',
             v_metric.curr, v_metric.prev, ROUND(v_metric.variation, 1))
    );
    v_alerts := v_alerts + 1;
  END IF;

  RETURN jsonb_build_object('alerts_created', v_alerts, 'at', now(), 'threshold_pct', v_threshold);
END $$;

GRANT EXECUTE ON FUNCTION public.detect_anomalies() TO service_role;

-- pg_cron: roda diário 09:00 BRT (12:00 UTC)
SELECT cron.schedule(
  'epic019-anomaly-detection',
  '0 12 * * *',
  $$ SELECT public.detect_anomalies(); $$
) WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'epic019-anomaly-detection');

COMMENT ON FUNCTION public.detect_anomalies() IS
  'EPIC-019 Story 19.6: detecta variações >25% week-over-week em respostas + dispatches. Slack alert + insert em anomaly_alerts.';
