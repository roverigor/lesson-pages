-- ═══════════════════════════════════════════════════════════════════════════
-- nps_results_filter_options — extended w/ surveys + auto_sessions list
--
-- Bug fix: dropdown "Formulário" no admin/nps-results estava vazio.
-- Agora retorna:
--   • cohorts   — distinct cohorts que aparecem em nps_results_unified
--   • classes   — distinct classes (deduplicadas) que aparecem
--   • surveys   — manual surveys com pelo menos 1 resposta (id, name, cohort_name)
--   • auto_sessions — sessões (class_id, date BRT) com pelo menos 1 resposta auto_class
-- ═══════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.nps_results_filter_options();

CREATE OR REPLACE FUNCTION public.nps_results_filter_options()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cohorts JSONB;
  v_classes JSONB;
  v_surveys JSONB;
  v_auto_sessions JSONB;
  v_sources JSONB;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  -- Cohorts distintos
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'name', name) ORDER BY name), '[]'::jsonb)
    INTO v_cohorts
  FROM public.cohorts
  WHERE EXISTS (SELECT 1 FROM public.nps_results_unified r WHERE r.cohort_id = cohorts.id);

  -- Classes distintas (DISTINCT em id pra evitar duplicatas)
  SELECT COALESCE(jsonb_agg(jsonb_build_object('id', id, 'name', name) ORDER BY name), '[]'::jsonb)
    INTO v_classes
  FROM public.classes
  WHERE EXISTS (SELECT 1 FROM public.nps_results_unified r WHERE r.class_id = classes.id);

  -- Manual surveys com respostas
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'id', sv.id,
      'name', sv.name,
      'cohort_name', co.name,
      'class_name', cl.name,
      'created_at', sv.created_at
    )
    ORDER BY sv.created_at DESC NULLS LAST
  ), '[]'::jsonb)
    INTO v_surveys
  FROM public.surveys sv
  LEFT JOIN public.cohorts co ON co.id = sv.cohort_id
  LEFT JOIN public.classes cl ON cl.id = sv.class_id
  WHERE EXISTS (
    SELECT 1 FROM public.nps_results_unified r
    WHERE r.source = 'manual_survey' AND r.survey_id = sv.id
  );

  -- Auto sessions (class_id + date BRT) com respostas auto_class
  SELECT COALESCE(jsonb_agg(
    jsonb_build_object(
      'class_id',    sess.class_id,
      'class_name',  sess.class_name,
      'cohort_name', sess.cohort_name,
      'date',        sess.session_date,
      'label',       sess.label,
      'total',       sess.total
    )
    ORDER BY sess.session_date DESC, sess.cohort_name
  ), '[]'::jsonb)
    INTO v_auto_sessions
  FROM (
    SELECT
      r.class_id,
      cl.name AS class_name,
      r.cohort_id,
      co.name AS cohort_name,
      (date_trunc('day', r.submitted_at AT TIME ZONE 'America/Sao_Paulo'))::date AS session_date,
      COALESCE(co.name, 'Sem turma') || ' · ' || COALESCE(cl.name, 'Aula') || ' — ' || to_char(date_trunc('day', r.submitted_at AT TIME ZONE 'America/Sao_Paulo'), 'DD/MM/YYYY') AS label,
      COUNT(*)::int AS total
    FROM public.nps_results_unified r
    LEFT JOIN public.classes cl ON cl.id = r.class_id
    LEFT JOIN public.cohorts co ON co.id = r.cohort_id
    WHERE r.source = 'auto_class' AND r.class_id IS NOT NULL
    GROUP BY r.class_id, cl.name, r.cohort_id, co.name, (date_trunc('day', r.submitted_at AT TIME ZONE 'America/Sao_Paulo'))::date
  ) sess;

  SELECT COALESCE(jsonb_agg(DISTINCT source), '[]'::jsonb) INTO v_sources FROM public.nps_results_unified;

  RETURN jsonb_build_object(
    'cohorts', v_cohorts,
    'classes', v_classes,
    'surveys', v_surveys,
    'auto_sessions', v_auto_sessions,
    'sources', v_sources
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.nps_results_filter_options() TO authenticated;
