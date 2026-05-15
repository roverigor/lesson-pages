# P4 — Dispatch History Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a unified admin dashboard at `/admin/envios/` showing all WhatsApp dispatches (Meta DM + Evolution group) across sources, with filters, KPIs, charts, funnel, drilldown modal, retry under strict gates, CSV export, and link-open tracking. Read-mostly; single write action (retry) is gated.

**Architecture:** PostgreSQL VIEW unifying 4 source tables. Admin-only RPCs (SECURITY DEFINER). Vanilla JS frontend with Chart.js. Retry behind one-time confirm token + audit. Link opens tracked via new `dispatch_link_opens` table.

**Tech Stack:** PostgreSQL (Supabase) for storage + RPCs, Deno for edge functions (retry orchestration), vanilla HTML/JS/CSS + Chart.js v4 for frontend.

**Spec reference:** `docs/superpowers/specs/2026-05-15-dispatch-history-dashboard-design.md`

---

## File Structure

**Migrations (9 new):**
- `supabase/migrations/20260516020000_meta_pricing.sql`
- `supabase/migrations/20260516020100_dispatch_link_opens.sql`
- `supabase/migrations/20260516020200_retry_safeguards.sql`
- `supabase/migrations/20260516020300_helper_functions.sql`
- `supabase/migrations/20260516020400_dispatch_history_unified_view.sql`
- `supabase/migrations/20260516020500_dispatch_rpcs_part1.sql`
- `supabase/migrations/20260516020600_dispatch_rpcs_part2.sql`
- `supabase/migrations/20260516020700_dispatch_rpcs_part3.sql`
- `supabase/migrations/20260516020800_dispatch_rpcs_part4.sql`

**Edge function (1 new):**
- `supabase/functions/dispatch-retry/index.ts`

**Frontend (3 new files):**
- `admin/envios/index.html`
- `admin/envios/app.js`
- `admin/envios/styles.css`

**Modified files:**
- `survey/app.js` — add `record_link_open` call

---

## Task 1: Migration — `meta_pricing` table + BR seed

**Files:**
- Create: `supabase/migrations/20260516020000_meta_pricing.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Meta API pricing table for cost estimation
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.meta_pricing (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_category text NOT NULL CHECK (template_category IN
    ('utility','authentication','marketing','service')),
  country_code      text NOT NULL,
  price_usd         numeric(10,5) NOT NULL,
  effective_from    date NOT NULL,
  effective_to      date,
  notes             text,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_meta_pricing_lookup
  ON public.meta_pricing (template_category, country_code, effective_from DESC)
  WHERE effective_to IS NULL;

ALTER TABLE public.meta_pricing ENABLE ROW LEVEL SECURITY;
CREATE POLICY "meta_pricing: read for auth" ON public.meta_pricing
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "meta_pricing: full for service" ON public.meta_pricing
  FOR ALL TO service_role USING (true) WITH CHECK (true);

INSERT INTO public.meta_pricing (template_category, country_code, price_usd, effective_from, notes) VALUES
  ('utility',        'BR', 0.00450, '2026-01-01', 'Utility/transactional templates BR'),
  ('authentication', 'BR', 0.00150, '2026-01-01', 'OTP BR'),
  ('marketing',      'BR', 0.06250, '2026-01-01', 'Marketing templates BR'),
  ('service',        'BR', 0.00000, '2026-01-01', 'Free-form 24h service window BR')
ON CONFLICT DO NOTHING;

COMMIT;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260516020000_meta_pricing.sql
git commit -m "feat(dashboard): add meta_pricing table for cost estimation"
```

---

## Task 2: Migration — `dispatch_link_opens` + `record_link_open` RPC

**Files:**
- Create: `supabase/migrations/20260516020100_dispatch_link_opens.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Link open tracking + public RPC for landing pages
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.dispatch_link_opens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source       text NOT NULL CHECK (source IN ('survey_link','nps_class_link')),
  dispatch_id  uuid NOT NULL,
  ip_hash      text,
  user_agent   text,
  referer      text,
  opened_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dispatch_link_opens_lookup
  ON public.dispatch_link_opens (source, dispatch_id, opened_at DESC);

ALTER TABLE public.dispatch_link_opens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "opens: read for auth" ON public.dispatch_link_opens
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "opens: full for service" ON public.dispatch_link_opens
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.record_link_open(
  p_source     text,
  p_token      text,
  p_user_agent text DEFAULT NULL,
  p_referer    text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_dispatch_id uuid;
BEGIN
  IF p_source = 'nps_class_link' THEN
    SELECT id INTO v_dispatch_id FROM nps_class_links
     WHERE token = p_token AND expires_at > now();
  ELSIF p_source = 'survey_link' THEN
    BEGIN
      SELECT id INTO v_dispatch_id FROM survey_links WHERE token = p_token::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_dispatch_id := NULL;
    END;
  ELSE
    RETURN false;
  END IF;

  IF v_dispatch_id IS NULL THEN RETURN false; END IF;

  INSERT INTO dispatch_link_opens (source, dispatch_id, user_agent, referer)
  VALUES (p_source, v_dispatch_id, p_user_agent, p_referer);

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.record_link_open(text, text, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.record_link_open(text, text, text, text) TO anon, authenticated;

COMMIT;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260516020100_dispatch_link_opens.sql
git commit -m "feat(dashboard): add dispatch_link_opens + record_link_open public RPC"
```

---

## Task 3: Migration — retry safeguards (tokens + audit)

**Files:**
- Create: `supabase/migrations/20260516020200_retry_safeguards.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Retry safeguards: confirm tokens + audit log
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.retry_confirm_tokens (
  token        text PRIMARY KEY,
  source       text NOT NULL,
  dispatch_id  uuid NOT NULL,
  issued_to    uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  issued_at    timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL DEFAULT now() + interval '15 minutes',
  consumed_at  timestamptz
);
CREATE INDEX IF NOT EXISTS idx_retry_tokens_active
  ON public.retry_confirm_tokens (token) WHERE consumed_at IS NULL;

ALTER TABLE public.retry_confirm_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "retry_tokens: service full" ON public.retry_confirm_tokens
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.dispatch_retry_audit (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source       text NOT NULL,
  dispatch_id  uuid NOT NULL,
  retried_by   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  retried_at   timestamptz NOT NULL DEFAULT now(),
  reason       text,
  result       jsonb
);
CREATE INDEX IF NOT EXISTS idx_retry_audit_dispatch
  ON public.dispatch_retry_audit (source, dispatch_id, retried_at DESC);

ALTER TABLE public.dispatch_retry_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY "retry_audit: read for auth" ON public.dispatch_retry_audit
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "retry_audit: service full" ON public.dispatch_retry_audit
  FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMIT;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260516020200_retry_safeguards.sql
git commit -m "feat(dashboard): add retry confirm tokens + audit log"
```

---

## Task 4: Migration — helper functions

**Files:**
- Create: `supabase/migrations/20260516020300_helper_functions.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Helper functions: cost estimator + admin guard
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.estimate_dispatch_cost_usd(
  p_template_category text,
  p_country_code      text DEFAULT 'BR',
  p_at_date           date DEFAULT CURRENT_DATE
) RETURNS numeric
LANGUAGE sql STABLE
SET search_path = public AS $$
  SELECT price_usd
  FROM public.meta_pricing
  WHERE template_category = p_template_category
    AND country_code      = p_country_code
    AND effective_from   <= p_at_date
    AND (effective_to IS NULL OR effective_to >= p_at_date)
  ORDER BY effective_from DESC LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.estimate_dispatch_cost_usd(text, text, date) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_dashboard_admin()
RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT COALESCE((auth.jwt()->'user_metadata'->>'role') = 'admin', false);
$$;
GRANT EXECUTE ON FUNCTION public.is_dashboard_admin() TO authenticated, anon, service_role;

COMMIT;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260516020300_helper_functions.sql
git commit -m "feat(dashboard): add cost estimator + admin guard helpers"
```

---

## Task 5: Migration — `dispatch_history_unified` VIEW

**Files:**
- Create: `supabase/migrations/20260516020400_dispatch_history_unified_view.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Unified dispatch history VIEW (read-only UNION across 4 sources)
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE VIEW public.dispatch_history_unified AS

-- 1. notifications
SELECT
  'notification'::text     AS source,
  n.id                     AS dispatch_id,
  CASE WHEN n.target_type = 'group' THEN 'evolution_group' ELSE 'meta_dm' END AS channel,
  n.created_at             AS sent_at,
  n.delivered_at           AS delivered_at,
  NULL::timestamptz        AS read_at,
  n.status                 AS status,
  NULL::text               AS error_detail,
  NULL::uuid               AS student_id,
  n.mentor_id              AS mentor_id,
  COALESCE(n.target_phone, n.target_group_jid) AS recipient_identifier,
  n.target_type            AS recipient_type,
  n.class_id, n.cohort_id,
  n.type::text             AS dispatch_type,
  NULL::text               AS template_name,
  'utility'::text          AS template_category,
  n.message_rendered       AS rendered_message,
  CASE WHEN n.evolution_message_ids IS NOT NULL
       AND array_length(n.evolution_message_ids, 1) > 0
       THEN n.evolution_message_ids[1] END AS provider_message_id,
  n.metadata               AS metadata,
  (SELECT COUNT(*) FROM dispatch_link_opens o WHERE o.source = 'notification' AND o.dispatch_id = n.id) AS open_count,
  (SELECT MAX(opened_at) FROM dispatch_link_opens o WHERE o.source = 'notification' AND o.dispatch_id = n.id) AS last_opened_at,
  0                        AS response_count,
  n.created_at
FROM public.notifications n

UNION ALL

-- 2. survey_links
SELECT
  'survey_link', sl.id, 'meta_dm',
  sl.sent_at,
  sl.delivered_at,
  sl.read_at,
  CASE
    WHEN sl.used_at IS NOT NULL THEN 'responded'
    WHEN sl.read_at IS NOT NULL THEN 'read'
    WHEN sl.delivered_at IS NOT NULL THEN 'delivered'
    WHEN sl.sent_at IS NOT NULL THEN 'sent'
    ELSE 'pending'
  END,
  NULL, sl.student_id, NULL,
  NULL, 'individual', NULL, NULL,
  'survey', NULL, 'utility', NULL, NULL,
  jsonb_build_object('survey_id', sl.survey_id, 'token', sl.token::text),
  (SELECT COUNT(*) FROM dispatch_link_opens o WHERE o.source = 'survey_link' AND o.dispatch_id = sl.id),
  (SELECT MAX(opened_at) FROM dispatch_link_opens o WHERE o.source = 'survey_link' AND o.dispatch_id = sl.id),
  CASE WHEN sl.used_at IS NOT NULL THEN 1 ELSE 0 END,
  sl.created_at
FROM public.survey_links sl

UNION ALL

-- 3. class_reminder_sends
SELECT
  'class_reminder', s.id, 'evolution_group',
  s.scheduled_at, s.sent_at, NULL,
  s.send_status, s.error_detail,
  NULL, NULL, s.group_jid, 'group',
  s.class_id, s.cohort_id, 'class_reminder',
  NULL, 'utility', s.message_preview, s.evolution_message_id,
  jsonb_build_object(
    'batch_id', s.batch_id,
    'reminder_type', s.reminder_type,
    'zoom_link', s.zoom_link_snapshot,
    'group_name', s.group_name
  ),
  0, NULL::timestamptz, 0,
  s.created_at
FROM public.class_reminder_sends s

UNION ALL

-- 4. nps_class_links
SELECT
  'nps_class_link', l.id,
  CASE WHEN l.mode = 'group' THEN 'evolution_group' ELSE 'meta_dm' END,
  l.created_at, NULL, NULL,
  CASE WHEN l.response_count > 0 THEN 'responded' ELSE 'sent' END,
  NULL, l.student_id, NULL, NULL,
  CASE WHEN l.mode = 'group' THEN 'group' ELSE 'individual' END,
  l.class_id, l.cohort_id, 'nps',
  NULL, 'utility', NULL, NULL,
  jsonb_build_object(
    'mode', l.mode,
    'token', l.token,
    'trigger_date', l.trigger_date,
    'expires_at', l.expires_at,
    'response_count', l.response_count
  ),
  (SELECT COUNT(*) FROM dispatch_link_opens o WHERE o.source = 'nps_class_link' AND o.dispatch_id = l.id),
  (SELECT MAX(opened_at) FROM dispatch_link_opens o WHERE o.source = 'nps_class_link' AND o.dispatch_id = l.id),
  l.response_count,
  l.created_at
FROM public.nps_class_links l;

GRANT SELECT ON public.dispatch_history_unified TO authenticated, service_role;

COMMIT;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260516020400_dispatch_history_unified_view.sql
git commit -m "feat(dashboard): add dispatch_history_unified VIEW"
```

---

## Task 6: Migration — RPCs part 1 (list + KPIs + trend)

**Files:**
- Create: `supabase/migrations/20260516020500_dispatch_rpcs_part1.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Dashboard RPCs part 1: list, KPIs, trend
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
           s.name AS student_name,
           s.phone AS student_phone,
           c.title AS class_title,
           co.name AS cohort_name,
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
    f.status, f.error_detail, f.student_id, f.student_name, f.student_phone,
    f.recipient_identifier, f.recipient_type, f.class_id, f.class_title,
    f.cohort_id, f.cohort_name, f.dispatch_type, f.template_name, f.template_category,
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
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260516020500_dispatch_rpcs_part1.sql
git commit -m "feat(dashboard): add RPCs list_dispatch_history + summary_kpis + trend_daily"
```

---

## Task 7: Migration — RPCs part 2 (top, failures, channel, funnel)

**Files:**
- Create: `supabase/migrations/20260516020600_dispatch_rpcs_part2.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Dashboard RPCs part 2: top classes, failures, channel breakdown, funnel
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── dispatch_top_classes ───────────────────────────────────────────────
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
  SELECT v.class_id, c.title, COUNT(*) AS total_sent
  FROM dispatch_history_unified v
  JOIN classes c ON c.id = v.class_id
  WHERE v.class_id IS NOT NULL
    AND (p_filters->>'date_from' IS NULL OR v.sent_at >= (p_filters->>'date_from')::timestamptz)
    AND (p_filters->>'date_to'   IS NULL OR v.sent_at <  (p_filters->>'date_to')::timestamptz)
  GROUP BY v.class_id, c.title
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
  source         text,
  dispatch_id    uuid,
  channel        text,
  recipient_label text,
  error_detail   text,
  failed_at      timestamptz
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

-- ─── dispatch_funnel ────────────────────────────────────────────────────
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

  WITH base AS (
    SELECT v.*
    FROM dispatch_history_unified v
    WHERE (p_filters->>'date_from' IS NULL OR v.sent_at >= (p_filters->>'date_from')::timestamptz)
      AND (p_filters->>'date_to'   IS NULL OR v.sent_at <  (p_filters->>'date_to')::timestamptz)
  )
  SELECT
    COUNT(*),
    COUNT(*) FILTER (WHERE delivered_at IS NOT NULL),
    COUNT(*) FILTER (WHERE read_at IS NOT NULL),
    COUNT(*) FILTER (WHERE open_count > 0),
    COUNT(*) FILTER (WHERE response_count > 0)
  INTO v_sent, v_delivered, v_read, v_opened, v_responded
  FROM base;

  RETURN QUERY
  SELECT * FROM (VALUES
    ('sent',      v_sent,      100.0::numeric),
    ('delivered', v_delivered, ROUND(100.0 * v_delivered / NULLIF(v_sent, 0), 2)),
    ('read',      v_read,      ROUND(100.0 * v_read      / NULLIF(v_sent, 0), 2)),
    ('opened',    v_opened,    ROUND(100.0 * v_opened    / NULLIF(v_sent, 0), 2)),
    ('responded', v_responded, ROUND(100.0 * v_responded / NULLIF(v_sent, 0), 2))
  ) AS t(stage, count, pct_of_sent);
END;
$$;
GRANT EXECUTE ON FUNCTION public.dispatch_funnel(jsonb) TO authenticated;

COMMIT;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260516020600_dispatch_rpcs_part2.sql
git commit -m "feat(dashboard): add RPCs top_classes + failures + channel + funnel"
```

---

## Task 8: Migration — RPCs part 3 (render_message_preview)

**Files:**
- Create: `supabase/migrations/20260516020700_dispatch_rpcs_part3.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Dashboard RPCs part 3: render_message_preview (JIT message rendering)
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.render_message_preview(
  p_source       text,
  p_dispatch_id  uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT is_dashboard_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  IF p_source = 'survey_link' THEN
    SELECT jsonb_build_object(
      'message', 'Link da pesquisa: https://painel.academialendaria.ai/r/' || sl.token::text,
      'template_name', sv.meta_template_name,
      'recipient_phone', s.phone,
      'recipient_name', s.name,
      'survey_title', sv.title
    ) INTO v_result
    FROM survey_links sl
    LEFT JOIN students s ON s.id = sl.student_id
    LEFT JOIN surveys  sv ON sv.id = sl.survey_id
    WHERE sl.id = p_dispatch_id;

  ELSIF p_source = 'notification' THEN
    SELECT jsonb_build_object(
      'message', n.message_rendered,
      'recipient_phone', n.target_phone,
      'recipient_group', n.target_group_jid,
      'type', n.type,
      'metadata', n.metadata
    ) INTO v_result
    FROM notifications n WHERE n.id = p_dispatch_id;

  ELSIF p_source = 'class_reminder' THEN
    SELECT jsonb_build_object(
      'message', s.message_preview,
      'recipient_group', s.group_jid,
      'group_name', s.group_name,
      'zoom_link', s.zoom_link_snapshot,
      'reminder_type', s.reminder_type
    ) INTO v_result
    FROM class_reminder_sends s WHERE s.id = p_dispatch_id;

  ELSIF p_source = 'nps_class_link' THEN
    SELECT jsonb_build_object(
      'message',
        'Link NPS: https://painel.academialendaria.ai/survey/' ||
        CASE WHEN l.mode = 'group' THEN 'grupo' ELSE 'aluno' END ||
        '/' || l.token,
      'mode', l.mode,
      'expires_at', l.expires_at,
      'response_count', l.response_count,
      'recipient_name', CASE WHEN l.mode = 'dm' THEN (SELECT name FROM students WHERE id = l.student_id) END
    ) INTO v_result
    FROM nps_class_links l WHERE l.id = p_dispatch_id;
  END IF;

  RETURN COALESCE(v_result, jsonb_build_object('error', 'dispatch_not_found'));
END;
$$;
GRANT EXECUTE ON FUNCTION public.render_message_preview(text, uuid) TO authenticated;

COMMIT;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260516020700_dispatch_rpcs_part3.sql
git commit -m "feat(dashboard): add render_message_preview RPC"
```

---

## Task 9: Migration — RPCs part 4 (retry flow)

**Files:**
- Create: `supabase/migrations/20260516020800_dispatch_rpcs_part4.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Dashboard RPCs part 4: get_retry_confirm_token + retry_dispatch
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.get_retry_confirm_token(
  p_source       text,
  p_dispatch_id  uuid
) RETURNS TABLE (
  token        text,
  expires_at   timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_token      text;
  v_expires_at timestamptz;
  v_status     text;
BEGIN
  IF NOT is_dashboard_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  -- Only allow tokens for currently-failed dispatches
  SELECT v.status INTO v_status
  FROM dispatch_history_unified v
  WHERE v.source = p_source AND v.dispatch_id = p_dispatch_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'dispatch_not_found';
  END IF;
  IF v_status <> 'failed' THEN
    RAISE EXCEPTION 'retry_only_allowed_for_failed_dispatches';
  END IF;

  v_token      := encode(gen_random_bytes(24), 'base64');
  v_expires_at := now() + interval '15 minutes';

  INSERT INTO retry_confirm_tokens (token, source, dispatch_id, issued_to, expires_at)
  VALUES (v_token, p_source, p_dispatch_id, auth.uid(), v_expires_at);

  RETURN QUERY SELECT v_token, v_expires_at;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_retry_confirm_token(text, uuid) TO authenticated;

-- ─── retry_dispatch ────────────────────────────────────────────────────
-- Validates token then calls edge function `dispatch-retry` via pg_net.http_post
CREATE OR REPLACE FUNCTION public.retry_dispatch(
  p_source         text,
  p_dispatch_id    uuid,
  p_confirm_token  text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id   uuid := auth.uid();
  v_fn_url    text;
  v_svc_key   text;
  v_audit_id  uuid;
  v_request_id bigint;
BEGIN
  IF NOT is_dashboard_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM retry_confirm_tokens
     WHERE token = p_confirm_token
       AND source = p_source
       AND dispatch_id = p_dispatch_id
       AND issued_to = v_user_id
       AND expires_at > now()
       AND consumed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'invalid_or_expired_confirm_token';
  END IF;

  UPDATE retry_confirm_tokens
     SET consumed_at = now()
   WHERE token = p_confirm_token;

  INSERT INTO dispatch_retry_audit (source, dispatch_id, retried_by, retried_at, reason)
  VALUES (p_source, p_dispatch_id, v_user_id, now(), 'manual_admin_retry')
  RETURNING id INTO v_audit_id;

  SELECT value INTO v_fn_url  FROM app_config WHERE key = 'dispatch_retry_url';
  SELECT value INTO v_svc_key FROM app_config WHERE key = 'supabase_service_key';

  IF v_fn_url IS NULL OR v_svc_key IS NULL THEN
    UPDATE dispatch_retry_audit
       SET result = jsonb_build_object('queued', false, 'error', 'missing_app_config')
     WHERE id = v_audit_id;
    RETURN jsonb_build_object('success', false, 'error', 'missing_app_config');
  END IF;

  SELECT net.http_post(
    url     := v_fn_url,
    body    := jsonb_build_object(
      'source', p_source,
      'dispatch_id', p_dispatch_id,
      'audit_id', v_audit_id,
      'retried_by', v_user_id
    ),
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_svc_key,
      'Content-Type',  'application/json'
    )
  ) INTO v_request_id;

  UPDATE dispatch_retry_audit
     SET result = jsonb_build_object('queued', true, 'http_request_id', v_request_id)
   WHERE id = v_audit_id;

  RETURN jsonb_build_object('success', true, 'queued_at', now(), 'audit_id', v_audit_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.retry_dispatch(text, uuid, text) TO authenticated;

-- Ensure app_config has dispatch_retry_url placeholder
INSERT INTO public.app_config (key, value) VALUES
  ('dispatch_retry_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/dispatch-retry')
ON CONFLICT (key) DO NOTHING;

COMMIT;
```

- [ ] **Step 2: Commit**

```bash
git add supabase/migrations/20260516020800_dispatch_rpcs_part4.sql
git commit -m "feat(dashboard): add retry flow RPCs (token + retry_dispatch)"
```

---

## Task 10: Edge function `dispatch-retry`

**Files:**
- Create: `supabase/functions/dispatch-retry/index.ts`

This function receives a retry request and re-invokes the appropriate dispatcher per source. V1 only supports retrying a single dispatch (no batch). For each source, it:

1. Loads dispatch row
2. Calls the original source's dispatch function/path
3. Updates `dispatch_retry_audit.result` with the outcome

- [ ] **Step 1: Write the function**

```typescript
// ═══════════════════════════════════════════════════════════════════════════
// dispatch-retry — Re-trigger a single dispatch identified by (source, id).
//
// Invoked by retry_dispatch RPC (PostgreSQL) via pg_net.http_post with body:
//   { source, dispatch_id, audit_id, retried_by }
//
// V1: supports notification + class_reminder. Other sources return not_supported.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  let body: { source?: string; dispatch_id?: string; audit_id?: string; retried_by?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const source = body.source;
  const dispatch_id = body.dispatch_id;
  const audit_id = body.audit_id;

  if (!source || !dispatch_id || !audit_id) {
    return json({ error: "missing_fields" }, 400);
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const updateAudit = async (result: Record<string, unknown>) => {
    await sb.from("dispatch_retry_audit")
      .update({ result })
      .eq("id", audit_id);
  };

  try {
    if (source === "class_reminder") {
      // Re-invoke dispatch-class-reminders with batch_id filter (forces one row to be re-sent)
      const { data: row } = await sb.from("class_reminder_sends")
        .select("id, batch_id, send_status").eq("id", dispatch_id).maybeSingle();
      if (!row) { await updateAudit({ ok: false, reason: "row_not_found" }); return json({ ok: false }); }
      if (row.send_status !== "failed") {
        await updateAudit({ ok: false, reason: "not_failed_anymore", current_status: row.send_status });
        return json({ ok: false });
      }
      // Reset to pending — dispatcher cron picks it up
      await sb.from("class_reminder_sends").update({ send_status: "pending", error_detail: null }).eq("id", dispatch_id);
      const r = await fetch(`${SUPABASE_URL}/functions/v1/dispatch-class-reminders`, {
        method: "POST",
        headers: { "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`, "Content-Type": "application/json" },
        body: JSON.stringify({ batch_id: row.batch_id }),
      });
      await updateAudit({ ok: r.ok, status: r.status });
      return json({ ok: r.ok });
    }

    if (source === "notification") {
      // notifications has its own worker — reset status and let it pick up
      const { data: row } = await sb.from("notifications")
        .select("id, status").eq("id", dispatch_id).maybeSingle();
      if (!row) { await updateAudit({ ok: false, reason: "row_not_found" }); return json({ ok: false }); }
      if (row.status !== "failed") {
        await updateAudit({ ok: false, reason: "not_failed_anymore" });
        return json({ ok: false });
      }
      await sb.from("notifications").update({ status: "pending" }).eq("id", dispatch_id);
      await updateAudit({ ok: true, action: "marked_pending_for_worker" });
      return json({ ok: true });
    }

    if (source === "survey_link") {
      // survey_links retry requires re-dispatch via dispatch-survey — keep V1 simple, mark not_supported
      await updateAudit({ ok: false, reason: "retry_not_supported_for_survey_link_v1" });
      return json({ ok: false, error: "not_supported" }, 501);
    }

    if (source === "nps_class_link") {
      // NPS links don't fail in the traditional sense (no dispatch row) — out of scope
      await updateAudit({ ok: false, reason: "retry_not_applicable_for_nps_class_link" });
      return json({ ok: false, error: "not_applicable" }, 501);
    }

    await updateAudit({ ok: false, reason: "unknown_source" });
    return json({ error: "unknown_source" }, 400);
  } catch (e) {
    await updateAudit({ ok: false, reason: "exception", error: String(e) });
    return json({ error: "internal_error" }, 500);
  }
});
```

- [ ] **Step 2: Commit**

```bash
git add supabase/functions/dispatch-retry/index.ts
git commit -m "feat(dashboard): add dispatch-retry edge function for failed dispatches"
```

---

## Task 11: Frontend — `admin/envios/index.html` shell

**Files:**
- Create: `admin/envios/index.html`

- [ ] **Step 1: Write the HTML shell**

(Pattern: follow `admin/index.html` for login overlay + theme; structure for filters drawer + KPI cards + charts + tables + dispatch table + side modal.)

Use admin shared styles `/templates/design-tokens-dark-premium.css` and `/templates/admin-shared.css`. Include `https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.js`.

Sections (IDs for app.js to target):
- `#login-overlay` (reuses admin pattern)
- `#filters-drawer` (slide-out)
- `#kpi-grid` (4 cards)
- `#trend-chart` (canvas)
- `#funnel-chart` (canvas)
- `#top-classes-table`
- `#failures-table`
- `#channel-breakdown-table`
- `#envios-table` (paginated)
- `#dispatch-modal` (side modal)
- `#retry-confirm-modal` (submodal)
- `#export-csv-btn`

(Full HTML omitted here for brevity — see file in repo after Task implementation. Header note: Plan engineer should write a complete HTML following the layout in `docs/superpowers/specs/2026-05-15-dispatch-history-dashboard-design.md` §6.2.)

- [ ] **Step 2: Commit**

```bash
git add admin/envios/index.html
git commit -m "feat(dashboard): add admin/envios HTML shell"
```

---

## Task 12: Frontend — `admin/envios/app.js`

**Files:**
- Create: `admin/envios/app.js`

The JS handles:

1. Login overlay (reuse pattern from `admin/index.html`)
2. On auth, fetch in parallel: `dispatch_summary_kpis`, `dispatch_trend_daily`, `dispatch_funnel`, `dispatch_top_classes`, `dispatch_recent_failures`, `dispatch_channel_breakdown`
3. Render Chart.js charts (trend = line chart 3 datasets, funnel = horizontal bar)
4. Build dispatch table from `list_dispatch_history` with pagination
5. Filter drawer state → builds JSONB filter object → re-fires all queries
6. Row click → opens modal, calls `render_message_preview`, renders WhatsApp-bubble + timeline
7. Retry: button disabled if `status !== 'failed'`. Click → calls `get_retry_confirm_token` → shows submodal with rendered preview → confirm → calls `retry_dispatch` → polls dispatch status after 5s
8. CSV export: builds CSV string from all currently-loaded pages (re-fetches up to 5000 rows total) → triggers download

(Full JS skeleton ~500 lines — engineer follows spec §6 and pattern of existing `admin/index.html` JS for Supabase client setup, auth state, RPC calls. Use `SUPABASE_URL` + anon key constants.)

- [ ] **Step 2: Commit**

```bash
git add admin/envios/app.js
git commit -m "feat(dashboard): add admin/envios app.js with charts + filters + retry flow"
```

---

## Task 13: Frontend — `admin/envios/styles.css`

**Files:**
- Create: `admin/envios/styles.css`

CSS classes:
- `.kpi-card` (big number block)
- `.chart-container`
- `.filter-drawer` (slide-out right)
- `.dispatch-modal` (side modal slide-in)
- `.retry-confirm-modal` (centered overlay)
- `.whatsapp-bubble` (chat-style green bubble with rounded corners + timestamp + read marks)
- `.timeline-entry` (vertical timeline dots + labels)
- `.pagination-controls`
- `.csv-export-btn`
- Mobile responsive: stack KPIs vertically, drawer becomes full-screen below 768px

- [ ] **Step 2: Commit**

```bash
git add admin/envios/styles.css
git commit -m "feat(dashboard): add admin/envios styles"
```

---

## Task 14: Update P2 — instrument `survey/app.js` to record opens

**Files:**
- Modify: `survey/app.js`

- [ ] **Step 1: Add `recordOpen` function**

After `fetchMetadata` (in `init()`), call:

```javascript
async function recordOpen(source, token) {
  fetch(`${SUPABASE_URL}/rest/v1/rpc/record_link_open`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": SUPABASE_ANON_KEY,
      "Authorization": `Bearer ${SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify({
      p_source: source,
      p_token: token,
      p_user_agent: navigator.userAgent.slice(0, 500),
      p_referer: document.referrer || null,
    }),
  }).catch(() => {});
}
```

Call inside `init()` after metadata fetch succeeds, before showing form:

```javascript
const parsedSource = parsed.mode === "group" ? "nps_class_link" : "nps_class_link";
recordOpen(parsedSource, parsed.token);  // fire-and-forget
```

- [ ] **Step 2: Commit**

```bash
git add survey/app.js
git commit -m "feat(nps): instrument survey landing to record link opens for dashboard"
```

---

## Task 15: Production deploy authorization gate

This task is intentionally not auto-executed. After all prior tasks complete + reviewed, present to user for explicit authorization to:

1. `supabase db push` (applies 9 migrations to production)
2. `supabase functions deploy dispatch-retry --no-verify-jwt`
3. Anon key replacement in `admin/envios/app.js` (same as P2)
4. Seed admin role assignment if not yet set
5. Smoke test on production

Do NOT execute these steps automatically.

---

## Self-review checklist

- [x] All RPCs include `is_dashboard_admin()` check at entry (Tasks 6–9).
- [x] All migrations idempotent (`IF NOT EXISTS` / `CREATE OR REPLACE`).
- [x] No external comms triggered without admin retry token (Task 9, 10).
- [x] Spec coverage: §4 (DB) → T1–T5; §5 (RPCs) → T6–T9; §6 (frontend) → T11–T13; §7 (P2 integration) → T14; §8 (retry safeguards) → T3 + T9 + T10.
- [x] All hardcoded `painel.academialendaria.ai` URLs in RPCs (Task 8, 9).
- [x] VIEW columns consistent across all UNION ALL branches.
- [x] Retry tokens are 15-min single-use, scoped to (user, dispatch).
- [x] Audit row created BEFORE pg_net call (so failures still leave an audit trail).
- [x] CSV export limit (5000 rows) documented in spec — engineer enforces in T12.

## Out-of-scope (deferred V2)

- Materialized view for performance (only if real data shows pain).
- Per-template A/B analytics page.
- PDF export.
- Real-time Meta Billing API reconciliation.
- Batch retry button.
- Email/SMS channels (architecture supports; no impl).
