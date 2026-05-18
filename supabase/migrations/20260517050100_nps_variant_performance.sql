-- ═══════════════════════════════════════════════════════════════════════════
-- NPS.P.11 — Variant performance ranking
-- Per-variant aggregation: sends + opens + responses + avg score.
-- Suggests deactivation when bottom variant is <30% of top performer.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.nps_variant_performance(
  p_days INT DEFAULT 30
)
RETURNS TABLE (
  variant_id      TEXT,
  channel         TEXT,
  active          BOOLEAN,
  sends_count     INT,
  open_count      INT,
  open_rate       NUMERIC,
  response_count  INT,
  response_rate   NUMERIC,
  avg_score       NUMERIC,
  performance_score NUMERIC,
  rank_in_channel INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_days INT := LEAST(GREATEST(p_days, 7), 365);
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  -- Variants seeded with empty performance show 0s but still rank
  RETURN QUERY
  WITH variant_sends AS (
    SELECT
      v.id AS variant_id,
      v.channel,
      v.active,
      -- Sends: count of dispatched jobs that picked this variant id
      (SELECT COUNT(*) FROM public.nps_class_dispatch_jobs j
        WHERE (j.variant_group_id = v.id OR j.variant_dm_id = v.id)
          AND j.finished_at > NOW() - (v_days || ' days')::interval
          AND j.status IN ('sent','partial')
      )::int AS sends_count,
      -- Opens (group: links + opens; dm: same)
      (SELECT COALESCE(SUM(
         (SELECT COUNT(*) FROM public.dispatch_link_opens o
           WHERE o.source = 'nps_class_link' AND o.dispatch_id = l.id)), 0)::int
        FROM public.nps_class_links l
        JOIN public.nps_class_dispatch_jobs j ON j.id = l.dispatch_job_id
        WHERE (j.variant_group_id = v.id OR j.variant_dm_id = v.id)
          AND l.mode = v.channel
          AND j.finished_at > NOW() - (v_days || ' days')::interval
      ) AS open_count,
      -- Responses + avg score
      (SELECT COUNT(*)::int FROM public.class_nps_responses r
        JOIN public.nps_class_links l ON l.id = r.link_id
        JOIN public.nps_class_dispatch_jobs j ON j.id = l.dispatch_job_id
        WHERE (j.variant_group_id = v.id OR j.variant_dm_id = v.id)
          AND l.mode = v.channel
          AND r.submitted_at > NOW() - (v_days || ' days')::interval
      ) AS response_count,
      (SELECT ROUND(AVG(r.nps_score)::numeric, 2) FROM public.class_nps_responses r
        JOIN public.nps_class_links l ON l.id = r.link_id
        JOIN public.nps_class_dispatch_jobs j ON j.id = l.dispatch_job_id
        WHERE (j.variant_group_id = v.id OR j.variant_dm_id = v.id)
          AND l.mode = v.channel
          AND r.submitted_at > NOW() - (v_days || ' days')::interval
      ) AS avg_score
    FROM public.nps_message_variants v
  ),
  with_rates AS (
    SELECT
      *,
      CASE WHEN sends_count > 0
        THEN ROUND(100.0 * open_count / sends_count, 1) ELSE 0 END AS open_rate,
      CASE WHEN sends_count > 0
        THEN ROUND(100.0 * response_count / sends_count, 1) ELSE 0 END AS response_rate,
      -- Composite performance score: 60% response rate + 40% open rate, scaled
      CASE WHEN sends_count > 0
        THEN ROUND((0.6 * (100.0 * response_count / sends_count) + 0.4 * (100.0 * open_count / sends_count))::numeric, 1)
        ELSE 0 END AS performance_score
    FROM variant_sends
  )
  SELECT
    w.variant_id,
    w.channel,
    w.active,
    w.sends_count,
    w.open_count,
    w.open_rate,
    w.response_count,
    w.response_rate,
    w.avg_score,
    w.performance_score,
    DENSE_RANK() OVER (PARTITION BY w.channel ORDER BY w.performance_score DESC, w.sends_count DESC)::int AS rank_in_channel
  FROM with_rates w
  ORDER BY w.channel, w.performance_score DESC, w.sends_count DESC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.nps_variant_performance(INT) TO authenticated;

COMMENT ON FUNCTION public.nps_variant_performance IS
  'NPS.P.11: variant ranking by composite score (60% response_rate + 40% open_rate). Returns rank per channel + suggestion threshold.';
