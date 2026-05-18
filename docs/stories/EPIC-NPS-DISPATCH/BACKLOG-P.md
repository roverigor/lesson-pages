# BACKLOG Chapter P — Product (PM Review)

**Epic:** EPIC-NPS-DISPATCH
**Source:** `docs/architecture/pm-review-nps-2026-05-17.md`
**Wave:** quick wins (1-3h) → big levers (M/L)

## Igor's answers shaped priorities

- **Q1 NPS consumers:** Professores + CS + equipe educacional (multi-stakeholder)
- **Q2 Display name:** "Academia Lendária" (premium brand correto)
- **Q3 Cost ceiling:** liberdade total (visibility yes, hard cap não)
- **Q4 Detractor SLA:** Slack real-time com nome+telefone do aluno em grupo dedicado
- **Q5 Variant ranking:** sistema calcula + sugere desativar; humano decide
- **Q6 First cohort:** N/A — Igor confia no fluxo, foco em garantir GRUPO CORRETO + MSG CORRETA + MOMENTO CERTO

## Stories

### Quick wins (~4h total file-only)

| ID | Title | Effort | Status |
|----|-------|--------|--------|
| **P.1** | Render preview por cohort antes de flip | S | Ready |
| **P.5** | Copy polish v1/v2/v5/v7 + drop "Galera" | S | Ready |
| **P.6** | Min-1-active variant guard | S | Ready |
| **P.7** | Cron status tile + register button | S-M | Ready |
| **P.9** | Slack digest mode + skip "aluno" fallback | S | Ready |
| **P.10** | Sanitize WA markdown chars em cohort/class | S | Ready |

### Big levers (next sprint)

| ID | Title | Effort | Status |
|----|-------|--------|--------|
| **P.2** | Detractor branch + Slack alert real-time | M | Ready |
| **P.3** | NPS results dashboard `admin/nps-results/` | L | Ready |
| **P.4** | Surface Meta template body in monitor | M | Ready |
| **P.11** | Variant performance ranking + suggestions | M | Ready |

### Possible later

| ID | Title | Effort | Status |
|----|-------|--------|--------|
| **P.8** | "Enviar pra mim" test send | S | Optional |

---

## P.1 — Render preview por cohort antes de flip

**Severity:** HIGH (GAP-1 PM review)
**Effort:** S
**Goal:** Antes de Igor flipar master switch ou forçar job, ver msg renderizada exata com cohort+class real.

**AC:**
- [ ] Botão "👁 Preview msg" em cada row do Mapa Zoom × Aula
- [ ] Modal mostra: variant escolhida (mock — real escolhe weighted random no envio) + body renderizado com `{{class_name}}`, `{{cohort_name}}`, `{{link}}` substituídos
- [ ] Mostra preview pra TODAS variants ativas + indica "rotação random escolhe uma na hora"
- [ ] Link é placeholder `painel.academialendaria.ai/survey/grupo/<será gerado>`

---

## P.2 — Detractor branch + Slack alert real-time

**Severity:** HIGH (Igor Q4 = real-time)
**Effort:** M
**Goal:** Nota 0-6 dispara Slack alert dedicado com info pra CS ligar.

**AC:**
- [ ] Survey `submit-survey-group` + `submit-survey` edge fns detectam score ≤6
- [ ] Lookup do aluno (se DM token tem student_id) — nome + telefone
- [ ] Post em Slack webhook `SLACK_DETRACTORS_WEBHOOK` (env var nova)
- [ ] Mensagem inclui: nome + telefone + cohort + class + session_date + score + comment + link survey
- [ ] Survey thank-you customizado por bucket:
  - 0-6: "Obrigado pelo feedback. Um membro do time vai te chamar pra entender melhor. 🙏"
  - 7-8: input adicional "Conte o que faltaria pra ser nota 10?"
  - 9-10: "Que bom! Conhece alguém que se beneficiaria do método? [link referral]"
- [ ] Mock-friendly (preview da branch)

---

## P.3 — NPS results dashboard `admin/nps-results/`

**Severity:** HIGH (Igor Q1 = profs+CS+equipe)
**Effort:** L
**Goal:** Page agregação por cohort + class + período. Multi-stakeholder.

**AC:**
- [ ] Page `admin/nps-results/index.html` + styles + app.js
- [ ] RPC `nps_results_aggregate(filters)` retornando:
  - NPS computado (promoters-detractors)/total × 100
  - Avg score
  - Distribution buckets (0-6, 7-8, 9-10)
  - Comments list por cohort
- [ ] Filters: date range, cohort, class
- [ ] Charts: NPS trend WoW + score distribution
- [ ] Export CSV detractor comments
- [ ] Role-aware (futuro: prof vê só suas aulas; CS vê detractors; admin vê tudo) — V1 admin-only
- [ ] Link no sidebar `admin/index.html`

---

## P.4 — Surface Meta template body in monitor

**Severity:** MED (Q2 reduziu severidade — display name já premium)
**Effort:** M
**Goal:** Variant card DM mostra body real (pulled via Meta API), não só template_name.

**AC:**
- [ ] Adicionar coluna `meta_template_body_cached TEXT` em `nps_message_variants`
- [ ] RPC `nps_admin_refresh_meta_template_body(variant_id)` fetch via Meta API
- [ ] Botão "🔄 atualizar body" no variant card DM
- [ ] Render body cached no expand do card

---

## P.5 — Copy polish + drop "Galera"

**Severity:** MED (premium brand correctness)
**Effort:** S
**Goal:** Tone consistente em todas 8 group variants.

**AC:**
- [ ] Migration ALTER `nps_message_variants` body_template:
  - `group_v1`: simplifica "Responde rapidinho... opção de colocar nome" → "Como foi pra vocês? (30s, anônimo se preferir)"
  - `group_v2`: "Galera" → "Pessoal"; "sem se identificar" → "anônimo, se preferir"
  - `group_v5`: header "{{cohort_name}}" → "Time {{cohort_name}}"
  - `group_v7`: adicionar `{{greeting}}` no opening
  - `group_v4`: trocar "Galera" → "Pessoal"
- [ ] Register usage rule: 2 max ("Pessoal" warm-formal + "Time {{cohort_name}}" cohort-aware)
- [ ] Emoji rule documented: max 1 emoji por mensagem, no opening ou closing, nunca mid-body

---

## P.6 — Min-1-active variant guard

**Severity:** MED (silent footgun)
**Effort:** S
**Goal:** Bloquear deactivate da última variant ativa por canal.

**AC:**
- [ ] RPC `nps_admin_update_variant` verifica: se p_active=false, COUNT(active) > 1 senão raise
- [ ] Frontend mostra mensagem ANTES de chamar RPC (UX): "Esta é a última variant ativa de Grupo — desativar pausa todos envios"
- [ ] Mock: validar mesma lógica

---

## P.7 — Cron status tile + register button

**Severity:** MED (silent fail mode)
**Effort:** S-M
**Goal:** Surface cron status no monitor.

**AC:**
- [ ] RPC `nps_admin_cron_status()` retornando: jobname, schedule, active flag, last_run (de `cron.job_run_details`), next_run estimado
- [ ] Adicionar resposta no `nps_admin_dashboard` retorno
- [ ] Tile no monitor (próximo do master switch):
  - 🟢 "Cron ativo — última execução X min atrás"
  - 🔴 "Cron não registrado — clique pra registrar"
- [ ] Botão "Registrar cron" chama RPC `nps_admin_register_cron()` (whitelist-only)
- [ ] Botão "Desregistrar cron" disponível também

---

## P.9 — Slack digest mode + skip fallback name

**Severity:** MED (Slack signal/noise)
**Effort:** S
**Goal:** Slack só posta em falha + digest 9pm. Skip DM se aluno sem nome.

**AC:**
- [ ] `dispatch-class-nps`:
  - `postSlack` só roda se `finalStatus IN ('partial','failed')`
  - Linha aluno sem name (não vem do students): skip DM, increment `dm_skipped_count`, log motivo `missing_name`
  - NÃO usa fallback "aluno" no template
- [ ] Nova edge fn `dispatch-class-nps-digest` (cron diário 21:00 BRT) — summary de últimas 24h jobs com counts + link `admin/envios`

---

## P.10 — Sanitize WA markdown chars

**Severity:** LOW (edge case mas premium)
**Effort:** S
**Goal:** Cohort/class names com `*_~\`` não quebram formatação WA.

**AC:**
- [ ] Helper `sanitizeForWA(text)` no edge fn — strip ou escape `*`, `_`, `~`, `` ` ``
- [ ] Aplicado em `class_name` e `cohort_name` antes de `renderTemplate`
- [ ] Test cases: "PS Advanced *T3" → "PS Advanced T3"; "Aula_15" → "Aula 15"

---

## P.11 — Variant performance ranking + suggestions

**Severity:** MED (Igor Q5)
**Effort:** M
**Goal:** Ranking de variants por performance (open rate + response rate + NPS médio das responses). Sugere desativar fracas. Humano decide.

**AC:**
- [ ] RPC `nps_variant_performance(p_days INT)` retornando por variant:
  - sends_count, open_count, open_rate, response_count, response_rate, avg_score (das responses), score_count
- [ ] Variant cards mostram badges: 🏆 best 🥈 2nd 🥉 3rd + ranking position
- [ ] Card de variant com performance <30% do top mostra sugestão "📊 considere desativar — performance 40% abaixo do top"
- [ ] Humano clica edit + toggle (não auto)
- [ ] Min de 30 sends antes de mostrar ranking (avoid early bias)

---

## Activation gate update

After PM stories close, before flag flip:

- [ ] All Chapter D Done ✓ (already)
- [ ] P.5 copy polish merged
- [ ] P.6 + P.9 + P.10 quick guards in place
- [ ] At least 1 DM template approved (Chapter T)
- [ ] P.1 preview confirms render integrity
- [ ] P.2 detractor branch live (CS Slack channel created + webhook set)
- [ ] P.7 cron status visible green
- [ ] Smoke test em cohort small confirmado
