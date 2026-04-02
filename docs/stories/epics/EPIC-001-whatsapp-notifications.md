# EPIC-001: Sistema de Notificações WhatsApp — Brownfield Enhancement

**Status:** Ready for Story Creation
**Criado por:** Morgan (@pm)
**Data:** 2026-04-02
**Projeto:** lesson-pages — Academia Lendária
**Arquitetura de referência:** `docs/architecture-notifications.md`

---

## Epic Goal

Implementar o sistema de notificações WhatsApp event-driven já arquitetado, permitindo que o admin envie avisos automáticos para grupos de alunos e mentores individuais diretamente do painel administrativo — eliminando comunicação manual via WhatsApp e garantindo auditoria completa de todos os envios.

---

## Existing System Context

- **Stack:** HTML/CSS/JS vanilla + Supabase (PostgreSQL + Edge Functions + Auth) + VPS Contabo com Evolution API
- **Auth:** Supabase Auth com roles via JWT metadata (`admin`, `mentor`, `student`)
- **Frontend admin:** `calendario/admin.html` — painel de controle de presença
- **Integração WhatsApp:** Evolution API em `http://194.163.179.68:8084`, instância `igor`
- **Banco existente:** tabelas `classes`, `cohorts`, `students`, `attendance` com RLS ativas
- **Arquitetura desenhada:** 5 ADRs documentados em `docs/architecture-notifications.md`

**O que já existe e pode ser reaproveitado:**
- Supabase client (`js/config.js`) com anon key configurado
- Padrão de autenticação e RLS já estabelecido — novas tabelas seguem o mesmo padrão
- `supabase/functions/send-whatsapp/index.ts` — skeleton da Edge Function existe (aguarda implementação)
- `db/notifications-schema.sql` — schema SQL já escrito e pronto para execução

---

## Enhancement Details

**O que está sendo adicionado:**

1. **Infraestrutura de dados** — 4 novas tabelas: `mentors`, `class_cohorts`, `class_mentors`, `notifications` com RLS policies apropriadas
2. **Edge Function funcional** — `send-whatsapp` com template engine, state machine (pending → processing → sent/partial/failed), integração Evolution API e retry logic
3. **Database Webhook** — trigger automático no INSERT da tabela `notifications`
4. **UI no painel admin** — seção "Notificações" no `calendario/admin.html` com modal de envio e histórico de status

**Como integra ao sistema existente:**
- Novas tabelas seguem padrão RLS existente (admin write, authenticated read)
- UI integra ao `calendario/admin.html` sem quebrar fluxo de presença atual
- Edge Function usa `service_role` key via Supabase Secrets (nunca exposta no frontend)
- Compatibilidade total com tabelas `classes` e `cohorts` existentes via FKs

**Critérios de sucesso:**
- Admin insere notificação no painel → grupo WhatsApp recebe mensagem em < 10 segundos
- Mentores individuais recebem mensagem no WhatsApp após inserção
- Status de cada notificação visível no painel (pending/sent/failed)
- Falhas são registradas com mensagem de erro auditável
- Nenhuma regressão no fluxo de presença existente

---

## Stories

### Story 1.1 — Migração de Schema e Dados Base
**Executor:** `@data-engineer` | **Quality Gate:** `@dev`
**Quality Gate Tools:** `[schema_validation, migration_review, rls_test, fk_integrity]`

**Descrição:** Executar o schema SQL para criar as 4 novas tabelas (`mentors`, `class_cohorts`, `class_mentors`, `notifications`) com RLS policies, índices e seeds iniciais de dados. Popular `class_cohorts` e `class_mentors` com dados existentes do sistema.

**Acceptance Criteria:**
- [ ] Tabela `mentors` criada com UNIQUE constraint em `phone`
- [ ] Tabela `class_cohorts` (bridge N:N) criada com FK para `classes` e `cohorts`
- [ ] Tabela `class_mentors` (bridge N:N) criada com FK para `classes` e `mentors`
- [ ] Tabela `notifications` criada com todos os campos do schema (`docs/architecture-notifications.md §3.1`)
- [ ] RLS policies aplicadas: `notifications` SELECT restrito a admin; `mentors/class_cohorts/class_mentors` readable por authenticated
- [ ] Dados de mentores existentes populados em `mentors` (com phones verificados)
- [ ] Mapeamento `class_cohorts` e `class_mentors` populado a partir de dados existentes
- [ ] Nenhuma tabela existente (`classes`, `cohorts`, `attendance`, `students`) alterada

**Quality Gates:**
- Pre-Commit: Validação de schema, service filter verification, RLS policies
- Pre-PR: SQL review, migration safety (sem DROP de tabelas existentes), FK integrity

**Risk:** Baixo — apenas adição de tabelas novas, sem alteração de dados existentes
**Rollback:** DROP das 4 novas tabelas (zero impacto no sistema existente)

---

### Story 1.2 — Edge Function send-whatsapp
**Executor:** `@dev` | **Quality Gate:** `@architect`
**Quality Gate Tools:** `[code_review, integration_test, error_handling_validation, security_scan]`

**Descrição:** Implementar a Edge Function `send-whatsapp` completa — conectando ao Supabase via service role, buscando dados relacionados (class, cohorts, mentors), renderizando templates `{{variavel}}`, enviando via Evolution API e atualizando o state machine da notificação.

**Acceptance Criteria:**
- [ ] Edge Function lê payload do Database Webhook e extrai `record` (notification)
- [ ] Guard: só processa `status === 'pending'` — rejeita silenciosamente outros status
- [ ] UPDATE atômico para `status = 'processing'` antes de qualquer envio (evita duplicatas)
- [ ] Template engine substitui todas as variáveis listadas em `docs/architecture-notifications.md §4.5`
- [ ] Envio para grupo via Evolution API: `POST /message/sendText/{instance}` com JID
- [ ] Envio individual para cada mentor via Evolution API com phone
- [ ] UPDATE final com status `sent`, `partial` ou `failed` + `evolution_response` JSONB
- [ ] Retry logic: se `retry_count < max_retries`, atualiza para `failed` sem crash
- [ ] Secrets (`EVOLUTION_API_KEY`, `EVOLUTION_API_URL`, `EVOLUTION_INSTANCE`) lidos de Supabase Secrets — nunca hardcoded
- [ ] Logs estruturados para debug (sem expor dados sensíveis)

**Quality Gates:**
- Pre-Commit: Security scan (sem secrets no código), error handling coverage
- Pre-PR: Integration test com webhook simulado, backward compatibility

**Risk:** Médio — código novo com integração externa; falhas são isoladas na Edge Function
**Rollback:** Desabilitar o Database Webhook (a tabela `notifications` permanece intacta)

---

### Story 1.3 — Database Webhook + UI de Notificações no Painel Admin
**Executor:** `@dev` | **Quality Gate:** `@architect`
**Quality Gate Tools:** `[ui_integration_test, rls_validation, regression_test, ux_review]`

**Descrição:** Configurar o Database Webhook no Supabase para acionar a Edge Function no INSERT de `notifications`, e implementar a seção "Notificações" no painel admin (`calendario/admin.html`) com modal de envio e histórico de status.

**Acceptance Criteria:**
- [ ] Database Webhook `notify-whatsapp-on-pending` configurado: tabela `notifications`, evento INSERT, target Edge Function `send-whatsapp`
- [ ] Seção "Notificações" adicionada ao `calendario/admin.html` (visível apenas para role `admin`)
- [ ] Botão "Enviar Aviso" abre modal com:
  - [ ] Seleção de tipo: `class_reminder`, `group_announcement`, `custom`
  - [ ] Seleção de classe/cohort (dropdown populado via Supabase)
  - [ ] Template pré-preenchido baseado no tipo selecionado
  - [ ] Campo de mensagem livre (para tipo `custom`)
  - [ ] Preview da mensagem renderizada
  - [ ] Botão de confirmação que faz INSERT em `notifications`
- [ ] Histórico de notificações: lista com status (pending/processing/sent/partial/failed) e timestamp
- [ ] Indicadores visuais de status (cor verde=sent, amarelo=pending, vermelho=failed)
- [ ] Fluxo de presença existente inalterado (nenhuma regressão no calendário)
- [ ] RLS válida: mentor não consegue ver tabela `notifications`

**Quality Gates:**
- Pre-Commit: RLS validation, UI regression test no fluxo de presença
- Pre-PR: End-to-end test (INSERT → webhook → Evolution API simulada → status update)
- Pre-Deployment: Teste real com grupo de teste e número do admin

**Risk:** Médio — UI integra a página existente; webhook depende de Edge Function (Story 1.2) estar funcional
**Rollback:** Remover a seção de Notificações do HTML + desabilitar o webhook

---

## Dependency Order

```
Story 1.1 (Schema) → Story 1.2 (Edge Function) → Story 1.3 (Webhook + UI)
```

Story 1.2 pode ser desenvolvida em paralelo com 1.1, mas só pode ser testada após 1.1 estar em produção. Story 1.3 depende de 1.1 e 1.2 completas.

---

## Compatibility Requirements

- [x] Tabelas existentes (`classes`, `cohorts`, `attendance`, `students`) inalteradas
- [x] APIs existentes inalteradas (sem novos endpoints — usa Supabase direto)
- [x] UI de presença (`calendario/admin.html`) sem regressão
- [x] Padrão de autenticação Supabase mantido (mesmo `js/config.js`)
- [x] Deploy via GitHub Actions mantido (sem alteração no pipeline)

---

## Risk Mitigation

| Risco | Severidade | Mitigação |
|-------|-----------|-----------|
| Evolution API offline | Alta | retry_count / max_retries; status 'failed' com erro detalhado |
| Timeout Edge Function (>60s) | Média | Marca 'processing' antes; batch se muitos mentores |
| JID de grupo incorreto | Baixa | Validação no INSERT + log em `evolution_response` |
| Regressão no fluxo de presença | Média | UI isolada em seção separada; testes explícitos de regressão |
| Mensagem duplicada (webhook retry) | Média | Guard atômico: só processa `status='pending'` |

**Rollback geral:** Desabilitar o Database Webhook no Supabase Dashboard — o sistema de presença continua operando normalmente sem qualquer alteração.

---

## Quality Assurance Strategy

- **CodeRabbit:** Todas as stories incluem review pre-commit (CRITICAL/HIGH auto-fix)
- **Story 1.1:** @data-engineer valida schema, RLS, FKs — @dev revisa
- **Story 1.2:** @architect valida integração Evolution API, state machine, segurança de secrets
- **Story 1.3:** Regression test explícito no fluxo de presença antes de merge

---

## Definition of Done

- [ ] Story 1.1: Todas as 4 tabelas criadas, RLS ativas, dados populados — verificado via Supabase Dashboard
- [ ] Story 1.2: Edge Function deployada, testada com INSERT manual, status atualizado corretamente
- [ ] Story 1.3: Webhook configurado, UI funcional, teste real de envio para grupo + número do admin
- [ ] Nenhuma regressão no fluxo de presença existente
- [ ] Documentação atualizada: `docs/architecture-notifications.md` atualizado com status "Implementado"
- [ ] Histórico de auditoria funcionando: todas as notificações registradas com `created_by`, `sent_at`, `evolution_response`

---

## Handoff para @sm

> "Por favor, crie as stories detalhadas para este epic brownfield. Considerações importantes:
>
> - Sistema existente: HTML/CSS/JS vanilla + Supabase + Evolution API (WhatsApp) no VPS Contabo
> - A arquitetura completa está documentada em `docs/architecture-notifications.md` — é a fonte de verdade
> - O schema SQL já existe em `db/notifications-schema.sql` — Story 1.1 precisa executá-lo e validar
> - A Edge Function skeleton existe em `supabase/functions/send-whatsapp/index.ts` — Story 1.2 implementa
> - Ordem de dependências: 1.1 → 1.2 → 1.3 (1.2 pode ser desenvolvida em paralelo com 1.1)
> - Critical: Story 1.3 inclui teste real de envio (não apenas simulado) antes de Done
> - Cada story deve verificar que o fluxo de presença existente continua funcionando
>
> O epic entrega o sistema de notificações WhatsApp completo e auditável para a Academia Lendária."

---

## Metadata

```yaml
epic_id: EPIC-001
version: 1.0.0
created_by: Morgan (@pm)
created_at: 2026-04-02
status: Ready for Story Creation
next_action: "@sm *draft EPIC-001"
architecture_ref: docs/architecture-notifications.md
stories_count: 3
estimated_complexity: STANDARD (9-15 score)
risk_level: LOW-MEDIUM
```
