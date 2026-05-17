-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Dashboard RPCs part 2: top_classes + recent_failures + channel + funnel
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── dispatch_top_classes ────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dispatch_top_classes(
  p_filters jsonb DEFAULT '{}'::jsonb,
  p_limit   int   DEFAULT 5
) RETURNS TABLE (
  class_id     uuid,
  class_title  text,
  total_sent   bigint
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_dashboard_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  SELECT v.class_id, c.name AS class_title, COUNT(*) AS total_sent
  FROM dispatch_history_unified v
  JOIN classes c ON c.id = v.class_id
  WHERE v.class_id IS NOT NULL
    AND (p_filters->>'date_from' IS NULL OR v.sent_at >= (p_filters->>'date_from')::timestamptz)
    AND (p_filters->>'date_to'   IS NULL OR v.sent_at <  (p_filters->>'date_to')::timestamptz)
  GROUP BY v.class_id, c.name
  ORDER BY total_sent DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 50);
END;
$$;
GRANT EXECUTE ON FUNCTION public.dispatch_top_classes(jsonb, int) TO authenticated;

-- ─── dispatch_recent_failures ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dispatch_recent_failures(
  p_hours int DEFAULT 24,
  p_limit int DEFAULT 20
) RETURNS TABLE (
  source           text,
  dispatch_id      uuid,
  channel          text,
  recipient_label  text,
  error_detail     text,
  failed_at        timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_dashboard_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  SELECT
    v.source, v.dispatch_id, v.channel,
    COALESCE(s.name, v.recipient_identifier, 'desconhecido') AS recipient_label,
    v.error_detail, v.sent_at AS failed_at
  FROM dispatch_history_unified v
  LEFT JOIN students s ON s.id = v.student_id
  WHERE v.status = 'failed'
    AND v.sent_at >= (now() - (LEAST(GREATEST(p_hours, 1), 168) || ' hours')::interval)
  ORDER BY v.sent_at DESC
  LIMIT LEAST(GREATEST(p_limit, 1), 100);
END;
$$;
GRANT EXECUTE ON FUNCTION public.dispatch_recent_failures(int, int) TO authenticated;

-- ─── dispatch_channel_breakdown ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dispatch_channel_breakdown(p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS TABLE (
  channel    text,
  total      bigint,
  delivered  bigint,
  failed     bigint
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
BEGIN
  IF NOT is_dashboard_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;
  RETURN QUERY
  SELECT
    v.channel,
    COUNT(*) AS total,
    COUNT(*) FILTER (WHERE v.delivered_at IS NOT NULL) AS delivered,
    COUNT(*) FILTER (WHERE v.status = 'failed') AS failed
  FROM dispatch_history_unified v
  WHERE (p_filters->>'date_from' IS NULL OR v.sent_at >= (p_filters->>'date_from')::timestamptz)
    AND (p_filters->>'date_to'   IS NULL OR v.sent_at <  (p_filters->>'date_to')::timestamptz)
  GROUP BY v.channel
  ORDER BY total DESC;
END;
$$;
GRANT EXECUTE ON FUNCTION public.dispatch_channel_breakdown(jsonb) TO authenticated;

-- ─── dispatch_funnel ─────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dispatch_funnel(p_filters jsonb DEFAULT '{}'::jsonb)
RETURNS TABLE (
  stage       text,
  count       bigint,
  pct_of_sent numeric
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_sent      bigint;
  v_delivered bigint;
  v_read      bigint;
  v_opened    bigint;
  v_responded bigint;
BEGIN
  IF NOT is_dashboard_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE delivered_at IS NOT NULL),
    COUNT(*) FILTER (WHERE read_at IS NOT NULL),
    COUNT(*) FILTER (WHERE open_count > 0),
    COUNT(*) FILTER (WHERE response_count > 0)
  INTO v_sent, v_delivered, v_read, v_opened, v_responded
  FROM dispatch_history_unified v
  WHERE (p_filters->>'date_from' IS NULL OR v.sent_at >= (p_filters->>'date_from')::timestamptz)
    AND (p_filters->>'date_to'   IS NULL OR v.sent_at <  (p_filters->>'date_to')::timestamptz);

  RETURN QUERY
  SELECT * FROM (VALUES
    ('sent'::text,      v_sent,      100.0::numeric),
    ('delivered'::text, v_delivered, ROUND(100.0 * v_delivered / NULLIF(v_sent, 0), 2)),
    ('read'::text,      v_read,      ROUND(100.0 * v_read      / NULLIF(v_sent, 0), 2)),
    ('opened'::text,    v_opened,    ROUND(100.0 * v_opened    / NULLIF(v_sent, 0), 2)),
    ('responded'::text, v_responded, ROUND(100.0 * v_responded / NULLIF(v_sent, 0), 2))
  ) AS t(stage, count, pct_of_sent);
END;
$$;
GRANT EXECUTE ON FUNCTION public.dispatch_funnel(jsonb) TO authenticated;

COMMIT;
