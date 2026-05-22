# EPIC-022 — Painel Refactor: Consolidação Backend + Foundation

## Status
Draft

## Owner
@pm (Morgan)

## Discovery base
- `docs/discovery/2026-05-22/01-architecture-map.md` (@architect Aria)
- `docs/discovery/2026-05-22/02-db-audit.md` (@data-engineer Dara)
- `docs/discovery/2026-05-22/03-ux-audit.md` (@ux-design-expert Uma)

## Problema

Após ~50 dias de execução paralela de épicos (EPIC-015 AC, EPIC-016 AC retries, EPIC-017 Hotmart, EPIC-018 lembretes, EPIC-019 attendance, EPIC-020 NPS, EPIC-021 NPS Hub) o painel acumulou **bagunça estrutural crítica**: 32 edge functions com 3 caminhos paralelos pra NPS (dispatch-class-nps + dispatch-survey + send-whatsapp legacy), 3 webhooks de compra sem precedência (ac/hotmart/generic), identidade do aluno triplicada (`students` + `student_imports` + `wa_group_members`) com phone em formatos divergentes que fazem JOINs falharem silenciosamente, 200 migrations resultando em 84 tabelas das quais **47% sem RLS**, e dual-identity de turma (`classes.cohort_id` deprecated coexistindo com `class_cohorts` M:N novo).

User precisa **parar de empilhar features e consolidar**. Antes de qualquer redesign visual (track DS Foundations paralelo) ou novas features, é necessário unificar identidade, eliminar paths duplicados, fechar gaps de segurança e estabelecer source-of-truth claro pra cada domínio. Sistema está em produção com 1k+ alunos ativos — refactor obriga feature flags, paralelo, idempotência e rollback documentado em cada migration.

## Objetivo

Eliminar todos os caminhos duplicados de dispatch/identidade/webhook do painel e fechar gaps de RLS — em até 6 semanas, sem downtime e sem regressão de envios em produção.

## Escopo IN

- Unificação de identidade do aluno (1 phone normalizado, 1 VIEW canônica)
- Consolidação de dispatch NPS em motor único + feature flag
- Redução de 3 → 2 dashboards NPS (operacional + análise)
- RLS em 100% das tabelas (39 tabelas pendentes)
- Webhook purchase com precedência canonical + dedup
- Cleanup `classes.cohort_id` deprecated
- Decisão registrada sobre NPS cron desativado (ADR)
- Audit de tabelas órfãs (`pending_student_assignments`, `notification_queue`, `alert_history`)
- Documentação de source-of-truth por domínio
- Delivery routing: coluna `provider` em `notifications` + roteamento em `dispatch-retry`

## Escopo OUT (explícito)

- **Design System foundations** → Track paralelo separado (DS v1, owner = @ux-design-expert)
- **Frontend redesign / migração tech stack** → Após DS v1 pronto, Epic futuro
- **Novas features de produto** (templates Meta novos, automações, etc.)
- **Migração de Evolution → Meta** (decisão pendente, fora deste epic)
- **Refactor de telas aluno** (`/aluno/*` — fora do escopo crítico)
- **Otimização de queries / índices** (exceto onde RLS exigir)
- **Migração tech stack admin** (mantém HTML+CSS atual até DS v1)

---

## Stories priorizadas

### S.022.1 — Unificar identidade do aluno (P0)

**Why:** Triple-identity (`students` + `student_imports` + `wa_group_members`) com phone em formatos divergentes ("+5511...", "11...", JSONB bruto AC) faz JOINs falharem silenciosamente. `dispatch_link_opens` e `nps_class_links` não sabem qual `student_id` usar. Campanhas perdem alunos. (Ref: 02-db-audit §3.1, §3.2)

**O que:**
- Implementar trigger `normalize_phone_e164()` em INSERT/UPDATE de `students`, `student_imports`, `wa_group_members`
- Backfill via RPC idempotente em todas as linhas existentes
- Criar VIEW canônica `v_students_unified` que mescla as 3 tabelas por phone normalizado + cohort_id
- Adicionar `UNIQUE(normalized_phone, cohort_id)` em `students`
- Documentar `students` como source-of-truth, `student_imports` como audit, `wa_group_members` como espelho WA
- ADR registrando decisão

**Acceptance criteria:**
1. 100% phones em `students.normalized_phone` no formato E.164 (+55DDD9XXXXXXXX)
2. VIEW `v_students_unified` retorna 1 linha por (phone E.164, cohort_id), mesclando colunas das 3 tabelas
3. Trigger normaliza em INSERT mesmo com input desformatado ("11 98765-4321", "+55 11...")
4. `find_duplicate_students()` RPC retorna 0 duplicates após backfill
5. Backfill é idempotente: rodar 2x não gera diff

**Riscos:** Migration em produção. Phone formatting precisa backwards-compat (manter coluna `phone` original 30 dias). Slack alert no apply.

**Estimativa:** L

---

### S.022.2 — Consolidar dispatch NPS em motor único (P0)

**Why:** 3 caminhos paralelos (dispatch-class-nps + dispatch-survey + send-whatsapp legacy) com schemas distintos (`nps_*`, `survey_*`, `notifications`). Tempo de manutenção 3x. Cliente não sabe qual dashboard consultar. (Ref: 01-architecture-map §4.1)

**O que:**
- **Recomendado:** `dispatch-survey` como canonical (mais novo, throttle 500ms, hybrid Meta+Evolution, schema generic)
- Mapear NPS class jobs → entries em `surveys` + `dispatch_history` (preservar `nps_class_dispatch_jobs` lock idempotency)
- Feature flag `nps_dispatch_engine` em `app_config`: `legacy` | `unified` (default `legacy` em prod)
- Deprecate `send-whatsapp` (notifications webhook): documentar como removed, manter 30 dias safety
- Migration de schema: adicionar `dispatch_type` enum em `dispatch_history`
- Smoke test em pre-prod antes de flip flag

**Acceptance criteria:**
1. `dispatch-survey` aceita tipo `nps_class` e gera entries equivalentes a `dispatch-class-nps`
2. Feature flag chave em prod com flip atômico via admin RPC
3. Rollback plan documentado (revert flag → legacy engine continua funcionando)
4. `send-whatsapp` marcado dormant com comentário em código + migration que desativa trigger notifications
5. Slack alert disparado no flip da flag

**Riscos:** Quebrar envios NPS em prod. **Plano de rollback obrigatório** (flag bidirecional). **Aprovação humana NON-NEGOTIABLE antes do flip** (per CLAUDE.md). Smoke test em turma sentinela primeiro.

**Estimativa:** L

---

### S.022.3 — Consolidar dashboards NPS (P0)

**Why:** 3 telas (`/admin/nps-results` + `/admin/nps-monitor` + `/admin/envios`) servem mesmo fluxo NPS com overlap. Admin não sabe qual abrir primeiro. PS RSVP aparece duplicado em `/admin/ps-rsvp` e aba dentro de `nps-results`. (Ref: 03-ux-audit §2.1, §2.3)

**O que:**
- **Target:** 2 telas max: `/admin/dispatch` (operacional: dispatcher + monitor + lembretes + master switch) e `/admin/insights` (análise: NPS results + PS RSVP analytics + exports)
- Plano de deprecation: redirect 301 de URLs antigas pras novas
- Manter dados/RPCs existentes; consolidação é apenas de UI/rotas
- Aba "Pré PS RSVP" sai de `nps-results` e fica em `/admin/insights` (mesma seção PS)
- Sidebar atualizada (remove duplicação "Comunicação" 2x)

**Acceptance criteria:**
1. `/admin/dispatch` carrega features de nps-monitor + lembretes-aulas + master switch
2. `/admin/insights` carrega features de nps-results + aba PS RSVP analytics
3. URLs antigas (`/admin/nps-results`, `/admin/nps-monitor`) retornam 301 pras novas
4. Sidebar consolidada (1 seção Comunicação, não 2)
5. Zero RPCs novos — apenas reorganização de UI

**Riscos:** Bookmarks de admin quebram → mitigado por 301. **Bloqueado por DS v1?** Não — esta story usa CSS atual (HTML+CSS custom), DS v1 vem depois.

**Estimativa:** M

---

### S.022.4 — RLS Hardening (P0 — segurança)

**Why:** Audit 2026-05-22 (@data-engineer notes) descobriu que **6 das 7 tabelas Tier 1 já têm RLS habilitado + POLICY, mas as policies são frouxas** (`USING (true)`, `auth.uid() IS NOT NULL`, inline role checks) — vazam dados pra qualquer authenticated. Restante (Tier 2 + Tier 3) tem gaps de cobertura mista. Não é "gap fix" puro de criar RLS do zero — é **hardening de policies permissivas existentes + ENABLE em tabelas faltantes**. (Ref: 02-db-audit §6 + 22.4.data-engineer-notes.md)

**O que:**
- **REPLACE** policies permissivas existentes em Tier 1 por `is_dashboard_admin()` only (Opção B confirmada — não existe link `students.id` ↔ `auth.users.id`, então self-read é inviável)
- **CREATE** RLS + POLICY em tabelas sem cobertura (ex: `staff`)
- Aplicar policy base por categoria:
  - **Tier 1 (sensível PII/financeiro)** — REPLACE policies frouxas por `is_dashboard_admin()` only + service_role bypass. Pattern com comment SQL `-- Future: adicionar OR <ownership_clause> when self-service NPS view ships` pra extensão futura.
  - **Tier 2 (operacional)** — `authenticated` read (UI admin) + `service_role` write (edge functions, cron)
  - **Tier 3 (referência/config)** — `authenticated` read + `is_dashboard_admin()` write
  - **Exceções justificadas** (service_role only, sem POLICY) — documentadas em ADR
- **REFACTOR pg_cron jobs** (Tarefa nova T11): jobs que escrevem em `app_config` precisam usar `service_role` connection (não admin user) pra permitir habilitar RLS em `app_config`. Após refactor, `app_config` entra no Tier 3 (não é mais exceção).
- Catálogo `docs/architecture/rls-policies.md` com decisão por tabela
- Exceções justificadas listadas em ADR-020 (não 019 — colision com ADR-019-cohort-sessions-explicit.md)

**Acceptance criteria:**
1. 100% tabelas críticas (Tier 1+2) com RLS habilitado + policy **restritiva** (não permissiva). REPLACE de policies `USING (true)`/`auth.uid() IS NOT NULL` quando aplicável.
2. Tier 3 com RLS habilitado + POLICY (incluindo `app_config` pós-refactor pg_cron)
3. Exceções (3 tabelas) documentadas em ADR-020 com justificativa SQL-side via `COMMENT ON TABLE`
4. Smoke test: user comum authenticated NÃO consegue ler tabelas Tier 1 (`class_nps_responses`, `student_attendance`, etc.)
5. Smoke test: admin (`is_dashboard_admin()=true`) lê tabelas Tier 1/2/3 normalmente
6. Smoke test: edge functions (service_role) continuam escrevendo sem regressão
7. Suite de smoke test cobre dashboards admin (`/admin/nps-results`, `/admin/dispatch`, etc.) — 0 falhas pós-apply
8. Migration idempotente (rerun seguro, usa `DROP POLICY IF EXISTS ... CREATE POLICY ...`)
9. Pre-flight check: função `is_dashboard_admin()` existe + retorna boolean esperado (CREATE OR REPLACE incluído na migration defensivo)
10. Pg_cron jobs refatorados não quebram após `ENABLE RLS app_config` — smoke validado em staging

**Riscos:** RLS muito restritiva pode quebrar queries existentes do admin. Pg_cron refactor pode quebrar jobs em prod se conexão service_role não estiver bem configurada. Mitigação: dry-run em staging via `pg_dump` + Docker local (não há staging DB dedicado).

**Estimativa:** L (~4-6 dias — scope ampliado pra incluir refactor pg_cron + smoke completo)

---

#### Anexo — Lista nominal de tabelas RLS Hardening (audit 2026-05-22 reconciliado)

> Methodology: audit @data-engineer (`22.4.data-engineer-notes.md` Q1) confirmou que cobertura RLS está **parcialmente presente mas frouxa**. Migration deve REPLACE policies permissivas (`USING (true)`, `auth.uid() IS NOT NULL`) por `is_dashboard_admin()` only. Lista re-classificada por **estado real em prod**, não por "tem ou não tem RLS".
>
> Discovery 02-db-audit §6 cita "39 tabelas sem RLS"; reconciliação atual conta **27 tabelas em escopo de hardening** + 4 exceções justificadas. Discrepância explicada por: (a) discovery contou tabelas dropadas + versões intermediárias, (b) audit @data-engineer descobriu 6/7 Tier 1 já com POLICY existente (replace, não create), (c) `app_config` migrado de exceção pra Tier 3 após refactor pg_cron (T11 da story).
>
> **AC #1 alvo:** as 27 tabelas listadas abaixo. Recontagem final via `SELECT relname FROM pg_class WHERE relrowsecurity = false` em produção, antes de fechar a story.

**A. Sem `ENABLE RLS` (precisa ENABLE + CREATE POLICY):**
- `staff` (Tier 1) — equipe interna com email/phone
- `notification_queue` (Tier 2) — fila legacy
- `schedule_overrides` (Tier 2) — overrides de cronograma
- `zoom_absence_alerts` (Tier 2) — alertas de ausência

**B. Com RLS habilitado + POLICY frouxa/permissiva (REPLACE POLICY obrigatório):**

*Tier 1 — REPLACE pra `is_dashboard_admin()` only:*
- `student_imports` — hoje inline `(raw_user_meta_data->>'role') = 'admin'` (padronizar)
- `wa_group_members` — hoje `auth.uid() IS NOT NULL` (vazamento real — qualquer authenticated lê phones)
- `class_nps_responses` — hoje `USING (true)` (vazamento — comments livres expostos)
- `student_attendance` — hoje authenticated read all (vazamento de presença)
- `response_metadata` — hoje inline check `IN ('admin','cs')` (manter `cs` ou expandir `is_dashboard_admin()` — flag pra @architect)
- `nps_class_links` — hoje `USING (true)` (vazamento — tokens magic-link expostos)

*Tier 2 — REPLACE permissivas onde aplicável (alguns já têm POLICY OK que preserva-se):*
- `audit_log` — preservar policies existentes, adicionar service_role explicit
- `class_reminder_batches` — anexo desatualizado, já tem POLICY (`read for auth` + `full for service`) — validar via `pg_policies` antes de touch
- `class_reminder_sends` — idem

**C. Com RLS habilitado + sem POLICY (CREATE POLICY novo):**

*Tier 2:*
- `class_cohort_access`
- `error_reports`
- `whatsapp_group_messages`
- `zoom_chat_messages`
- `zoom_import_queue`
- `automation_executions`
- `automation_rules`
- `automation_runs`
- `alert_history`
- `engagement_daily_ranking`

*Tier 3:*
- `integration_sources`
- `lesson_abstracts`
- `survey_templates` — já tem `cs_admin_read_templates`, padronizar

**D. Pendente refactor pg_cron (T11) antes de habilitar RLS:**
- `app_config` (Tier 3) — hoje `DISABLE ROW LEVEL SECURITY` explícito (migration `20260407202000_app_config.sql:15`). `pg_cron` (superuser) precisa ler. Refactor T11: jobs `process_zoom_import_queue()` e `zoom-absence-alert` usar `service_role` connection. **DEPOIS** habilitar RLS + POLICY Tier 3.

**Resumo aritmético (escopo RLS Hardening):**

| Tier | Count | Notas |
|------|-------|-------|
| Tier 1 | 7 | 6 REPLACE + 1 CREATE (`staff`) |
| Tier 2 | 16 | Mix de REPLACE/CREATE/preserve — validar `pg_policies` T1 |
| Tier 3 | 4 | `app_config` (pós-T11) + `integration_sources` + `lesson_abstracts` + `survey_templates` |
| **Total escopo** | **27** | — |
| Exceções | 4 | Documentadas em ADR-020, mantém sem POLICY |

**Exceções justificadas (mantém sem POLICY, service_role only — documentar em ADR-020):**
- `ac_dispatch_callbacks` — webhooks internos (já flagged em discovery §6)
- `oauth_states` — usado apenas pelo flow OAuth callback, nunca query por user
- `ac_purchase_events` — escrito só por webhook, lido por edge functions com service_role
- `ac_product_mappings` — escrito só por webhook, lido por edge functions com service_role

**Total nominal universe:** 27 (em escopo) + 4 (exceções) = 31 tabelas auditadas.

> **Importante:** count de 28 anterior considerava `oauth_states` no Tier 3 e como exceção simultaneamente (duplicação). Reconciliação 2026-05-22 fixa em 27 escopo + 4 exceções únicas.

---

### S.022.5 — Webhook purchase canonical (P1)

**Why:** 3 webhooks compra (ac-purchase + hotmart-purchase + generic-purchase) sem precedência clara. Se Hotmart event fire ambos hotmart-* e generic-*, qual ganha? AC sync diverge. (Ref: 01-architecture-map §4.3)

**O que:**
- **Recomendado:** `ac-purchase-webhook` como canonical (AC é source-of-truth contratual)
- `hotmart-purchase-webhook` → fallback dedicado (apenas eventos sem AC counterpart)
- `generic-purchase-webhook` → deprecated, redirect a logging-only nos próximos 30 dias
- Tabela `ac_purchase_events` ganha coluna `source` enum ('ac'|'hotmart'|'generic')
- Dedup por `(email, product_id, purchase_date)` tupla
- Documentação de precedência em `docs/architecture/purchase-flow.md`

**Acceptance criteria:**
1. Mesmo evento via 2 webhooks (AC + Hotmart) gera 1 linha em `ac_purchase_events`
2. Precedência documentada: AC > Hotmart > Generic
3. `generic-purchase-webhook` retorna 410 Gone após 30 dias safety window
4. ADR registrando decisão e rationale

**Riscos:** Perder eventos durante migration. Manter os 3 ativos lendo, mas só AC escrevendo durante safety window.

**Estimativa:** M

---

### S.022.6 — Cleanup dual-identity turma (P1)

**Why:** `classes.cohort_id` deprecated coexistindo com `class_cohorts` (M:N novo). Queries antigas vs novas inconsistentes. `get_weekly_attendance()` pode buscar via path errado. (Ref: 02-db-audit §3.3)

**O que:**
- Audit grep de todos os usos de `classes.cohort_id` em queries, RPCs, edge functions
- Migrar 100% para `class_cohorts` JOIN
- Backfill: garantir que cada `classes.cohort_id` tem entry equivalente em `class_cohorts`
- DEPRECATED comment em coluna por 1 sprint
- Drop coluna `classes.cohort_id` após verificação (migration final)

**Acceptance criteria:**
1. Zero grep matches de `classes.cohort_id` em código (exceto migration de drop)
2. `get_weekly_attendance()` e `get_present_students()` usam `class_cohorts`
3. Backfill verificável: `SELECT count(*) FROM classes WHERE cohort_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM class_cohorts WHERE class_id = classes.id)` = 0
4. Drop migration tem rollback documentado

**Riscos:** Drop de coluna em prod. Manter coluna 1 sprint em DEPRECATED antes do drop.

**Estimativa:** M

---

### S.022.9 — Delivery routing: provider column (P1)

**Why:** Discovery `01-architecture-map.md §4.4` identifica que 2 webhooks (`delivery-webhook` Evolution + `meta-delivery-webhook` Meta) logam status na mesma tabela (`notifications` — concept "delivery_status" do discovery) **sem coluna `provider`**. `dispatch-retry` fica ambiguo (não sabe se chama Evolution ou Meta para retry), causando risco de retries pelo provider errado ou falha silenciosa. <!-- REVIEW: discovery cita "delivery_status table" mas implementação atual stora em `notifications` — confirmar tabela alvo com @data-engineer antes de migration -->

**O que:**
- Adicionar coluna `provider TEXT NOT NULL DEFAULT 'evolution'` em `notifications` (tabela onde delivery columns vivem hoje, conforme `20260402200000_delivery_status.sql`). Se discovery indicar tabela separada `delivery_status` dedicada (verificar com @data-engineer), aplicar nessa.
- Constraint: `CHECK (provider IN ('evolution', 'meta'))`
- Backfill registros existentes: inferir provider via:
  - Se `evolution_message_ids` populated → `provider = 'evolution'`
  - Se ID externo Meta detectado (formato WAMID — começa com `wamid.`) → `provider = 'meta'`
  - Senão → log em Slack pra review humano (NÃO assumir default)
- Atualizar `dispatch-retry` edge function pra rotear baseado em coluna `provider` (substituir heurística atual)
- Adicionar NOT NULL constraint **após** backfill 100% (em migration separada — 2-step)
- Update **todos** dispatchers existentes (`dispatch-survey`, `dispatch-class-nps`, `dispatch-class-reminders`, `dispatch-ps-rsvp`, `admin-send-group-once`) pra gravar `provider` em todo INSERT em `notifications`

**Acceptance criteria:**
1. Coluna `provider` existe em `notifications` com CHECK constraint `IN ('evolution', 'meta')` e NOT NULL (após backfill)
2. 100% registros têm provider preenchido — validação SQL: `SELECT COUNT(*) FROM notifications WHERE provider IS NULL` retorna 0 antes do NOT NULL apply
3. `dispatch-retry` resolve qual API chamar (Evolution vs Meta) via leitura da coluna `provider`, sem heurística frágil baseada em ID format
4. Test case: forçar retry de 1 message com `provider='evolution'` + 1 com `provider='meta'` — ambos roteiam corretamente, audit em `dispatch_retry_audit`
5. Slack alert se backfill detectar registro sem provider inferível (formato ID ambíguo ou null)
6. Todos dispatchers gravam `provider` em INSERT (grep verificação em `supabase/functions/`)
7. Migration idempotente (rerun seguro): re-aplicar não duplica coluna nem altera valores existentes

**Riscos:** Backfill em produção pode mismatch provider de mensagens antigas (especialmente registros pré-Meta-integration onde só Evolution existia, default `'evolution'` provavelmente correto, mas pós-Meta híbrido precisa heurística). Mitigação: dry-run em staging + sample review humano (10 registros aleatórios) antes do NOT NULL apply. Slack alert obrigatório no apply.

**Estimativa:** M

**Why:** Migrations comentam `-- SELECT cron.schedule(...)` em jobs NPS. Pode ser intencional (NON-NEGOTIABLE: comunicação externa requer gate humano per `CLAUDE.md`) ou esquecido durante refactor. Decisão precisa ser explícita + auditada antes de qualquer re-ativação. Re-ativar silenciosamente = violação direta da regra "Comunicação Externa" e potencial disparo massivo não-autorizado pra alunos em produção.

**O que:**
1. Investigar histórico git/migrations: quando foi comentado, por quem, em qual contexto (commit message + PR)
2. Listar **TODOS** os crons NPS comentados/desativados (não só `20260517010400_dispatch_class_nps_cron.sql`) — incluir `pg_cron` jobs `cron.unschedule(...)`, jobs marcados `active=false`, e jobs com `-- SELECT cron.schedule` comentado em qualquer migration
3. Consultar logs de produção dos últimos 30 dias: NPS dispatches esperados vs efetivos (relatório anexo ao ADR)
4. Pra **CADA** cron identificado, classificar:
   - **Intencional (dormente)** — documentar em ADR + manter comentado + comment SQL explicando "Dormante por decisão DD-MM-YYYY ref ADR-XXX"
   - **Esquecido** — propor re-ativação **COM gate explícito** (UI button, não cron silencioso). Re-ativação NUNCA direta.
5. Criar ADR em `docs/architecture/decisions/ADR-XXX-nps-cron-status.md` com decisão completa, listagem + relatório de logs

**Acceptance criteria (todos NON-NEGOTIABLE, alinhados com CLAUDE.md "Comunicação Externa"):**
1. ADR criado listando **TODOS** crons NPS atuais (ativos + dormentes + comentados) com classificação por cron
2. Relatório anexo ao ADR: dispatches NPS esperados vs efetivos nos últimos 30 dias em produção
3. Para **qualquer** re-ativação proposta: UI button explícito de disparo em `/admin/dispatch` (não cron silencioso pra usuários externos)
4. Preview obrigatório da lista de destinatários + conteúdo do template antes do envio
5. Confirmação modal com count total + amostra de destinatários
6. Audit log em tabela dedicada (`nps_dispatch_audit` ou `audit_log` com `event_type='nps_manual_dispatch'`) gravando quem-quando-quantos
7. Modo dry-run disponível (envia 0 mensagens, mas log completo do que seria enviado)
8. Slack alert no startup + final de cada dispatch (per regra `slack-always-on-dispatchers` em MEMORY)
9. **PROIBIDO:** re-ativar cron silenciosamente sem aprovação humana explícita por mensagem do user neste epic. Se a decisão for reativar, o ADR registra a **autorização literal** (citação textual de mensagem do user) como pre-condition.
10. **Se opção "dormante intencional":** comment SQL explícito na migration original (`-- DORMANT BY DESIGN ref ADR-XXX, do NOT uncomment without re-running gate review`)

**Test cases:**
- Verdict "reativar com gate": rodar 1 dispatch de teste em turma sentinela (1 aluno) — verificar preview render + confirmation modal + audit log entry + Slack alert
- Verdict "dormante": grep `cron.schedule` nas migrations identificadas retorna apenas linhas comentadas

**Riscos:** Re-ativação acidental causa disparo massivo pra alunos em produção (1k+ ativos). Mitigação: gate humano + dry-run obrigatório + Slack alert + autorização literal no ADR. Violação CLAUDE.md "Comunicação Externa" se reativar template sem revisão de conteúdo atual.

**Estimativa:** S (investigação + ADR sem re-ativação) + M (se decisão = reativar com gate UI completo + audit log) = **M total**

---

### S.022.8 — Tabelas órfãs cleanup (P2)

**Why:** `pending_student_assignments`, `notification_queue`, `alert_history` aparentam abandonadas. Confunde diagnósticos. (Ref: 02-db-audit §5)

**O que:**
- Audit últimos 90 dias: queries de write/read em cada tabela (logs Supabase + grep código)
- Decisão por tabela:
  - **Keep:** justificar em comment SQL
  - **Deprecate:** rename `_deprecated_YYYYMMDD` + alert se write ocorrer
  - **Drop:** migration final (após 1 sprint deprecated)
- Atualizar `docs/architecture/schema.md` com mapa de tabelas ativas

**Acceptance criteria:**
1. Cada uma das 3 tabelas com decisão documentada
2. Se drop: backup snapshot antes
3. Lista de tabelas ativas atualizada

**Estimativa:** S

---

## Dependências

- **Track paralelo DS Foundations v1** (@ux-design-expert) — não bloqueia este Epic. Stories de frontend redesign (Epic futuro) dependem DS v1 pronto.
- **S.022.3 (consolidar dashboards)** usa CSS atual — NÃO espera DS v1.
- **S.022.1 (identidade aluno)** é foundation pra S.022.5 (purchase webhook) — sequenciar.
- **S.022.4 (RLS)** pode rodar paralelo com S.022.1.
- **S.022.2 (dispatch unificado)** depende de S.022.1 (phone normalizado pra matching correto).
- **S.022.9 (delivery provider column)** pode rodar paralelo com S.022.5 — independente de identidade, mas afeta `dispatch-retry` que toca todos dispatchers.

**Ordem recomendada:** S.022.4 + S.022.1 em paralelo → S.022.2 + S.022.6 em paralelo → S.022.5 + S.022.9 em paralelo → S.022.3 → S.022.7 + S.022.8.

## Risco maior

**Qualquer migration em produção é high-risk.** Sistema EM PRODUÇÃO com envios diários. Toda story de migration precisa:
- **Dry-run** em snapshot/staging antes
- **Idempotência** verificada (rerun seguro)
- **Rollback** documentado em comment no header da migration
- **Slack alert** no `db:migrate` apply (start + finish)
- **Smoke test** pós-apply em 1 cohort sentinela antes de full rollout
- **Feature flag** pra qualquer mudança de comportamento de dispatch (S.022.2 obrigatório)
- **Aprovação humana** (per CLAUDE.md NON-NEGOTIABLE) antes de qualquer flip de flag que envie mensagem real

## Métricas de sucesso

- **0** paths duplicados pra NPS dispatch (S.022.2 done)
- **100%** tabelas críticas Tier 1+2+3 com RLS Hardening (S.022.4 done) — 27 tabelas em escopo + 4 exceções justificadas (incl. `app_config` pós-refactor pg_cron)
- **100%** registros com phone E.164 normalizado em `students`, `student_imports`, `wa_group_members` (S.022.1 done)
- **Admin consegue resposta NPS em 1 dashboard só** (`/admin/insights`) — S.022.3 done
- **0** grep matches de `classes.cohort_id` em código (S.022.6 done)
- **1 webhook canonical** pra purchase (S.022.5 done)
- **100% registros `notifications` com `provider` preenchido** + `dispatch-retry` roteando via coluna (S.022.9 done)
- **Tempo médio de manutenção/feature dispatch** cai 50% (proxy: linhas de código duplicadas em edge functions)

---

## Change Log

- **2026-05-22** — Epic criado por @pm (Morgan) baseado em discovery 01/02/03-2026-05-22.
- **2026-05-22** — PO validation @po (Pax) verdict GO 8/10 com 3 fixes obrigatórios. Ver `EPIC-022-validation.md`.
- **2026-05-22** — Fixes PO aplicados: S.022.9 adicionada (delivery provider column, P1) + S.022.7 fortalecida (gate humano NON-NEGOTIABLE alinhado com CLAUDE.md "Comunicação Externa", 10 AC + 2 test cases) + S.022.4 lista nominal anexada (28 tabelas tier-classified + 4 exceções justificadas, methodology documentada). Escopo IN + Dependências + Métricas atualizados.
- **2026-05-22** — Reconciliação S.022.4 (post-NO-GO + data-engineer notes): reframed "RLS Gap Fix" → "RLS Hardening" (6/7 Tier 1 já tem RLS mas POLICY frouxa — REPLACE, não CREATE-only). Anexo re-classificado por estado real (A sem ENABLE / B REPLACE / C CREATE / D refactor). `app_config` movido de exceção pra Tier 3 + nova tarefa T11 refactor pg_cron. Count reconciliado: 27 escopo + 4 exceções (era 28 com `oauth_states` duplicado). ADR-019 → ADR-020 (colision). Pattern Tier 1 confirmado: `is_dashboard_admin()` only (Opção B — não existe link `students.id` ↔ `auth.users.id`).
