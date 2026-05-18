-- ═══════════════════════════════════════════════════════════════════════════
-- Opção B — Repoint nps_results_* RPCs to nps_results_unified VIEW.
-- Adds source filter so dashboard can split auto_class vs manual_survey.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── Summary ───
CREATE OR REPLACE FUNCTION public.nps_results_summary(
  p_filters JSONB DEFAULT '{}'::jsonb
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_total     INT;
  v_promoters INT;
  v_passives  INT;
  v_detractors INT;
  v_avg       NUMERIC;
  v_nps       NUMERIC;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE score >= 9),
    COUNT(*) FILTER (WHERE score BETWEEN 7 AND 8),
    COUNT(*) FILTER (WHERE score <= 6),
    ROUND(AVG(score)::numeric, 2)
  INTO v_total, v_promoters, v_passives, v_detractors, v_avg
  FROM public.nps_results_unified r
  WHERE
    (p_filters->>'date_from' IS NULL OR r.submitted_at >= (p_filters->>'date_from')::timestamptz)
    AND (p_filters->>'date_to' IS NULL OR r.submitted_at <  (p_filters->>'date_to')::timestamptz)
    AND (p_filters->>'cohort_id' IS NULL OR r.cohort_id = (p_filters->>'cohort_id')::uuid)
    AND (p_filters->>'class_id' IS NULL OR r.class_id = (p_filters->>'class_id')::uuid)
    AND (p_filters->>'mode' IS NULL OR r.mode = p_filters->>'mode')
    AND (p_filters->>'source' IS NULL OR r.source = p_filters->>'source');

  v_nps := CASE WHEN v_total > 0
    THEN ROUND(100.0 * (v_promoters - v_detractors) / v_total, 1)
    ELSE NULL END;

  RETURN jsonb_build_object(
    'total', v_total,
    'promoters', v_promoters,
    'passives', v_passives,
    'detractors', v_detractors,
    'avg_score', v_avg,
    'nps_score', v_nps,
    'promoter_pct', CASE WHEN v_total > 0 THEN ROUND(100.0 * v_promoters / v_total, 1) ELSE 0 END,
    'passive_pct',  CASE WHEN v_total > 0 THEN ROUND(100.0 * v_passives / v_total, 1) ELSE 0 END,
    'detractor_pct',CASE WHEN v_total > 0 THEN ROUND(100.0 * v_detractors / v_total, 1) ELSE 0 END
  );
END;
$$;

-- ─── Trend ───
CREATE OR REPLACE FUNCTION public.nps_results_trend(
  p_weeks INT DEFAULT 12,
  p_filters JSONB DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  week_start DATE,
  total      INT,
  promoters  INT,
  detractors INT,
  nps        NUMERIC,
  avg_score  NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_weeks INT := LEAST(GREATEST(p_weeks, 1), 52);
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT
      date_trunc('week', r.submitted_at AT TIME ZONE 'America/Sao_Paulo')::date AS wk,
      r.score
    FROM public.nps_results_unified r
    WHERE r.submitted_at >= (CURRENT_DATE - (v_weeks || ' weeks')::interval)
      AND (p_filters->>'cohort_id' IS NULL OR r.cohort_id = (p_filters->>'cohort_id')::uuid)
      AND (p_filters->>'class_id' IS NULL OR r.class_id = (p_filters->>'class_id')::uuid)
      AND (p_filters->>'source' IS NULL OR r.source = p_filters->>'source')
  )
  SELECT
    wk,
    COUNT(*)::int,
    COUNT(*) FILTER (WHERE score >= 9)::int,
    COUNT(*) FILTER (WHERE score <= 6)::int,
    CASE WHEN COUNT(*) > 0
      THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE score >= 9) - COUNT(*) FILTER (WHERE score <= 6)) / COUNT(*), 1)
      ELSE NULL END,
    ROUND(AVG(score)::numeric, 2)
  FROM base
  GROUP BY wk
  ORDER BY wk;
END;
$$;

-- ─── By cohort ───
CREATE OR REPLACE FUNCTION public.nps_results_by_cohort(
  p_filters JSONB DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  cohort_id   UUID,
  cohort_name TEXT,
  total       INT,
  nps         NUMERIC,
  avg_score   NUMERIC,
  detractors  INT,
  promoters   INT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    r.cohort_id,
    c.name,
    COUNT(*)::int,
    CASE WHEN COUNT(*) > 0
      THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE r.score >= 9) - COUNT(*) FILTER (WHERE r.score <= 6)) / COUNT(*), 1)
      ELSE NULL END,
    ROUND(AVG(r.score)::numeric, 2),
    COUNT(*) FILTER (WHERE r.score <= 6)::int,
    COUNT(*) FILTER (WHERE r.score >= 9)::int
  FROM public.nps_results_unified r
  LEFT JOIN public.cohorts c ON c.id = r.cohort_id
  WHERE
    (p_filters->>'date_from' IS NULL OR r.submitted_at >= (p_filters->>'date_from')::timestamptz)
    AND (p_filters->>'date_to' IS NULL OR r.submitted_at <  (p_filters->>'date_to')::timestamptz)
    AND (p_filters->>'source' IS NULL OR r.source = p_filters->>'source')
  GROUP BY r.cohort_id, c.name
  ORDER BY COUNT(*) DESC;
END;
$$;

-- ─── By class ───
CREATE OR REPLACE FUNCTION public.nps_results_by_class(
  p_filters JSONB DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  class_id   UUID,
  class_name TEXT,
  total      INT,
  nps        NUMERIC,
  avg_score  NUMERIC
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    r.class_id,
    cl.name,
    COUNT(*)::int,
    CASE WHEN COUNT(*) > 0
      THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE r.score >= 9) - COUNT(*) FILTER (WHERE r.score <= 6)) / COUNT(*), 1)
      ELSE NULL END,
    ROUND(AVG(r.score)::numeric, 2)
  FROM public.nps_results_unified r
  LEFT JOIN public.classes cl ON cl.id = r.class_id
  WHERE
    r.class_id IS NOT NULL
    AND (p_filters->>'date_from' IS NULL OR r.submitted_at >= (p_filters->>'date_from')::timestamptz)
    AND (p_filters->>'date_to' IS NULL OR r.submitted_at <  (p_filters->>'date_to')::timestamptz)
    AND (p_filters->>'cohort_id' IS NULL OR r.cohort_id = (p_filters->>'cohort_id')::uuid)
    AND (p_filters->>'source' IS NULL OR r.source = p_filters->>'source')
  GROUP BY r.class_id, cl.name
  ORDER BY COUNT(*) DESC
  LIMIT 50;
END;
$$;

-- ─── Comments (now includes source column) ───
CREATE OR REPLACE FUNCTION public.nps_results_comments(
  p_filters JSONB DEFAULT '{}'::jsonb,
  p_limit INT DEFAULT 100
)
RETURNS TABLE (
  response_id    UUID,
  source         TEXT,
  submitted_at   TIMESTAMPTZ,
  nps_score      INT,
  bucket         TEXT,
  comment        TEXT,
  mode           TEXT,
  name_provided  TEXT,
  cohort_name    TEXT,
  class_name     TEXT,
  student_name   TEXT,
  student_phone  TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_limit INT := LEAST(GREATEST(p_limit, 1), 500);
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    r.response_id,
    r.source,
    r.submitted_at,
    r.score,
    CASE
      WHEN r.score >= 9 THEN 'promoter'
      WHEN r.score >= 7 THEN 'passive'
      ELSE 'detractor'
    END,
    r.comment,
    r.mode,
    r.name_provided,
    co.name,
    cl.name,
    CASE WHEN r.student_id IS NOT NULL THEN s.name ELSE NULL END,
    CASE WHEN r.student_id IS NOT NULL THEN s.phone ELSE NULL END
  FROM public.nps_results_unified r
  LEFT JOIN public.cohorts co ON co.id = r.cohort_id
  LEFT JOIN public.classes cl ON cl.id = r.class_id
  LEFT JOIN public.students s ON s.id = r.student_id
  WHERE
    (p_filters->>'date_from' IS NULL OR r.submitted_at >= (p_filters->>'date_from')::timestamptz)
    AND (p_filters->>'date_to' IS NULL OR r.submitted_at <  (p_filters->>'date_to')::timestamptz)
    AND (p_filters->>'cohort_id' IS NULL OR r.cohort_id = (p_filters->>'cohort_id')::uuid)
    AND (p_filters->>'class_id' IS NULL OR r.class_id = (p_filters->>'class_id')::uuid)
    AND (p_filters->>'source' IS NULL OR r.source = p_filters->>'source')
    AND (p_filters->>'bucket' IS NULL OR
         (p_filters->>'bucket' = 'detractor' AND r.score <= 6) OR
         (p_filters->>'bucket' = 'passive' AND r.score BETWEEN 7 AND 8) OR
         (p_filters->>'bucket' = 'promoter' AND r.score >= 9))
    AND (p_filters->>'only_with_comment' IS NULL OR
         (p_filters->>'only_with_comment')::boolean = false OR
         (r.comment IS NOT NULL AND length(trim(r.comment)) > 0))
  ORDER BY r.submitted_at DESC
  LIMIT v_limit;
END;
$$;

-- ─── Filter options now extended to include source list ───
CREATE OR REPLACE FUNCTION public.nps_results_filter_options()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cohorts JSONB;
  v_classes JSONB;
  v_sources JSONB;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'name', name) ORDER BY name), '[]'::jsonb)
    INTO v_cohorts
  FROM public.cohorts
  WHERE EXISTS (SELECT 1 FROM public.nps_results_unified r WHERE r.cohort_id = cohorts.id);

  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'name', name) ORDER BY name), '[]'::jsonb)
    INTO v_classes
  FROM public.classes
  WHERE EXISTS (SELECT 1 FROM public.nps_results_unified r WHERE r.class_id = classes.id);

  SELECT jsonb_agg(DISTINCT source) INTO v_sources FROM public.nps_results_unified;

  RETURN jsonb_build_object(
    'cohorts', v_cohorts,
    'classes', v_classes,
    'sources', COALESCE(v_sources, '[]'::jsonb)
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.nps_results_summary(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nps_results_trend(INT, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nps_results_by_cohort(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nps_results_by_class(JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nps_results_comments(JSONB, INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.nps_results_filter_options() TO authenticated;

COMMIT;
