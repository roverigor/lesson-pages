# BACKLOG Chapter E — Engineering Debt

**Epic:** EPIC-NPS-DISPATCH
**Wave:** 3 (post-flag-flip cleanup)
**Owner:** @data-engineer + @dev

Items abaixo são concerns de arquiteto, não-bloqueantes pra V1. Pegar por ordem após Chapter D fechado e dispatcher rodando estável.

---

## NPS.E.1 — Atomic round-robin com row lock

**Severity:** HIGH
**Effort:** S (30min)
**Status:** Ready

`nps_next_variant` em `20260517010200_nps_enqueue_rpcs.sql:137-191` faz SELECT + UPDATE separados. Runs concorrentes podem pegar mesma variant.

**Fix:** Wrap em `SELECT ... FROM nps_variant_rotation_state WHERE channel = $1 FOR UPDATE` no topo.

**AC:**
- [ ] Function reescrita com row lock
- [ ] Bench test: 10 concorrentes → cada um pega variant distinto em rotação

---

## NPS.E.2 — Multi-cohort enqueue from Zoom hook

**Severity:** HIGH
**Effort:** M (2h)
**Status:** Ready (after D.1)
**Open question:** product decision (review.md #1)

Trigger `trg_enqueue_nps_after_zoom_processed` resolve cohort via `class_cohort_access LIMIT 1`. PS Advanced/Fundamentals = N cohorts → só 1 recebe NPS.

**Fix:** Loop over all `class_cohort_access` rows pra class, enqueue 1 job per cohort.

**AC:**
- [ ] PS Advanced Zoom-end gera 1 job per cohort com presença
- [ ] Cohorts sem presença não geram job
- [ ] Idempotência preservada (UNIQUE constraint funciona com N jobs distintos)

---

## NPS.E.3 — FOR UPDATE SKIP LOCKED worker pattern

**Severity:** MED
**Effort:** S (1h)
**Status:** Ready (after D.3)

`dispatch-class-nps/index.ts:132-142` usa PostgREST UPDATE...RETURNING. Sob concorrência, locks longos durante Meta API call.

**Fix:** Criar RPC `nps_acquire_pending_jobs(p_limit INT)` que retorna IDs via `SELECT FOR UPDATE SKIP LOCKED LIMIT p_limit` + UPDATE status='in_progress'. Edge function chama essa RPC pra job pickup.

**AC:**
- [ ] RPC criada com SKIP LOCKED
- [ ] Edge function refatorado pra consumir
- [ ] Bench: 3 ticks concorrentes processam jobs distintos sem deadlock

---

## NPS.E.4 — IP hash em record_link_open

**Severity:** HIGH
**Effort:** S (45min)
**Status:** Ready

`record_link_open` em `20260516020100_dispatch_link_opens.sql:52-53` aceita 4 params mas não popula `ip_hash`. Coluna fica NULL. Perde dedupe de unique openers (spec §4.2 mandava).

**Fix:** Server-side hash via `inet_client_addr()` + salt do `app_config`. Ou aceitar `p_ip_hash` do client (worse — client computes).

**AC:**
- [ ] Function calcula hash server-side via daily-rotated salt
- [ ] Coluna `ip_hash` populada em novos opens
- [ ] Backfill NULL: deixar legacy NULL (não regenerar)

---

## NPS.E.5 — Deprecate trigger_date in favor of session_date

**Severity:** MED
**Effort:** M (2h, multi-touch)
**Status:** Ready (after U.2)

`nps_class_links` tem ambas `trigger_date` (P2 original) e `session_date` (P3 add). Dual concepts pro mesmo dado. P2 backfill copiou trigger_date → session_date.

**Fix:** Migration que (a) torna `trigger_date` GENERATED ALWAYS AS (session_date) STORED ou (b) DROP coluna. Update consumers (`get_nps_link_metadata`, VIEW, admin RPC).

**AC:**
- [ ] Decidir abordagem (generated col vs drop)
- [ ] Migration aplicada
- [ ] Todos consumers atualizados
- [ ] Zero rows com trigger_date != session_date pós-migration

---

## NPS.E.6 — Fail-fast on missing NPS_IP_HASH_SALT

**Severity:** MED
**Effort:** S (15min)
**Status:** Ready

`submit-survey-group/index.ts:19` default `"fallback-rotate-me"` se env var ausente. Funciona mas hash sem rotação = identificável.

**Fix:** Throw 500 + alert Slack se salt ausente em produção (detectar via `Deno.env.get('ENVIRONMENT') === 'production'`).

**AC:**
- [ ] Function falha rápido sem salt
- [ ] Slack alert dispara se vazio
- [ ] Documentar em `.env.example`

---

## NPS.E.7 — Fix dispatch_link_opens CHECK or remove dead VIEW branch

**Severity:** HIGH
**Effort:** S (15min)
**Status:** Ready (after D.1)

`20260516020100_dispatch_link_opens.sql:10` CHECK só aceita `'survey_link','nps_class_link'`. VIEW arm de `notifications` tem subquery `WHERE source='notification'` — sempre vazio.

**Fix:** Remover subquery do arm notifications (V1) ou extender CHECK pra incluir 'notification' + 'class_reminder' (V2).

**AC:**
- [ ] CHECK constraint updated OR VIEW subquery removed
- [ ] `dispatch_funnel` retorna count consistent
