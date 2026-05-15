-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-020 Story 20.6 — Calibration feedback loop
-- + EPIC-019 Story 19.9 — Export pipeline básico
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── engagement_feedback (CS rep marca falso positivo / outcome) ────────
CREATE TABLE IF NOT EXISTS public.engagement_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  cs_user_id uuid REFERENCES auth.users(id),
  predicted_bucket text,
  predicted_prob_churn numeric(4,3),
  actual_outcome text NOT NULL CHECK (actual_outcome IN (
    'recovered', 'churned', 'false_positive', 'irrelevant'
  )),
  notes text,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_engagement_feedback_student
  ON public.engagement_feedback (student_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_engagement_feedback_outcome
  ON public.engagement_feedback (actual_outcome);

ALTER TABLE public.engagement_feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cs_admin_read_feedback" ON public.engagement_feedback FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));
CREATE POLICY "cs_admin_insert_feedback" ON public.engagement_feedback FOR INSERT
  WITH CHECK ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));
GRANT SELECT, INSERT ON public.engagement_feedback TO authenticated;

-- ─── Story 19.9 — Export functions ──────────────────────────────────────
-- Function: export_dashboard_csv() — retorna CSV string consolidado
CREATE OR REPLACE FUNCTION public.export_dashboard_summary(p_days integer DEFAULT 30)
RETURNS jsonb LANGUAGE sql STABLE SECURITY DEFINER AS $$
  WITH stats AS (
    SELECT
      (SELECT COUNT(*) FROM public.v_valid_students) AS total_valid_students,
      (SELECT COUNT(*) FROM public.cohorts WHERE active = true) AS active_cohorts,
      (SELECT COUNT(*) FROM public.surveys WHERE status = 'active') AS active_surveys,
      (SELECT COUNT(*) FROM public.survey_links WHERE created_at > now() - (p_days || ' days')::interval) AS dispatches_period,
      (SELECT COUNT(*) FROM public.survey_responses WHERE submitted_at > now() - (p_days || ' days')::interval) AS responses_period,
      (SELECT COUNT(*) FROM public.pending_student_assignments WHERE resolved_at IS NULL) AS pending_unresolved,
      (SELECT COUNT(*) FROM public.student_engagement_scores WHERE bucket IN ('heavy_at_risk', 'disengaged') AND data_quality_flag = 'valid') AS at_risk_total
  ),
  bucket_dist AS (
    SELECT bucket, COUNT(*) AS n
    FROM public.student_engagement_scores
    WHERE data_quality_flag = 'valid'
    GROUP BY bucket
  )
  SELECT jsonb_build_object(
    'period_days', p_days,
    'generated_at', now(),
    'stats', (SELECT to_jsonb(s) FROM stats s),
    'engagement_buckets', (SELECT jsonb_object_agg(bucket, n) FROM bucket_dist),
    'response_rate_pct', CASE
      WHEN (SELECT dispatches_period FROM stats) > 0
      THEN ROUND(((SELECT responses_period FROM stats)::numeric / (SELECT dispatches_period FROM stats)) * 100, 2)
      ELSE 0
    END
  );
$$;

GRANT EXECUTE ON FUNCTION public.export_dashboard_summary(integer) TO authenticated;

COMMENT ON TABLE public.engagement_feedback IS
  'EPIC-020 Story 20.6: CS rep marca outcome real vs prediction. Calibration loop V2 ML usa esses dados.';

COMMENT ON FUNCTION public.export_dashboard_summary(integer) IS
  'EPIC-019 Story 19.9: snapshot consolidado de KPIs operacionais pra export/integrações externas.';
