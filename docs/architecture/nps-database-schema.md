# NPS Dispatch — Database Schema Reference

**Last updated:** 2026-05-18
**Scope:** All tables, VIEWs, RPCs, triggers, and crons created or consumed by the NPS dispatch system (P2 + P3 + P4 + admin monitor + results dashboard).
**Audience:** Anyone modifying this codebase — read before ALTER or RENAME on any table listed.

> ⚠️ **Why this doc exists:** Mid-session migrations broke the unified VIEW because column references drifted from the original P4 shape. Use this as the canonical source-of-truth. Update it whenever you ship a migration that touches any table here.

---

## 1. System map

```
┌─────────────────┐
│ Zoom meeting    │
│  .ended         │
└────────┬────────┘
         │ webhook → zoom_import_queue → sync_staff_attendance → zoom_meetings.processed = true
         ▼
┌─────────────────────────────┐
│ TRIGGER                     │
│ trg_enqueue_nps_after_      │
│ zoom_processed              │
└────────┬────────────────────┘
         │ loops class_cohort_access → enqueue_nps_class_dispatch per cohort
         ▼
┌──────────────────────────────────┐
│ nps_class_dispatch_jobs (queue)  │
└────────┬─────────────────────────┘
         │ cron */5min POST → edge fn
         ▼
┌──────────────────────────────────┐
│ edge fn: dispatch-class-nps      │
│ - picks variant (weighted random)│
│ - resolves students              │
│ - sends Evolution group + Meta DM│
└────────┬─────────────────────────┘
         │ inserts nps_class_links (group token + N dm tokens)
         ▼
┌─────────────────────────────┐         ┌──────────────────────────────┐
│ Aluno opens landing         │ ──────▶ │ dispatch_link_opens          │
│ /survey/{grupo|aluno}/<tok> │         └──────────────────────────────┘
└────────┬────────────────────┘
         │ submits via edge fn submit-survey-group
         ▼
┌──────────────────────────────────┐         ┌──────────────────────────┐
│ class_nps_responses              │  if 0-6 │ Slack #cs-detractors     │
│ (response attribution)           │ ──────▶│ (Block Kit, name+phone)  │
└──────────────────────────────────┘         └──────────────────────────┘
```

---

## 2. Tables CREATED by NPS epic

### 2.1 `nps_class_links` (P2 + P3)
**Migrations:** `20260516010000_nps_class_links.sql` + `20260517010350_nps_class_links_delivery_columns.sql`
**Purpose:** One row per survey token. Group mode = 1 link per (cohort, class, date). DM mode = 1 link per (cohort, class, date, student).

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | auto |
| `token` | text UNIQUE | auto: `encode(gen_random_bytes(16), 'hex')` |
| `class_id` | uuid NULLABLE FK→classes | P3 made nullable (cohort-only edge cases) |
| `cohort_id` | uuid NOT NULL FK→cohorts | |
| `trigger_date` | date NOT NULL | legacy P2; equals session_date |
| `session_date` | date | P3 added; backfilled from trigger_date |
| `mode` | text CHECK ('group','dm') | |
| `student_id` | uuid NULLABLE FK→students | required when mode='dm', forbidden when 'group' (CHECK) |
| `expires_at` | timestamptz NOT NULL | |
| `response_count` | int DEFAULT 0 | bumped by `increment_nps_link_response_count` |
| `created_by` | text DEFAULT 'system' | |
| `created_at` | timestamptz DEFAULT now() | |
| `send_status` | text DEFAULT 'pending' CHECK ('pending','sent','failed','skipped') | P3 added |
| `sent_at` | timestamptz | P3 |
| `evolution_message_id` | text | P3 (group sends) |
| `meta_message_id` | text | P3 (DM sends) |
| `error_detail` | text | P3 |
| `dispatch_job_id` | uuid FK→nps_class_dispatch_jobs | P3 link back to job |

**Indexes:**
- `idx_nps_class_links_group_unique` UNIQUE partial WHERE mode='group' on `(COALESCE(class_id,sentinel), cohort_id, COALESCE(session_date,trigger_date))`
- `idx_nps_class_links_dm_unique` UNIQUE partial WHERE mode='dm' on same + student_id
- `idx_nps_links_dispatch_status` on `(send_status, sent_at)`
- `idx_nps_links_dispatch_job` on `dispatch_job_id`

**Consumers:** edge fn `dispatch-class-nps` (writes), edge fn `submit-survey-group` (reads + validates), RPC `get_nps_link_metadata` (anon landing), VIEW `dispatch_history_unified`, dashboard P4.

---

### 2.2 `class_nps_responses` (P2)
**Migration:** `20260516010100_class_nps_responses.sql`
**Purpose:** Anonymous or attributed NPS submissions.

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `link_id` | uuid FK→nps_class_links | |
| `class_id` | uuid FK→classes | snapshot |
| `cohort_id` | uuid FK→cohorts | snapshot |
| `mode` | text CHECK ('group','dm') | |
| `student_id` | uuid FK→students | only when mode='dm' |
| `nps_score` | int CHECK 0-10 | |
| `comment` | text | |
| `name_provided` | text | only when mode='group' (optional self-id) |
| `ip_hash` | text | SHA-256 with daily salt rotation |
| `user_agent` | text | truncated 500 |
| `submitted_at` | timestamptz DEFAULT now() | **column name = `submitted_at`, NOT `created_at`** |

**Consumers:** RPCs `nps_results_*`, `nps_admin_dashboard.stats.responses_24h`.

⚠️ **Common mistake:** referencing `created_at` instead of `submitted_at` → 500 error. Caught in NPS.U.1.

---

### 2.3 `nps_class_dispatch_jobs` (P3)
**Migration:** `20260517010000_nps_class_dispatch_jobs.sql`
**Purpose:** Queue of pending/in-progress/finished dispatch jobs (1 per cohort × class × date).

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `class_id` | uuid NULLABLE FK→classes | |
| `cohort_id` | uuid NOT NULL FK→cohorts | |
| `session_date` | date NOT NULL | |
| `zoom_meeting_id` | text | snapshot for audit |
| `status` | text CHECK ('pending','in_progress','sent','partial','skipped','failed') | |
| `scheduled_at` | timestamptz NOT NULL DEFAULT now() | NOW + 5min on enqueue |
| `started_at`, `finished_at` | timestamptz | |
| `group_send_status` | text CHECK ('sent','skipped','failed','not_applicable') | |
| `group_send_error`, `group_evolution_message_id` | text | |
| `dm_sent_count`, `dm_failed_count`, `dm_skipped_count` | int DEFAULT 0 | |
| `total_eligible_students` | int | |
| `error_detail` | text | |
| `variant_group_id`, `variant_dm_id` | text | telemetry |
| `metadata` | jsonb | |
| `created_at`, `updated_at` | timestamptz | trigger maintains updated_at |

**Indexes:**
- `uq_nps_job_per_class_session_active` UNIQUE partial WHERE status NOT IN ('skipped','failed') on `(cohort_id, COALESCE(class_id, sentinel), session_date)` — idempotency
- `idx_nps_job_pending_due` on `scheduled_at` WHERE status='pending'
- `idx_nps_job_cohort_date` on `(cohort_id, session_date DESC)`

---

### 2.4 `nps_message_variants` (P3)
**Migration:** `20260517010100_nps_variants_and_config.sql` + `20260517030100_nps_variant_pool_expansion.sql` + `20260517040000_nps_variants_copy_polish.sql`
**Purpose:** Router pool — 8 group variants + 3 dm variants seeded.

| Column | Type | Notes |
|--------|------|-------|
| `id` | text PK | e.g. 'group_v4', 'dm_v1' |
| `channel` | text CHECK ('group','dm') | |
| `body_template` | text | with `{{class_name}} {{cohort_name}} {{link}} {{greeting}}` |
| `meta_template_name` | text | only DM (Meta-approved template name) |
| `active` | bool DEFAULT true | DM variants ship inactive |
| `weight` | int DEFAULT 1 CHECK >0 | weighted random pick |
| `created_at` | timestamptz | |

**Consumers:** `nps_next_variant` RPC, admin monitor variant editor, `nps_variant_performance` ranking.

---

### 2.5 `nps_variant_rotation_state` (P3)
**Migration:** `20260517010100_nps_variants_and_config.sql`
**Purpose:** Atomic telemetry of last variant picked per channel.

| Column | Type | Notes |
|--------|------|-------|
| `channel` | text PK CHECK ('group','dm') | |
| `last_variant_id` | text FK→nps_message_variants | |
| `rotation_count` | bigint DEFAULT 0 | total picks lifetime |
| `updated_at` | timestamptz | |

⚠️ `nps_next_variant` uses `FOR UPDATE` on this row → atomic under concurrency.

---

### 2.6 `nps_dispatch_config` (P3)
**Migration:** `20260517010100_nps_variants_and_config.sql` + `20260518010000_nps_test_mode.sql`
**Purpose:** Feature flags + tunables. Read by edge fn on every cron tick.

| Key | Default | Description |
|-----|---------|-------------|
| `nps_dispatch_enabled` | `false` | Master flag |
| `nps_cohort_cooldown_hours` | `12` | Min hours between jobs per cohort |
| `nps_dispatch_delay_minutes` | `5` | Delay enqueue→earliest send |
| `nps_dispatch_max_dm_per_run` | `50` | Cap per cron tick |
| `nps_dispatch_dm_throttle_ms` | `10000` | Throttle between DMs (min 1000) |
| `nps_test_mode_enabled` | `false` | Test mode flag |
| `nps_test_mode_phone` | `''` | Override phone (digits-only, 10-15 chars) |
| `nps_test_mode_group_jid` | `''` | Override group JID (validated as `*@g.us`) |

⚠️ Whitelisted by `nps_admin_set_config`. Adding new key requires updating that RPC's IF clause.

---

### 2.7 `dispatch_link_opens` (P4)
**Migration:** `20260516020100_dispatch_link_opens.sql`
**Purpose:** Track when survey landing pages are opened.

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid PK | |
| `source` | text CHECK ('survey_link','nps_class_link') | ⚠️ does NOT include 'notification' even though VIEW has a dead subquery for it |
| `dispatch_id` | uuid | |
| `opened_at` | timestamptz DEFAULT now() | |
| `user_agent`, `referer` | text | |
| `ip_hash` | text | currently NOT populated by `record_link_open` RPC (NPS.E.4 open) |

---

### 2.8 `meta_pricing` (P4)
**Migration:** `20260516020000_meta_pricing.sql`
**Purpose:** Per-country, per-category Meta API price for cost estimation.

Seeded BR: utility 0.0045, auth 0.0015, marketing 0.0625, service 0.0.

| Column | Type |
|--------|------|
| `country` text | |
| `category` text | |
| `price_usd` numeric | |
| `effective_date` date | versioned |

Consumed by `estimate_dispatch_cost_usd()` helper.

---

### 2.9 `retry_confirm_tokens` + `dispatch_retry_audit` (P4)
**Migration:** `20260516020200_retry_safeguards.sql`
**Purpose:** Two-step retry safeguards.

- `retry_confirm_tokens`: 15-min single-use confirm tokens. Cols: `id, user_id, source, dispatch_id, token, created_at, consumed_at`.
- `dispatch_retry_audit`: permanent retry log. Cols: `id, user_id, source, dispatch_id, attempted_at, result jsonb`.

---

## 3. Tables MODIFIED (ALTER) by NPS epic

### 3.1 `cohorts` (existing — DO NOT recreate)
**Modified by:** `20260517030000_nps_cohort_group_verified.sql`
**Added columns:**
- `whatsapp_group_verified` bool DEFAULT false
- `whatsapp_group_verified_at` timestamptz
- `whatsapp_group_verified_by` uuid FK→auth.users
- `whatsapp_group_label` text

⚠️ Default false means new cohorts NEVER send to group until admin verifies via `/admin/nps-monitor/`.

Pre-existing columns NPS uses:
- `id`, `name`, `whatsapp_group_jid`, `whatsapp_group_link` (set by `fetch-group-invite-links` edge fn)

---

## 4. Tables READ-ONLY (do NOT modify from NPS migrations)

These are owned by other systems but consumed by NPS:

| Table | Used for | Schema notes |
|-------|----------|--------------|
| `classes` | aula name + zoom_meeting_id binding | column is **`name`** NOT `title` (caught in NPS.D.2) |
| `class_cohort_access` | bridge class × cohort (loop source for trigger) | NPS.E.2 multi-cohort fix uses this |
| `students` | recipient resolution | columns: `name, phone, cohort_id, active, is_mentor` |
| `student_attendance` | attendance-gate eligibility | columns: `student_id, class_date, cohort_id`. No `status` column — presence-only |
| `zoom_meetings` | trigger source on `.processed=true` | columns: `zoom_meeting_id, start_time, cohort_id, processed` |
| `notifications` | legacy dispatch arm in VIEW | columns NPS reads: `id, target_type, created_at, delivered_at, status, mentor_id, target_phone, target_group_jid, class_id, cohort_id, type, message_rendered, evolution_message_ids, metadata` |
| `survey_links` | legacy survey arm in VIEW | columns NPS reads: `id, sent_at, delivered_at, read_at, used_at, send_status, student_id, cohort_id, survey_id, token, created_at` |
| `class_reminder_sends` | class reminders arm in VIEW | columns NPS reads: `id, scheduled_at, sent_at, send_status, error_detail, cohort_id, group_jid, class_id, reminder_type, message_preview, evolution_message_id, batch_id, zoom_link_snapshot, group_name, created_at` |
| `meta_templates` | DM template approval status | Read by P.4 (future) |
| `app_config` | cron auth, dispatcher URLs | rows: `supabase_service_key`, `dispatch_class_nps_url`, etc |
| `holidays` | `is_holiday()` check in enqueue | |
| `auth.users` | verified_by tracking | |
| `cron.job` + `cron.job_run_details` | pg_cron native — read by `nps_admin_cron_status` |

---

## 5. VIEWs

### 5.1 `dispatch_history_unified`
**Migration:** `20260516020400_dispatch_history_unified_view.sql` (golden source) + `20260517010500_dispatch_view_use_send_status.sql` (P3 surgical patch)

**Column shape (24 cols — do NOT change without updating ALL P4 RPCs):**

`source, dispatch_id, channel, sent_at, delivered_at, read_at, status, error_detail, student_id, mentor_id, recipient_identifier, recipient_type, class_id, cohort_id, dispatch_type, template_name, template_category, rendered_message, provider_message_id, metadata, open_count, last_opened_at, response_count, created_at`

**4 UNION arms:** `notifications` + `survey_links` + `class_reminder_sends` + `nps_class_links`.

⚠️ **Critical:** changing this VIEW shape breaks `list_dispatch_history`, `dispatch_summary_kpis`, `dispatch_trend_daily`, `dispatch_top_classes`, `dispatch_recent_failures`, `dispatch_channel_breakdown`, `dispatch_funnel`.

---

## 6. RPCs catalog

### 6.1 Public/anon (called from landing pages)
- `get_nps_link_metadata(token)` — landing page metadata lookup
- `submit-survey-group` (edge fn) — anonymous form submit
- `record_link_open(source, token, user_agent, referer)` — track opens

### 6.2 Service-role (called from edge fns + crons)
- `enqueue_nps_class_dispatch(class_id, cohort_id, session_date, zoom_meeting_id)` — idempotent enqueue
- `nps_next_variant(channel)` — atomic weighted-random pick + telemetry update
- `nps_resolve_eligible_students(class_id, cohort_id, session_date)` — student filter
- `increment_nps_link_response_count(link_id)` — counter bump

### 6.3 Admin-only (gated by `is_dashboard_admin()`)
- `nps_admin_dashboard()` — full monitor payload (config + variants + rotation + jobs + stats + pending_verification)
- `nps_admin_set_config(key, value)` — whitelisted setter with type validation
- `nps_admin_update_variant(id, body, active)` — variant edit with min-1-active guard
- `nps_admin_skip_job(job_id, reason)` — cancel pending/in_progress
- `nps_admin_force_job_now(job_id)` — bring scheduled_at to NOW
- `nps_admin_reset_stuck_job(job_id)` — in_progress→pending after 15min
- `nps_admin_list_cohort_groups()` — cohorts × JID × verification state × classes_bound
- `nps_admin_set_cohort_group_verified(cohort_id, verified, label)` — flip verified flag
- `nps_admin_refresh_group_invite(cohort_id)` — triggers fetch-group-invite-links
- `nps_admin_zoom_class_map()` — zoom × class × cohort resolution map
- `nps_admin_cron_status()` — reads cron.job + last run
- `nps_admin_register_cron()` / `nps_admin_unregister_cron()` — toggle cron schedule
- `nps_results_summary(filters)` — NPS computed + buckets
- `nps_results_trend(weeks, filters)` — weekly NPS over time
- `nps_results_by_cohort(filters)` / `nps_results_by_class(filters)` — breakdowns
- `nps_results_comments(filters, limit)` — comments feed
- `nps_results_filter_options()` — cohorts + classes for dropdowns
- `nps_variant_performance(days)` — ranking by composite score

### 6.4 Helper functions
- `is_dashboard_admin()` — JWT role check
- `nps_is_valid_group_jid(jid)` — regex check `^[\w._-]+@g\.us$`
- `nps_config_value/bool/int(key, default)` — config readers
- `estimate_dispatch_cost_usd(category, country, date)` — cost helper
- `is_holiday(date)` — BR holiday lookup
- `sanitize_for_wa()` — applied client-side in edge fn (not RPC)

---

## 7. Triggers

| Trigger | Table | When | Function | Purpose |
|---------|-------|------|----------|---------|
| `trg_nps_job_updated_at` | `nps_class_dispatch_jobs` | BEFORE UPDATE | `set_nps_job_updated_at()` | auto updated_at |
| `zoom_meetings_nps_enqueue` | `zoom_meetings` | AFTER UPDATE OF processed | `trg_enqueue_nps_after_zoom_processed()` | enqueues 1 job per cohort linked to class (NPS.E.2 multi-cohort) |

---

## 8. Cron jobs (pg_cron)

⚠️ **Not registered in migration anymore (NPS.D.5)** — must be manually scheduled AFTER human authorization. See `docs/runbooks/nps-post-class-activation.md` step 6.

- `dispatch-class-nps-tick` — schedule `*/5 * * * *` — POSTs to dispatch-class-nps with service-role bearer

Pre-existing crons referenced:
- `class-reminders-tick` (separate system)
- `daily_staff_reminders` (separate)

---

## 9. Edge functions

| Function | Auth | Purpose |
|----------|------|---------|
| `submit-survey-group` | public/anon | Survey form submit (rate-limited per IP) |
| `dispatch-class-nps` | service-role only | Main dispatcher worker |
| `dispatch-retry` | service-role only | Retry failed dispatches |
| `zoom-webhook` | HMAC verified | Receives Zoom events (existed) |
| `fetch-group-invite-links` | service-role | Pulls WA group invite via Evolution (existed) |

---

## 10. Migration timeline (NPS epic only)

| Date | File | What |
|------|------|------|
| 2026-05-16 | `20260516010000_nps_class_links.sql` | P2 — token table |
| 2026-05-16 | `20260516010100_class_nps_responses.sql` | P2 — responses |
| 2026-05-16 | `20260516010200_get_nps_link_metadata_rpc.sql` | P2 — public RPC (fixed NPS.D.2) |
| 2026-05-16 | `20260516010300_increment_nps_link_response_count.sql` | P2 — counter RPC |
| 2026-05-16 | `20260516020000_meta_pricing.sql` | P4 — pricing |
| 2026-05-16 | `20260516020100_dispatch_link_opens.sql` | P4 — open tracking |
| 2026-05-16 | `20260516020200_retry_safeguards.sql` | P4 — retry confirm + audit |
| 2026-05-16 | `20260516020300_helper_functions.sql` | P4 — cost + admin helpers |
| 2026-05-16 | `20260516020400_dispatch_history_unified_view.sql` | P4 — **VIEW golden source** |
| 2026-05-16 | `20260516020500_dispatch_rpcs_part1.sql` | P4 — list + KPIs + trend (fixed NPS.D.2) |
| 2026-05-16 | `20260516020600_dispatch_rpcs_part2.sql` | P4 — top + failures + channel + funnel (fixed NPS.D.2) |
| 2026-05-16 | `20260516020700_dispatch_rpcs_part3.sql` | P4 — preview |
| 2026-05-16 | `20260516020800_dispatch_rpcs_part4.sql` | P4 — retry RPCs |
| 2026-05-17 | `20260517010000_nps_class_dispatch_jobs.sql` | P3 — queue |
| 2026-05-17 | `20260517010100_nps_variants_and_config.sql` | P3 — variants + config |
| 2026-05-17 | `20260517010200_nps_enqueue_rpcs.sql` | P3 — enqueue + variant pick + resolve students |
| 2026-05-17 | `20260517010300_zoom_post_attendance_nps_hook.sql` | P3 — trigger (single-cohort version) |
| 2026-05-17 | `20260517010350_nps_class_links_delivery_columns.sql` | P3 — ALTER nps_class_links |
| 2026-05-17 | `20260517010400_dispatch_class_nps_cron.sql` | P3 — URL config (NPS.D.5 removed cron.schedule) |
| 2026-05-17 | `20260517010500_dispatch_view_use_send_status.sql` | P3 — VIEW patch (surgically rewritten in NPS.D.1) |
| 2026-05-17 | `20260517020000_nps_admin_rpcs.sql` | P3-UI — admin RPCs |
| 2026-05-17 | `20260517020100_fix_nps_admin_dashboard_submitted_at.sql` | NPS.U.1 — column fix |
| 2026-05-17 | `20260517030000_nps_cohort_group_verified.sql` | Safety L1+L2 |
| 2026-05-17 | `20260517030100_nps_variant_pool_expansion.sql` | Humanize V1+V2 |
| 2026-05-17 | `20260517030200_nps_admin_group_link_helpers.sql` | UI helpers |
| 2026-05-17 | `20260517030300_nps_admin_zoom_class_map.sql` | Zoom map RPC |
| 2026-05-17 | `20260517040000_nps_variants_copy_polish.sql` | P.5 copy |
| 2026-05-17 | `20260517040100_nps_min_active_guard.sql` | P.6 guard |
| 2026-05-17 | `20260517040200_nps_cron_status_rpcs.sql` | P.7 cron RPCs |
| 2026-05-17 | `20260517050000_nps_results_aggregation.sql` | P.3 results RPCs |
| 2026-05-17 | `20260517050100_nps_variant_performance.sql` | P.11 ranking |
| 2026-05-18 | `20260518010000_nps_test_mode.sql` | Test mode |
| 2026-05-18 | `20260518020000_nps_multi_cohort_trigger.sql` | NPS.E.2 multi-cohort fix |
| 2026-05-18 | `20260518020100_nps_pending_verification_count.sql` | Pending verify banner |

---

## 11. Common pitfalls (caught + fixed)

| Pitfall | Caught in | Fix migration |
|---------|-----------|---------------|
| `classes.title` doesn't exist (use `name`) | architect review | NPS.D.2 |
| VIEW rewrite referencing nonexistent columns on notifications/survey_links | architect review | NPS.D.1 |
| `class_nps_responses.created_at` doesn't exist (use `submitted_at`) | architect review | NPS.U.1 |
| `student_attendance` has no `status` column (presence-only) | spec deviation | acknowledged in code |
| Edge fns without auth → CLAUDE.md violation | architect review | NPS.D.3 (+ `verifyServiceRole`) |
| Cron schedule auto-registered at migration time → CLAUDE.md violation | architect review | NPS.D.5 (moved to runbook) |
| `nps_next_variant` non-atomic round-robin race | architect concern #6 | added `FOR UPDATE` in NPS humanize migration |
| Trigger picks 1 cohort via LIMIT 1 (multi-cohort PS bug) | architect concern #9 | NPS.E.2 fix `20260518020000` |
| Last active variant can be deactivated → silent skip | PM review | NPS.P.6 |
| Hardcoded fallback `"aluno"` in DM template | PM review | NPS.P.9 skip path |
| WA markdown chars in cohort/class names break formatting | PM review | NPS.P.10 sanitize |

---

## 12. Before you ship a migration that touches anything above

**Checklist:**
- [ ] Read the column names of the actual table (do not trust your memory)
- [ ] Check this doc to see what reads/writes the table
- [ ] If touching `dispatch_history_unified` VIEW, preserve the 24-column shape — update P4 RPCs in lockstep otherwise
- [ ] If renaming an RPC, search frontend (`survey/`, `admin/envios/`, `admin/nps-monitor/`, `admin/nps-results/`) for callers
- [ ] If adding to `nps_dispatch_config`, update whitelist in `nps_admin_set_config`
- [ ] If changing trigger logic, dry-run idempotency: same Zoom event firing twice must not double-dispatch
- [ ] Update **this doc** in the same PR

---

---

## 13. System dependencies (external + internal)

### 13.1 External services (third-party APIs)

| Service | Used for | Auth | Failure impact | Owner |
|---------|----------|------|----------------|-------|
| **Meta Cloud API (WhatsApp Business)** | DM template sends (`https://graph.facebook.com/v21.0/{PHONE_ID}/messages`) | `META_API_KEY` bearer token | DMs fail; group still works via Evolution | Igor / Meta Business Manager |
| **Evolution API** | WhatsApp group sends (`{EVOLUTION_API_URL}/message/sendText/{INSTANCE}`) + invite link fetch | `EVOLUTION_API_KEY` header | Group sends fail; DMs continue via Meta | Self-hosted (precisa instance up) |
| **Zoom Cloud (REST + Webhook)** | Source of meeting.ended events that trigger NPS dispatch | HMAC signature verify via `ZOOM_WEBHOOK_SECRET` | No NPS dispatched automatically; manual enqueue still works | Zoom App Marketplace |
| **OpenAI API** | Class recording transcript summarization (existing zoom-attendance, NOT NPS) | `OPENAI_API_KEY` | Resumos não gerados; NPS não afetado | Igor |
| **Slack webhooks** | Detractor alerts (P.2) + dev alerts (dispatch failures) | webhook URLs em env vars | Alertas perdidos; envios continuam | Internal Slack workspace |
| **Hotmart webhook** (existing) | Cria cohorts/students automaticamente | shared secret | Onboarding manual fallback | Hotmart |
| **ActiveCampaign** (existing) | Customer lifecycle, NÃO usado direto pelo NPS | API key | Não afeta NPS | AC |

### 13.2 Supabase infrastructure (project `gpufcipkajppykmnmdeh`)

| Component | Used for | Notes |
|-----------|----------|-------|
| **PostgreSQL 15+** | All tables/RPCs/triggers/VIEW | Hosted in Supabase |
| **Auth (Supabase Auth)** | Admin JWT (`user_metadata.role = 'admin'`) | Used by `is_dashboard_admin()` |
| **Edge Functions (Deno runtime)** | submit-survey-group, dispatch-class-nps, dispatch-retry | Each fn has own env vars |
| **pg_net** | DB → Edge Function HTTP calls (cron + retry_dispatch) | `net.http_post(url, body, headers)` |
| **pg_cron** | Scheduled tick `*/5min` para dispatch worker | `cron.schedule()` + `cron.job_run_details` |
| **Storage** | Not used by NPS | — |
| **Realtime** | Not used by NPS | — |
| **RLS** | Enabled em todas tabelas NPS — service_role bypass + admin read | Policies definidas por migration |

### 13.3 Frontend dependencies (CDN, vanilla JS)

| Lib | Version | Used in | Purpose |
|-----|---------|---------|---------|
| `@supabase/supabase-js` | v2 UMD | all admin pages + survey landing | Auth + RPC calls |
| `chart.js` | v4.4.1 | admin/envios + admin/nps-results | KPI charts (line, doughnut) |
| Google Fonts `Inter` | 400-900 | all admin pages | Typography |
| Lucide icons | latest | admin/index sidebar | Icons (existing dependency) |

**Frontend não usa framework** — HTML + CSS + vanilla JS. Sem build step, sem npm install em prod. Tudo via CDN.

### 13.4 Edge function shared modules (`supabase/functions/_shared/`)

| Module | Exports | Consumers |
|--------|---------|-----------|
| `auth.ts` | `verifyAdminOrCs`, `verifyAdminStrict`, `verifyServiceRole`, `decodeJwtRole`, `timingSafeEqual` | dispatch-class-nps, dispatch-retry, submit-survey, dispatch-survey, ac-report-dispatch |
| `evolution-group.ts` | `sendEvolutionGroupText` | dispatch-class-nps, dispatch-class-reminders |
| `meta-whatsapp.ts` | `sendWhatsApp`, `sendWhatsAppTemplate`, type `MetaSendResult` | dispatch-class-nps, dispatch-survey, ac-report-dispatch |
| `slack.ts` | `sendDM` (Slack DM helper) | dispatch-survey |

⚠️ Mudanças em `_shared/auth.ts` afetam TODAS edge fns acima — testar individualmente.

### 13.5 Environment variables required

**Edge function secrets (Supabase → Project Settings → Secrets):**

| Var | Used by | Required | Notes |
|-----|---------|----------|-------|
| `SUPABASE_URL` | all fns | YES | auto-injected pelo Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | all fns + verifyServiceRole | YES | auto-injected |
| `SUPABASE_ANON_KEY` | submit-survey-group | YES | auto-injected |
| `META_API_KEY` | dispatch-class-nps + dispatch-survey | YES quando ativar | bearer token Meta WhatsApp |
| `META_PHONE_NUMBER_ID` | dispatch-class-nps + dispatch-survey | YES | Meta phone ID |
| `META_GRAPH_VERSION` | meta-whatsapp.ts | optional | default `v21.0` |
| `EVOLUTION_API_URL` | dispatch-class-nps + class-reminders | YES quando ativar | URL da instância Evolution |
| `EVOLUTION_API_KEY` | idem | YES | apikey header |
| `EVOLUTION_INSTANCE` | idem | YES | nome da instance |
| `ZOOM_WEBHOOK_SECRET` | zoom-webhook | YES | HMAC verify |
| `OPENAI_API_KEY` | zoom-webhook (transcript) | optional | só pra resumos |
| `NPS_IP_HASH_SALT` | submit-survey-group | YES | rotate periodicamente |
| `SLACK_DETRACTORS_WEBHOOK` | submit-survey-group | optional | alerta P.2 |
| `SLACK_DEV_ALERTS_WEBHOOK` | dispatch-class-nps | optional | failure summary (P.9) |

**DB-level config (`app_config` table — set via SQL):**

| Key | Used by | Critical? |
|-----|---------|-----------|
| `supabase_service_key` | cron + retry_dispatch (passa Bearer header pra edge fns) | YES — sem isso cron 401 |
| `dispatch_class_nps_url` | cron tick destination | YES |
| `class_reminders_dispatch_url` | reminders cron (separate) | só se reminders ativo |
| `fetch_group_invite_links_url` | nps_admin_refresh_group_invite RPC | optional |
| `app.zoom_attendance_url` | zoom_import_queue consumer | YES — existing |

### 13.6 Cross-system dependencies (NPS depends on existing systems)

| Upstream system | What NPS reads from | Failure impact |
|-----------------|---------------------|----------------|
| **Zoom-attendance pipeline** | `zoom_meetings.processed`, `student_attendance` rows | Trigger não dispara; student elegibilidade fallback all-enrolled |
| **Class management (admin/config turmas)** | `classes.zoom_meeting_id`, `class_cohort_access` bridge | Sem binding = trigger não resolve; jobs ficam órfãos |
| **Cohort management (admin/index)** | `cohorts.name`, `cohorts.whatsapp_group_jid`, `cohorts.whatsapp_group_link` | Sem cohort/JID = não envia |
| **Student management** | `students.name`, `students.phone`, `students.cohort_id`, `students.active`, `students.is_mentor` | Sem phone = skipped; sem name = P.9 skip |
| **Holidays system** | `is_holiday(date)` fn + `holidays` table | Enqueue retorna `reason='holiday'` em feriados |
| **EPIC-015 CS area** | `is_dashboard_admin()` helper (criado lá) | Sem role check = todos RPCs 401 |
| **Class reminders (P3 sibling)** | Compartilha `evolution-group.ts`, `_shared/auth.ts`, `app_config.supabase_service_key` | Mudança em helper afeta ambos |
| **Dispatch survey legacy (EPIC-004)** | Compartilha `meta-whatsapp.ts`, `survey_links` table na VIEW | VIEW reshape quebrou outrora |

### 13.7 Downstream consumers (depend on NPS outputs)

| Consumer | Reads from NPS | If NPS down |
|----------|---------------|-------------|
| **admin/envios dashboard (P4)** | `dispatch_history_unified` VIEW | KPIs zeram pra source `nps_class_link` |
| **admin/nps-monitor** | `nps_admin_dashboard` + 10 outros RPCs | Tela vazia / 500 |
| **admin/nps-results** | `nps_results_*` RPCs + `class_nps_responses` | Dashboard sem dados |
| **Slack #cs-detractors** (futuro) | submit-survey-group POSTs | CS não recebe alerts detractor |
| **Survey landing page público** | `get_nps_link_metadata` + `submit-survey-group` | Alunos veem "link inválido" |
| **Webhook delivery callbacks** | `nps_class_links.meta_message_id` mapping | Status delivered/read não atualiza |

### 13.8 VPS infrastructure (Contabo)

| Component | Role | Failure impact |
|-----------|------|----------------|
| `194.163.179.68` (Contabo VPS) | Hosts Nginx + landing static files | `/survey/*` + admin pages offline |
| Nginx (config `infra/nginx.conf`) | Reverse proxy + rewrites + CSP | URLs não resolvem |
| Docker container `lesson-pages` (porta 3080) | Serve static HTML/CSS/JS | Frontend offline |
| GitHub Actions deploy (`.github/workflows/deploy.yml`) | CI/CD on push to main | Deploy manual |
| Let's Encrypt cert | TLS pra `painel.academialendaria.ai` + `painel.igorrover.com.br` (DR) | HTTPS falha |
| DNS A records | Routing | Domain unresolvable |

### 13.9 Repository structure dependencies

```
lesson-pages/
├── admin/
│   ├── index.html                # admin shell sidebar (links pra envios/monitor/results)
│   ├── envios/                   # P4 history dashboard
│   ├── nps-monitor/              # P3-UI control plane
│   ├── nps-results/              # P3 results dashboard
│   └── lembretes-aulas/          # class reminders (sibling system)
├── survey/                       # P2 public landing
│   ├── index.html
│   ├── styles.css
│   └── app.js
├── js/
│   └── config.js                 # SUPABASE_CONFIG global (url + anonKey)
├── templates/
│   ├── design-tokens-dark-premium.css   # shared design system
│   ├── admin-shared.css                 # shared admin styles
│   └── login-overlay.css                # shared login UI
├── supabase/
│   ├── functions/                # edge fns + _shared
│   └── migrations/               # all DB DDL + RPCs
├── docs/
│   ├── architecture/
│   │   ├── nps-database-schema.md       # ← este arquivo
│   │   ├── review-nps-2026-05-17.md     # architect review
│   │   └── pm-review-nps-2026-05-17.md  # PM review
│   ├── runbooks/
│   │   ├── nps-post-class-activation.md
│   │   ├── nps-nginx-rewrite.md
│   │   └── nps-test-tokens.md
│   ├── stories/EPIC-NPS-DISPATCH/       # all P/D/U/T/E/O stories
│   └── superpowers/
│       ├── specs/                       # P2/P3/P4 design docs
│       └── plans/                       # implementation plans
└── infra/
    └── nginx.conf
```

⚠️ Frontend usa paths absolutos `/templates/...`, `/js/config.js`, `/admin/...`. Mudar repo root = quebra tudo.

### 13.10 Version pinning

| Item | Version | Why pinned |
|------|---------|-----------|
| `@supabase/supabase-js` | `@2` (UMD CDN) | Major version v2 — v3 quebra API |
| Deno std (`https://deno.land/std@0.177.0/http/server.ts`) | 0.177.0 | Compat com Supabase Edge runtime atual |
| `@supabase/supabase-js@2.39.0` (edge fns) | 2.39.0 | Estabilidade ESM imports |
| `chart.js@4.4.1` | 4.4.1 | Mock CDN — atualizar manual quando major bump |
| Meta Graph API | `v21.0` | Atual em 2026-05; rotacionar quando deprecation chega |

### 13.11 Single points of failure (audit)

🔴 **HIGH:**
- `supabase_service_key` em `app_config` — sem isso cron 401 e dispatcher trava
- `META_API_KEY` — sem isso 100% dos DMs falham (group via Evolution sobrevive)
- `nps_dispatch_enabled = true` flag — single boolean controla tudo
- Trigger `zoom_meetings_nps_enqueue` — se desabilitado, dispatcher para de receber jobs

🟡 **MED:**
- `EVOLUTION_INSTANCE` connectivity (instance pode cair) — group send falha
- pg_cron schedule — se unschedule, jobs ficam pending forever
- `NPS_IP_HASH_SALT` rotation — se nunca rotacionar, rate-limit dedupe fica previsível

🟢 **LOW:**
- Slack webhook — alertas perdidos mas não quebra envio
- OpenAI API — só afeta transcripts, não NPS
- Chart.js CDN — KPIs não renderizam, tabelas continuam

---

## 14. Dependency upgrade checklist

Antes de bumpar major version de qualquer item:

- [ ] **Supabase JS** — testar todos `sb.rpc()` calls + `sb.auth.*`
- [ ] **Deno runtime** — verificar Edge Functions logs sem deprecation warnings
- [ ] **Meta Graph API** — checar deprecation date no Meta dashboard; testar template send em staging
- [ ] **Evolution API** — endpoint paths podem mudar entre majors; smoke test
- [ ] **Chart.js** — option keys mudam; testar trend + funnel
- [ ] **pg_cron / pg_net** — Supabase atualiza junto; revisar release notes

---

**End of reference.** Last commit touching schema: see `git log --oneline supabase/migrations/`.
