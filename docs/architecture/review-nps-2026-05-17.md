# Architect Review — NPS P2/P3/P4 + Admin Backend (2026-05-17)

**Reviewer:** Aria (@architect, autonomous)
**Scope:** P2 (anon form), P3 (post-class dispatcher), P4 (dispatch dashboard) + P3-UI admin RPCs
**Branch:** `feature/15.0-ac-discovery`
**Status:** File-only — no production deploy

---

## TL;DR

- **Recommendation: NO-GO** for any DB push until the critical findings below are fixed. Three migrations contain references to columns that do not exist on real tables — they will fail at `apply` time or the first RPC call, taking the dashboard + admin monitor down.
- Conceptually the architecture is sound: layered safety gates (`nps_dispatch_enabled` flag + DM variants `active=false` + manual SQL toggle + retry two-step confirm) align with the CLAUDE.md NON-NEGOTIABLE.
- However the P3 VIEW rewrite (`20260517010500_*`) silently breaks every P4 RPC that consumes it. This appears to be a code-merge accident — the rewrite used a different column shape than P4 was coded against.
- Edge functions `dispatch-retry` and `dispatch-class-nps` have no authentication on the public HTTPS endpoint. Once the master flag is flipped to true, anyone with the URL can POST and trigger sends. Must add shared-secret/JWT verification before flag flip.
- Domain migration is well aligned (academialendaria everywhere in new code; igorrover only persists in old zoom/send-whatsapp functions).

---

## Strengths

- **Gate-by-default design** is layered well:
  - `nps_dispatch_config.nps_dispatch_enabled = 'false'` seeded in `20260517010100_nps_variants_and_config.sql:34`.
  - DM variants seeded `active = false` in `20260517010100_nps_variants_and_config.sql:55-57`. Even if flag is flipped, no DM template will be picked until admin manually activates one.
  - Edge function `dispatch-class-nps/index.ts:110` short-circuits before any send when flag is off.
- **Idempotency at the right boundary:**
  - `nps_class_dispatch_jobs` unique partial index on `(cohort_id, COALESCE(class_id, ...), session_date) WHERE status NOT IN ('skipped','failed')` (`20260517010000_*:33-35`) prevents duplicate active jobs.
  - `enqueue_nps_class_dispatch` does pre-check before insert, returning `already_exists` cleanly.
  - `nps_class_links` unique partial indexes (`20260517010350_*:42-58`) prevent duplicate group/DM links per session.
- **Retry safeguards** in P4 are constitutionally clean: status gate (failed-only) + two-step confirm modal + one-time 15-min token tied to user+dispatch in `retry_confirm_tokens` + permanent `dispatch_retry_audit` row.
- **PII hygiene** in P2 submit (`submit-survey-group/index.ts:103`): daily-rotating salt for `ip_hash`; phone numbers never logged in dispatch-class-nps.
- **Admin RPC whitelist** (`20260517020000_*:155-163`) prevents arbitrary config keys from being written. Boolean and int validation per key. Throttle floor enforced (`1000ms` min).
- **Reset-stuck-job has cooling period** (`20260517020000_*:353`) — 15min minimum before reset, preventing accidental races with a live tick.
- **Round-robin state is per-channel** (`nps_variant_rotation_state` PK=channel) — clean separation of group vs dm rotation.

---

## Critical findings (must fix before deploy)

### 1. [SEV: CRITICAL] `get_nps_link_metadata` references non-existent column `classes.title`
- **Location:** `supabase/migrations/20260516010200_get_nps_link_metadata_rpc.sql:42`
- **Problem:** Returns `c.title`. The `classes` table column is `name` (see `20260402190833_baseline_existing_schema.sql:82`). First call from anon landing page will throw `column c.title does not exist`. Landing page will render "Link inválido" for every valid token.
- **Fix:** Replace `c.title` with `c.name AS class_name` in the SELECT.

### 2. [SEV: CRITICAL] P4 dashboard RPCs reference non-existent column `classes.title` (twice)
- **Location:** `supabase/migrations/20260516020500_dispatch_rpcs_part1.sql:56`, `20260516020600_dispatch_rpcs_part2.sql:21,27`
- **Problem:** `list_dispatch_history` and `dispatch_top_classes` JOIN `classes c` and select `c.title`. Every dashboard load will 500. Spec used `class_title` consistently — implementation deviated.
- **Fix:** Use `c.name`. Update return-type column name to match (`class_name` vs `class_title`) and update `admin/envios/app.js` accordingly. Recommend renaming the RETURNS column to `class_name` end-to-end for clarity.

### 3. [SEV: CRITICAL] `20260517010500_dispatch_view_use_send_status.sql` rebuilds the unified VIEW with the WRONG column shape and references non-existent columns
- **Location:** `supabase/migrations/20260517010500_dispatch_view_use_send_status.sql`
- **Problems (multiple, blocking):**
  - **Migration will fail at apply time.** References columns that do not exist:
    - `notifications.channel` (no such column — `notifications` has `target_type`, not `channel`)
    - `notifications.scheduled_at` (no such column)
    - `notifications.phone_number` (column is `target_phone`)
    - `notifications.purpose` (no such column — closest is `type`)
    - `notifications.template_name` (no such column)
    - `notifications.error` (column is `error_message`)
    - `survey_links.send_channel`, `survey_links.scheduled_at`, `survey_links.recipient_phone`, `survey_links.cohort_id`, `survey_links.template_name`, `survey_links.error_detail`, `survey_links.responded_at` — none exist (`survey_links` has only `survey_id, student_id, token, used_at, created_at, sent_at, send_status, delivered_at, read_at, version_id, meta_message_id, cohort_snapshot_name, expires_at`).
  - **Even if columns existed, the column count + names changed vs the P4 VIEW** (`20260516020400_dispatch_history_unified_view.sql`). The earlier P4 RPCs reference `v.delivered_at`, `v.read_at`, `v.recipient_identifier`, `v.recipient_type`, `v.template_category`, `v.template_name`, `v.dispatch_type`, `v.metadata`, `v.error_detail`, `v.rendered_message`. The new VIEW drops/renames most of those.
- **Impact:** `supabase db push` aborts at this migration; if force-applied with `CREATE OR REPLACE` bypass, all P4 dashboard RPCs break (every call returns "column ... does not exist").
- **Fix:** **Revert this migration to a minimal patch** that only touches the `nps_class_links` UNION arm — keeping the column shape from `20260516020400_*`. Concretely: drop `20260517010500_*` and inline its only legitimate change (use `l.send_status` instead of `'sent'` for the NPS arm) into a new migration that doesn't reshape the other 3 arms.

### 4. [SEV: CRITICAL] `dispatch-retry` and `dispatch-class-nps` edge functions have no auth
- **Location:** `supabase/functions/dispatch-retry/index.ts` (entire file), `supabase/functions/dispatch-class-nps/index.ts` (entire file)
- **Problem:** Both functions accept POST with no JWT or shared-secret validation. The `dispatch-retry` body just needs `{source, dispatch_id, audit_id}`; the dispatcher accepts an empty body. Public URLs are predictable (`gpufcipkajppykmnmdeh.supabase.co/functions/v1/{name}`). Once `nps_dispatch_enabled=true`, an anonymous external POST will trigger sends.
- **CLAUDE.md NON-NEGOTIABLE risk:** the "human approval per execution" promise is broken if the function is callable by anyone. Even with the flag off, an attacker who flips the flag (e.g. via an admin's stolen JWT, also exposed because `nps_admin_set_config` is `GRANT EXECUTE` to `authenticated`) can immediately trigger a mass send.
- **Fix:**
  - Reject requests whose `Authorization` header doesn't carry service-role bearer (matches `SUPABASE_SERVICE_ROLE_KEY`). Implement once in `_shared/auth.ts` and import in both functions.
  - Or require an additional shared secret `X-Dispatch-Secret` env var; cron and retry RPC pass it from `app_config`.

### 5. [SEV: CRITICAL] `nps_admin_dashboard` references non-existent column `class_nps_responses.created_at`
- **Location:** `supabase/migrations/20260517020000_nps_admin_rpcs.sql:118`
- **Problem:** Filters `WHERE created_at > NOW() - interval '24 hours'` but `class_nps_responses` only has `submitted_at` (see `20260516010100_class_nps_responses.sql:20`). Every dashboard render will 500.
- **Fix:** Use `submitted_at` instead of `created_at`.

---

## Concerns (should address but not blocking the gate flip)

### 6. [SEV: HIGH] `nps_next_variant` round-robin is not atomic
- **Location:** `20260517010200_nps_enqueue_rpcs.sql:137-191`
- **Problem:** SELECT chooses next variant then UPDATE writes `last_variant_id`. Two concurrent runs (cron + manual `job_id`) could pick the same variant and update twice. Not destructive but defeats round-robin guarantee under load.
- **Fix:** Wrap in `SELECT ... FROM nps_variant_rotation_state WHERE channel=$1 FOR UPDATE` at the top of the function (forces row lock).

### 7. [SEV: HIGH] `dispatch_link_opens.source` CHECK forbids 'notification' but VIEW queries that source
- **Location:** `20260516020100_dispatch_link_opens.sql:10` (CHECK clause), `20260516020400_dispatch_history_unified_view.sql:33-34` (subquery filter)
- **Problem:** The VIEW for the `notifications` arm has `WHERE o.source = 'notification' AND o.dispatch_id = n.id` — but the CHECK constraint only allows `'survey_link','nps_class_link'`. Subquery always returns 0/NULL. Dead branch in the VIEW. Confusing and easy to break later when adding open tracking for notifications.
- **Fix:** Either remove the dead subquery from the notifications arm (recommended for V1) OR extend CHECK to allow `'notification'`.

### 8. [SEV: HIGH] `record_link_open` does not store IP hash even though column + spec call for it
- **Location:** `20260516020100_dispatch_link_opens.sql:52-53`
- **Problem:** Function accepts only `p_source, p_token, p_user_agent, p_referer`. INSERT leaves `ip_hash` NULL. Spec (section 4.2 + 9) mandates the same daily-salt hash as P2. Loses ability to dedupe unique openers.
- **Fix:** Either add `p_ip_hash` parameter (frontend computes nothing — better to drop the column from spec) OR compute server-side via `inet_client_addr()` + a configurable salt.

### 9. [SEV: HIGH] Hook resolves cohort by blind `LIMIT 1` from `class_cohort_access`
- **Location:** `20260517010300_zoom_post_attendance_nps_hook.sql:37-49`
- **Problem:** When a Zoom meeting maps to a class that has multiple cohorts (PS Advanced/Fundamentals always do), the trigger picks ONE arbitrary cohort and enqueues a single job. All other cohorts attending the same class never receive NPS. Wrong cardinality.
- **Fix:** Change the trigger to enqueue **one job per resolvable cohort** for the class (loop over `class_cohort_access` rows). Or push the multi-cohort resolution into `enqueue_nps_class_dispatch` (accept array). Spec section 8.1 lightly acknowledged this but implementation collapses to single cohort.

### 10. [SEV: MED] Job acquisition lacks `FOR UPDATE SKIP LOCKED`
- **Location:** `supabase/functions/dispatch-class-nps/index.ts:132-142`
- **Problem:** Cron tick uses PostgREST `update().eq("status","pending").lte("scheduled_at",NOW).select().limit(10)`. PostgREST translates to a single UPDATE...RETURNING which Postgres serializes — concurrent runs won't double-process, but they will block on each other. With long Meta API calls inside the function, locks hold for minutes.
- **Fix:** Pre-select job IDs via a custom RPC that does `SELECT id FROM nps_class_dispatch_jobs WHERE status='pending' AND scheduled_at <= NOW() FOR UPDATE SKIP LOCKED LIMIT 10`, mark in_progress, return IDs to caller. Standard worker queue pattern.

### 11. [SEV: MED] `expires_at` index has non-immutable predicate
- **Location:** `20260516010000_nps_class_links.sql:42-43`
- **Problem:** `CREATE INDEX ... WHERE expires_at > now()`. `now()` is STABLE not IMMUTABLE; some Postgres versions reject this as predicate. If accepted, the predicate is evaluated at index-creation time — so the partial index covers only rows valid at migration time; new tokens added later may or may not be indexed depending on stat updates. Confusing semantics.
- **Fix:** Drop the WHERE clause (full index) or use a sentinel timestamp constant.

### 12. [SEV: MED] RLS policy on `nps_class_dispatch_jobs` uses fragile JWT shape
- **Location:** `20260517010000_*:68`, also `20260517010100_*:78,91`
- **Problem:** `(auth.jwt() ->> 'user_metadata')::jsonb ->> 'role'`. Casting text-to-jsonb is unnecessary and inconsistent with the project's convention (`auth.jwt()->'user_metadata'->>'role'` everywhere else). If `user_metadata` is already a JSON object (which it is in Supabase Auth), the text cast may double-encode.
- **Fix:** Change to `(auth.jwt()->'user_metadata'->>'role') = 'admin'` to match the rest of the codebase.

### 13. [SEV: MED] Cron schedule for `dispatch-class-nps-tick` is unconditional
- **Location:** `20260517010400_dispatch_class_nps_cron.sql:22-46`
- **Problem:** Schedules a recurring cron unconditionally when migration applies. The cron itself does a no-op while `nps_dispatch_enabled=false` (function bails), so safe at the message-send layer. But: creating the cron at migration time means external comms infrastructure is "armed" once `db push` runs. Per CLAUDE.md, ANY action that re-schedules a worker of envio should be gated.
- **Fix:** Either move cron creation out of migration into a separate one-shot SQL run AFTER human approval; OR add `IF NOT EXISTS` guard checking config flag before scheduling. Simplest: make migration apply but cron stays unscheduled; runbook `nps-post-class-activation.md` activates cron via SQL when ready.

### 14. [SEV: MED] No backfill of `notifications` ↔ `dispatch_link_opens.source` link
- **Location:** Architecture-wide.
- **Problem:** Funnel "Aberto link" stage relies on `open_count > 0`. Only `survey_link` and `nps_class_link` sources are open-tracked. Notifications and class_reminders show 0 opens forever — funnel under-reports. Acceptable for V1 but caller should know.
- **Fix:** Document in dashboard. V2: extend instrumentation if/when notifications/reminders have URLs.

### 15. [SEV: MED] First-name extraction in DM template
- **Location:** `supabase/functions/dispatch-class-nps/index.ts:313`
- **Problem:** `link.name.split(" ")[0]` — fails on names with leading whitespace, names with only one component (returns same string OK), names with non-ASCII. Empty `name` yields empty string, which Meta will reject as invalid template parameter.
- **Fix:** Sanitize and fallback: `(link.name || 'aluno').trim().split(/\s+/)[0] || 'aluno'`.

### 16. [SEV: MED] `student_attendance` has no `status` column but spec implies present/partial
- **Location:** spec `2026-05-17-nps-post-class-zoom-trigger-design.md:67-68`, impl `20260517010200_nps_enqueue_rpcs.sql:226-238`
- **Problem:** Implementation correctly does NOT filter by status (the table has no `status` column — only `source`, `duration_minutes`). Effectively any student with a `student_attendance` row for the date is "present". Aligns with table reality, deviates from spec language. Document the deviation; spec was wrong.
- **Fix:** Update spec to remove "status IN ('present','partial')" language. Optional: use `duration_minutes >= N` as a minimum-engagement gate.

---

## Nits (style / hygiene)

- `dispatch-class-nps/index.ts:32` — `BASE_URL` hardcoded constant; consider env var for parity with rest of project.
- `dispatch_rpcs_part3.sql:54` — hardcodes `painel.academialendaria.ai` in URL string. Parameterize via `app_config` for DR fallback symmetry.
- `submit-survey-group/index.ts:19` — `IP_HASH_SALT` default `"fallback-rotate-me"` will silently work but defeats hash purpose. Fail-fast if env var missing in production.
- `nps_class_links` has both `trigger_date` and `session_date` columns now (P3 added `session_date`). Backfill is fine, but the data model has dual concepts that mean the same thing. Pick one, deprecate the other in a follow-up migration.
- The increment RPC has `GRANT EXECUTE ... TO service_role` only — correct for protecting the counter — but the edge function calls it correctly.
- Comments in `20260517010100_*:54-57` say "DM variants ship inactive" but only the `active` column is `false`. Worth a defense-in-depth log line whenever DM dispatch attempts to fetch active DM variant and finds none.

---

## Story decomposition recommendation

### Chapter U — UI admin monitor

**NPS.U.1 — Fix admin RPC `class_nps_responses.created_at` bug**
- Goal: Replace `created_at` with `submitted_at` in `nps_admin_dashboard` and any downstream callers.
- AC:
  - `nps_admin_dashboard()` returns without error for an admin caller.
  - 24h-stat `responses_24h` reflects rows from `class_nps_responses.submitted_at`.
  - Migration is additive (CREATE OR REPLACE FUNCTION).
- Deps: `20260517020000_nps_admin_rpcs.sql`
- Effort: S. Risk: low.

**NPS.U.2 — Admin monitor HTML page (`admin/nps-monitor/`)**
- Goal: Build login-gated SPA that calls `nps_admin_dashboard` on load + admin actions.
- AC:
  - Same auth pattern as `admin/envios/` (Supabase JS, JWT role check).
  - Renders: config table (with read-only display), variants grid (toggle active + edit body), pending+recent jobs tables, 24h stats KPIs.
  - Buttons wired to `nps_admin_set_config`, `nps_admin_update_variant`, `nps_admin_skip_job`, `nps_admin_force_job_now`, `nps_admin_reset_stuck_job`.
  - Each destructive action requires a confirm dialog (CLAUDE.md).
- Deps: NPS.U.1
- Effort: M. Risk: low.

**NPS.U.3 — CSS + JS hygiene + responsive**
- Goal: Match painel design system, mobile-ready, no console errors.
- AC:
  - Page loads on viewport widths 375-1920.
  - All state transitions visible (loading spinners, error banners).
  - Lighthouse a11y >= 90.
- Deps: NPS.U.2
- Effort: S. Risk: low.

### Chapter D — Deploy infrastructure

**NPS.D.1 — Migration reorder / fix VIEW rewrite**
- Goal: Eliminate the broken `20260517010500_dispatch_view_use_send_status.sql`. Replace with surgical patch.
- AC:
  - New migration drops + recreates `dispatch_history_unified` preserving the column shape from `20260516020400_*` and changing only the NPS arm's status derivation to `COALESCE(l.send_status, ...)`.
  - `supabase db push` completes cleanly against staging.
  - All P4 RPCs return without column-not-found errors.
- Deps: none (this is the blocker for everything else)
- Effort: M. Risk: HIGH (touches the data plane).

**NPS.D.2 — Fix `classes.title` bug in 3 migrations**
- Goal: Replace `c.title` with `c.name` in `get_nps_link_metadata`, `list_dispatch_history`, `dispatch_top_classes`.
- AC:
  - All 3 functions return without column errors.
  - Frontend (survey landing + admin/envios) updated for any return-column renames.
- Deps: NPS.D.1
- Effort: S. Risk: low.

**NPS.D.3 — Add auth to dispatch-retry + dispatch-class-nps**
- Goal: Reject calls without service-role bearer.
- AC:
  - Both functions return 401 when called without `Authorization: Bearer <service_key>`.
  - Cron continues to work (passes header).
  - `retry_dispatch` SQL passes header.
- Deps: none
- Effort: S. Risk: low.

**NPS.D.4 — Set `app_config.supabase_service_key`**
- Goal: Ensure retry path can fire pg_net.
- AC:
  - Row exists in `app_config` with service-role JWT.
  - `retry_dispatch` reaches edge function (audit shows `queued: true`).
- Deps: NPS.D.3
- Effort: S. Risk: low (secret handling).

**NPS.D.5 — Make NPS cron schedule conditional on master flag**
- Goal: Move `cron.schedule(...)` for `dispatch-class-nps-tick` out of migration into runbook step.
- AC:
  - Migration only registers `app_config.dispatch_class_nps_url`.
  - `runbooks/nps-post-class-activation.md` includes the `SELECT cron.schedule(...)` snippet to run after flag flip.
  - Existing schedule (if applied) can be safely unscheduled.
- Deps: none
- Effort: S. Risk: low.

### Chapter T — Templates Meta approval

**NPS.T.1 — Submit 3 DM templates to Meta for approval**
- Goal: Submit `nps_post_class_v1/v2/v3` to Meta Business Manager.
- AC:
  - 3 templates submitted with `{{1}}=first_name`, `{{2}}=class_name` body + 1 button param (token).
  - `meta_templates` table tracks status='PENDING' → 'APPROVED'.
- Deps: none
- Effort: S. Risk: med (Meta approval timing).

**NPS.T.2 — Activate DM variants after approval**
- Goal: Flip `active=true` on `nps_message_variants` for approved templates only.
- AC:
  - Admin runs `nps_admin_update_variant(...)` per approved variant.
  - Round-robin includes only active variants.
- Deps: NPS.T.1
- Effort: S. Risk: low.

### Chapter E — Engineering improvements / debt

**NPS.E.1 — Atomic round-robin with row lock**
- Deps: none. Effort: S. Risk: low.

**NPS.E.2 — Multi-cohort enqueue from Zoom hook**
- Deps: NPS.D.1. Effort: M. Risk: med (changes cardinality, validate against PS Advanced/Fundamentals).

**NPS.E.3 — `FOR UPDATE SKIP LOCKED` worker pattern in dispatch-class-nps**
- Deps: NPS.D.3. Effort: S. Risk: low.

**NPS.E.4 — IP hash in `record_link_open`**
- Deps: none. Effort: S. Risk: low.

**NPS.E.5 — Deprecate `nps_class_links.trigger_date` in favor of `session_date`**
- Deps: NPS.U.2 (UI must adapt). Effort: M. Risk: med (touches public RPC + view).

**NPS.E.6 — Fail-fast on missing `NPS_IP_HASH_SALT` in prod**
- Deps: none. Effort: S. Risk: low.

**NPS.E.7 — Fix `dispatch_link_opens` CHECK constraint or remove dead VIEW branch**
- Deps: NPS.D.1. Effort: S. Risk: low.

### Chapter O — Operational / runbook polish

**NPS.O.1 — Update `nps-post-class-activation.md` runbook**
- Goal: Reflect NPS.D.5 (cron-after-flag) and NPS.T.2 (variant flip after Meta approval).
- AC:
  - Runbook has explicit "GO/NO-GO" gate before flag flip.
  - Includes smoke-test SQL (1-2 student dry-run).
- Deps: NPS.D.5, NPS.T.2. Effort: S. Risk: low.

**NPS.O.2 — Document admin monitor in `nps-test-tokens.md` or new runbook**
- AC: Admin can navigate from runbook to monitor page and recognize each control. Effort: S. Risk: low.

**NPS.O.3 — Smoke test plan for first cohort**
- AC: Pick a 1-student test cohort, force a job via `nps_admin_force_job_now`, verify group+DM received, response in `class_nps_responses`. Effort: S. Risk: low.

---

## Open questions for product

1. **Multi-cohort dispatch behavior for PS Advanced/Fundamentals**: should one Zoom meeting enqueue N jobs (one per cohort with attendance) or 1 job with N tokens? Current code does the latter via `class_cohort_access` LIMIT 1 — likely wrong. (NPS.E.2)
2. **NPS for mentors**: dispatcher filters `is_mentor=false`. Confirm: mentors do NOT receive NPS, correct?
3. **Cooldown semantics**: 12h cohort-wide cooldown means a cohort with 2 classes/day gets 1 NPS only. Intentional? Or should cooldown be per (class_id, cohort_id, day)?
4. **Cost categorization**: all NPS DMs marked as `'utility'`. Meta may classify the actual templates as `'marketing'` — costs jump 14x. Confirm category once templates approved (NPS.T.1).
5. **Group token reuse**: anyone in the WA group can forward the survey link to non-members. Acceptable? (Spec section 7 says yes, intentional.)
6. **Daily salt rotation**: `submit-survey-group` uses today's UTC date. Boundary (00:00 UTC = 21:00 BRT) causes a hash discontinuity mid-evening. Confirm acceptable.
