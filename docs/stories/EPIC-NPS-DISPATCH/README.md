# EPIC NPS-DISPATCH — Post-Class Feedback Automation

**Created:** 2026-05-17
**Owner:** @pm (Morgan)
**Architect review:** `docs/architecture/review-nps-2026-05-17.md` — VERDICT: NO-GO until critical fixes applied
**Status:** Active (Chapter D blockers must close before Chapter U/T can deploy)
**Branch:** `feature/15.0-ac-discovery`

## Goal

Automate NPS feedback collection at end of every class — Zoom-end trigger → dual-channel dispatch (Evolution group + Meta DM template) → public anonymous landing → admin monitoring + dashboard analytics. Gate-protected per CLAUDE.md NON-NEGOTIABLE (no real send without human flip).

## Already delivered (file-only, awaiting fixes)

| Sub-project | Status | Artifacts |
|-------------|--------|-----------|
| P2 — Anonymous group form landing | Done file-only | 4 migrations + edge fn + `survey/` UI + 2 runbooks |
| P3 — Post-class dispatcher | Done file-only | 7 migrations + edge fn + cron + trigger + runbook |
| P4 — Dispatch history dashboard | Done file-only | 9 migrations + edge fn retry + `admin/envios/` UI |
| P3-UI backend — Admin RPCs | Done file-only | 1 migration with 6 admin RPCs |

15 commits between `3fb49f1` and `2ec5c61`. Zero production deploy.

## Architect verdict

NO-GO. 5 CRITICAL findings (blocker), 11 HIGH/MED concerns (debt), nits.

**Blocker summary:**
1. `classes.title` doesn't exist in 3 migrations → dashboard 500s
2. P3 VIEW rewrite references nonexistent columns → `db push` aborts
3. Edge functions `dispatch-retry` + `dispatch-class-nps` have NO auth → flag flip = open dispatcher
4. `class_nps_responses.created_at` doesn't exist in admin RPC
5. Cron schedule unconditional at migration time (must be runbook-gated)

## Chapter index

| Chapter | Focus | Stories | Priority |
|---------|-------|---------|----------|
| **D** | Deploy infrastructure (BLOCKERS) | D.1, D.2, D.3, D.4, D.5 | **CRITICAL — must close first** |
| **U** | UI admin monitor | U.1, U.2, U.3 | HIGH (depends on D) |
| **T** | Meta template approval | T.1, T.2 | HIGH (depends on D, gates flag flip) |
| **E** | Engineering debt | E.1–E.7 | MED (post-flag-flip cleanup) |
| **O** | Operational / runbooks | O.1, O.2, O.3 | MED (parallel to T) |

## Story files

- `NPS.D.1.story.md` — Fix VIEW rewrite (BLOCKER)
- `NPS.D.2.story.md` — Fix `classes.title` bug (3 places)
- `NPS.D.3.story.md` — Add auth to edge functions
- `NPS.D.4.story.md` — Set service_key in app_config
- `NPS.D.5.story.md` — Cron-after-flag-flip
- `NPS.U.1.story.md` — Fix admin RPC submitted_at bug
- `NPS.U.2.story.md` — Admin monitor HTML
- `NPS.U.3.story.md` — Admin monitor CSS+JS+responsive
- `NPS.T.1.story.md` — Submit Meta DM templates
- `NPS.T.2.story.md` — Activate variants after approval
- `BACKLOG-E.md` — Engineering debt items E.1–E.7
- `BACKLOG-O.md` — Operational items O.1–O.3

## Dependency graph

```
NPS.D.1 (VIEW fix)
   └→ NPS.D.2 (title bug)
        └→ NPS.D.3 (auth) ─┬→ NPS.D.4 (service_key)
                            └→ NPS.E.3 (skip locked)
NPS.D.5 (cron-after-flag) ── independent

NPS.U.1 (RPC fix) ─→ NPS.U.2 (HTML) ─→ NPS.U.3 (CSS+JS)

NPS.T.1 (submit) ─→ NPS.T.2 (activate)

E.1–E.7, O.1–O.3 mostly independent, post-deploy
```

## Activation gate (per CLAUDE.md NON-NEGOTIABLE)

Following must all be GREEN before flipping `nps_dispatch_enabled='true'`:

- [ ] All Chapter D stories Done
- [ ] At least 1 Chapter T story (DM template approved by Meta) Done
- [ ] NPS.U.2 admin monitor renders without errors
- [ ] Smoke test on internal cohort (NPS.O.3) passes
- [ ] Slack `#dev-alerts` webhook configured
- [ ] Manual SQL: `UPDATE nps_message_variants SET active=true WHERE channel='dm' AND id IN (approved variants)`
