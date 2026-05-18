# Devops Deploy Report — NPS Epic

**Date:** 2026-05-18
**Agent:** @devops (Gage)
**Branch:** `feature/15.0-ac-discovery`
**HEAD SHA:** `d8b9c054`
**Operator:** roverigor (active GH account)

---

## Constitutional context (CLAUDE.md NON-NEGOTIABLE)

Per `~/.claude/CLAUDE.md` and `lesson-pages/.claude/CLAUDE.md`:

> NUNCA execute ação que envia mensagem real (WhatsApp/Email/SMS/Slack push externo a aluno/cliente/lead) sem autorização humana explícita no momento da execução.

This deploy was executed under that gate. **No external messaging behavior was activated.** Code was published; activation toggles remain in Igor's hands.

---

## ✅ Completed

### Phase 1 — Git push + PR
- **Push:** `git push -u origin feature/15.0-ac-discovery` → 21 new commits published (range `5232d70..d8b9c054`)
- **PR #2 updated:** https://github.com/roverigor/lesson-pages/pull/2
  - Title: `feat(nps): EPIC anonymous-form + dispatch dashboard + post-class dispatcher + admin monitor`
  - Body: comprehensive epic summary covering Chapters A/B/C/D/U/P/T + architecture refs + deploy gate checklist
  - Base: `main` · Head: `feature/15.0-ac-discovery` · Mergeable: YES · State: OPEN
  - **Status:** Awaiting human review (NOT merged — per spec)
- **Pre-commit hooks:** N/A (no new commits created during devops phase)
- **Commits ahead of `origin/main`:** 30

---

## ⏸ Gated (human action required)

### Phase 2 — Database migrations (NOT APPLIED)

**Reason:** Supabase CLI is installed (`v2.98.2`) and `supabase/.temp/linked-project.json` confirms link to project `gpufcipkajppykmnmdeh` (calendario-aulas), but **no `SUPABASE_ACCESS_TOKEN` is configured** in this environment. Per CLAUDE.md NON-NEGOTIABLE, devops must not autonomously authenticate secrets.

**Required action (Igor):**
```bash
# 1. Obtain personal access token from https://supabase.com/dashboard/account/tokens
export SUPABASE_ACCESS_TOKEN=sbp_xxxxxxxxxxxx

# 2. Dry-run preview
cd /home/rover/lesson-pages
supabase migration list
supabase db push --dry-run

# 3. Apply if clean
supabase db push
```

**Pending migration files** (in `supabase/migrations/`, newest first — all from this branch):
- `20260518020100_nps_pending_verification_count.sql`
- `20260518020000_nps_multi_cohort_trigger.sql` ← NPS.E.2 fix
- `20260518010000_nps_test_mode.sql`
- `20260517050100_nps_variant_performance.sql`
- `20260517050000_nps_results_aggregation.sql`
- `20260517040200_nps_cron_status_rpcs.sql`
- `20260517040100_nps_min_active_guard.sql`
- `20260517040000_nps_variants_copy_polish.sql`
- `20260517030300_nps_admin_zoom_class_map.sql`
- `20260517030200_nps_admin_group_link_helpers.sql`
- `20260517030100_nps_variant_pool_expansion.sql`
- `20260517030000_nps_cohort_group_verified.sql`
- `20260517020100_fix_nps_admin_dashboard_submitted_at.sql`
- `20260517020000_nps_admin_rpcs.sql`
- `20260517010500_dispatch_view_use_send_status.sql`
- `20260517010400_dispatch_class_nps_cron.sql` ⚠️ contains cron registration — see note below
- `20260517010350_nps_class_links_delivery_columns.sql`
- `20260517010300_zoom_post_attendance_nps_hook.sql`
- `20260517010200_nps_enqueue_rpcs.sql`
- `20260517010100_nps_variants_and_config.sql`

**⚠️ Cron note:** Migration `20260517010400_dispatch_class_nps_cron.sql` registers `dispatch-class-nps-tick`. Per CLAUDE.md NON-NEGOTIABLE #2 ("DO NOT register the cron"), Igor must **review this migration's SQL before applying** and consider commenting out the `cron.schedule(...)` call until master flag activation is desired. The dispatcher itself remains gated by `nps_dispatch_enabled=false`, so even if the cron fires, no external send will occur — but this should be a conscious decision.

### Phase 3 — Edge functions (NOT DEPLOYED)

**Reason:** Same — needs `SUPABASE_ACCESS_TOKEN`.

**Required action (Igor):**
```bash
export SUPABASE_ACCESS_TOKEN=sbp_xxxxxxxxxxxx
cd /home/rover/lesson-pages
supabase functions deploy submit-survey-group --no-verify-jwt
supabase functions deploy dispatch-class-nps  --no-verify-jwt
supabase functions deploy dispatch-retry      --no-verify-jwt
```

### Phase 5 — Secrets (NOT SET)

Per NON-NEGOTIABLE #4 and #5, devops did not set any secrets. Igor must verify/set in Supabase Dashboard → Settings → Edge Functions:

| Secret | Status to verify | Notes |
|--------|------------------|-------|
| `SUPABASE_SERVICE_ROLE_KEY` | required | Used as `app_config.supabase_service_key` internally |
| `META_API_KEY` | **ROTATE — exposed in chat 2026-05-04** per memory `meta-secrets-gap.md` | |
| `META_PHONE_NUMBER_ID` | required | |
| `INTERNAL_NPS_DISPATCH_KEY` | required | See `docs/architecture/nps-database-schema.md` |

### Phase 6 — Activation toggles (NOT FLIPPED)

All gated. Exact SQL when ready:

```sql
-- Step 1: confirm migrations + functions deployed, secrets verified, test in test-mode first

-- Step 2 (optional, for E2E dry-run): redirect all dispatches to admin
UPDATE app_config SET value = '+5511XXXXXXXXX' WHERE key = 'nps_test_redirect_phone';
UPDATE app_config SET value = '<test-group-jid>' WHERE key = 'nps_test_redirect_group_id';
UPDATE app_config SET value = 'true' WHERE key = 'nps_test_mode_enabled';

-- Step 3 (when ready to send to real students): activate master flag
UPDATE app_config SET value = 'true' WHERE key = 'nps_dispatch_enabled';

-- Step 4 (optional, after WhatsApp template approval): activate DM channel
UPDATE nps_message_variants SET active = true WHERE channel = 'dm';
```

---

## ❌ Errors / Skipped

| Item | Why |
|------|-----|
| `supabase db push` | No `SUPABASE_ACCESS_TOKEN` available — would require human auth |
| `supabase functions deploy …` | Same — no access token |
| Setting `app_config.supabase_service_key` | NON-NEGOTIABLE #4 — must paste real SRK manually |
| Setting Meta secrets | NON-NEGOTIABLE #5 — historical exposure flagged in memory |
| Registering cron `dispatch-class-nps-tick` | NON-NEGOTIABLE #2 — moved to runbook |
| Setting `nps_dispatch_enabled = true` | NON-NEGOTIABLE #1 — master flag stays `false` |
| Activating DM variants | NON-NEGOTIABLE #3 |
| Merging PR #2 | Per task spec — left for human review |

---

## What is LIVE in production now

**Nothing changed in production behavior.** Strictly:

- `feature/15.0-ac-discovery` branch is now visible on GitHub at HEAD `d8b9c054`
- PR #2 (open, mergeable) has an updated description reflecting the full epic
- Frontend on `painel.academialendaria.ai` is unchanged (GitHub Actions only deploys from `main`)
- No Supabase migrations applied
- No edge functions deployed
- No cron scheduled
- No secrets set
- All NPS dispatch behavior remains gated by `nps_dispatch_enabled=false`

---

## What is STILL gated by human action

Ordered checklist (each step blocks the next):

### A. Code review + merge
1. **Review PR #2** — https://github.com/roverigor/lesson-pages/pull/2
   - Verify CodeRabbit findings are addressed
   - Spot-check Chapter D architect review fixes (`e2a96ce`)
2. **Merge PR #2** to `main` (triggers GitHub Actions → auto-deploy frontend to VPS Contabo `194.163.179.68`)

### B. Database
3. **Authenticate Supabase CLI:**
   ```bash
   export SUPABASE_ACCESS_TOKEN=sbp_xxxxx  # from supabase.com/dashboard/account/tokens
   ```
4. **Preview SQL:** `supabase db push --dry-run`
5. **Review cron migration:** open `supabase/migrations/20260517010400_dispatch_class_nps_cron.sql` and decide whether to keep `cron.schedule(...)` active or comment-out before push
6. **Apply migrations:** `supabase db push`
7. **Verify:** `supabase migration list` — all rows show `Applied`

### C. Edge functions
8. **Deploy:**
   ```bash
   supabase functions deploy submit-survey-group --no-verify-jwt
   supabase functions deploy dispatch-class-nps  --no-verify-jwt
   supabase functions deploy dispatch-retry      --no-verify-jwt
   ```
9. **Verify:** `supabase functions list` shows all three at the new version

### D. Secrets
10. **Supabase Dashboard → Settings → Edge Functions → Add secret:**
    - `SUPABASE_SERVICE_ROLE_KEY` — copy from Project Settings → API → service_role key
    - `META_API_KEY` — **ROTATE FIRST** (exposed in chat 2026-05-04), then paste new value
    - `META_PHONE_NUMBER_ID`
    - `INTERNAL_NPS_DISPATCH_KEY` — generate fresh: `openssl rand -hex 32`
11. **Mirror service key into DB config** (used by RPCs):
    ```sql
    UPDATE app_config SET value = '<SRK>' WHERE key = 'supabase_service_key';
    ```

### E. Dry-run validation (recommended)
12. **Test mode setup:**
    ```sql
    UPDATE app_config SET value = '+55…YOUR_PHONE'    WHERE key = 'nps_test_redirect_phone';
    UPDATE app_config SET value = '<your-test-group>' WHERE key = 'nps_test_redirect_group_id';
    UPDATE app_config SET value = 'true'              WHERE key = 'nps_test_mode_enabled';
    ```
13. **Activate master flag (still test-mode redirected):**
    ```sql
    UPDATE app_config SET value = 'true' WHERE key = 'nps_dispatch_enabled';
    ```
14. **Trigger one class manually** via `/admin/nps-monitor` → "Disparar amostra"
15. **Observe:** message arrives at YOUR redirect phone/group (not students)
16. **Inspect dashboard:** `/admin/envios` shows the dispatch row

### F. Real activation
17. **Turn test mode OFF:**
    ```sql
    UPDATE app_config SET value = 'false' WHERE key = 'nps_test_mode_enabled';
    ```
18. **(Optional)** Activate DM channel after WhatsApp template approval:
    ```sql
    UPDATE nps_message_variants SET active = true WHERE channel = 'dm';
    ```
19. **Monitor first real cron tick** in `/admin/nps-monitor` and Slack alerts
20. **Verify cron schedule** (only if commented out in step 5):
    ```sql
    SELECT cron.schedule('dispatch-class-nps-tick', '*/5 * * * *',
      $$ SELECT net.http_post(... see runbook ... ) $$);
    ```

---

## References

- PR: https://github.com/roverigor/lesson-pages/pull/2
- Schema source of truth: `docs/architecture/nps-database-schema.md`
- Architect review: `docs/architecture/architect-review-nps-dispatch.md`
- PM review: `docs/architecture/pm-review-nps.md`
- Constitutional gate: `~/.claude/CLAUDE.md` § "Comunicação Externa — Aprovação Humana Obrigatória"
- Meta key rotation: memory `meta-secrets-gap.md`

---

## Run 2 — with token

**Timestamp:** 2026-05-18 ~12:35 UTC
**Token source:** user-provided `SUPABASE_ACCESS_TOKEN` (exported, never persisted)
**CLI version:** supabase 2.98.2
**Scope:** gated-safe migration push + edge function deploy + read-only verification

### Phase A — Migration content audit (PASS)

Inspected `supabase/migrations/20260517010400_dispatch_class_nps_cron.sql`:
- Only `INSERT INTO app_config (key='dispatch_class_nps_url', ...)` — idempotent
- `cron.unschedule` wrapped in defensive `IF EXISTS` (never creates a job)
- The full `cron.schedule(...)` block is commented out (lines 36-60)
- **Verdict:** safe to apply, does NOT activate any worker

Also scanned all 35 pending migration files for `cron.schedule`, `net.http_post`, `DROP TABLE`, `DROP COLUMN`, `TRUNCATE`:
- 2 occurrences of `net.http_post` (in `20260516020800_dispatch_rpcs_part4.sql` and `20260517030200_nps_admin_group_link_helpers.sql`) — both **inside RPC function bodies**, not auto-executed at migration time; only fire when admin invokes the RPC AND `supabase_service_key` is present
- 1 occurrence of `cron.schedule` (in `20260517040200_nps_cron_status_rpcs.sql`) — **inside `nps_admin_register_cron()` RPC**, not auto-executed; the runbook step 6 calls this RPC explicitly after human approval
- 0 destructive statements

### Phase B — Migration deploy (PARTIAL — blocked by content bug)

Commands executed (all with `SUPABASE_ACCESS_TOKEN` exported):

| Command | Exit | Outcome |
|---|---|---|
| `supabase --version` | 0 | `2.98.2` |
| `supabase migration list` | 0 | 35 pending listed, including `20260515110000` older than some remote (out-of-order) |
| `supabase db push --dry-run` | 0 | Warned: needs `--include-all` for out-of-order migration |
| `supabase db push --dry-run --include-all` | 0 | Clean plan, 35 migrations queued |
| `supabase db push --include-all` | non-zero | **FAILED on migration 2 of 35** |

#### ✅ Migration applied

- `20260515110000_schedule_overrides_reschedule_link.sql` — confirmed via `migration list` (local + remote both `20260515110000`)

#### ❌ Migration FAILED

- `20260516010000_nps_class_links.sql`
- **Error:** `ERROR: functions in index predicate must be marked IMMUTABLE (SQLSTATE 42P17)`
- **Offending statement (line 5 of migration):**
  ```sql
  CREATE INDEX IF NOT EXISTS idx_nps_class_links_expires
    ON public.nps_class_links (expires_at)
    WHERE expires_at > now()
  ```
- **Root cause:** PostgreSQL requires IMMUTABLE functions in partial index predicates; `now()` is STABLE, not IMMUTABLE
- **Action taken:** STOPPED per directive — did NOT retry with workarounds; did NOT touch the migration file
- **Side-effect:** all 33 subsequent migrations also did not apply (sequential push)

### Phase C — Edge function deploy (FULL SUCCESS)

| Function | Exit | Version | Status |
|---|---|---|---|
| `submit-survey-group` | 0 | v1 | ACTIVE (`43a40d51-6cdc-4fd8-88d4-8b53cd31ca8e`) — deployed 2026-05-18 12:35:23 UTC |
| `dispatch-class-nps` | 0 | v1 | ACTIVE (`f08ec8f8-3358-43de-95d4-d0338b96a4d1`) — deployed 2026-05-18 12:35:29 UTC |
| `dispatch-retry` | 0 | v1 | ACTIVE (`63f33692-55be-4c19-9a2f-5f7b9647afd4`) — deployed 2026-05-18 12:35:37 UTC |

All three functions are now LIVE on `gpufcipkajppykmnmdeh`. They are inert until invoked.

> ⚠️ Note: `dispatch-class-nps` is the worker that, once the cron is registered + dispatch flag flipped, will send NPS surveys to students. Per CLAUDE.md NON-NEGOTIABLE, no cron registration or flag flip was performed.

### Phase D — Verification (read-only)

```sql
SELECT
  EXISTS (SELECT 1 FROM cron.job WHERE jobname='dispatch-class-nps-tick') AS cron_registered,
  EXISTS (SELECT 1 FROM app_config WHERE key='supabase_service_key')     AS service_key_set,
  EXISTS (SELECT 1 FROM app_config WHERE key='dispatch_class_nps_url')   AS dispatch_url_set;
```

| Column | Value | Notes |
|---|---|---|
| `cron_registered` | **false** | Correct — gated, requires human approval |
| `service_key_set` | **true** | Already configured by Igor (Run 1) |
| `dispatch_url_set` | **false** | Expected — migration `20260517010400` never reached |

NPS table check:

```sql
SELECT
  EXISTS (...where table_name='nps_dispatch_config')  AS config_table_exists,
  EXISTS (...where table_name='nps_message_variants') AS variants_table_exists,
  EXISTS (...where table_name='nps_class_links')      AS class_links_exists;
```

| Column | Value |
|---|---|
| `config_table_exists` | **false** |
| `variants_table_exists` | **false** |
| `class_links_exists` | **false** |

All three NPS-domain tables are absent because the migration chain blocked on `20260516010000`. The NPS dispatch feature is **non-functional end-to-end** until the index bug is fixed and migrations re-pushed.

### Summary

#### ✅ Completed
1. Audit of migration content (35 files, all safe to apply)
2. Dry-run validation (`db push --dry-run --include-all` — clean)
3. Applied 1 migration: `20260515110000_schedule_overrides_reschedule_link.sql`
4. Deployed 3 edge functions (versions 1): `submit-survey-group`, `dispatch-class-nps`, `dispatch-retry`
5. Read-only verification of gated flags (cron=false, dispatch_url=false — both correct)

#### ⚠️ Warnings
1. CLI emits "Docker is not running" during function deploy — harmless, deploy still succeeds via Management API
2. CLI emits "no SMS provider is enabled" on every command — unrelated to this deploy
3. CLI version 2.98.2 is behind latest (2.99.0); no impact on this run
4. The `20260515110000` migration applied successfully but creates `reschedule_link` columns on a table that downstream migrations expect — the partial deploy state is **internally consistent** for that single migration but **incomplete** for any feature that depends on NPS tables

#### ❌ Failed
1. **Migration `20260516010000_nps_class_links.sql`** — partial index uses `now()` (STABLE) in predicate, PostgreSQL requires IMMUTABLE. This is a code bug in the migration file. Cascade-blocked the remaining 33 migrations.
   - **Recommended fix (NOT applied — out of scope for this run):** drop the `WHERE expires_at > now()` clause from the index (make it a regular b-tree index), OR add a scheduled cleanup job to expire rows, OR use `WHERE expires_at IS NOT NULL` as a coarse filter. Decision belongs to @architect / @data-engineer.

#### ⏸ Still gated (NOT executed — require human approval)

Per CLAUDE.md NON-NEGOTIABLE:

1. **Fix migration `20260516010000` index predicate** — code change, then re-push:
   ```bash
   export SUPABASE_ACCESS_TOKEN=sbp_...
   supabase db push --include-all
   ```
2. **Set `dispatch_class_nps_url`** (will happen automatically when migration `20260517010400` finally applies)
3. **Set master flag to enable dispatch:**
   ```sql
   UPDATE nps_dispatch_config SET value='true' WHERE key='nps_dispatch_enabled';
   ```
4. **Activate DM variants:**
   ```sql
   UPDATE nps_message_variants SET active=true WHERE id IN (...);
   ```
5. **Register cron job** (via UI button or directly):
   ```sql
   SELECT public.nps_admin_register_cron();
   -- OR paste the inline cron.schedule from runbook step 6
   ```
6. **Merge PR #2 to main** (after cleanup and re-deploy verification)

### Token handling

`SUPABASE_ACCESS_TOKEN` was exported per-command in the local shell only. It was never written to disk, never committed, never logged outside of CLI stderr. Token is no longer in active shell state at end of this run (each Bash invocation is a fresh shell per harness).

---

*Generated by @devops (Gage) — Synkra AIOX DevOps Authority*
