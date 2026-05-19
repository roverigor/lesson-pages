-- ═══════════════════════════════════════════════════════════════════════════
-- nps_results_by_survey — labels priorizam form/session name (cohort vai pra meta)
--
-- Antes: "<cohort> · <form>"  → "Cohort Fund T5 · Expectativas"
-- Depois: "<form>"             → "Expectativas"  (cohort em coluna cohort_name separada)
-- ═══════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.nps_results_by_survey(jsonb);

CREATE OR REPLACE FUNCTION public.nps_results_by_survey(
  p_filters JSONB DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  kind          TEXT,
  group_key     TEXT,
  label         TEXT,
  survey_id     UUID,
  class_id      UUID,
  class_name    TEXT,
  class_kind    TEXT,
  cohort_id     UUID,
  cohort_name   TEXT,
  session_date  DATE,
  session_index INT,
  total         INT,
  dm_total      INT,
  group_total   INT,
  nps           NUMERIC,
  dm_nps        NUMERIC,
  group_nps     NUMERIC,
  avg_score     NUMERIC,
  first_at      TIMESTAMPTZ,
  last_at       TIMESTAMPTZ
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
  WITH
  manual AS (
    SELECT
      'manual'::text                                    AS kind,
      r.survey_id::text                                 AS group_key,
      r.survey_id                                       AS survey_id,
      sv.class_id                                       AS class_id,
      cl.name                                           AS class_name,
      cl.kind                                           AS class_kind,
      r.cohort_id                                       AS cohort_id,
      co.name                                           AS cohort_name,
      NULL::date                                        AS session_date,
      NULL::int                                         AS session_index,
      COALESCE(sv.name, 'Formulário sem nome')          AS label,
      COUNT(*)::int                                     AS total,
      COUNT(*) FILTER (WHERE r.mode = 'dm')::int        AS dm_total,
      COUNT(*) FILTER (WHERE r.mode = 'group')::int     AS group_total,
      CASE WHEN COUNT(*) > 0
        THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE r.score >= 9) - COUNT(*) FILTER (WHERE r.score <= 6)) / COUNT(*), 1)
        ELSE NULL END                                   AS nps,
      CASE WHEN COUNT(*) FILTER (WHERE r.mode = 'dm') > 0
        THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE r.score >= 9 AND r.mode = 'dm') - COUNT(*) FILTER (WHERE r.score <= 6 AND r.mode = 'dm')) / COUNT(*) FILTER (WHERE r.mode = 'dm'), 1)
        ELSE NULL END                                   AS dm_nps,
      CASE WHEN COUNT(*) FILTER (WHERE r.mode = 'group') > 0
        THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE r.score >= 9 AND r.mode = 'group') - COUNT(*) FILTER (WHERE r.score <= 6 AND r.mode = 'group')) / COUNT(*) FILTER (WHERE r.mode = 'group'), 1)
        ELSE NULL END                                   AS group_nps,
      ROUND(AVG(r.score)::numeric, 2)                   AS avg_score,
      MIN(r.submitted_at)                               AS first_at,
      MAX(r.submitted_at)                               AS last_at
    FROM public.nps_results_unified r
    LEFT JOIN public.surveys sv ON sv.id = r.survey_id
    LEFT JOIN public.cohorts co ON co.id = r.cohort_id
    LEFT JOIN public.classes cl ON cl.id = sv.class_id
    WHERE r.source = 'manual_survey'
      AND r.survey_id IS NOT NULL
      AND (p_filters->>'date_from' IS NULL OR r.submitted_at >= (p_filters->>'date_from')::timestamptz)
      AND (p_filters->>'date_to'   IS NULL OR r.submitted_at <  (p_filters->>'date_to')::timestamptz)
      AND (p_filters->>'cohort_id' IS NULL OR r.cohort_id = (p_filters->>'cohort_id')::uuid)
      AND (p_filters->>'source'    IS NULL OR p_filters->>'source' = 'manual_survey')
    GROUP BY r.survey_id, sv.name, sv.class_id, cl.name, cl.kind, r.cohort_id, co.name
  ),

  auto_agg AS (
    SELECT
      r.class_id,
      r.cohort_id,
      (date_trunc('day', r.submitted_at AT TIME ZONE 'America/Sao_Paulo'))::date AS session_date,
      COUNT(*)::int                                     AS total,
      COUNT(*) FILTER (WHERE r.mode = 'dm')::int        AS dm_total,
      COUNT(*) FILTER (WHERE r.mode = 'group')::int     AS group_total,
      CASE WHEN COUNT(*) > 0
        THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE r.score >= 9) - COUNT(*) FILTER (WHERE r.score <= 6)) / COUNT(*), 1)
        ELSE NULL END                                   AS nps,
      CASE WHEN COUNT(*) FILTER (WHERE r.mode = 'dm') > 0
        THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE r.score >= 9 AND r.mode = 'dm') - COUNT(*) FILTER (WHERE r.score <= 6 AND r.mode = 'dm')) / COUNT(*) FILTER (WHERE r.mode = 'dm'), 1)
        ELSE NULL END                                   AS dm_nps,
      CASE WHEN COUNT(*) FILTER (WHERE r.mode = 'group') > 0
        THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE r.score >= 9 AND r.mode = 'group') - COUNT(*) FILTER (WHERE r.score <= 6 AND r.mode = 'group')) / COUNT(*) FILTER (WHERE r.mode = 'group'), 1)
        ELSE NULL END                                   AS group_nps,
      ROUND(AVG(r.score)::numeric, 2)                   AS avg_score,
      MIN(r.submitted_at)                               AS first_at,
      MAX(r.submitted_at)                               AS last_at
    FROM public.nps_results_unified r
    WHERE r.source = 'auto_class'
      AND r.class_id IS NOT NULL
      AND (p_filters->>'date_from' IS NULL OR r.submitted_at >= (p_filters->>'date_from')::timestamptz)
      AND (p_filters->>'date_to'   IS NULL OR r.submitted_at <  (p_filters->>'date_to')::timestamptz)
      AND (p_filters->>'cohort_id' IS NULL OR r.cohort_id = (p_filters->>'cohort_id')::uuid)
      AND (p_filters->>'class_id'  IS NULL OR r.class_id  = (p_filters->>'class_id')::uuid)
      AND (p_filters->>'source'    IS NULL OR p_filters->>'source' = 'auto_class')
    GROUP BY r.class_id, r.cohort_id, (date_trunc('day', r.submitted_at AT TIME ZONE 'America/Sao_Paulo'))::date
  ),

  auto_with_index AS (
    SELECT
      a.*,
      cl.name AS class_name,
      cl.kind AS class_kind,
      co.name AS cohort_name,
      CASE
        WHEN cl.kind = 'ps' THEN NULL
        ELSE (
          SELECT COUNT(*)::int + 1
          FROM public.zoom_meetings zm
          WHERE zm.class_id = a.class_id
            AND zm.cohort_id = a.cohort_id
            AND zm.start_time IS NOT NULL
            AND (zm.start_time AT TIME ZONE 'America/Sao_Paulo')::date < a.session_date
        )
      END AS session_index
    FROM auto_agg a
    LEFT JOIN public.classes cl ON cl.id = a.class_id
    LEFT JOIN public.cohorts co ON co.id = a.cohort_id
  )

  SELECT
    m.kind, m.group_key, m.label,
    m.survey_id, m.class_id, m.class_name, m.class_kind,
    m.cohort_id, m.cohort_name,
    m.session_date, m.session_index,
    m.total, m.dm_total, m.group_total,
    m.nps, m.dm_nps, m.group_nps, m.avg_score,
    m.first_at, m.last_at
  FROM manual m

  UNION ALL

  SELECT
    'auto'::text                                                                 AS kind,
    'session:' || a.class_id::text || ':' || COALESCE(a.cohort_id::text, 'null') || ':' || to_char(a.session_date, 'YYYY-MM-DD') AS group_key,
    CASE
      WHEN a.class_kind = 'ps' THEN COALESCE(a.class_name, 'PS') || ' — ' || to_char(a.session_date, 'DD/MM')
      WHEN a.session_index IS NOT NULL THEN 'Aula ' || lpad(a.session_index::text, 2, '0') || ' — ' || COALESCE(a.class_name, 'Aula') || ' (' || to_char(a.session_date, 'DD/MM') || ')'
      ELSE COALESCE(a.class_name, 'Aula') || ' — ' || to_char(a.session_date, 'DD/MM')
    END                                                                          AS label,
    NULL::uuid       AS survey_id,
    a.class_id, a.class_name, a.class_kind,
    a.cohort_id, a.cohort_name,
    a.session_date, a.session_index,
    a.total, a.dm_total, a.group_total,
    a.nps, a.dm_nps, a.group_nps, a.avg_score,
    a.first_at, a.last_at
  FROM auto_with_index a

  ORDER BY last_at DESC NULLS LAST
  LIMIT 200;
END;
$$;

GRANT EXECUTE ON FUNCTION public.nps_results_by_survey(JSONB) TO authenticated;

COMMENT ON FUNCTION public.nps_results_by_survey(JSONB) IS
  'NPS Results — breakdown por formulário/sessão. Label primário = nome do form/sessão; cohort_name retornado em coluna separada pra meta secundária no UI.';
