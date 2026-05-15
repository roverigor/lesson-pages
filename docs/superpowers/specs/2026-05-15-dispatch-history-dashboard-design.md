# P4 — Dispatch History Dashboard

**Status:** Draft
**Date:** 2026-05-15
**Author:** Orion (aiox-master)
**Parent epic:** Unified Dispatch Visibility (standalone sub-project; sibling to P1/P2/P3 NPS workstream)
**Depends on:** none (foundational; reads existing tables + P2's `nps_class_links`)
**Blocks:** none

---

## 1. Motivation

Direction (diretoria) lacks single-pane visibility of all outbound messaging across channels. Existing CS portal has a similar tool but in a separate codebase. The painel (`painel.academialendaria.ai`) needs a friendlier UX-UI version that:

- Shows ALL dispatches (Meta DM + Evolution group + future Email/SMS)
- Exact preview of the WhatsApp message as the student received it
- Status: sent / delivered / read / opened (link clicked) / responded / ignored / failed
- Dashboard widgets (KPIs, trends, top-class breakdown, funnel)
- Meta API cost estimate ($)
- Filters (date, channel+status, class/cohort/student, dispatch type, template)
- CSV export of filtered results
- Drilldown modal with WhatsApp-style preview + status timeline + retry button (status=failed only)

This sub-project is internal (admin-only) and read-mostly. The single write operation — retry — sits behind a strict confirmation gate (CLAUDE.md NON-NEGOTIABLE: external comms require explicit human approval per send).

---

## 2. Goals & Non-Goals

### Goals (V1)

- Unified read-only VIEW over 4 dispatch sources: `notifications`, `survey_links`, `class_reminder_sends`, `nps_class_links`.
- Anonymous link-open tracking via new table `dispatch_link_opens` (+ public RPC).
- Backend RPCs (admin-only via JWT role check): list, KPIs, trends, top classes, failures, channel breakdown, render preview, retry.
- Admin page at `/admin/envios/` (Painel) with:
  - 4 KPI cards
  - 3 trend line charts (envios/dia, custo/dia, falhas/dia)
  - 3 tables (top turmas, falhas 24h, breakdown canal)
  - Conversion funnel (sent → delivered → read → opened → responded)
  - Filterable paginated dispatch table (50/page)
  - Side-modal drilldown with WhatsApp-style rendered preview + status timeline + retry (failed only)
- CSV export of currently filtered rows.
- `meta_pricing` table for Meta API cost estimation, seeded with current BR prices.
- All URLs use `painel.academialendaria.ai` as canonical (env var `PAINEL_BASE_URL`); `painel.igorrover.com.br` keeps working as DR fallback.

### Non-Goals (deferred)

- Live websocket updates (V1 = pull on user action / page load).
- Meta Business Billing API reconciliation (V2 — currently estimate-only).
- PDF export (V2 — CSV only for V1).
- Batch retry (V1 = single dispatch retry per click).
- Materialized view (only if performance shows pain on real data — V1 stays on plain VIEW).
- Email/SMS channels (architecture supports them via `channel` column; no implementation here — YAGNI until real channels exist).
- Edit / cancel pending dispatch (out of scope — separate feature).
- Dashboard for Slack alerts (user excluded Slack).

---

## 3. Architecture

```
Frontend (admin/envios/index.html, app.js)
  ↓ Supabase JS client (anon key + JWT admin)
Backend RPCs (PostgreSQL SECURITY DEFINER, is_dashboard_admin() guard)
  ↓
dispatch_history_unified VIEW (UNION ALL of 4 source tables)
  + LEFT JOIN LATERAL dispatch_link_opens (open_count, last_opened_at)
  ↓
Source tables (read-only): notifications, survey_links,
                            class_reminder_sends, nps_class_links
Pricing: meta_pricing (versioned by effective_from/to)
Retry safeguards: retry_confirm_tokens, dispatch_retry_audit
```

**Decomposition principle:** RPCs are the API contract; the VIEW is an implementation detail; the frontend never queries the VIEW directly. This lets the VIEW change (add sources, switch to materialized) without breaking the frontend.

---

## 4. Database

### 4.1 `meta_pricing` (new)

```sql
CREATE TABLE public.meta_pricing (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_category text NOT NULL CHECK (template_category IN
    ('utility','authentication','marketing','service')),
  country_code      text NOT NULL,
  price_usd         numeric(10,5) NOT NULL,
  effective_from    date NOT NULL,
  effective_to      date,
  notes             text,
  created_at        timestamptz DEFAULT now()
);
CREATE INDEX idx_meta_pricing_lookup ON meta_pricing
  (template_category, country_code, effective_from DESC) WHERE effective_to IS NULL;
```

**Seed (BR, 2026):**

| category       | country | USD     | notes                              |
|----------------|---------|---------|------------------------------------|
| utility        | BR      | 0.00450 | Utility/transactional templates    |
| authentication | BR      | 0.00150 | OTP                                |
| marketing      | BR      | 0.06250 | Marketing templates                |
| service        | BR      | 0.00000 | Free-form 24h service window       |

Admin updates the table when Meta announces price changes — keeps history via `effective_from/effective_to`.

### 4.2 `dispatch_link_opens` (new)

```sql
CREATE TABLE public.dispatch_link_opens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source       text NOT NULL CHECK (source IN ('survey_link','nps_class_link')),
  dispatch_id  uuid NOT NULL,
  ip_hash      text,
  user_agent   text,
  referer      text,
  opened_at    timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX idx_dispatch_link_opens_lookup
  ON public.dispatch_link_opens (source, dispatch_id, opened_at DESC);
ALTER TABLE public.dispatch_link_opens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "opens: read for auth" ON public.dispatch_link_opens
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "opens: full for service" ON public.dispatch_link_opens
  FOR ALL TO service_role USING (true) WITH CHECK (true);
```

### 4.3 `retry_confirm_tokens` + `dispatch_retry_audit` (new)

```sql
CREATE TABLE public.retry_confirm_tokens (
  token        text PRIMARY KEY,
  source       text NOT NULL,
  dispatch_id  uuid NOT NULL,
  issued_to    uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  issued_at    timestamptz DEFAULT now(),
  expires_at   timestamptz DEFAULT now() + interval '15 minutes',
  consumed_at  timestamptz
);
CREATE INDEX idx_retry_tokens_active
  ON retry_confirm_tokens (token) WHERE consumed_at IS NULL;

CREATE TABLE public.dispatch_retry_audit (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source       text NOT NULL,
  dispatch_id  uuid NOT NULL,
  retried_by   uuid REFERENCES auth.users(id),
  retried_at   timestamptz DEFAULT now(),
  reason       text,
  result       jsonb
);
CREATE INDEX idx_retry_audit_dispatch
  ON dispatch_retry_audit (source, dispatch_id, retried_at DESC);
```

### 4.4 `dispatch_history_unified` VIEW

UNION ALL over 4 source tables, LEFT JOIN LATERAL with `dispatch_link_opens` to enrich `open_count`. See section 2-bis of the brainstorming transcript for the full VIEW DDL (notifications + survey_links + class_reminder_sends + nps_class_links).

Columns (uniform shape):

```
source, dispatch_id, channel, sent_at, delivered_at, read_at,
status, error_detail, student_id, mentor_id,
recipient_identifier, recipient_type,
class_id, cohort_id, dispatch_type, template_name, template_category,
rendered_message, provider_message_id, metadata,
open_count, last_opened_at, unique_openers, response_count,
created_at
```

Status mapping (per source):

| Source              | Status derivation                                                |
|---------------------|------------------------------------------------------------------|
| notifications       | direct `status` column                                           |
| survey_links        | derived: used_at > responded > read_at > delivered_at > sent_at > pending |
| class_reminder_sends| direct `send_status` column                                      |
| nps_class_links     | derived: response_count>0 ⇒ responded; else sent                 |

### 4.5 Helper functions

```sql
-- Resolves price for template+country+date
CREATE FUNCTION public.estimate_dispatch_cost_usd(
  p_template_category text, p_country_code text DEFAULT 'BR',
  p_at_date date DEFAULT CURRENT_DATE
) RETURNS numeric LANGUAGE sql STABLE;

-- Admin guard
CREATE FUNCTION public.is_dashboard_admin() RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT (auth.jwt()->'user_metadata'->>'role') = 'admin';
$$;
```

---

## 5. Backend RPCs

All RPCs are `SECURITY DEFINER` + start with `IF NOT is_dashboard_admin() THEN RAISE 'forbidden'`.

| Function                          | Purpose                                                |
|-----------------------------------|--------------------------------------------------------|
| `list_dispatch_history(filters, page, size)` | Paginated filtered list (50/page)        |
| `dispatch_summary_kpis(filters)`  | 4 big numbers (sent, delivered%, read%, cost$) + open% + response% |
| `dispatch_trend_daily(filters, days)`  | Line chart data (envios/dia, custo/dia, falhas/dia) |
| `dispatch_top_classes(filters, limit)` | Top N classes by total dispatches              |
| `dispatch_recent_failures(filters)` | Failures in last 24h with details                  |
| `dispatch_channel_breakdown(filters)` | Counts grouped by channel                         |
| `dispatch_funnel(filters)`        | Funnel stages: sent→delivered→read→opened→responded   |
| `render_message_preview(source, dispatch_id)` | JSON with rendered text + recipient    |
| `get_retry_confirm_token(source, dispatch_id)` | Issues 15-min one-time token         |
| `retry_dispatch(source, dispatch_id, confirm_token)` | Re-dispatches via edge function  |
| `record_link_open(source, token, ip_hash, ua, referer)` | Public (anon) — instrumentation from landing pages |

**Filter JSONB shape:**

```json
{
  "date_from": "2026-05-08T00:00:00Z",
  "date_to":   "2026-05-15T23:59:59Z",
  "channels":  ["meta_dm","evolution_group"],
  "statuses":  ["sent","delivered","read","failed"],
  "class_id":  "uuid",
  "cohort_id": "uuid",
  "student_search": "joão",
  "dispatch_types": ["nps","survey","class_reminder"],
  "template_name": "encerramento_fundamentals_v3"
}
```

All filter fields are optional; absent fields skip that filter.

---

## 6. Frontend UI

### 6.1 Route

- Path: `/admin/envios/` (Painel)
- Auth: requires login + `user_metadata.role = 'admin'`
- Files: `admin/envios/index.html`, `admin/envios/app.js`, `admin/envios/styles.css`
- Follows existing admin pattern (login overlay → main UI after auth)

### 6.2 Layout

```
┌──────────────────────────────────────────────────────────────────────────┐
│ Painel Admin — Envios            [Filtros ⌄]  [Atualizar]  [Export CSV] │
├──────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐                   │
│  │ ENVIOS   │ │ ENTREGUE │ │ LIDO     │ │ CUSTO    │                   │
│  │  1.234   │ │   92%    │ │   78%    │ │ $5.43    │  (4 KPI cards)    │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘                   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Tendência últimos 30 dias                                        │   │
│  │  [line chart: envios/dia, custo/dia, falhas/dia]                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Funil: enviado → entregue → lido → aberto → respondido          │   │
│  │  [horizontal funnel chart with %]                                │   │
│  └─────────────────────────────────────────────────────────────────┘   │
│                                                                          │
│  ┌──────────────────────┐ ┌──────────────────┐ ┌──────────────────┐   │
│  │ Top turmas (envios)  │ │ Falhas 24h       │ │ Canais           │   │
│  │ 1. PS Fund — 345     │ │ • João (Meta...) │ │ Meta DM: 67%     │   │
│  │ 2. Adv — 210         │ │ • Maria (Evol..) │ │ Evolution: 33%   │   │
│  │ 3. Cohort T6 — 188   │ │ ...              │ │                  │   │
│  └──────────────────────┘ └──────────────────┘ └──────────────────┘   │
│                                                                          │
│  ┌─────────────────────────────────────────────────────────────────┐   │
│  │ Envios (1.234 total — pg 1 de 25)                               │   │
│  │ ┌───────────┬──────────┬──────────────┬─────────┬──────┬──────┐│   │
│  │ │ Data      │ Canal    │ Para         │ Tipo    │ Status│ $   ││   │
│  │ ├───────────┼──────────┼──────────────┼─────────┼──────┼──────┤│   │
│  │ │ 15/05 09h │ Meta DM  │ João Silva   │ NPS     │ ✓ Lido│ 0.005││   │
│  │ │ 15/05 09h │ Evol grp │ Cohort Fund6 │ Reminder│ ✓ Sent│ —   ││   │
│  │ │ 15/05 08h │ Meta DM  │ Maria        │ Survey  │ ✗ Fail│ —   ││   │
│  │ │ ...       │ ...      │ ...          │ ...     │ ...  │ ...  ││   │
│  │ └───────────┴──────────┴──────────────┴─────────┴──────┴──────┘│   │
│  │ [Anterior] Página 1 de 25 [Próxima]                              │   │
│  └─────────────────────────────────────────────────────────────────┘   │
└──────────────────────────────────────────────────────────────────────────┘
```

### 6.3 Filter drawer

Right-side slide-out drawer. Sections:

1. **Período:** date range picker (default last 7d).
2. **Canal + Status:** chip multi-select. Channels: Meta DM, Evolution Group. Status: pending, sent, delivered, read, responded, failed.
3. **Turma + Aluno:** dropdown class, dropdown cohort (filtered by class), text input for student name/phone search.
4. **Tipo + Template:** dropdown dispatch type (nps, survey, class_reminder, notification, custom). Dropdown template name (populated from distinct values).

Apply button triggers RPC calls with built JSONB filter object.

### 6.4 Drilldown side modal

Slide-in from right (50% viewport on desktop, full-screen on mobile). Sections:

**Header:** `<channel icon> <recipient> · <sent_at>`

**WhatsApp preview:** chat-style bubble rendering the message exactly as the student saw it:

```
┌──────────────────────────────────────┐
│  WhatsApp simulator                  │
│  ┌─────────────────────────────────┐ │
│  │ Olá, João!                      │ │
│  │                                 │ │
│  │ Sua aula de PS Fundamentals    │ │
│  │ acabou de terminar. Como foi   │ │
│  │ pra você?                      │ │
│  │                                 │ │
│  │ 🔗 painel.academialendaria.ai/ │ │
│  │    survey/aluno/abc123def      │ │
│  │                              09:14 ✓✓│
│  └─────────────────────────────────┘ │
└──────────────────────────────────────┘
```

Bubble styling matches WhatsApp green theme, includes timestamp + read marks (✓✓ green if read).

**Timeline:**

```
● Enviado     15/05 09:14:23
● Entregue    15/05 09:14:25 (+2s)
● Lido        15/05 09:18:11 (+4min)
● Aberto link 15/05 09:18:34 (+23s)
○ Respondido  ainda aguardando
```

**Metadata:** key-value table (template name, provider_message_id, retry count, etc).

**Actions:**
- "Reenviar" button (only if status='failed' — disabled otherwise) → opens confirm submodal:
  ```
  ┌────────────────────────────────────────────────┐
  │  ⚠️ Confirmar reenvio                          │
  │                                                │
  │  Destinatário: João Silva (+55 11 99...)      │
  │  Mensagem:                                    │
  │    <rendered preview, read-only>              │
  │                                                │
  │  Esta ação envia uma mensagem real ao aluno. │
  │  [ Cancelar ]            [ Sim, reenviar ]   │
  └────────────────────────────────────────────────┘
  ```
- "Fechar" closes modal.

### 6.5 Charts library

Use **Chart.js v4** (vanilla JS, no React/Vue dependency). Loaded from CDN. Existing admin pages use this library elsewhere in the painel — follow precedent.

### 6.6 CSV Export

Button in toolbar. Click → builds CSV client-side from currently loaded `list_dispatch_history` rows (all pages — fetches up to 5000 rows; warn if more). Columns: data, canal, destinatário, tipo, template, status, custo, link aberto?, respondeu?. Downloads as `envios-{date_from}-to-{date_to}.csv`.

---

## 7. P2 integration: open tracking

`survey/app.js` is updated to call `record_link_open` RPC on init (after metadata fetches successfully, before showing the form). Fire-and-forget — never blocks UX. Failure on this RPC does not impact the form.

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

For existing `survey_links` dispatched through `dispatch-survey` (which uses redirect via `r/{token}` short URL hosted in survey landing page): that landing page also needs the same instrumentation. Out of scope for P4 spec — separate small task in P4 plan (covered as "Task: instrument existing landing pages").

---

## 8. Retry safeguards (CLAUDE.md compliance)

The retry button is the single write action in this dashboard. CLAUDE.md NON-NEGOTIABLE: external comms require explicit human approval at execution time. The retry flow enforces this in three layers:

1. **Status gate:** button only enabled for `status='failed'` dispatches (no re-sending successful messages).
2. **Two-step confirm:**
   - First click → opens confirm submodal showing rendered preview + recipient.
   - Submodal shows full message — admin reads what they're about to re-send.
   - Confirm requires explicit click.
3. **One-time token:** confirm submodal calls `get_retry_confirm_token` which issues a 15-min single-use token tied to (user, dispatch_id). The actual `retry_dispatch` RPC requires this token. Tokens expire and consume — no reusable confirmation.

**Audit:** every retry recorded in `dispatch_retry_audit` (who, when, source, dispatch_id, result) — permanent record.

**No batch retry:** V1 explicitly excludes "retry all failures" button. One dispatch at a time. Batch operations require human review of each item.

---

## 9. Security

- All read RPCs check `is_dashboard_admin()` (rejects with 403 if not admin).
- Public RPC `record_link_open` is the only anon-callable function — does not require auth, only validates token exists in source table.
- IP hashing on opens: same daily-rotating-salt pattern as P2 submit-survey-group (sha256(ip + env_salt + UTC_date)).
- VIEW `dispatch_history_unified` SELECT granted to authenticated; admin guard is in RPC layer, not at view level (allows future role expansion without policy churn).
- Service role can write everything (used by edge functions, never exposed to clients).

---

## 10. Performance considerations

| Concern | V1 Strategy | V2 Plan (if needed) |
|---------|-------------|---------------------|
| VIEW scan cost | Indexes on `sent_at DESC` per source | Materialized view refreshed hourly |
| Pagination | OFFSET-based (50/page) | Keyset pagination (`WHERE sent_at < cursor`) |
| Trend aggregation | GROUP BY day, scan source | Pre-aggregate to `dispatch_daily_summary` table |
| CSV export | Up to 5000 rows client-side | Server-side streaming (Deno edge function) |

Hard limits enforced:
- `list_dispatch_history`: max page=100, max size=200
- `dispatch_trend_daily`: max days=365
- CSV export: 5000-row cap with warning above

---

## 11. Testing strategy

### 11.1 Unit / SQL tests

- Each RPC: validate admin guard rejects non-admin (`auth.jwt()->>'role' != 'admin'`).
- `list_dispatch_history` with each filter combination: assertions on `WHERE` clauses applied.
- `estimate_dispatch_cost_usd` returns correct USD per category/date.
- `dispatch_funnel` math correct (counts stages independently — no overcounting).
- `record_link_open` rejects invalid tokens, inserts on valid.

### 11.2 Integration (manual + curl)

- Seed dummy rows in each source table, query VIEW, assert union returns all.
- Open a survey link page → confirm `dispatch_link_opens` row created.
- Retry flow: failed dispatch → request confirm token → submit retry → audit row created.

### 11.3 E2E (browser)

- Login as admin → page loads without 403.
- Login as non-admin → 403 banner, no data shown.
- Apply filters → URL query string updates, RPC re-fires, table updates.
- Click row → modal opens with preview + timeline.
- Retry button: disabled for non-failed; click failed → confirm modal → confirm → status changes to 'pending' within 5s.
- CSV export downloads file matching displayed rows.

### 11.4 Performance smoke

- With 10k rows in unified VIEW, `list_dispatch_history` returns under 500ms p95.
- With 100k rows: if p95 > 2s, flag for V2 materialized view migration.

---

## 12. Migration plan (file structure)

```
supabase/migrations/
  20260516020000_meta_pricing.sql                     -- table + seed
  20260516020100_dispatch_link_opens.sql              -- table + RLS + record_link_open RPC
  20260516020200_retry_safeguards.sql                 -- retry_confirm_tokens + dispatch_retry_audit
  20260516020300_helper_functions.sql                 -- estimate_dispatch_cost_usd + is_dashboard_admin
  20260516020400_dispatch_history_unified_view.sql    -- the VIEW
  20260516020500_dispatch_rpcs_part1.sql              -- list, summary_kpis, trend_daily
  20260516020600_dispatch_rpcs_part2.sql              -- top_classes, failures, channel_breakdown, funnel
  20260516020700_dispatch_rpcs_part3.sql              -- render_message_preview
  20260516020800_dispatch_rpcs_part4.sql              -- get_retry_confirm_token, retry_dispatch

supabase/functions/
  dispatch-retry/index.ts                             -- edge function that retry_dispatch calls
                                                       --   (encapsulates per-source re-dispatch logic)

admin/envios/
  index.html
  app.js
  styles.css

survey/app.js                                         -- updated to call record_link_open
```

---

## 13. Acceptance criteria

1. Admin opens `/admin/envios/` → page loads with last-7-day data.
2. 4 KPI cards display: total sent count, delivered%, read%, total cost USD.
3. Trend chart shows envios/dia, custo/dia, falhas/dia for the period.
4. Funnel shows 5 stages with counts and conversion %.
5. Top classes / failures 24h / channel breakdown tables populated.
6. Filters: changing date range / channel / status / class / dispatch type updates all widgets and the table.
7. Pagination works (50/page, prev/next, page count).
8. Click row → modal slides in showing WhatsApp-style preview + status timeline + metadata.
9. Retry button: visible only for status='failed'. Click → confirm modal → confirm → re-dispatch enqueued.
10. Retry audit row created in `dispatch_retry_audit`.
11. CSV export downloads filtered data.
12. Non-admin user opening URL gets 403 from RPCs (UI shows access denied message).
13. P2 landing page (`survey/app.js`) instruments link opens → rows appear in `dispatch_link_opens`.
14. Dashboard's funnel "Aberto link" stage uses `open_count > 0` from VIEW.
15. All hardcoded `painel.igorrover.com.br` URLs replaced with `painel.academialendaria.ai` (or env-driven base URL).

---

## 14. Out-of-scope / future

- Real-time Meta Billing API reconciliation (V2)
- PDF/excel export (V2)
- Edit / cancel pending dispatch
- Bulk retry
- Per-template performance analytics page (separate feature)
- A/B test analytics for message variants (would integrate with P3 router round-robin)
- Slack alert metrics
- Email/SMS channels (architecture supports; no impl until channels exist)
