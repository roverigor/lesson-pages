# PM Review — NPS Dispatch (2026-05-17)

**Reviewer:** @pm (Morgan)
**Scope:** Product/UX/Ops gaps NOT covered by architect's review (`review-nps-2026-05-17.md`).
**Lens:** Premium-brand stakes (200 high-ticket purchases/month).

---

## TL;DR

- **Ship-ready as a control plane, NOT as an aluno-facing experience.** Monitor UI is a strong ops tool; recipient touchpoints (DM template, survey landing, thank-you state) feel under-finished for premium brand.
- **Igor can flip the switch with confidence on infra terms** (verified groups + zoom map + eligible preview), but **cannot preview the exact rendered message that will hit a specific cohort** before flipping. That is the single highest-impact gap.
- **Group variants 4–8 are noticeably better than the original 1–3.** Variants 1, 2, 5 still read "agency template" — fix copy or deactivate them; current weighted-random gives 12.5% each.
- **No reporting layer for the data we are collecting.** We capture NPS scores + opens + responses but there is no aggregation surface for Igor to act on. Survey closes → data sits in tables.
- **Failure modes lean on Slack + SQL.** At midnight, "what broke" requires reading Postgres. Monitor should surface last error + retry CTA inline.

---

## Strengths (honest, not generous)

1. **Master switch friction is calibrated correctly.** Modal + explicit acceptance checkbox + clear copy on "Mensagens reais serão enviadas a alunos via WhatsApp" (`admin/nps-monitor/index.html:286–299`, `app.js:550–566`). This is the right level of ritual.
2. **Zoom × Aula × Turma map is genuinely useful.** Three-color status pills + "✕ sem zoom_meeting_id — trigger nunca dispara" copy (`app.js:444`) lets Igor diagnose trigger-chain breaks visually without SQL.
3. **Group verification gate (L2) ships off-by-default with per-cohort verified flag + label + verified_at audit.** Premium-brand correct.
4. **Eligible students preview is the trust-builder.** Showing the actual aluno list per cohort with the explainer of source tables (`app.js:524–531`) gives Igor reality-check before flip.
5. **Dry-run path exists end-to-end.** Function honors `dry_run: true`, creates tokens, doesn't send. Solid for smoke testing.
6. **L1 JID format validation + L2 verified flag layered defense.** Even if a JID is corrupted in DB, regex blocks send. Good defensive programming bleeding into product safety.

---

## High-impact gaps (premium-brand stakes)

### GAP-1 — No "preview rendered message for THIS cohort before sending"
**Severity:** HIGH
**Observation:** Variants are visible, eligible students are visible, but there is no single screen showing "if I dispatch cohort X right now, this exact text will hit this exact WA group." Igor must mentally render `{{class_name}}`, `{{cohort_name}}`, `{{link}}` from a template he's seeing in another section.
**Why it matters:** First send to a premium cohort is irreversible reputationally. A typo in cohort name (`"PS Fundamentals T2"` vs `"PS Fundamentals — T2"`) becomes visible only post-send.
**Fix:** Add "👁 Preview render" button per pending job — modal shows fully-rendered group + DM body with the real cohort/class names + a dummy `{{link}}` placeholder + which variant will be picked (or "weighted-random will pick from N active").
**Effort:** S (frontend only; reuses existing variant + cohort data already in `state.data`).

### GAP-2 — DM aluno sees zero brand context when WhatsApp notif fires
**Severity:** HIGH
**Observation:** DM template is `nps_post_class_v*` controlled by Meta Business Manager — body is opaque from this codebase. Variants table only shows `meta_template_name` label (`migration 20260517010100:55–57`). The actual DM copy is not auditable here.
**Why it matters:** Aluno gets push notification "Nova mensagem de [Phone Number Display Name]" — if that display name isn't "Academia Lendária" (or equivalent), it reads as random number = high-ticket recipient deletes/blocks. Same risk for the body's tone.
**Fix:**
1. Add `display_phone_name` config check to monitor (read from `META_PHONE_NUMBER_ID` profile via API once, cache).
2. Add `meta_template_body_cached` column to `nps_message_variants` — admin RPC pulls approved template body from Meta API once on activation, displays it in the Router section so Igor verifies copy without leaving panel.
**Effort:** M (Meta API integration; one new RPC + UI render).

### GAP-3 — Survey thank-you state is generic
**Severity:** MEDIUM
**Observation:** `survey/index.html:60–62` — "Obrigado!" + "Sua opinião é fundamental." Detractor (0–6), passive (7–8), promoter (9–10) all see same screen. For 0–6, there is no follow-up — that is a missed save.
**Why it matters:** High-ticket detractor is a recoverable churn signal IF you trigger a human follow-up. Right now the data lands in a table, no one is paged.
**Fix:** Branch thank-you by score:
- 0–6: "Obrigado. Um membro da equipe vai te procurar pra entender melhor." + alert in Slack `#cs-detractors` with student_id + comment.
- 7–8: "Valeu! Conte o que faltaria pra ser nota 10?" + secondary input box.
- 9–10: "Que bom! Tem alguém que se beneficiaria do método? [link de indicação]" → referral CTA.
**Effort:** M (3 thank-you variants + Slack webhook + referral link infrastructure).

### GAP-4 — No NPS aggregation dashboard exists
**Severity:** HIGH
**Observation:** P4 covers **dispatch history** (sent/failed/opens/responses counts), not **NPS results aggregation**. There is no screen answering "what is NPS for Fundamentals T4 over last 30 days, with comments listed."
**Why it matters:** This is the entire point of the system. If Igor cannot consume scores easily, the dispatcher becomes data-collection theater.
**Fix:** New page `admin/nps-results/` — per cohort + per class breakdown: avg score, NPS computed properly ((promoters - detractors)/total × 100), detractor comments list, week-over-week trend. Tie to `nps_class_responses` table.
**Effort:** L (new page + RPCs + aggregation SQL).

### GAP-5 — "Variantes ativas" toggle has no minimum guard
**Severity:** MEDIUM
**Observation:** `app.js:809–836` — admin can deactivate all 8 group variants. Function `nps_next_variant` returns empty when `v_total = 0` (migration line 62–64), dispatcher logs `no_variant` skip. No UI guard.
**Why it matters:** Easy footgun. Igor edits one variant late at night, accidentally unchecks active on the last one, next morning all dispatches skip group sends silently. Slack alerts will fire but only after damage.
**Fix:** Block "Salvar" in variant modal if it would leave 0 active variants for that channel. Show warning "Esta é a última variant ativa de Grupo — desativar pausa todos os envios de grupo."
**Effort:** S (frontend validation).

### GAP-6 — Cron is registered manually in runbook step 6, no UI surface
**Severity:** MEDIUM
**Observation:** `docs/runbooks/nps-post-class-activation.md:75–103` — cron registration is a SQL block to paste. Monitor has no "Cron status: ✓ scheduled, last tick X min ago" indicator.
**Why it matters:** Master switch ON + cron not registered = silent failure mode. Master switch OFF + cron registered = jobs ticking but bailing on flag = wasted invocations + log noise.
**Fix:** Read `cron.job` table in dashboard RPC, surface "🕒 Cron `dispatch-class-nps-tick`: ativo (último tick 3min atrás)" near master switch. Add "Registrar cron" button if missing.
**Effort:** S-M.

### GAP-7 — No "test send to my number" path
**Severity:** MEDIUM
**Observation:** Dry-run creates tokens but doesn't send. There is no "send the rendered DM to Igor's phone only" path.
**Why it matters:** Meta template approval ≠ guarantee body is good. Igor needs to receive the actual DM on his own WhatsApp before flipping for 200 alunos. Today path is "approve at Meta → flip flag → send to real cohort." Too risky.
**Fix:** "Enviar pra mim" button per DM variant — uses Igor's phone from `admin_users.phone`, sends template with placeholder params, marks the resulting `nps_class_links` row `created_by='admin_test'` so it doesn't pollute analytics.
**Effort:** S.

### GAP-8 — Spam protection on forwarded links
**Severity:** LOW
**Observation:** Token is single-use-feeling but actually allows multiple opens (recorded), one submit per token (assumed — need to confirm in `submit-survey-group` fn). If aluno forwards link, anyone with token can submit.
**Why it matters:** Premium positioning + anonymous form = trolling vector. Not catastrophic since DM tokens are per-student.
**Fix:** Rate-limit per-token submissions (1 per token, already likely enforced) + per-IP submissions per cohort (3/day). Add CAPTCHA only if abuse detected — premium UX doesn't tolerate friction for clean traffic.
**Effort:** S (assuming submit fn already does 1-per-token).

---

## Copy improvements

Re-reading the 8 group variants honestly:

### Keep as-is (premium-tone-correct)
- **group_v4:** "Galera, valeu pela energia em *{{class_name}}*! ✨ ... Pra fechar com chave de ouro, dá uma nota rapidinho — ajuda demais ... _(anônimo, 30s)_" — warmth + signal of brevity. **Best variant.**
- **group_v6:** "Pessoal, encerramos *{{class_name}}* agora há pouco. 👇 Se tiver 30 segundos, agradeceríamos muito a nota: ... Obrigado pela presença e dedicação. 🙏" — formal-warm, respeitful tone fits high-ticket.
- **group_v8:** "Time {{cohort_name}}! Obrigado pela presença em *{{class_name}}* hoje. Pra continuarmos refinando cada encontro, nota rápida aqui:" — clean, premium.

### Fix
- **group_v1:** "Pessoal, obrigado pela presença em *{{class_name}}* hoje! 💜 Queremos saber como foi pra vocês. Responde rapidinho aqui (anônimo, opção de colocar nome): {{link}}" — "Responde rapidinho" is fine but "opção de colocar nome" is awkward in-message UX explanation. **Suggest:** "Pessoal, obrigado pela presença em *{{class_name}}* hoje 💜 Como foi pra vocês? (30s, anônimo se preferir) → {{link}}"
- **group_v2:** "Galera, fechamos *{{class_name}}* agora! 🚀 ... Leva 30s, podem responder sem se identificar." — "Galera" inconsistent with premium positioning when next variant says "Time {{cohort_name}}". Also "sem se identificar" sounds clinical. **Suggest:** Replace "Galera" → "Pessoal" or "Time"; replace "sem se identificar" → "anônimo, se preferir".
- **group_v5:** "{{cohort_name}} 🎯 Feedback express sobre *{{class_name}}* hoje? Link rápido aqui: {{link}} Sua nota orienta o próximo módulo." — "Feedback express" + "Link rápido aqui" reads like SaaS B2B newsletter. **Suggest:** Soften header — "Time {{cohort_name}} 🎯" → matches v3/v8 cadence.
- **group_v7:** "Avaliação rápida da aula *{{class_name}}*? {{link}} Pode responder anônimo se preferir — sua opinião direciona evolução do conteúdo. 💜" — no greeting, opens cold. Premium brand opens with relationship signal. **Suggest:** Prepend "Pessoal," or use the `{{greeting}}` slot already wired in `dispatch-class-nps/index.ts:101` ("Boa noite, ...").

### Tone consistency
- 5 of 8 use emoji-as-punctuation (💜 ✨ 🎯 🚀 🙏). 3 do not. Pick a rule: emoji at end of opener, none mid-body, none in the link line. Right now emojis are scattered.
- "Galera" appears in v2, v4. "Pessoal" in v1, v6, v7. "Time" in v3, v5, v8. **Pick two registers max** — "Pessoal" (warm-formal) + "Time {{cohort_name}}" (cohort-aware). Drop "Galera".

### Fallback name
- `dispatch-class-nps/index.ts:361`: `const firstName = (link.name || "aluno").trim().split(/\s+/)[0] || "aluno"`. **"aluno" as fallback is wrong for premium high-ticket.** If a student name is missing, the DM template renders "Olá, aluno!" which screams batch send. **Suggest:** Skip DM entirely when name is missing — log as `skipped: missing_name`. Better silent skip than impersonal message.

---

## Missing flows / scenarios

### MF-1 — Meta template rejected
No UI flow surfaces a rejected template state. If Meta rejects `nps_post_class_v2` after running for a week, dispatcher silently keeps failing DMs with `meta_template_pending`. **Fix:** Variant card should show Meta status badge (`APPROVED` / `PENDING` / `REJECTED`) — admin RPC reads `meta_templates` table.

### MF-2 — Wrong-cohort dispatch — no undo
If dispatcher sends to a wrong cohort (e.g., verification was wrong), there is no "recall message" path because WhatsApp messages can't be unsent past 7min. Need a **soft-undo**: expire all tokens from that job + auto-send apology message to group. **Fix:** "Marcar como dispatch errado" action on `recent_jobs` row → invalidates tokens + queues recovery message + Slack alert.

### MF-3 — Cohort with no eligible students
`nps_resolve_eligible_students` could return 0 (everyone absent, all marked `is_mentor=true`, etc.). Dispatcher would still send group message with `{{link}}` working but DMs = 0. Group msg arrives in dead group. **Fix:** Pre-flight in `processJob` — if students.length === 0 AND group not verified → skip job entirely with reason `no_recipients`.

### MF-4 — Re-arming a cohort after disable
If Igor disables variant for a specific cohort (today not possible, see GAP), or unverifies a group, there's no "remind me to re-verify" path. Verification has no expiry. **Fix:** `verified_at` should expire after 90 days — UI shows "🟡 verificação envelheceu, re-verificar".

### MF-5 — Cohort name with markdown chars
WhatsApp interprets `*text*` as bold, `_text_` as italic. Cohort names like `"PS Advanced — T3*"` (with stray asterisk) would break formatting mid-message. **Fix:** Sanitize cohort_name + class_name to strip `*`, `_`, `~`, `` ` `` before injecting into template.

---

## Observability gaps

### OB-1 — No "dispatcher health score"
KPI grid has counts (jobs/DMs/opens/responses) but no health verdict. **Suggest:** Single tile "🟢 SAUDÁVEL" / "🟡 DEGRADADO" / "🔴 CRÍTICO" based on rules (failure rate >20% in 24h = degraded; cron silent >10min = critical).

### OB-2 — No Meta API cost forecast
At 200 sales/month × ~8 classes per cohort × N cohorts × DM template cost (~$0.005-0.015/msg utility category in Brazil), monthly cost is non-trivial. No UI surface tracks "this month: X DMs sent, ~$Y estimated, projected $Z by end of month." **Fix:** Add cost line to KPI grid with hardcoded cost-per-msg config knob.

### OB-3 — Slack noise is everything-or-nothing
`postSlack` fires on every job completion (`dispatch-class-nps/index.ts:421–426`). At full cadence (3 cohorts × 8 classes/week = 24 jobs/week), Slack `#dev-alerts` gets 24 routine ✅ messages weekly. Will get muted, important failures will drown. **Fix:** Only post on `status IN ('partial','failed')` OR daily digest at 9pm BRT.

### OB-4 — No "last successful dispatch" timestamp
If Igor returns Monday after a quiet weekend, monitor shows current state but not "last green dispatch was Friday 21:35 BRT". **Fix:** Add to KPI grid or header.

### OB-5 — Cron last-tick is invisible
Same point as GAP-6. Plus: even with cron status, no "next expected tick at HH:MM" — admin can't tell if dispatcher is alive without waiting 5min.

### OB-6 — Open-rate per variant is not surfaced
Telemetry exists (`nps_variant_rotation_state.rotation_count`) but no comparison "group_v4 → 67% open vs group_v2 → 31% open." **Fix:** Variant card shows aggregated open/response rate over last 30 days. This is the data that should drive deactivating weak variants.

---

## Trust UX — verdict per ritual

| Ritual | Verdict | Notes |
|--------|---------|-------|
| Grupos Verificados | **GOOD** | Modal confirmation + label + audit timestamp. Strong. |
| Mapa Zoom × Aula × Turma | **GOOD** | Visual chain status + 3 explicit failure modes. **Best part of UI.** |
| Eligible students preview | **GOOD** | Source-table explainer + per-cohort breakdown. Trust-correct. |
| Master switch | **GOOD** | Ritual checkbox + copy. Right level. |
| Variant edit | **GAP** | No "preview rendered for cohort X" before save. (GAP-1) |
| Cron status | **GAP** | Invisible. (GAP-6/OB-5) |
| DM template body | **GAP** | Opaque, requires Meta Business Manager. (GAP-2) |

---

## Recommendations — prioritized

1. **NPS.P.1 — Render preview per cohort** (S) — block flip until Igor sees what hits cohort X. Maps to GAP-1.
2. **NPS.P.2 — Detractor branch on thank-you + Slack alert** (M) — recover 0–6 scorers. Maps to GAP-3. Highest revenue lever.
3. **NPS.P.3 — NPS results dashboard** (L) — `admin/nps-results/` page. Maps to GAP-4. Without this the system is data-theater.
4. **NPS.P.4 — Surface Meta template body in monitor** (M) — pull from Meta API once on activation. Maps to GAP-2.
5. **NPS.P.5 — Variant copy polish + drop "Galera"** (S) — see Copy section. Fix v1, v2, v5, v7. Maps to Tone Consistency.
6. **NPS.P.6 — Min-1-active-variant guard** (S) — frontend block in `saveVariant`. Maps to GAP-5.
7. **NPS.P.7 — Cron status tile + "Registrar cron" button** (S-M) — Maps to GAP-6/OB-5.
8. **NPS.P.8 — "Enviar pra mim" test send** (S) — Maps to GAP-7.
9. **NPS.P.9 — Slack digest mode (failures + 9pm summary only)** (S) — Maps to OB-3.
10. **NPS.P.10 — Sanitize cohort/class names for WA markdown chars** (S) — Maps to MF-5.

Quick wins (do this week): P.5, P.6, P.7, P.9, P.10 — all S, all under 4h total.
Big lever (do next): P.2 + P.3 — these turn the system from data-collection into a revenue/retention loop.

---

## Open questions for Igor

1. **Who consumes NPS scores today?** Is there a CS person reading detractors, or is this for your own product-direction sense-checking? Drives priority of P.2 vs P.3.
2. **Meta template display name** — what shows up as the WhatsApp sender on aluno's phone? Confirms GAP-2 severity.
3. **Acceptable cost ceiling** for Meta DMs/month? Drives whether OB-2 needs hardening.
4. **Detractor follow-up SLA** — if a 3/10 lands, when do you want to know? Real-time Slack vs daily digest.
5. **Variant deactivation strategy** — do you want to A/B test variants by open-rate (auto-deactivate worst) or hand-curate? Drives OB-6 design.
6. **First test cohort** — internal mentors or a real (low-stakes) student cohort? Determines whether P.8 ("Enviar pra mim") is enough or we also need a "test cohort" concept.
