-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-020 Story 20.1a — Engagement Engine Foundation
-- 3 tabelas (signals + scores + feedback) + worker function + backfill 90d.
-- Baseado em ADR-017 decisões finais Aria.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── engagement_signals (raw events, append-only) ───────────────────────
CREATE TABLE IF NOT EXISTS public.engagement_signals (
  id uuid DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  cohort_id_at_event uuid REFERENCES public.cohorts(id),
  signal_type text NOT NULL CHECK (signal_type IN (
    'zoom_attendance', 'manual_attendance', 'survey_response',
    'meta_link_click', 'login_painel'
  )),
  signal_value numeric(4,3) NOT NULL CHECK (signal_value BETWEEN 0 AND 1),
  occurred_at timestamptz NOT NULL,
  meta jsonb,
  source_record_id uuid,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (id, occurred_at)
);

CREATE INDEX IF NOT EXISTS idx_signals_student_time
  ON public.engagement_signals (student_id, occurred_at DESC);
CREATE INDEX IF NOT EXISTS idx_signals_type_student
  ON public.engagement_signals (signal_type, student_id, occurred_at DESC);

ALTER TABLE public.engagement_signals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cs_admin_read_signals" ON public.engagement_signals FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));
GRANT SELECT ON public.engagement_signals TO authenticated;
GRANT INSERT ON public.engagement_signals TO service_role;

-- ─── student_engagement_scores ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.student_engagement_scores (
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  cohort_id uuid REFERENCES public.cohorts(id),
  score_30d numeric(4,3) NOT NULL DEFAULT 0,
  prob_churn numeric(4,3) NOT NULL DEFAULT 0,
  bucket text NOT NULL DEFAULT 'cold_start' CHECK (bucket IN (
    'engaged', 'light_at_risk', 'heavy_at_risk',
    'disengaged', 'never_engaged', 'cold_start'
  )),
  signals_breakdown jsonb,
  last_engagement_at timestamptz,
  data_quality_flag text DEFAULT 'valid',
  needs_recompute boolean DEFAULT false,
  computed_at timestamptz DEFAULT now(),
  PRIMARY KEY (student_id, cohort_id)
);

CREATE INDEX IF NOT EXISTS idx_engagement_scores_bucket
  ON public.student_engagement_scores (bucket, prob_churn DESC);
CREATE INDEX IF NOT EXISTS idx_engagement_scores_dirty
  ON public.student_engagement_scores (needs_recompute) WHERE needs_recompute = true;

ALTER TABLE public.student_engagement_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cs_admin_read_scores" ON public.student_engagement_scores FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));
GRANT SELECT ON public.student_engagement_scores TO authenticated;

-- ─── Decay weight function (step function — Aria approved) ──────────────
CREATE OR REPLACE FUNCTION public.engagement_decay_weight(p_occurred_at timestamptz)
RETURNS numeric LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN now() - p_occurred_at <= interval '7 days'  THEN 1.00
    WHEN now() - p_occurred_at <= interval '14 days' THEN 0.70
    WHEN now() - p_occurred_at <= interval '30 days' THEN 0.40
    WHEN now() - p_occurred_at <= interval '60 days' THEN 0.15
    ELSE 0.05
  END;
$$;

-- ─── Worker: recompute scores ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.recompute_engagement_scores()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_count integer := 0;
BEGIN
  SET LOCAL statement_timeout = '120s';

  -- Pra cada student × cohort, computa score baseado em signals
  WITH per_student AS (
    SELECT
      s.id AS student_id,
      sc.cohort_id,
      COALESCE(SUM(es.signal_value * public.engagement_decay_weight(es.occurred_at))
               FILTER (WHERE es.signal_type IN ('zoom_attendance', 'manual_attendance')) / NULLIF(COUNT(*) FILTER (WHERE es.signal_type IN ('zoom_attendance', 'manual_attendance')), 0), 0) AS att_score,
      COALESCE(SUM(es.signal_value * public.engagement_decay_weight(es.occurred_at))
               FILTER (WHERE es.signal_type = 'survey_response') / 3.0, 0) AS srv_score,
      MAX(es.occurred_at) AS last_engagement,
      COUNT(*) AS signal_count,
      s.is_valid_student
    FROM public.students s
    LEFT JOIN public.student_cohorts sc ON sc.student_id = s.id
    LEFT JOIN public.engagement_signals es ON es.student_id = s.id
    GROUP BY s.id, sc.cohort_id, s.is_valid_student
  )
  INSERT INTO public.student_engagement_scores (
    student_id, cohort_id, score_30d, prob_churn, bucket,
    signals_breakdown, last_engagement_at, data_quality_flag,
    needs_recompute, computed_at
  )
  SELECT
    student_id,
    cohort_id,
    LEAST(1.0, 0.50 * att_score + 0.30 * LEAST(srv_score, 1) + 0.20 * 0)::numeric(4,3) AS score,
    LEAST(1.0, GREATEST(0.0, 1 - 1/(1 + exp(-( (0.50 * att_score + 0.30 * LEAST(srv_score, 1)) * 4 - 2)))))::numeric(4,3) AS prob,
    CASE
      WHEN signal_count = 0 THEN 'never_engaged'
      WHEN last_engagement < now() - interval '14 days' AND signal_count < 3 THEN 'cold_start'
      WHEN (1 - 1/(1 + exp(-( (0.50 * att_score + 0.30 * LEAST(srv_score, 1)) * 4 - 2)))) < 0.20 THEN 'engaged'
      WHEN (1 - 1/(1 + exp(-( (0.50 * att_score + 0.30 * LEAST(srv_score, 1)) * 4 - 2)))) < 0.50 THEN 'light_at_risk'
      WHEN (1 - 1/(1 + exp(-( (0.50 * att_score + 0.30 * LEAST(srv_score, 1)) * 4 - 2)))) < 0.80 THEN 'heavy_at_risk'
      ELSE 'disengaged'
    END,
    jsonb_build_object('attendance', att_score, 'survey', srv_score, 'manual', 0, 'signal_count', signal_count),
    last_engagement,
    CASE WHEN is_valid_student THEN 'valid' ELSE 'fantasma' END,
    false,
    now()
  FROM per_student
  WHERE cohort_id IS NOT NULL
  ON CONFLICT (student_id, cohort_id) DO UPDATE SET
    score_30d = EXCLUDED.score_30d,
    prob_churn = EXCLUDED.prob_churn,
    bucket = EXCLUDED.bucket,
    signals_breakdown = EXCLUDED.signals_breakdown,
    last_engagement_at = EXCLUDED.last_engagement_at,
    data_quality_flag = EXCLUDED.data_quality_flag,
    needs_recompute = false,
    computed_at = now();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('rows_computed', v_count, 'at', now());
END $$;

GRANT EXECUTE ON FUNCTION public.recompute_engagement_scores() TO service_role, authenticated;

-- ─── Backfill signals 90d (zoom attendance + survey responses) ──────────
INSERT INTO public.engagement_signals (student_id, signal_type, signal_value, occurred_at, meta, source_record_id)
SELECT
  student_id,
  CASE WHEN source = 'manual' THEN 'manual_attendance' ELSE 'zoom_attendance' END,
  CASE WHEN duration_minutes >= 15 THEN 1.0 ELSE 0.5 END,
  class_date::timestamptz,
  jsonb_build_object('meeting_id', zoom_meeting_id, 'duration_min', duration_minutes, 'source', source),
  id
FROM public.student_attendance
WHERE class_date > now() - interval '90 days'
ON CONFLICT DO NOTHING;

INSERT INTO public.engagement_signals (student_id, signal_type, signal_value, occurred_at, meta, source_record_id)
SELECT
  student_id,
  'survey_response',
  1.0,
  submitted_at,
  jsonb_build_object('survey_id', survey_id),
  id
FROM public.survey_responses
WHERE submitted_at > now() - interval '90 days'
ON CONFLICT DO NOTHING;

-- ─── Initial compute ────────────────────────────────────────────────────
SELECT public.recompute_engagement_scores();

-- ─── pg_cron: full recompute diário 03:00 ───────────────────────────────
SELECT cron.schedule(
  'epic020-engagement-recompute',
  '0 3 * * *',
  $$ SELECT public.recompute_engagement_scores(); $$
) WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'epic020-engagement-recompute');

COMMENT ON TABLE public.student_engagement_scores IS
  'EPIC-020 Story 20.1a: score per (student, cohort). Recomputed daily 03h via pg_cron.';
