# EPIC-015 — Área CS Dedicada: Forms + Onboarding ActiveCampaign

**Status:** Draft (aguardando @qa critique)
**Prioridade:** High
**PM:** Morgan (@pm)
**Criado:** 2026-05-04
**Spec:** `docs/stories/EPIC-015-cs-area/spec/spec.md`
**Requirements:** `docs/stories/EPIC-015-cs-area/spec/requirements.json`

---

## Objetivo

Construir braço dedicado do sistema lesson-pages para o time de Customer Success operar autonomamente: criar formulários de qualquer tipo (NPS, CSAT, Onboarding, custom), gerenciar cohorts e alunos, disparar via Meta Cloud API com tracking aluno-centric, e receber automaticamente novos alunos do ActiveCampaign após cada compra.

---

## Resultado de Negócio

| KPI | Meta |
|---|---|
| Tempo "compra AC → form recebido" | < 5 min (auto-dispatch) |
| Forms novos criados pelo CS sem dev | 100% autônomo |
| Cobertura tracking 4 timestamps | 100% sent_at, > 80% delivered/read (depende plano Meta) |
| SLA pendentes resolvidos | < 24h (alert Slack se >) |
| Pendentes/dia esperado | < 10% das compras |

---

## Contexto Técnico

### O que já existe (REUSO ~70%)

| Recurso | Localização | Reuso |
|---|---|---|
| Meta Cloud API integration (`sendWhatsAppTemplate`) | `dispatch-survey/index.ts` L119-181 | Extrair para `_shared/meta-whatsapp.ts` |
| Tabelas surveys/links/questions/responses/answers | `supabase/migrations/20260408*.sql` | Estender (não recriar) |
| Edge Function `dispatch-survey` (Meta + chunked) | `supabase/functions/dispatch-survey/` | Refatorar para receber `student_ids` explícitos |
| Edge Function `submit-survey` | idem | Manter |
| Cohorts + students + RLS | `baseline_existing_schema.sql` | Reusar |
| Admin tab Avaliações + `surveys.js` (964 linhas) | `js/admin/surveys.js` | Migrar para `cs-portal` (mantém legado admin) |
| Auth Supabase JWT user_metadata role | toda app | Estender (`role='cs'`) |

### O que precisa ser criado (~30%)

1. Repo separado `cs-portal` (Docker + GitHub Actions independentes)
2. 7 tabelas novas: `survey_versions`, `ac_purchase_events`, `pending_student_assignments`, `ac_product_mappings`, `ac_dispatch_callbacks`, `meta_templates` (+ extensões em existentes)
3. 3 Edge Functions novas: `ac-purchase-webhook`, `ac-report-dispatch`, `meta-delivery-webhook`
4. Frontend `cs-portal` completo (sidebar 8 tabs + form builder + drill-down + pendentes)
5. Nginx routing `/cs/*` → container `:3081`

---

## Stories (19)

| # | Story | Repo | Tamanho |
|---|---|---|---|
| 15.0 | AC Discovery + validação 13 OQs | lesson-pages | S |
| 15.A | Schema migrations (7 tabelas + extensões) | lesson-pages | M |
| 15.B | Edge function `ac-purchase-webhook` | lesson-pages | M |
| 15.C | Edge function `ac-report-dispatch` | lesson-pages | S |
| 15.I | Edge function `meta-delivery-webhook` | lesson-pages | M |
| 15.J | Bootstrap repo `cs-portal` + Docker + CI | cs-portal | M |
| 15.K | Nginx VPS routing `/cs/*` | infra | S |
| 15.1 | Role `cs` + auth + redirect role-based | shared | M |
| 15.2 | UI cohorts CRUD | cs-portal | M |
| 15.3 | UI alunos por turma (manual + CSV) | cs-portal | M |
| 15.4 | Refactor dispatch-survey + UI individual avulso | mixed | M |
| 15.5 | Área CS standalone + sidebar 8 tabs | cs-portal | M |
| 15.6 | Form builder full (13 tipos drag-drop) | cs-portal | L |
| 15.7 | Histórico/auditoria + drill-down aluno | cs-portal | S |
| 15.8 | Meta templates registry (tabela DB + UI) | mixed | S |
| 15.D | UI mappings AC + lista eventos | cs-portal | M |
| 15.E | Observabilidade + alertas Slack | lesson-pages | S |
| 15.F | Resolução cohort manual (UI pendentes) | cs-portal | M |
| 15.G | Versioning forms | mixed | S |

**Total: ~160 tasks. Estimativa: 5-6 sprints.**

---

## Decisões Arquiteturais Chave

| Decisão | Escolha | Motivo |
|---|---|---|
| Auth | Login compartilhado + redirect role-based | Reuso Supabase Auth; admin tem super-acesso a `/cs/*` |
| Repo | Separado (`cs-portal`) | Autonomia CS team com Claude Code próprio |
| Migrations | Centralizadas em `lesson-pages` | Governance schema via PR review |
| Async dispatch | Worker pg_cron OR direct call em background | AC timeout 10s |
| Idempotência | UNIQUE `ac_event_id` + ON CONFLICT | Webhook AC pode reenviar |
| Versionamento | Tabela `survey_versions` | Edita não invalida links |
| Cohort histórico | Campo TEXT `cohort_snapshot_name` | Simplicidade > tabela dedicada |
| Meta templates | Tabela DB editável | CS troca template sem deploy |
| Form-Cohort binding | Form vincula ao **aluno**, não cohort | Tracking aluno-centric (req do user) |
| Tracking | 4 timestamps obrigatórios (`sent/delivered/read/responded`) | NFR-16 — saber exatamente o que aluno recebeu |
| CS scope | CS vê **todos** alunos/cohorts | Decisão user — sem escopo restrito |
| Cohort órfão | Pendente até resolução manual | NÃO dispara form sem cohort |

---

## Dependências

### Externas
- **ActiveCampaign** — webhook outbound para nosso endpoint + API para callback
- **Meta Cloud API** — template aprovado + (opcional) plano com delivery webhook
- **GitHub** — repo `cs-portal` + permissões CS team
- **Anthropic** — contas Claude Code para CS team (autonomia)

### Internas
- Supabase project `gpufcipkajppykmnmdeh` (compartilhado)
- VPS Contabo (porta 3081 livre + nginx config)
- Slack workspace (alerts CS)
- Repo lesson-pages (migrations + edge functions hub)

---

## Bloqueio Atual

**Story 15.0 é PRÉ-REQUISITO ABSOLUTO.** Sem validar 13 OQs em `requirements.json#openQuestions`, não inicia 15.A em diante.

OQs críticas:
1. Plataforma é ActiveCampaign mesmo (vs ActiveMember360, custom)
2. Payload exemplo do webhook AC
3. AC suporta HMAC ou só URL token
4. AC permite escrever custom_field via API
5. `ac_event_id` único OR derivado
6. Meta plano suporta `messages.update` webhook
7. Lista templates Meta atuais aprovados
8. ac_product_mappings 1:1 confirmado
9. GitHub access para repo `cs-portal`

---

## Riscos Top 5

| ID | Risco | Severidade | Mitigação |
|---|---|---|---|
| R1 | AC sem HMAC | High | Story 15.0 valida; fallback URL token |
| R3 | LGPD purge falha | High | NFR-13 cron + auditoria |
| R4 | DB schema drift cs-portal × lesson-pages | High | CON-14 governance |
| R6 | AC webhook timeout | Critical | NFR-6 + async obrigatório |
| R8 | Idempotência falha → duplicidade | Critical | NFR-4 UNIQUE + ON CONFLICT |

---

## Próximos Passos

1. **@qa critique** sobre `spec.md` (5 dimensões)
2. **@architect** ADR sobre async dispatch + queue strategy
3. **@po** validar spec
4. **@sm `*draft`** Story 15.0 (Discovery)
5. Após GO 15.0 → drafting paralelo demais stories
6. **`*execute-epic`** wave-based

---

## Referências

- Spec completa: `docs/stories/EPIC-015-cs-area/spec/spec.md`
- Requirements: `docs/stories/EPIC-015-cs-area/spec/requirements.json`
- EPIC-004 (NPS/CSAT base reusada): `docs/stories/epics/EPIC-004-nps-csat-surveys.md`
- Constitution: `.aiox-core/constitution.md`
- VPS info: `.claude/CLAUDE.md`
