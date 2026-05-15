# EPIC-015 — Área CS Dedicada: NPS/Onboarding/Forms + Integração ActiveCampaign

**Spec Version:** 1.0
**Status:** Draft (aguardando @qa critique + @architect ADR)
**Created:** 2026-05-04
**Author:** @pm (Morgan)
**Pipeline Phase:** Spec (post-Gather)
**Source:** `requirements.json` v2.0
**Complexity Class:** COMPLEX (score ~18/25)

---

## 1. Visão Executiva

Construir braço dedicado do sistema lesson-pages para o time de Customer Success operar autonomamente: criar formulários (NPS, CSAT, Onboarding, custom), gerenciar cohorts e alunos, disparar via Meta Cloud API com tracking aluno-centric, e receber automaticamente novos alunos do ActiveCampaign via webhook após cada compra.

**Objetivo de Negócio:** automatizar onboarding pós-compra + dar autonomia total ao CS para forms NPS/CSAT/feedback sem dependência de dev.

**Resultado Esperado:**
- Tempo médio "compra AC → form recebido" < 5 minutos (auto-dispatch)
- 0 dependência do CS em admin/dev para criar forms novos
- Tracking 100% aluno-centric (sent/delivered/read/responded)
- Histórico imutável mesmo se aluno trocar de cohort

---

## 2. Escopo

### 2.1 IN SCOPE (V1)

- Login compartilhado com redirect role-based (`cs` → `/cs/`, `admin` → `/admin/`)
- Repo separado `cs-portal` com Docker e GitHub Actions independentes
- UI completa CS: cohorts, alunos, forms (builder), disparos (cohort + individual + misto), pendentes, histórico, mappings AC
- Edge function `ac-purchase-webhook` (HMAC + dedup + auto/pending)
- Edge function `ac-report-dispatch` (callback AC com retry exponencial)
- Edge function `meta-delivery-webhook` (delivered + read tracking)
- Form builder completo (13 tipos de pergunta, drag-drop, preview live, versionamento)
- Tracking 4 timestamps + cohort_snapshot_name imutável
- Fila de pendentes com resolução manual + Slack alerts
- Meta templates registry em DB (CS edita sem deploy)

### 2.2 OUT OF SCOPE (V2+)

- Lógica condicional de perguntas (mostrar Q3 só se Q1=sim)
- UI dedicada de gestão de users CS (V1 = Supabase dashboard)
- SSO / MFA para CS team
- Multi-language Meta templates (V1 = pt_BR apenas)
- Polling AC API (V1 = só push webhook)
- Heurística suggested_cohort em Discovery (decisão @architect em OQ-10)
- Mapping N:N produto AC ↔ cohort (V1 = 1:1)

### 2.3 Referência Cruzada

| Capítulo | Refere a |
|---|---|
| Functional Requirements | requirements.json `functional[]` (FR-1 a FR-17) |
| Non-Functional | requirements.json `nonFunctional[]` (NFR-1 a NFR-20) |
| Constraints | requirements.json `constraints[]` (CON-1 a CON-14) |
| Acceptance | requirements.json `interactions[]` + 20 ACs Given/When/Then |

---

## 3. Requisitos Funcionais (Resumo + Trace)

| ID | Requisito | Prio | Trace AC | Trace EC |
|---|---|---|---|---|
| FR-1 | Login compartilhado + redirect role-based | P0 | AC-1, AC-2, AC-3 | EC-9 |
| FR-2 | CS gerencia cohorts (CRUD) | P0 | AC-9 | EC-7, EC-22 |
| FR-3 | CS gerencia alunos (manual + CSV) | P0 | — | EC-2, EC-19, EC-23 |
| FR-4 | Form builder autônomo (13 tipos) | P0 | AC-7 | EC-18 |
| FR-5 | Disparo cohort via Meta template | P0 | AC-9 | EC-3, EC-6, EC-22 |
| FR-6 | Disparo individual avulso | P0 | AC-8 | EC-3, EC-6 |
| FR-7 | Webhook inbound AC (HMAC + dedup) | P0 | AC-4, AC-14, AC-15 | EC-1, EC-4, EC-12, EC-24 |
| FR-8 | Auto-criar Student + auto-vincular cohort | P0 | AC-4 | EC-2, EC-17 |
| FR-9 | Fila Pendentes (cohort órfão) | P0 | AC-5 | EC-17 |
| FR-10 | Resolução manual + criar mapping permanente | P0 | AC-6 | EC-8 |
| FR-11 | Callback outbound AC (retry 3x) | P0 | AC-12, AC-13 | EC-10 |
| FR-12 | Histórico/timeline aluno-centric | P1 | AC-11, AC-16 | EC-16, EC-26 |
| FR-13 | Versionamento forms (edita sem invalidar) | P1 | AC-10 | EC-5 |
| FR-14 | Dashboard observabilidade integrações | P1 | — | EC-1, EC-3, EC-10 |
| FR-15 | Mappings AC CRUD | P0 | — | EC-11, EC-17 |
| FR-16 | Tracking 4 timestamps obrigatório | P0 | AC-11, AC-19, AC-20 | EC-20 |
| FR-17 | Timeline imutável a mudanças de cohort | P1 | AC-16 | EC-7, EC-16 |

---

## 4. Arquitetura

### 4.1 Topologia de Repos e Serviços

```
┌─────────────────────────────────────────────────────────────┐
│  GitHub                                                      │
│  ├─ roverigor/lesson-pages   (admin painel + edge functions │
│  │                            + migrations DB centralizadas)│
│  └─ roverigor/cs-portal      (frontend CS independente)    │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Supabase (gpufcipkajppykmnmdeh) — COMPARTILHADO            │
│  ├─ Auth (single user pool, role-based JWT)                 │
│  ├─ Tabelas (cohorts, students, surveys, ac_*, pending_*)   │
│  ├─ RLS policies por role                                   │
│  └─ Edge Functions:                                         │
│     ├─ dispatch-survey         (existente, refatorar)       │
│     ├─ submit-survey           (existente)                  │
│     ├─ ac-purchase-webhook     (NOVA — Story 15.B)          │
│     ├─ ac-report-dispatch      (NOVA — Story 15.C)          │
│     └─ meta-delivery-webhook   (NOVA — Story 15.I)          │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  VPS Contabo 194.163.179.68                                 │
│  ├─ Container lesson-pages   :3080  (painel admin)          │
│  └─ Container cs-portal      :3081  (NOVO — Story 15.J)     │
│                                                              │
│  Nginx routing:                                             │
│   painel.igorrover.com.br  → :3080                          │
│   painel.igorrover.com.br/cs/* → :3081 (Story 15.K)         │
└─────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────┐
│  Externos                                                    │
│  ├─ ActiveCampaign  (purchase webhook → ac-purchase-webhook)│
│  ├─ Meta Cloud API  (templates outbound + delivery webhook) │
│  └─ Slack           (alerts CS team)                        │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Schema Diff

**Tabelas Existentes (manter):**
- `surveys`, `survey_questions`, `survey_responses`, `survey_answers`, `survey_links`
- `cohorts`, `student_cohorts`, `students`
- `student_nps`, `notifications`

**Tabelas Novas (7):**
1. `survey_versions` — snapshot perguntas por versão
2. `ac_purchase_events` — audit log webhooks AC
3. `pending_student_assignments` — fila órfãos
4. `ac_product_mappings` — regra produto → cohort + survey + template
5. `ac_dispatch_callbacks` — registros callback AC
6. `meta_templates` — registry templates aprovados
7. (cohort_snapshots OPCIONAL — decisão: usar campo TEXT direto)

**Extensões em Tabelas Existentes:**
- `students` adiciona `ac_contact_id UNIQUE NULLABLE`
- `survey_links` adiciona `delivered_at`, `read_at`, `version_id`, `meta_message_id`, `cohort_snapshot_name`
- `surveys` adiciona `category` ENUM e `current_version_id`

### 4.3 Auth & RLS Matrix

| Tabela | role=admin | role=cs | anon (token) |
|---|---|---|---|
| `cohorts` | ALL | ALL (CRUD) | — |
| `students` | ALL | ALL | — |
| `student_cohorts` | ALL | ALL | — |
| `surveys` | ALL | ALL | — |
| `survey_versions` | ALL | ALL | SELECT (via token) |
| `survey_questions` | ALL | ALL | SELECT (via token) |
| `survey_links` | ALL | ALL | SELECT WHERE token = $1 |
| `survey_responses` | SELECT | SELECT | INSERT (via service role) |
| `survey_answers` | SELECT | SELECT | INSERT (via service role) |
| `ac_purchase_events` | ALL | SELECT | — |
| `pending_student_assignments` | ALL | ALL | — |
| `ac_product_mappings` | ALL | ALL | — |
| `ac_dispatch_callbacks` | SELECT | SELECT | — |
| `meta_templates` | ALL | ALL | — |

### 4.4 Edge Functions (5)

| Função | Status | Auth | Trigger |
|---|---|---|---|
| `dispatch-survey` | refatorar | JWT admin/cs OR service_role | UI dispatch + worker async |
| `submit-survey` | manter | service_role (anon access via token) | `/avaliacao/responder?token=X` |
| `ac-purchase-webhook` | **nova** | HMAC X-AC-Signature | POST AC → nosso endpoint |
| `ac-report-dispatch` | **nova** | service_role internal | chamada após dispatch sucesso |
| `meta-delivery-webhook` | **nova** | Meta verify token + HMAC X-Hub-Signature-256 | Meta envia messages.update |

### 4.5 Fluxos Críticos

Detalhados em `requirements.json#interactions[INT-1..INT-6]`.

Resumo decisões arquiteturais:

| Decisão | Escolha | Rationale |
|---|---|---|
| Async dispatch | Worker pg_cron OR direct call em background | AC timeout 10s, dispatch leva 10s+ por aluno |
| Idempotência | UNIQUE constraint `ac_event_id` + ON CONFLICT DO NOTHING | Webhook AC pode reenviar |
| Versionamento forms | Tabela `survey_versions` com snapshot perguntas | Edita não invalida links já enviados |
| Cohort snapshot | Campo TEXT em `survey_links.cohort_snapshot_name` | Simples; não precisa tabela dedicada |
| Meta templates | Tabela DB editável CS | CS troca template sem deploy |
| Callback AC | Retry exponencial 1s/4s/16s + DLQ | Resiliência sem perder confirmação |
| Repo separado | `cs-portal` repo + Docker independente | Autonomia CS team com Claude Code próprio |
| Migrations centralizadas | `lesson-pages/supabase/migrations/` | Schema governance via PR review |

### 4.6 Decisões Deferidas para @architect *plan (ADR)

| Decisão | Critique ID | Escopo @architect |
|---|---|---|
| Tech stack frontend `cs-portal` | CRIT-1 | Vanilla JS+esbuild (recomendado) vs Vue/React; impacta 15.J/15.5/15.6 |
| Mitigação cold start Edge Function (NFR-6 < 2s) | CRIT-5 | Warm-up cron pg_cron vs minimal-sync handler vs Cloudflare Worker |
| Migration plan EPIC-004 → EPIC-015 | CRIT-4 | Backfill, feature flag rollback, shadow mode, cutover gradual |

### 4.7 File Manifest

| Arquivo | Ação | Story | Propósito |
|---|---|---|---|
| `supabase/migrations/20260505100000_epic015_schema.sql` | create | 15.A | 7 tabelas novas + extensões (`students.ac_contact_id`, `survey_links.{delivered_at,read_at,version_id,meta_message_id,cohort_snapshot_name}`, `surveys.{category,current_version_id}`) |
| `supabase/migrations/20260505100100_epic015_rls.sql` | create | 15.A | RLS policies novas tabelas + extensão políticas existentes para role 'cs' |
| `supabase/migrations/20260505100200_epic015_purge_cron.sql` | create | 15.A | pg_cron job purge `ac_purchase_events` > 90d |
| `supabase/migrations/20260505100300_epic015_pending_alert_cron.sql` | create | 15.A | pg_cron job Slack alert pendentes > 24h |
| `supabase/functions/_shared/meta-whatsapp.ts` | create | 15.A | Extrair `sendWhatsAppTemplate` de dispatch-survey (CON-10) |
| `supabase/functions/_shared/ac-utils.ts` | create | 15.B | HMAC validation + AC payload parsers |
| `supabase/functions/ac-purchase-webhook/index.ts` | create | 15.B | Edge function inbound AC |
| `supabase/functions/ac-report-dispatch/index.ts` | create | 15.C | Edge function callback outbound AC |
| `supabase/functions/meta-delivery-webhook/index.ts` | create | 15.I | Edge function delivery/read receipts Meta |
| `supabase/functions/dispatch-survey/index.ts` | modify | 15.4 | Refactor: aceitar `student_ids` explícitos; usar `_shared/meta-whatsapp.ts`; chamar callback ac-report-dispatch após sucesso |
| `admin/index.html` (login) + `js/admin/auth.js` | modify | 15.1 | Redirect role-based (cs → /cs/, admin → /admin/) |
| `cs-portal/Dockerfile` | create | 15.J | Container porta 3081 |
| `cs-portal/.github/workflows/deploy.yml` | create | 15.J | CI/CD repo separado |
| `cs-portal/CLAUDE.md` | create | 15.J | Regras Claude Code repo CS |
| `cs-portal/index.html` | create | 15.5 | Home + sidebar 8 tabs |
| `cs-portal/js/auth-guard.js` | create | 15.1 | Auth guard role 'cs' OR 'admin' |
| `cs-portal/js/cohorts.js` | create | 15.2 | UI cohorts CRUD |
| `cs-portal/js/students.js` | create | 15.3 | UI alunos + bulk CSV |
| `cs-portal/js/dispatch.js` | create | 15.4 | UI dispatch (cohort/individual/misto) |
| `cs-portal/js/forms-builder.js` | create | 15.6 | Form builder drag-drop |
| `cs-portal/js/forms-list.js` | create | 15.6 | Lista forms + ações |
| `cs-portal/js/pending.js` | create | 15.F | UI fila pendentes |
| `cs-portal/js/history.js` | create | 15.7 | Timeline drill-down aluno |
| `cs-portal/js/integrations.js` | create | 15.D | UI mappings AC + eventos |
| `cs-portal/js/observability.js` | create | 15.E + 15.D | Métricas dashboard |
| `cs-portal/css/cs-shared.css` | create | 15.5 | Estilos CS (reuso design-tokens-dark-premium) |
| `/etc/nginx/sites-available/painel-lesson-pages` (VPS) | modify | 15.K | Rota `/cs/*` → :3081 |
| `docs/architecture/ADR-015-cs-portal-tech-stack.md` | create | 15.0 + plan | ADR @architect |
| `docs/guides/cs-onboarding-guide.md` | create | pós-15.J | Manual CS team |
| `.github/CODEOWNERS` (root lesson-pages) | modify | 15.0 | Auto-assign @architect em supabase/migrations/* (CRIT-11) |

### 4.8 Migration Plan EPIC-004 → EPIC-015

(Deferido para @architect *plan ADR — ver §4.6 e CRIT-4 em critique.json)

Princípios mínimos a respeitar:
- Backfill `survey_recipients` a partir de `surveys` existentes com `cohort_id`
- Feature flag `EPIC015_NEW_DISPATCH` para rollback do `dispatch-survey` legacy
- Shadow mode rodando ambos paths durante 1 sprint pré-cutover
- Cutover gradual: novos surveys usam fluxo novo; surveys ativos pré-migração mantêm fluxo antigo até encerramento

### 4.9 Dependency Versions

| Dependência | Versão Pinned | Notas |
|---|---|---|
| Supabase JS SDK | `@supabase/supabase-js@2.39.0` | Já em uso no projeto |
| Deno std (Edge Functions) | `0.177.0` | Já em uso |
| Meta Graph API | `v21.0` | Já em uso (`graph.facebook.com/v21.0`) |
| ActiveCampaign API | TBD (validar OQ-1 / Story 15.0) | Provável v3 |
| esbuild (cs-portal frontend) | TBD (decisão @architect §4.6) | Se vanilla JS escolhido |

### 4.10 Governance DB Schema

Deferido para infra/devops em Story 15.0. Implementação mínima:
- `.github/CODEOWNERS` auto-assign `@architect` para `supabase/migrations/*`
- PR template com checklist obrigatório: RLS habilitada, idempotência, rollback documentado
- CI gate valida migrations vêm de PRs aprovados por `@architect`

---

## 5. Acceptance Criteria

### Login & Auth

```gherkin
AC-1: GIVEN user com user_metadata.role='cs' em /admin/login
      WHEN auth completa
      THEN redirect → /cs/

AC-2: GIVEN user role='admin'
      WHEN navega para /cs/
      THEN acesso permitido (super-acesso)

AC-3: GIVEN user role='cs'
      WHEN tenta /admin/
      THEN 403 + redirect /cs/
```

### Webhook AC

```gherkin
AC-4: GIVEN AC envia POST purchase com produto MAPEADO
      WHEN webhook valida HMAC + dedup
      THEN cria/atualiza student → vincula cohort → enfileira dispatch → 200 < 2s

AC-5: GIVEN AC envia evento produto SEM mapping
      WHEN webhook processa
      THEN cria student → INSERT pending_student_assignments → Slack alert → 200

AC-14: GIVEN AC reenvia mesmo evento (mesmo ac_event_id)
       WHEN webhook recebe 2ª vez
       THEN dedup detectado → 200 + log "duplicate" → sem efeito colateral

AC-15: GIVEN webhook AC chega sem header HMAC válido
       WHEN edge function valida
       THEN 401 + log security alert + Slack notify
```

### Resolução Manual

```gherkin
AC-6: GIVEN CS abre /cs/pendentes e seleciona aluno
      WHEN escolhe cohort + clica "Atribuir"
      THEN UPDATE student_cohorts → dispara form → resolved_at marcado
```

### Forms

```gherkin
AC-7: GIVEN CS em /cs/forms/new
      WHEN arrasta perguntas + salva
      THEN surveys + survey_versions v1 + survey_questions inseridos, status='draft'

AC-10: GIVEN survey com 3 disparos enviados (versão 1)
       WHEN CS edita perguntas + salva
       THEN nova survey_versions v2; alunos antigos respondem v1; novos disparos usam v2
```

### Disparo

```gherkin
AC-8: GIVEN CS cria survey + seleciona 5 alunos via search multi-select
      WHEN clica "Disparar"
      THEN 5 survey_links criados (cada com cohort_snapshot_name) → 5 mensagens Meta (10s delay) → send_status='sent'

AC-9: GIVEN CS dispara survey p/ cohort com 50 alunos
      WHEN clica "Disparar cohort"
      THEN 50 survey_links → cohort_snapshot registrado → batch chunked
```

### Tracking

```gherkin
AC-11: GIVEN aluno recebeu form
       WHEN dispara via Meta + Meta confirma delivery + aluno lê + aluno responde
       THEN survey_links tem sent_at, delivered_at, read_at preenchidos + survey_responses tem submitted_at

AC-16: GIVEN aluno X foi de cohort A → cohort B
       WHEN CS abre histórico aluno X
       THEN vê todos disparos de cohort A (cohort_snapshot_name='A') + cohort B sem perda

AC-19: GIVEN aluno recebe mensagem Meta
       WHEN Meta envia messages.update status='delivered'
       THEN survey_links.delivered_at preenchido (correlação via meta_message_id)

AC-20: GIVEN aluno clica link → preenche form
       WHEN POST /submit-survey
       THEN survey_responses + survey_links.used_at + survey_answers gravados
```

### Callback AC

```gherkin
AC-12: GIVEN dispatch concluído com sucesso
       WHEN dispatch-survey termina
       THEN POST AC API com contact_id + custom_field 'form_dispatched' → ac_dispatch_callbacks status='ok'

AC-13: GIVEN AC API offline 1ª tentativa
       WHEN callback falha
       THEN retry 3x backoff exp; se falhar todas → DLQ + alert
```

### Edge Cases (resumo)

```gherkin
AC-17: GIVEN aluno cadastrado sem `phone`
       WHEN dispatch tenta enviar
       THEN survey_links.send_status='skipped' + relatório CS

AC-18: GIVEN pending_student_assignment criado há > 24h sem resolved_at
       WHEN cron diário roda
       THEN Slack alert escalation CS team
```

### CRUD CS (added per critique CRIT-2)

```gherkin
AC-21: GIVEN CS user em /cs/alunos
       WHEN cria, edita, importa CSV ou remove (soft) aluno
       THEN students tabela reflete operação + audit log gravado + RLS permite role='cs'

AC-22: GIVEN CS user em /cs/integracoes/mappings
       WHEN cria/edita/desativa ac_product_mapping (ac_product_id + cohort + survey + template)
       THEN ac_product_mappings tabela atualizada + próximo webhook AC do produto auto-resolve

AC-23: GIVEN CS user em /cs/integracoes (dashboard observabilidade)
       WHEN abre tab "Eventos AC"
       THEN vê count últimos 30d (received/processed/failed), fail rate %, lista paginada com filtros (status, data) + drill-down por evento (payload + erro)

AC-24: GIVEN CS user logado (role='cs')
       WHEN abre /cs/alunos
       THEN vê TODOS alunos ativos do sistema (sem filtro de escopo por cohort assignment) — confirma decisão EC-26
```

---

## 6. Stories (19) e Decomposição

| # | Story | Repo | Tamanho | Depende |
|---|---|---|---|---|
| 15.0 | AC Discovery (validar 13 OQs) | lesson-pages | S | — |
| 15.A | Schema migrations (7 tabelas + extensões) | lesson-pages | M | 15.0 |
| 15.B | Edge function `ac-purchase-webhook` | lesson-pages | M | 15.A |
| 15.C | Edge function `ac-report-dispatch` | lesson-pages | S | 15.A |
| 15.I | Edge function `meta-delivery-webhook` | lesson-pages | M | 15.A |
| 15.J | Bootstrap repo `cs-portal` + Docker + CI | cs-portal | M | — (paralelo) |
| 15.K | Nginx VPS routing `/cs/*` → :3081 | infra | S | 15.J |
| 15.1 | Role `cs` + auth + redirect role-based | shared | M | 15.A |
| 15.2 | UI cohorts CRUD | cs-portal | M | 15.J + 15.1 |
| 15.3 | UI alunos por turma (manual + CSV) | cs-portal | M | 15.2 |
| 15.4 | Refactor dispatch-survey + UI individual avulso | mixed | M | 15.A + 15.J |
| 15.5 | Área CS standalone + sidebar 8 tabs | cs-portal | M | 15.1 |
| 15.6 | Form builder full (13 tipos drag-drop) | cs-portal | L | 15.5 + 15.G |
| 15.7 | Histórico/auditoria + drill-down aluno | cs-portal | S | 15.5 + 15.A |
| 15.8 | Meta templates registry (tabela DB + UI) | mixed | S | 15.A |
| 15.D | UI mappings AC + lista eventos | cs-portal | M | 15.B + 15.5 |
| 15.E | Observabilidade + alertas Slack | lesson-pages | S | 15.B + 15.C |
| 15.F | Resolução cohort manual (UI pendentes) | cs-portal | M | 15.A + 15.5 |
| 15.G | Versioning forms (schema + UI badge) | mixed | S | 15.A |

**Total: ~160 tasks distribuídas em 19 stories.** Estimativa: 5-6 sprints com paralelismo.

### 6.1 Caminho Crítico

```
15.0 Discovery → 15.A Schema → 15.B AC webhook → 15.C Callback → 15.I Meta delivery
                                                                 ↓
15.J Repo cs-portal (paralelo) → 15.1 Auth → 15.5 Sidebar → 15.6 Builder + 15.F Pendentes
                                                                 ↓
                                            15.D + 15.E + 15.7 (paralelo final)
```

---

## 7. Riscos e Mitigações

| ID | Risco | Severidade | Mitigação |
|---|---|---|---|
| R1 | AC sem suporte HMAC | High | Story 15.0 valida ANTES de 15.B; fallback URL token |
| R2 | Meta plano sem delivery webhook | Medium | NFR-17 vira best-effort; delivered/read sem cobertura completa |
| R3 | LGPD purge falha → > 90d em prod | High | Cron pg_cron + alerta; auditoria mensal |
| R4 | DB schema drift cs-portal × lesson-pages | High | CON-14 + governance @architect |
| R5 | Form builder scope creep | Medium | OUT_OF_SCOPE explícito (ASM-10); MVP enxuto |
| R6 | AC webhook timeout 10s | Critical | NFR-6 + dispatch async obrigatório (CON-2) |
| R7 | Aluno limbo (criado sem cohort) por > 7 dias | Medium | NFR-12 SLA 24h + Slack daily |
| R8 | Idempotência falha → duplicidade | Critical | NFR-4 + EC-1 + UNIQUE constraint |
| R9 | CS Claude Code edita migration | Critical | CON-14 + repo separado bloqueia acesso |
| R10 | Meta API rate limit / ban | High | CON-3 throttle 10s + monitoring |
| R11 | AC reenvia phone diferente → confusão | Medium | EC-19 UPDATE + audit log |
| R12 | PII em payload AC | High | CON-7 + NFR-13 purge 90d + RLS |
| R13 | Suggested cohort heurística falha | Low | Opcional V1 (OQ-10 decide) |

---

## 8. Open Questions Bloqueantes

13 OQs em `requirements.json#openQuestions[]`. Críticas para destravar Story 15.0:

| OQ | Ação | Owner |
|---|---|---|
| OQ-1, OQ-2, OQ-3, OQ-5, OQ-11 | Validar AC plataforma + payload + auth + idempotência + cardinalidade | @analyst + @architect |
| OQ-6, OQ-8 | Meta Cloud API capabilities + templates aprovados | @devops |
| OQ-13 | GitHub repo cs-portal + permissões | @devops |
| OQ-7, OQ-9, OQ-10, OQ-12 | Decisões de produto não-bloqueantes | @pm |

---

## 9. Compliance & Constituição

| Artigo | Aderência | Notas |
|---|---|---|
| I — CLI First | ✅ | Edge functions e CLI Supabase |
| II — Agent Authority | ✅ | Stories delegadas conforme matriz |
| III — Story-Driven | ✅ | 19 stories formais propostas |
| IV — No Invention | ⚠️ | Spec rastreável mas Discovery (15.0) precisa preencher OQs antes de implementar |
| V — Quality First | ✅ | NFRs explícitos + 28 ECs + QA gate por story |
| VI — Absolute Imports | N/A | Frontend convention |

---

## 10. Próximos Passos

1. **@qa critique** — 5 dimensões (clarity, completeness, testability, feasibility, alignment). Verdict: APPROVED / NEEDS_REVISION / BLOCKED
2. **@architect** — ADR sobre async dispatch + queue model + retry strategy
3. **@po** — validar spec contra PRD/épico
4. **@sm** — drafting 19 stories sequencialmente (Story 15.0 primeiro)
5. **`*execute-epic`** — wave-based parallel após GO de Stories 15.0/15.A

---

## Changelog

| Versão | Data | Mudanças |
|---|---|---|
| 1.0 | 2026-05-04 | Spec inicial pós-elicitation 9/9 categorias |
