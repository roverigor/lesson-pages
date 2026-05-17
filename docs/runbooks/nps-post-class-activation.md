# Runbook — P3 NPS Post-Class Dispatcher Activation

**Status:** code merged, **disabled** by default (`nps_dispatch_enabled = false`).
**Owner:** @aiox-master / @data-engineer / human approval before flip.

## Pre-activation Checklist

- [ ] Migrations deployed: `supabase db push` (7 P3 files: `20260517010000..20260517010500`).
- [ ] Edge function deployed: `supabase functions deploy dispatch-class-nps --no-verify-jwt`.
- [ ] Cron registered: `SELECT jobname FROM cron.job WHERE jobname='dispatch-class-nps-tick';` returns 1 row.
- [ ] Meta templates approved + active:
  - `nps_post_class_v1` (body: 2 vars + URL button)
  - `nps_post_class_v2`
  - `nps_post_class_v3`
  - Confirm via `SELECT name, status FROM meta_templates WHERE name LIKE 'nps_post_class%';`.
- [ ] After approval, flip DM variants active: `UPDATE nps_message_variants SET active=true WHERE channel='dm';`
- [ ] `app_config.supabase_service_key` set (cron auth) — `SELECT * FROM app_config WHERE key='supabase_service_key';`.
- [ ] Slack webhook env var `SLACK_DEV_ALERTS_WEBHOOK` set on edge function (optional but recommended).
- [ ] Test cohort identified (small group, internal mentors first).

## Smoke Test (dry-run)

```sql
-- 1. Manual enqueue for a past session (use existing cohort + class):
SELECT public.enqueue_nps_class_dispatch(
  'CLASS_UUID'::uuid,
  'COHORT_UUID'::uuid,
  CURRENT_DATE,
  'optional_zoom_meeting_id'
);
-- Returns {enqueued: false, reason: 'feature_disabled'} — expected when flag off.

-- 2. Flip ON temporarily for smoke:
UPDATE nps_dispatch_config SET value='true' WHERE key='nps_dispatch_enabled';

-- 3. Manual enqueue again — should return {enqueued: true, job_id}.
SELECT public.enqueue_nps_class_dispatch('CLASS_UUID', 'COHORT_UUID', CURRENT_DATE, NULL);

-- 4. Trigger dispatch with dry_run:
SELECT net.http_post(
  url := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/dispatch-class-nps',
  body := '{"dry_run": true, "job_id": "JOB_UUID"}'::jsonb,
  headers := jsonb_build_object('Authorization', 'Bearer ' || current_setting('app.svc_key'), 'Content-Type', 'application/json')
);

-- 5. Inspect:
SELECT * FROM nps_class_dispatch_jobs WHERE id = 'JOB_UUID';
SELECT mode, send_status, token, student_id FROM nps_class_links WHERE dispatch_job_id = 'JOB_UUID';
```

## Activation Sequence

1. **Verify all pre-checks above passed.**
2. Flip flag for live test on 1 cohort:
   ```sql
   UPDATE nps_dispatch_config SET value='true' WHERE key='nps_dispatch_enabled';
   ```
3. Wait for next class to end. Observe:
   - Zoom webhook → `zoom_meetings.processed=true` → trigger fires.
   - Cron tick within 5 min picks job.
   - Slack alert posts in `#dev-alerts`.
   - Verify msgs in WA group + DMs.
4. If issues: flip OFF, debug.
   ```sql
   UPDATE nps_dispatch_config SET value='false' WHERE key='nps_dispatch_enabled';
   ```

## Rollback

- Flip flag OFF — pending jobs stay `pending`, in-progress jobs finish naturally.
- To purge unsent jobs:
  ```sql
  UPDATE nps_class_dispatch_jobs SET status='skipped', error_detail='manual_rollback'
   WHERE status='pending';
  ```

## Monitoring

```sql
-- Last 24h overview:
SELECT status, COUNT(*)
  FROM nps_class_dispatch_jobs
 WHERE created_at > NOW() - interval '24 hours'
 GROUP BY status;

-- Failures:
SELECT id, cohort_id, class_id, session_date, error_detail, dm_failed_count, group_send_error
  FROM nps_class_dispatch_jobs
 WHERE status IN ('failed','partial')
   AND created_at > NOW() - interval '24 hours';

-- Cohort rotation variants:
SELECT * FROM nps_variant_rotation_state;

-- Cooldown active for cohort:
SELECT cohort_id, MAX(created_at) AS last_dispatch
  FROM nps_class_dispatch_jobs
 WHERE created_at > NOW() - interval '12 hours'
 GROUP BY cohort_id;
```

## Failure Modes

| Symptom | Diagnose | Recovery |
|---------|----------|----------|
| Job stuck `in_progress` >15min | edge function crashed mid-run | `UPDATE ... SET status='pending', started_at=NULL` to retry |
| DMs all `failed` with `meta_not_configured` | env vars missing | `supabase secrets set META_API_KEY=... META_PHONE_NUMBER_ID=...` |
| DMs `failed` 4xx with template error | template not approved or name mismatch | check `meta_templates`, fix variant `meta_template_name` |
| Group send `failed` evolution_http_4xx | group jid invalid or instance disconnected | check Evolution dashboard, refresh JID |
| Trigger doesn't fire | `processed` flag not set on zoom_meetings | check zoom-attendance edge function logs |
| Cooldown blocks legitimate dispatch | edit `nps_cohort_cooldown_hours` lower (min 0 disables) |
| Spam — multiple jobs for same session | unique constraint should prevent; investigate trigger double-fire |

## Notes

- Cooldown is per **cohort** not per class. PS cohort with 2 classes on same day → second blocked.
- Holiday check uses `is_holiday(session_date)` — won't fire on configured holidays.
- Group send goes via Evolution API (free text); DM via Meta template (24h-window bypass).
- Round-robin state in `nps_variant_rotation_state` — survives restarts.
