-- ═══════════════════════════════════════════════════════════════════════════
-- Function: survey_low_response_alert()
-- Retorna surveys com taxa resposta < 20% nos últimos 30d (com >= 5 disparos).
-- Usado por dashboard /cs/dashboard pra alertas operacionais.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.survey_low_response_alert()
RETURNS TABLE (
  survey_id uuid,
  survey_name text,
  total_dispatches bigint,
  total_responses bigint,
  response_rate numeric
)
LANGUAGE sql STABLE SECURITY DEFINER AS $$
  WITH dispatches AS (
    SELECT
      sl.survey_id,
      COUNT(*) AS total
    FROM public.survey_links sl
    WHERE sl.created_at > now() - interval '30 days'
    GROUP BY sl.survey_id
    HAVING COUNT(*) >= 5
  ),
  responses AS (
    SELECT
      sr.survey_id,
      COUNT(*) AS total
    FROM public.survey_responses sr
    WHERE sr.submitted_at > now() - interval '30 days'
    GROUP BY sr.survey_id
  )
  SELECT
    s.id,
    s.name,
    d.total,
    COALESCE(r.total, 0),
    ROUND((COALESCE(r.total, 0)::numeric / d.total) * 100, 2)
  FROM dispatches d
  JOIN public.surveys s ON s.id = d.survey_id
  LEFT JOIN responses r ON r.survey_id = d.survey_id
  WHERE COALESCE(r.total, 0)::numeric / d.total < 0.20
  ORDER BY (COALESCE(r.total, 0)::numeric / d.total) ASC;
$$;

GRANT EXECUTE ON FUNCTION public.survey_low_response_alert() TO authenticated;

COMMENT ON FUNCTION public.survey_low_response_alert() IS
  'Surveys com taxa resposta < 20% últimos 30d (com >= 5 disparos). Usado por dashboard CS pra alertas.';
