-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Dashboard RPCs part 1: list_dispatch_history + summary_kpis + trend_daily
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── list_dispatch_history ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.list_dispatch_history(
  p_filters jsonb DEFAULT '{}'::jsonb,
  p_page    integer DEFAULT 1,
  p_size    integer DEFAULT 50
) RETURNS TABLE (
  source              text,
  dispatch_id         uuid,
  channel             text,
  sent_at             timestamptz,
  delivered_at        timestamptz,
  read_at             timestamptz,
  status              text,
  error_detail        text,
  student_id          uuid,
  student_name        text,
  student_phone       text,
  recipient_identifier text,
  recipient_type      text,
  class_id            uuid,
  class_title         text,
  cohort_id           uuid,
  cohort_name         text,
  dispatch_type       text,
  template_name       text,
  template_category   text,
  rendered_message    text,
  open_count          int,
  last_opened_at      timestamptz,
  response_count      int,
  cost_usd            numeric,
  metadata            jsonb,
  total_count         bigint
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_offset int := GREATEST(0, (p_page - 1) * p_size);
  v_size   int := LEAST(GREATEST(p_size, 1), 200);
BEGIN
  IF NOT is_dashboard_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  RETURN QUERY
  WITH filtered AS (
    SELECT v.*,
           s.name AS s_student_name,
           s.phone AS s_student_phone,
           c.name AS c_class_title,
           co.name AS co_cohort_name,
           COALESCE(estimate_dispatch_cost_usd(v.template_category, 'BR', v.sent_at::date), 0) AS cost_usd
    FROM dispatch_history_unified v
    LEFT JOIN students s ON s.id = v.student_id
    LEFT JOIN classes  c ON c.id = v.class_id
    LEFT JOIN cohorts  co ON co.id = v.cohort_id
    WHERE
      (p_filters->>'date_from' IS NULL OR v.sent_at >= (p_filters->>'date_from')::timestamptz)
      AND (p_filters->>'date_to'   IS NULL OR v.sent_at <  (p_filters->>'date_to')::timestamptz)
      AND (p_filters->'channels'   IS NULL OR jsonb_array_length(p_filters->'channels') = 0
           OR v.channel = ANY(SELECT jsonb_array_elements_text(p_filters->'channels')))
      AND (p_filters->'statuses'   IS NULL OR jsonb_array_length(p_filters->'statuses') = 0
           OR v.status  = ANY(SELECT jsonb_array_elements_text(p_filters->'statuses')))
      AND (p_filters->>'class_id'  IS NULL OR v.class_id  = (p_filters->>'class_id')::uuid)
      AND (p_filters->>'cohort_id' IS NULL OR v.cohort_id = (p_filters->>'cohort_id')::uuid)
      AND (p_filters->>'student_search' IS NULL
           OR s.name  ILIKE '%' || (p_filters->>'student_search') || '%'
           OR s.phone ILIKE '%' || (p_filters->>'student_search') || '%')
      AND (p_filters->'dispatch_types' IS NULL OR jsonb_array_length(p_filters->'dispatch_types') = 0
           OR v.dispatch_type = ANY(SELECT jsonb_array_elements_text(p_filters->'dispatch_types')))
      AND (p_filters->>'template_name' IS NULL OR v.template_name = p_filters->>'template_name')
  )
  SELECT
    f.source, f.dispatch_id, f.channel, f.sent_at, f.delivered_at, f.read_at,
    f.status, f.error_detail, f.student_id, f.s_student_name, f.s_student_phone,
    f.recipient_identifier, f.recipient_type, f.class_id, f.c_class_title,
    f.cohort_id, f.co_cohort_name, f.dispatch_type, f.template_name, f.template_category,
    f.rendered_message, f.open_count, f.last_opened_at, f.response_count,
    f.cost_usd, f.metadata,
    COUNT(*) OVER() AS total_count
  FROM filtered f
  ORDER BY f.sent_at DESC NULLS LAST, f.dispatch_id
  LIMIT v_size OFFSET v_offset;
END;
$$;
GRANT EXECUTE ON FUNCTION public.list_dispatch_history(jsonb, integer, integer) TO authenticated;

-- ─── dispatch_summary_kpis ───────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dispatch_summary_kpis(p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS TABLE (
  total_sent      bigint,
  delivered_pct   numeric,
  read_pct        numeric,
  total_cost_usd  numeric,
  open_pct        numeric,
  response_pct    numeric
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_dashboard_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  RETURN QUERY
  WITH base AS (
    SELECT v.*,
           COALESCE(estimate_dispatch_cost_usd(v.template_category, 'BR', v.sent_at::date), 0) AS cost_usd
    FROM dispatch_history_unified v
    LEFT JOIN students s ON s.id = v.student_id
    WHERE
      (p_filters->>'date_from' IS NULL OR v.sent_at >= (p_filters->>'date_from')::timestamptz)
      AND (p_filters->>'date_to'   IS NULL OR v.sent_at <  (p_filters->>'date_to')::timestamptz)
      AND (p_filters->'channels'   IS NULL OR jsonb_array_length(p_filters->'channels') = 0
           OR v.channel = ANY(SELECT jsonb_array_elements_text(p_filters->'channels')))
      AND (p_filters->'statuses'   IS NULL OR jsonb_array_length(p_filters->'statuses') = 0
           OR v.status  = ANY(SELECT jsonb_array_elements_text(p_filters->'statuses')))
      AND (p_filters->>'class_id'  IS NULL OR v.class_id  = (p_filters->>'class_id')::uuid)
      AND (p_filters->>'cohort_id' IS NULL OR v.cohort_id = (p_filters->>'cohort_id')::uuid)
      AND (p_filters->'dispatch_types' IS NULL OR jsonb_array_length(p_filters->'dispatch_types') = 0
           OR v.dispatch_type = ANY(SELECT jsonb_array_elements_text(p_filters->'dispatch_types')))
  )
  SELECT
    COUNT(*) AS total_sent,
    ROUND(100.0 * COUNT(*) FILTER (WHERE delivered_at IS NOT NULL) / NULLIF(COUNT(*),0), 2) AS delivered_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE read_at      IS NOT NULL) / NULLIF(COUNT(*),0), 2) AS read_pct,
    COALESCE(SUM(cost_usd), 0)::numeric(12,4) AS total_cost_usd,
    ROUND(100.0 * COUNT(*) FILTER (WHERE open_count > 0)     / NULLIF(COUNT(*),0), 2) AS open_pct,
    ROUND(100.0 * COUNT(*) FILTER (WHERE response_count > 0) / NULLIF(COUNT(*),0), 2) AS response_pct
  FROM base;
END;
$$;
GRANT EXECUTE ON FUNCTION public.dispatch_summary_kpis(jsonb) TO authenticated;

-- ─── dispatch_trend_daily ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dispatch_trend_daily(
  p_filters jsonb DEFAULT '{}'::jsonb,
  p_days    int DEFAULT 30
) RETURNS TABLE (
  day              date,
  total_sent       bigint,
  total_failed     bigint,
  total_delivered  bigint,
  total_cost_usd   numeric
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_days int := LEAST(GREATEST(p_days, 1), 365);
BEGIN
  IF NOT is_dashboard_admin() THEN
    RAISE EXCEPTION 'forbidden' USING ERRCODE='42501';
  END IF;

  RETURN QUERY
  SELECT
    v.sent_at::date AS day,
    COUNT(*) AS total_sent,
    COUNT(*) FILTER (WHERE v.status = 'failed') AS total_failed,
    COUNT(*) FILTER (WHERE v.delivered_at IS NOT NULL) AS total_delivered,
    COALESCE(SUM(estimate_dispatch_cost_usd(v.template_category, 'BR', v.sent_at::date)), 0)::numeric(12,4)
  FROM dispatch_history_unified v
  WHERE v.sent_at >= (CURRENT_DATE - (v_days || ' days')::interval)
    AND (p_filters->'channels' IS NULL OR jsonb_array_length(p_filters->'channels') = 0
         OR v.channel = ANY(SELECT jsonb_array_elements_text(p_filters->'channels')))
    AND (p_filters->'dispatch_types' IS NULL OR jsonb_array_length(p_filters->'dispatch_types') = 0
         OR v.dispatch_type = ANY(SELECT jsonb_array_elements_text(p_filters->'dispatch_types')))
  GROUP BY v.sent_at::date
  ORDER BY day ASC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.dispatch_trend_daily(jsonb, int) TO authenticated;

COMMIT;
