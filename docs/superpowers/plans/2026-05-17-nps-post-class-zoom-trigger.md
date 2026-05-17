# Plan — P3 NPS Post-Class Zoom-End Dispatcher

**Spec:** `docs/superpowers/specs/2026-05-17-nps-post-class-zoom-trigger-design.md`
**Date:** 2026-05-17
**Approach:** file-only autonomous (deploy gate humano).

## Task Sequence

### Task 1 — Migration: dispatch jobs table
**File:** `supabase/migrations/20260517010000_nps_class_dispatch_jobs.sql`
- Create `nps_class_dispatch_jobs` table with full schema from spec §4.1.
- Indexes: `uq_nps_job_per_class_session` partial, `idx_nps_job_pending_due` partial.
- Trigger `updated_at` auto-update.
- RLS: only service role can write; admin can read.

### Task 2 — Migration: variants + rotation state + config
**File:** `supabase/migrations/20260517010100_nps_variants_and_config.sql`
- Create `nps_message_variants` table.
- Create `nps_variant_rotation_state` table.
- Create `nps_dispatch_config(key TEXT PRIMARY KEY, value TEXT)` if `core_config` doesn't exist (verify with `SELECT to_regclass('core_config')` before).
- Seed: `nps_dispatch_enabled='false'`, `nps_cohort_cooldown_hours='12'`, `nps_dispatch_delay_minutes='5'`.
- Seed 3 group variants + 3 dm variants (using approved Meta template names).

### Task 3 — Migration: enqueue RPC + round-robin RPC
**File:** `supabase/migrations/20260517010200_nps_enqueue_rpcs.sql`
- `enqueue_nps_class_dispatch(p_class_id UUID, p_cohort_id UUID, p_session_date DATE)` — verify feature flag, check holiday via `is_brazilian_holiday`, check cooldown (12h default), insert job idempotently. Returns `{job_id, enqueued, reason}`.
- `nps_next_variant(p_channel TEXT)` — atomic round-robin update of `nps_variant_rotation_state`, returns variant row.
- `nps_resolve_eligible_students(p_class_id UUID, p_cohort_id UUID, p_session_date DATE)` — returns SETOF student rows considering PS mode (attendance-gated) vs cohort mode (all enrolled).

### Task 4 — Migration: hook in zoom queue consumer
**File:** `supabase/migrations/20260517010300_zoom_post_attendance_hook.sql`
- Locate existing zoom_import_queue consumer fn (likely `process_zoom_import_queue` or similar).
- Wrap with `AFTER sync_staff_attendance_from_zoom`, add call to `enqueue_nps_class_dispatch` per distinct (class_id, cohort_id, session_date) tuple imported.
- If consumer doesn't exist (cron handles via direct SQL), add separate trigger on `zoom_meetings` for `UPDATE OF processed WHEN OLD.processed=false AND NEW.processed=true`.

### Task 5 — Edge function `dispatch-class-nps`
**File:** `supabase/functions/dispatch-class-nps/index.ts`
- Pattern based on `dispatch-class-reminders` + `dispatch-survey`.
- Reads `nps_dispatch_config.nps_dispatch_enabled` — bail if false.
- Loops pending jobs (limit 10 per run), `SELECT FOR UPDATE SKIP LOCKED` style via `UPDATE ... WHERE status='pending' ... RETURNING`.
- For each job:
  - Choose variant via `nps_next_variant`.
  - Insert group token in `nps_class_links(mode='group')`.
  - Insert N dm tokens.
  - Send group via Evolution (`_shared/evolution-group.ts`).
  - Send DM loop with 10s throttle, max 50 per run, via Meta template (`_shared/meta-whatsapp.ts`).
  - Update job counts + status.
  - Post Slack summary.

### Task 6 — Cron schedule
**File:** `supabase/migrations/20260517010400_dispatch_class_nps_cron.sql`
- `cron.schedule('dispatch-class-nps-tick', '*/5 * * * *', SELECT net.http_post(...))`.
- Use `current_setting('app.settings.service_role_key', true)` or store in `pgsodium`/secrets.
- Idempotent: `cron.unschedule` first if exists.

### Task 7 — VIEW update + dashboard hint
**File:** `supabase/migrations/20260517010500_dispatch_history_include_nps_jobs.sql`
- Verify `dispatch_history_unified` VIEW (created in P4) already includes `nps_class_links`.
- If not, ALTER (DROP + CREATE) to add UNION ALL for `nps_class_dispatch_jobs` joined with `nps_class_links` (aggregate dm sends per job + group send into one summary row).
- Update P4 RPCs source filter to accept `'nps_class_dispatch'`.

### Task 8 — Runbook + activation guide
**File:** `docs/runbooks/nps-post-class-activation.md`
- Pre-activation checklist: Meta templates approved? Cooldown ok? Test cohort identified?
- Smoke test SQL: manually enqueue 1 job for past session, observe dispatch.
- Toggle flag: `UPDATE nps_dispatch_config SET value='true' WHERE key='nps_dispatch_enabled'`.
- Rollback: `UPDATE ... value='false'`. Jobs in-flight finish naturally.
- Monitoring: `SELECT status, COUNT(*) FROM nps_class_dispatch_jobs GROUP BY status`.

## Deploy Sequence (gate-protected, human-authorized)

1. `supabase db push` — 7 new migrations.
2. `supabase functions deploy dispatch-class-nps --no-verify-jwt`.
3. Verify cron registered: `SELECT * FROM cron.job WHERE jobname='dispatch-class-nps-tick'`.
4. Confirm flag is `false`.
5. Approve Meta templates (`nps_post_class_v1`, `nps_post_class_v2`, `nps_post_class_v3`) — if not approved, dispatcher logs and skips dm.
6. Run smoke test (Task 8 runbook).
7. Toggle flag `true` on test cohort first, then broaden.

## Risks

- **R1 — Spam if hook fires twice:** mitigated by UNIQUE constraint, but test idempotency carefully.
- **R2 — PS mode mass DM:** se 200 alunos presentes, 200 DMs em 5min = throttle pode acumular fila. Mitigado por loop multi-tick.
- **R3 — Meta template rejection:** se template not approved, DM falha, group ainda funciona. Aceitável.
- **R4 — Evolution rate limit em rajadas:** group send é 1 msg só por job, baixo risco.
- **R5 — Aluno em múltiplos cohorts gera múltiplos DMs no mesmo dia:** filtro DISTINCT no resolve, OK.

## Estimated Effort

8 tasks, ~3-4h focused work. Implementation file-only autonomous; deploy needs human auth + Meta template approval.
