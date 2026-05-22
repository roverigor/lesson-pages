-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: agrupa "por formulário/sessão" pelo ID do disparo (dispatch_job_id),
-- não pela data da resposta.
--
-- Bug anterior: auto_class agregava por (class_id, cohort_id,
-- date_trunc('day', submitted_at)) — ou seja, data em que aluno respondeu.
-- Resultado: uma resposta atrasada criava sessão fantasma rotulada como
-- "Aula NN" cuja NN era inferida pelo zoom_meetings.start_time < data da
-- resposta (não da aula).
--
-- Fix: agrupa por nps_class_links.dispatch_job_id (chave real de cada envio).
-- Fallback pra legacy_link_id quando link existe mas dispatch_job_id é NULL
-- (rows P2 manuais). Último fallback mantém o comportamento antigo só pra
-- linhas legadas sem link nenhum.
--
-- session_date passa a vir do link (data efetiva da aula); first_at/last_at
-- continuam baseados nas respostas. dispatch_sent_at trazido pra UI mostrar
-- "Enviado em DD/MM".
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DROP FUNCTION IF EXISTS public.nps_results_by_survey(jsonb);

CREATE OR REPLACE FUNCTION public.nps_results_by_survey(
  p_filters JSONB DEFAULT '{}'::jsonb
)
RETURNS TABLE (
  kind             TEXT,
  group_key        TEXT,
  label            TEXT,
  survey_id        UUID,
  dispatch_job_id  UUID,
  link_id          UUID,
  class_id         UUID,
  class_name       TEXT,
  class_kind       TEXT,
  cohort_id        UUID,
  cohort_name      TEXT,
  session_date     DATE,
  session_index    INT,
  total            INT,
  dm_total         INT,
  group_total      INT,
  nps              NUMERIC,
  dm_nps           NUMERIC,
  group_nps        NUMERIC,
  avg_score        NUMERIC,
  first_at         TIMESTAMPTZ,
  last_at          TIMESTAMPTZ,
  dispatch_sent_at TIMESTAMPTZ
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
      NULL::uuid                                        AS dispatch_job_id,
      NULL::uuid                                        AS link_id,
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
      MAX(r.submitted_at)                               AS last_at,
      NULL::timestamptz                                 AS dispatch_sent_at
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

  -- Agrupa por dispatch_job_id (preferencial). Quando dispatch_job_id é NULL
  -- mas link existe, agrupa por link_id (P2 legacy). Quando nem link, cai pra
  -- chave histórica (class+cohort+date da resposta) só pra não perder linha.
  auto_agg AS (
    SELECT
      COALESCE(
        lnk.dispatch_job_id::text,
        r.legacy_link_id::text,
        r.class_id::text || ':' || COALESCE(r.cohort_id::text, 'null') || ':'
          || to_char((date_trunc('day', r.submitted_at AT TIME ZONE 'America/Sao_Paulo'))::date, 'YYYY-MM-DD')
      )                                                AS anchor_key,
      (array_agg(lnk.dispatch_job_id) FILTER (WHERE lnk.dispatch_job_id IS NOT NULL))[1] AS dispatch_job_id,
      (array_agg(r.legacy_link_id)    FILTER (WHERE r.legacy_link_id   IS NOT NULL))[1] AS link_id,
      r.class_id,
      r.cohort_id,
      -- Prefere a data real da aula (do link); fallback é a data da resposta.
      COALESCE(
        MAX(lnk.session_date),
        (date_trunc('day', MAX(r.submitted_at) AT TIME ZONE 'America/Sao_Paulo'))::date
      )                                                AS session_date,
      MIN(lnk.sent_at)                                 AS dispatch_sent_at,
      COUNT(*)::int                                    AS total,
      COUNT(*) FILTER (WHERE r.mode = 'dm')::int       AS dm_total,
      COUNT(*) FILTER (WHERE r.mode = 'group')::int    AS group_total,
      CASE WHEN COUNT(*) > 0
        THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE r.score >= 9) - COUNT(*) FILTER (WHERE r.score <= 6)) / COUNT(*), 1)
        ELSE NULL END                                  AS nps,
      CASE WHEN COUNT(*) FILTER (WHERE r.mode = 'dm') > 0
        THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE r.score >= 9 AND r.mode = 'dm') - COUNT(*) FILTER (WHERE r.score <= 6 AND r.mode = 'dm')) / COUNT(*) FILTER (WHERE r.mode = 'dm'), 1)
        ELSE NULL END                                  AS dm_nps,
      CASE WHEN COUNT(*) FILTER (WHERE r.mode = 'group') > 0
        THEN ROUND(100.0 * (COUNT(*) FILTER (WHERE r.score >= 9 AND r.mode = 'group') - COUNT(*) FILTER (WHERE r.score <= 6 AND r.mode = 'group')) / COUNT(*) FILTER (WHERE r.mode = 'group'), 1)
        ELSE NULL END                                  AS group_nps,
      ROUND(AVG(r.score)::numeric, 2)                  AS avg_score,
      MIN(r.submitted_at)                              AS first_at,
      MAX(r.submitted_at)                              AS last_at
    FROM public.nps_results_unified r
    LEFT JOIN public.nps_class_links lnk ON lnk.id = r.legacy_link_id
    WHERE r.source = 'auto_class'
      AND r.class_id IS NOT NULL
      AND (p_filters->>'date_from' IS NULL OR r.submitted_at >= (p_filters->>'date_from')::timestamptz)
      AND (p_filters->>'date_to'   IS NULL OR r.submitted_at <  (p_filters->>'date_to')::timestamptz)
      AND (p_filters->>'cohort_id' IS NULL OR r.cohort_id = (p_filters->>'cohort_id')::uuid)
      AND (p_filters->>'class_id'  IS NULL OR r.class_id  = (p_filters->>'class_id')::uuid)
      AND (p_filters->>'source'    IS NULL OR p_filters->>'source' = 'auto_class')
    GROUP BY
      COALESCE(
        lnk.dispatch_job_id::text,
        r.legacy_link_id::text,
        r.class_id::text || ':' || COALESCE(r.cohort_id::text, 'null') || ':'
          || to_char((date_trunc('day', r.submitted_at AT TIME ZONE 'America/Sao_Paulo'))::date, 'YYYY-MM-DD')
      ),
      r.class_id,
      r.cohort_id
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
      CASE WHEN a.class_kind = 'ps' THEN COALESCE(a.class_name, 'PS') || ' — ' || to_char(a.session_date, 'DD/MM')
           WHEN a.session_index IS NOT NULL THEN 'Aula ' || lpad(a.session_index::text, 2, '0') || ' — ' || COALESCE(a.class_name, 'Aula') || ' (' || to_char(a.session_date, 'DD/MM') || ')'
           ELSE COALESCE(a.class_name, 'Aula') || ' — ' || to_char(a.session_date, 'DD/MM') END AS label,
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
  'NPS Results — agrupa "por formulário/sessão" pelo dispatch_job_id real do envio (fallback link_id, fallback session+date). Devolve dispatch_job_id, link_id, session_date real (data da aula) e dispatch_sent_at separados de first_at/last_at (respostas).';

-- ═══════════════════════════════════════════════════════════════════════════
-- Extende nps_results_comments com filtros dispatch_job_id e link_id pra UI
-- conseguir abrir o detalhe de um card específico sem depender de date range.
-- ═══════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.nps_results_comments(JSONB, INT);
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
  v_limit INT := LEAST(GREATEST(p_limit, 1), 1000);
  v_search TEXT := NULLIF(trim(p_filters->>'search'), '');
  v_dispatch_id UUID := NULLIF(p_filters->>'dispatch_job_id','')::uuid;
  v_link_id UUID := NULLIF(p_filters->>'link_id','')::uuid;
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
    CASE WHEN r.student_id IS NOT NULL THEN s.name  ELSE NULL END,
    CASE WHEN r.student_id IS NOT NULL THEN s.phone ELSE NULL END
  FROM public.nps_results_unified r
  LEFT JOIN public.cohorts  co ON co.id = r.cohort_id
  LEFT JOIN public.classes  cl ON cl.id = r.class_id
  LEFT JOIN public.students s  ON s.id  = r.student_id
  LEFT JOIN public.nps_class_links lnk ON lnk.id = r.legacy_link_id
  WHERE
    (p_filters->>'date_from' IS NULL OR r.submitted_at >= (p_filters->>'date_from')::timestamptz)
    AND (p_filters->>'date_to'   IS NULL OR r.submitted_at <  (p_filters->>'date_to')::timestamptz)
    AND (p_filters->>'cohort_id' IS NULL OR r.cohort_id = (p_filters->>'cohort_id')::uuid)
    AND (p_filters->>'class_id'  IS NULL OR r.class_id  = (p_filters->>'class_id')::uuid)
    AND (p_filters->>'mode'      IS NULL OR r.mode = p_filters->>'mode')
    AND (p_filters->>'source'    IS NULL OR r.source = p_filters->>'source')
    AND (p_filters->>'survey_id' IS NULL OR r.survey_id = (p_filters->>'survey_id')::uuid)
    AND (v_dispatch_id IS NULL OR lnk.dispatch_job_id = v_dispatch_id)
    AND (v_link_id     IS NULL OR r.legacy_link_id = v_link_id)
    AND (p_filters->>'bucket' IS NULL OR
         (p_filters->>'bucket' = 'detractor' AND r.score <= 6) OR
         (p_filters->>'bucket' = 'passive'   AND r.score BETWEEN 7 AND 8) OR
         (p_filters->>'bucket' = 'promoter'  AND r.score >= 9))
    AND (p_filters->>'only_with_comment' IS NULL OR
         (p_filters->>'only_with_comment')::boolean = false OR
         (r.comment IS NOT NULL AND length(trim(r.comment)) > 0))
    AND (v_search IS NULL OR (
         r.comment       ILIKE '%' || v_search || '%' OR
         r.name_provided ILIKE '%' || v_search || '%' OR
         co.name         ILIKE '%' || v_search || '%' OR
         cl.name         ILIKE '%' || v_search || '%' OR
         s.name          ILIKE '%' || v_search || '%' OR
         s.phone         ILIKE '%' || v_search || '%'
       ))
  ORDER BY r.submitted_at DESC
  LIMIT v_limit;
END;
$$;

GRANT EXECUTE ON FUNCTION public.nps_results_comments(JSONB, INT) TO authenticated;

COMMENT ON FUNCTION public.nps_results_comments(JSONB, INT) IS
  'NPS Results — comments/respostas. Suporta filtros dispatch_job_id e link_id pra abrir detalhe de envio específico sem date range.';

COMMIT;
