# Architecture Map — painel.academialendaria.ai
> Discovery Parte 1 — 2026-05-22 — by @architect (Aria) / AIOX

## 1. Sistemas identificados

| Sistema | Edge Functions | Crons | Pages/UI | Integrações |
|---------|---|---|---|---|
| **NPS Dispatcher** | dispatch-class-nps (P3) | 2+ jobs pending | /admin/nps-monitor, /admin/nps-results | Meta WhatsApp, Evolution WA |
| **Class Reminders** | dispatch-class-reminders (P3) | prep: 5m tick | /admin/lembretes-aulas | Evolution WA |
| **PS RSVP (Pronto Socorro)** | dispatch-ps-rsvp | morning trigger | /admin/ps-rsvp | Meta WhatsApp |
| **Generic Surveys** | dispatch-survey (newest) | cron-driven | /survey/ (public) | Meta WhatsApp, AC |
| **Purchase Webhooks** | ac-purchase-webhook, hotmart-purchase-webhook, generic-purchase-webhook | none | admin-only | ActiveCampaign, Hotmart |
| **Deliveries & Retries** | dispatch-retry, delivery-webhook, meta-delivery-webhook | ac-retries: 5m | internal only | Evolution, Meta APIs |
| **Admin Ad-hoc Sends** | admin-send-group-once | none | /admin/envios | Evolution WA |
| **Class Attendance** | zoom-webhook, zoom-attendance (implied) | daily pipeline | /admin/lembretes-aulas | Zoom API |

---

## 2. Edge Functions Inventory (32 total)

### Dispatch/Send Layer (9 functions)
| Função | Propósito | Última Mod | Status |
|--------|----------|-----------|--------|
| **dispatch-class-nps** | Post-class NPS via cron (*/5m) + manual job lock | 2026-05-20 | **Ativo** — EPIC-021 Hub |
| **dispatch-class-reminders** | Batch group reminders (approved→pending) | 2026-05-18 | **Ativo** |
| **dispatch-ps-rsvp** | PS-only morning DM blitz, all students | 2026-05-19 | **Ativo** |
| **dispatch-survey** | Generic survey admin dispatch (throttled 500ms) | 2026-05-22 | **Ativo** — Hybrid Meta+Evolution |
| **dispatch-retry** | DLQ retry processor (failed→pending) | 2026-05-18 | **Ativo** — EPIC-016 AC |
| **admin-send-group-once** | Manual one-off group send via token | —¹ | **Ativo** |
| **send-whatsapp** | Webhook-triggered from notifications table | 2026-04-22 | **Legacy** — DB webhook path |
| **send-whatsapp-reminder** | Scheduled notifications (unused?) | 2026-04-22 | **Dormant** |
| **send-slack-alert** | Detractor alerts to channel | 2026-05-15 | **Ativo** |

### Webhook Receivers (8 functions)
| Função | Propósito | Última Mod | Status |
|--------|----------|-----------|--------|
| **ac-purchase-webhook** | ActiveCampaign purchase events | 2026-05-15 | **Ativo** — EPIC-015 |
| **hotmart-purchase-webhook** | Hotmart purchase events | 2026-05-15 | **Ativo** |
| **generic-purchase-webhook** | Fallback/other purchases | 2026-05-15 | **Ativo** |
| **delivery-webhook** | Evolution delivery status | 2026-04-22 | **Ativo** |
| **meta-delivery-webhook** | Meta delivery status | 2026-04-22 | **Ativo** |
| **zoom-webhook** | Zoom meeting end/attendance | —¹ | **Ativo** |
| **evolution-health-ping** | Health check (*/5m cron) | 2026-04-22 | **Ativo** |
| **class-reminders-healthcheck** | Batch table state monitor | 2026-05-18 | **Ativo** |

### NPS/Survey Specific (5 functions)
| Função | Propósito | Última Mod | Status |
|--------|----------|-----------|--------|
| **nps-preflight-check** | Pre-dispatch validation | 2026-05-18 | **Ativo** |
| **nps-class-report-daily** | Daily NPS summary email/report | 2026-05-20 | **Ativo** — EPIC-021 |
| **analyze-response-sentiment** | NPS comment AI analysis | 2026-05-15 | **Dormant** (setup only) |
| **create-meta-template** | Template mgmt for Meta API | 2026-05-18 | **Ativo** |
| **admin-fetch-meta-template** | Admin UI template lookup | 2026-05-18 | **Ativo** |

### Utility/Infra (10 functions)
Remaining: prepare-class-reminders, resolve-wa-invite, list-wa-groups, fetch-group-invite-links, zoom-attendance (implied), Slack reminders, shared utils (_shared/).

---

## 3. Integrações externas

| Serviço | Onde Chamado | Finalidade | Observações |
|---------|---|---|---|
| **Meta WhatsApp Cloud API** | dispatch-survey, dispatch-class-nps (DM templates), dispatch-ps-rsvp | Send individual templates + text | Uses META_PHONE_NUMBER_ID, META_API_KEY |
| **Evolution API (legacy)** | dispatch-class-reminders, dispatch-class-nps (groups), admin-send-group-once | Send group messages + status | EVOLUTION_API_URL, EVOLUTION_INSTANCE |
| **ActiveCampaign (AC)** | ac-purchase-webhook → db trigger → ac-report-dispatch, _shared/ac-utils.ts | Purchase event sync + automation | AC_API_KEY, api-us1 region (env var) |
| **Hotmart** | hotmart-purchase-webhook → db | Purchase event sync (secondary) | Fallback to generic-purchase-webhook |
| **Zoom** | zoom-webhook, zoom-attendance EF, attendance_intelligence cron | Meeting end webhooks + attendance import | ZOOM_WEBHOOK_SECRET |
| **Supabase Realtime + pg_cron** | All dispatchers + 32+ cron jobs | Real-time DB polling, scheduled workers | 20+ active cron jobs |
| **Slack** | send-slack-alert, dispatch-class-nps, nps-class-report-daily | Admin alerts + NPS summaries | SLACK_WEBHOOK_URL, SLACK_IGOR_USER_ID |

---

## 4. Paths Duplicados Detectados — 🔴 CRÍTICO

### 4.1 **NPS Survey Dispatch — 3 Caminhos Paralelos**
```
Path A: dispatch-class-nps (cron-driven, post-class trigger)
  ├─ Uses: nps_class_dispatch_jobs table
  ├─ Sends via: Meta DM templates + Evolution groups
  └─ Logs: nps_class_links (idempotent)

Path B: dispatch-survey (admin one-shot, any survey)
  ├─ Uses: surveys + survey_responses (generic)
  ├─ Sends via: Meta DM templates + Evolution groups
  └─ Logs: dispatch_history + survey_links

Path C: send-whatsapp (legacy webhook from notifications)
  ├─ Uses: notifications table
  ├─ Sends via: Evolution text OR Meta text
  └─ Logs: delivery_status (async)

🔴 **Risk**: Três schemas diferentes (nps_*, survey_*, notifications), três tabelas de log. 
Confunde banco + cliente não sabe qual dashboard consultar.
```

**Files**: 
- `/supabase/functions/dispatch-class-nps/index.ts:1-587`
- `/supabase/functions/dispatch-survey/index.ts:1-535`
- `/supabase/functions/send-whatsapp/index.ts:1-621`

---

### 4.2 **Class Reminders — 2 Caminhos**
```
Path A: dispatch-class-reminders (official)
  ├─ Cron: */5 min on class_reminder_batches (approved status)
  ├─ Sends via: Evolution groups only
  └─ Logs: class_reminder_sends table

Path B: send-whatsapp (fallback?)
  ├─ Cron: via notifications webhook
  ├─ Sends via: Evolution OR Meta
  └─ Logs: delivery_status table

🔴 **Risk**: If notifications table gets used as fallback, two parallel 
dispatch pipelines exist for reminders, causing duplication/out-of-order delivery.
```

**Files**: 
- `/supabase/functions/dispatch-class-reminders/index.ts:1-188`
- `/supabase/functions/send-whatsapp/index.ts:1-621`

---

### 4.3 **Purchase → AC Sync — Diverging Handling**
```
Path A: ac-purchase-webhook → ac_dispatch_callbacks table → ac-report-dispatch
  └─ Handles: Purchase event → AC contact field update

Path B: generic-purchase-webhook → ??? (unclear target)
  └─ Handles: Non-AC purchases (Hotmart fallback?)

Path C: hotmart-purchase-webhook → ??? (duplicate generic?)
  └─ Handles: Hotmart-specific events

🔴 **Risk**: 3 webhooks for 1 problem. Generic + Hotmart may conflict.
Unclear which takes precedence or if both fire on same event.
```

**Files**: 
- `/supabase/functions/ac-purchase-webhook/index.ts`
- `/supabase/functions/hotmart-purchase-webhook/index.ts`
- `/supabase/functions/generic-purchase-webhook/index.ts`

---

### 4.4 **Delivery Status — Diverging Sources**
```
Path A: delivery-webhook (Evolution delivery status)
  └─ Logs: delivery_status table

Path B: meta-delivery-webhook (Meta delivery status)
  └─ Logs: delivery_status table (same?)

🔴 **Risk**: Two integrations logging to same table. No provider field 
to distinguish. Retry logic in dispatch-retry may retry wrong path.
```

**Files**: 
- `/supabase/functions/delivery-webhook/index.ts`
- `/supabase/functions/meta-delivery-webhook/index.ts`
- `/supabase/functions/dispatch-retry/index.ts`

---

### 4.5 **NPS Admin Dashboard — Dual Views (nps-monitor vs nps-results)**
```
Page A: /admin/nps-monitor (P3-UI — dispatcher control)
  ├─ RPC: nps_admin_dashboard, nps_admin_set_config, nps_admin_force_job_now
  ├─ Purpose: Dispatch job queue management
  └─ Audience: Igor (dev ops)

Page B: /admin/nps-results (P.3-UI — results consumer)
  ├─ RPC: nps_results_summary, nps_results_trend, nps_results_filter_options
  ├─ Purpose: Analytics / prof feedback view
  └─ Audience: Profs, CS, equipe educacional

🟡 **Risk**: Not a full duplicate, but confusing separation. 
Two admin pages for one feature (NPS). No unified admin console.
```

**Files**: 
- `/admin/nps-monitor/app.js:1-1523`
- `/admin/nps-results/app.js:1-1157`

---

## 5. Recomendações de Consolidação (Top 5)

### 🔴 **1. UNIFY: Single Survey Dispatch Engine**
**Action**: Merge dispatch-class-nps + dispatch-survey into `dispatch-unified-survey`.
- Keep nps_class_dispatch_jobs table (EPIC-021).
- Map surveys → job types (nps_class, custom_survey, etc.).
- Single log table: dispatch_history with `dispatch_type` enum.
- **Impact**: -2 edge functions, -2 schemas, -1 admin dashboard (nps-results only).
- **EPIC**: EPIC-021 NPS Hub consolidation.
- **Timeline**: Critical path blocker if not done soon.

---

### 🔴 **2. ISOLATE: send-whatsapp Legacy Path**
**Action**: Deprecate send-whatsapp, disable notifications webhook trigger.
- Migrate any active notifications → dispatch system.
- Keep send-whatsapp as fallback for 30 days (safety).
- **Impact**: Removes 1 parallel path, forces all sends through cron-driven dispatchers.
- **EPIC**: EPIC-016 AC cleanup or new EPIC.

---

### 🟡 **3. CONSOLIDATE: Purchase Webhooks (ac + hotmart + generic)**
**Action**: Route all three webhooks to single `purchase-unified-handler`.
- Detect source (AC, Hotmart, generic) from signature.
- Single db table with `provider` enum + standard schema.
- **Impact**: -2 edge functions, unified purchase pipeline.
- **EPIC**: EPIC-015 AC sync or EPIC-020 (Hotmart).

---

### 🟡 **4. SEPARATE: Delivery Status by Provider**
**Action**: Add `provider` enum (evolution|meta) to delivery_status table.
- OR: Create delivery_status_evolution + delivery_status_meta.
- Update dispatch-retry to respect provider routing.
- **Impact**: Removes ambiguity, prevents wrong-path retries.
- **EPIC**: EPIC-016 Dispatch reliability.

---

### 🟡 **5. UNIFY ADMIN: Single NPS Console**
**Action**: Merge nps-monitor + nps-results into `/admin/nps-console`.
- Tab 1: Dispatcher (job queue, manual triggers, config).
- Tab 2: Results (filters, trends, comments, detractor alerts).
- **Impact**: -1 page, shared RPC set, unified UI.
- **EPIC**: EPIC-021 Phase 2.

---

## 6. Open Questions

1. **send-whatsapp webhook**: Is notifications table still in use? Should it be deprecated entirely?
   - **Blocker**: Before consolidation.

2. **Purchase webhook precedence**: If Hotmart event fires both hotmart-purchase-webhook AND generic-purchase-webhook, which AC sync wins?
   - **Blocker**: Before purchase consolidation.

3. **Delivery status routing**: When dispatch-retry fires, how does it know whether to call Evolution or Meta retry endpoint?
   - **Blocker**: May cause failed retries.

4. **NPS cron disabled?**: `/supabase/migrations/20260517010400_dispatch_class_nps_cron.sql` has `-- SELECT cron.schedule(...)` (commented out). Is NPS cron intentionally disabled or migration incomplete?
   - **Blocker**: May explain missed NPS dispatches.

5. **AC sync direction**: Is ac-report-dispatch the only AC→DB sync, or does DB→AC sync exist? (One-way vs bidirectional?)
   - **Impact**: Affects EPIC-015 consolidation strategy.

6. **Survey/NPS schema**: Why separate `nps_*` tables from `survey_*` tables? Should they merge?
   - **Impact**: Architecture decision point for Phase 2.

---

**Generated by**: @architect (Aria) — AIOX Discovery Engine  
**Date**: 2026-05-22  
**Repo**: `/home/rover/lesson-pages`  
**Scope**: Brownfield architecture mapping (static analysis only)
