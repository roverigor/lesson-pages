-- ═══════════════════════════════════════════════════════════════════════════
-- Story 22.0 / ADR-019: Refactor nps_results_by_survey pra usar resolve_session_number()
--
-- Substitui inline COUNT(zoom_meetings) por chamada à função utilitária
-- resolve_session_number() (criada em 20260522010000).
--
-- Mantém todo resto da função idêntico ao hotfix 2026-05-22.
--
-- DOWN: 20260522010300_nps_results_by_survey_refactor.down.sql
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DROP FUNCTION IF EXISTS public.nps_results_by_survey(jsonb);

CREATE OR REPLACE FUNCTION public.nps_results_by_survey(
  p_filters JSONB DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  kind TEXT, group_key TEXT, label TEXT,
  survey_id UUID, dispatch_job_id UUID, link_id UUID,
  class_id UUID, class_name TEXT, class_kind TEXT,
  cohort_id UUID, cohort_name TEXT,
  session_date DATE, session_index INT,
  total INT, dm_total INT, group_total INT,
  nps NUMERIC, dm_nps NUMERIC, group_nps NUMERIC,
  avg_score NUMERIC,
  first_at TIMESTAMPTZ, last_at TIMESTAMPTZ,
  dispatch_sent_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  WITH manual AS (
    SELECT 'manual'::text AS kind, r.survey_id::text AS group_key, r.survey_id, NULL::uuid AS dispatch_job_id,
      NULL::uuid AS link_id, sv.class_id, cl.name AS class_name, cl.kind AS class_kind,
      r.cohort_id, co.name AS cohort_name, NULL::date AS session_date, NULL::int AS session_index,
      COALESCE(sv.name, 'Formulário sem nome') AS label,
      COUNT(*)::int AS total, COUNT(*) FILTER (WHERE r.mode='dm')::int AS dm_total, COUNT(*) FILTER (WHERE r.mode='group')::int AS group_total,
      CASE WHEN COUNT(*)>0 THEN ROUND(100.0*(COUNT(*) FILTER (WHERE r.score>=9)-COUNT(*) FILTER (WHERE r.score<=6))/COUNT(*),1) ELSE NULL END AS nps,
      CASE WHEN COUNT(*) FILTER (WHERE r.mode='dm')>0 THEN ROUND(100.0*(COUNT(*) FILTER (WHERE r.score>=9 AND r.mode='dm')-COUNT(*) FILTER (WHERE r.score<=6 AND r.mode='dm'))/COUNT(*) FILTER (WHERE r.mode='dm'),1) ELSE NULL END AS dm_nps,
      CASE WHEN COUNT(*) FILTER (WHERE r.mode='group')>0 THEN ROUND(100.0*(COUNT(*) FILTER (WHERE r.score>=9 AND r.mode='group')-COUNT(*) FILTER (WHERE r.score<=6 AND r.mode='group'))/COUNT(*) FILTER (WHERE r.mode='group'),1) ELSE NULL END AS group_nps,
      ROUND(AVG(r.score)::numeric,2) AS avg_score, MIN(r.submitted_at) AS first_at, MAX(r.submitted_at) AS last_at, NULL::timestamptz AS dispatch_sent_at
    FROM public.nps_results_unified r
    LEFT JOIN public.surveys sv ON sv.id=r.survey_id
    LEFT JOIN public.cohorts co ON co.id=r.cohort_id
    LEFT JOIN public.classes cl ON cl.id=sv.class_id
    WHERE r.source='manual_survey' AND r.survey_id IS NOT NULL
      AND (p_filters->>'date_from' IS NULL OR r.submitted_at >= (p_filters->>'date_from')::timestamptz)
      AND (p_filters->>'date_to'   IS NULL OR r.submitted_at <  (p_filters->>'date_to')::timestamptz)
      AND (p_filters->>'cohort_id' IS NULL OR r.cohort_id = (p_filters->>'cohort_id')::uuid)
      AND (p_filters->>'source'    IS NULL OR p_filters->>'source' = 'manual_survey')
    GROUP BY r.survey_id, sv.name, sv.class_id, cl.name, cl.kind, r.cohort_id, co.name
  ),
  auto_agg AS (
    SELECT COALESCE(lnk.dispatch_job_id::text, r.legacy_link_id::text, r.class_id::text || ':' || COALESCE(r.cohort_id::text,'null') || ':' || to_char((date_trunc('day', r.submitted_at AT TIME ZONE 'America/Sao_Paulo'))::date,'YYYY-MM-DD')) AS anchor_key,
      (array_agg(lnk.dispatch_job_id) FILTER (WHERE lnk.dispatch_job_id IS NOT NULL))[1] AS dispatch_job_id,
      (array_agg(r.legacy_link_id) FILTER (WHERE r.legacy_link_id IS NOT NULL))[1] AS link_id,
      (array_agg(lnk.session_number_snapshot) FILTER (WHERE lnk.session_number_snapshot IS NOT NULL))[1] AS snapshot_session,
      r.class_id, r.cohort_id,
      COALESCE(MAX(lnk.session_date), (date_trunc('day', MAX(r.submitted_at) AT TIME ZONE 'America/Sao_Paulo'))::date) AS session_date,
      MIN(lnk.sent_at) AS dispatch_sent_at, COUNT(*)::int AS total,
      COUNT(*) FILTER (WHERE r.mode='dm')::int AS dm_total, COUNT(*) FILTER (WHERE r.mode='group')::int AS group_total,
      CASE WHEN COUNT(*)>0 THEN ROUND(100.0*(COUNT(*) FILTER (WHERE r.score>=9)-COUNT(*) FILTER (WHERE r.score<=6))/COUNT(*),1) ELSE NULL END AS nps,
      CASE WHEN COUNT(*) FILTER (WHERE r.mode='dm')>0 THEN ROUND(100.0*(COUNT(*) FILTER (WHERE r.score>=9 AND r.mode='dm')-COUNT(*) FILTER (WHERE r.score<=6 AND r.mode='dm'))/COUNT(*) FILTER (WHERE r.mode='dm'),1) ELSE NULL END AS dm_nps,
      CASE WHEN COUNT(*) FILTER (WHERE r.mode='group')>0 THEN ROUND(100.0*(COUNT(*) FILTER (WHERE r.score>=9 AND r.mode='group')-COUNT(*) FILTER (WHERE r.score<=6 AND r.mode='group'))/COUNT(*) FILTER (WHERE r.mode='group'),1) ELSE NULL END AS group_nps,
      ROUND(AVG(r.score)::numeric,2) AS avg_score, MIN(r.submitted_at) AS first_at, MAX(r.submitted_at) AS last_at
    FROM public.nps_results_unified r
    LEFT JOIN public.nps_class_links lnk ON lnk.id=r.legacy_link_id
    WHERE r.source='auto_class' AND r.class_id IS NOT NULL
      AND (p_filters->>'date_from' IS NULL OR r.submitted_at >= (p_filters->>'date_from')::timestamptz)
      AND (p_filters->>'date_to'   IS NULL OR r.submitted_at <  (p_filters->>'date_to')::timestamptz)
      AND (p_filters->>'cohort_id' IS NULL OR r.cohort_id = (p_filters->>'cohort_id')::uuid)
      AND (p_filters->>'class_id'  IS NULL OR r.class_id  = (p_filters->>'class_id')::uuid)
      AND (p_filters->>'source'    IS NULL OR p_filters->>'source' = 'auto_class')
    GROUP BY COALESCE(lnk.dispatch_job_id::text, r.legacy_link_id::text, r.class_id::text || ':' || COALESCE(r.cohort_id::text,'null') || ':' || to_char((date_trunc('day', r.submitted_at AT TIME ZONE 'America/Sao_Paulo'))::date,'YYYY-MM-DD')), r.class_id, r.cohort_id
  ),
  auto_with_index AS (
    SELECT a.*, cl.name AS class_name, cl.kind AS class_kind, co.name AS cohort_name,
      CASE WHEN cl.kind='ps' THEN NULL
        ELSE public.resolve_session_number(a.class_id, a.cohort_id, a.session_date, a.snapshot_session)
      END AS session_index
    FROM auto_agg a
    LEFT JOIN public.classes cl ON cl.id=a.class_id
    LEFT JOIN public.cohorts co ON co.id=a.cohort_id
  ),
  combined AS (
    SELECT m.kind, m.group_key, m.label, m.survey_id, m.dispatch_job_id, m.link_id,
      m.class_id, m.class_name, m.class_kind, m.cohort_id, m.cohort_name,
      m.session_date, m.session_index, m.total, m.dm_total, m.group_total,
      m.nps, m.dm_nps, m.group_nps, m.avg_score, m.first_at, m.last_at, m.dispatch_sent_at
    FROM manual m
    UNION ALL
    SELECT 'auto'::text AS kind,
      CASE WHEN a.dispatch_job_id IS NOT NULL THEN 'dispatch:' || a.dispatch_job_id::text
           WHEN a.link_id IS NOT NULL THEN 'link:' || a.link_id::text
           ELSE 'session:' || a.class_id::text || ':' || COALESCE(a.cohort_id::text,'null') || ':' || to_char(a.session_date,'YYYY-MM-DD') END AS group_key,
      CASE WHEN a.class_kind='ps' THEN COALESCE(a.class_name,'PS') || ' — ' || to_char(a.session_date,'DD/MM')
           WHEN a.session_index IS NOT NULL THEN 'Aula ' || lpad(a.session_index::text,2,'0') || ' — ' || COALESCE(a.class_name,'Aula') || ' (' || to_char(a.session_date,'DD/MM') || ')'
           ELSE COALESCE(a.class_name,'Aula') || ' — ' || to_char(a.session_date,'DD/MM') END AS label,
      NULL::uuid AS survey_id, a.dispatch_job_id, a.link_id,
      a.class_id, a.class_name, a.class_kind, a.cohort_id, a.cohort_name,
      a.session_date, a.session_index, a.total, a.dm_total, a.group_total,
      a.nps, a.dm_nps, a.group_nps, a.avg_score, a.first_at, a.last_at, a.dispatch_sent_at
    FROM auto_with_index a
  )
  SELECT c.kind, c.group_key, c.label, c.survey_id, c.dispatch_job_id, c.link_id,
    c.class_id, c.class_name, c.class_kind, c.cohort_id, c.cohort_name,
    c.session_date, c.session_index, c.total, c.dm_total, c.group_total,
    c.nps, c.dm_nps, c.group_nps, c.avg_score, c.first_at, c.last_at, c.dispatch_sent_at
  FROM combined c
  ORDER BY COALESCE(c.dispatch_sent_at, c.last_at) DESC NULLS LAST
  LIMIT 200;
END;
$$;

GRANT EXECUTE ON FUNCTION public.nps_results_by_survey(JSONB) TO authenticated;

COMMENT ON FUNCTION public.nps_results_by_survey(JSONB) IS
  'Story 22.0 / ADR-019 — Refactored: session_index via resolve_session_number() (snapshot > cohort_sessions > legacy heurística).';

COMMIT;
