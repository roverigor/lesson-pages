# EPIC-003 — Segurança e DB Hardening

## Metadata

```yaml
epic_id: EPIC-003
title: Segurança e DB Hardening
status: InProgress
priority: Critical
depends_on: EPIC-002 (Done)
estimated_effort: ~41h
estimated_cost: R$ 6.150
created_by: "@pm (Morgan)"
created_at: 06/04/2026
related_report: docs/reports/TECHNICAL-DEBT-REPORT.md
debt_ids_resolved:
  - SYS-C2 (credenciais Zoom hardcoded)
  - SYS-C3 (credenciais Evolution API hardcoded)
  - SYS-C5 (CORS Allow-Origin: * em Edge Functions)
  - DB-C1 (tabela classes sem DDL documentado)
  - DB-M1 (sem migrations versionadas)
  - DB-R2 (classes sem RLS documentada)
  - DB-NEW-C1 (verificar migration delivery_status em produção)
  - DB-NEW-C2 (confirmar CHECK constraint de status)
  - SYS-H2 (zero testes)
  - SYS-H3 (sem linting)
  - UX-NEW-A1 (sem feedback visual para ações críticas)
```

---

## Epic Goal

Eliminar os 2 débitos críticos de segurança (credenciais hardcoded) e os principais débitos altos de banco de dados e qualidade — garantindo que o sistema possa crescer com segurança, rastreabilidade e manutenibilidade.

---

## Problem

A plataforma lesson-pages opera com credenciais de acesso ao Zoom e ao WhatsApp escritas diretamente no código-fonte. Qualquer colaborador com acesso ao repositório pode visualizá-las. Uma exposição acidental pode comprometer as integrações que sustentam as aulas da Academia Lendária — videochamadas e comunicação com alunos.

Paralelamente, o banco de dados cresceu sem documentação formal nem versionamento de schemas. Não há como saber com certeza quais mudanças foram aplicadas em produção, o que torna cada deploy um exercício de confiança. A ausência de testes amplifica o problema: uma regressão pode chegar aos alunos sem detecção.

---

## Solution Overview

As credenciais serão movidas para variáveis de ambiente seguras gerenciadas pelo Supabase (Secrets), sem alterar o comportamento atual das funções. O CORS será restrito a domínios conhecidos. O schema da tabela `classes` será documentado formalmente com DDL, RLS e índices, e convertido em migration versionada pelo Supabase CLI. Todos os scripts SQL avulsos serão migrados para o sistema de migrations oficial. Smoke tests cobrirão os 3 fluxos críticos do sistema. Linting e feedback visual serão adicionados para fechar os gaps de qualidade mais urgentes.

---

## Stories

### Story 3.1 — Mover Credenciais para Variáveis de Ambiente ✅ DONE

**Executor:** @dev (Dex)
**Effort:** ~3h
**Debt IDs:** SYS-C2, SYS-C3
**Status:** Done — verificado em 06/04/2026

**Resultado:** Todas as Edge Functions já usam `Deno.env.get()`. Todos os Secrets estão configurados no Supabase (13 secrets verificados via `supabase secrets list`). Nenhuma credencial hardcoded encontrada no código.

---

### Story 3.2 — Restringir CORS nas Edge Functions ✅ DONE

**Executor:** @dev (Dex)
**Effort:** ~1h
**Debt ID:** SYS-C5
**Status:** Done — verificado em 06/04/2026

**Resultado:** CORS restrito a `https://lesson-pages.vercel.app` em send-whatsapp, zoom-oauth e zoom-attendance. delivery-webhook usa token auth no query param (sem necessidade de CORS frontend).

> ⚠️ **Pendente:** adicionar `https://calendario.igorrover.com.br` como origem permitida — o domínio VPS não está na lista atual. Criar issue minor.

---

### Story 3.3 — Schema Completo e RLS da Tabela `classes` ✅ DONE

**Executor:** @data-engineer (Dara)
**Effort:** ~4h
**Debt IDs:** DB-C1, DB-R2
**Status:** Done — verificado em 06/04/2026

**Resultado:** Migration `20260406120000_classes_schema_rls.sql` criada e aplicada em produção. Formaliza colunas `type/start_date/end_date` em `classes`, `valid_from/valid_until` em `class_mentors`, UNIQUE constraint em `class_cohort_access`, RLS completa com anon read para calendário público em classes/class_mentors/mentors, e RLS admin-only para class_cohort_access. Schema doc salvo em `supabase/docs/classes-schema.sql`.

**Acceptance Criteria:**
- [x] DDL completo da tabela `classes` documentado (todos os campos, tipos, constraints, defaults)
- [x] Migration Supabase CLI criada em `supabase/migrations/` com o schema formal
- [x] RLS policies implementadas para `classes`: leitura pública para calendário, escrita restrita a admin
- [x] Índices criados para os campos de consulta frequente (`start_date`, `end_date`, `type`, `valid_from`, ciclo ativo)
- [x] Migration aplicada em produção via `supabase db push`
- [x] Schema file salvo em `supabase/docs/classes-schema.sql`

---

### Story 3.4 — Migrar Scripts SQL para Supabase CLI Migrations ✅ DONE

**Executor:** @data-engineer (Dara)
**Effort:** ~4h
**Debt IDs:** DB-M1, DB-NEW-C1, DB-NEW-C2
**Priority:** High

**Contexto:**
O banco de dados foi construído com scripts SQL avulsos em `db/`. Não há rastreabilidade de quais mudanças foram aplicadas em produção. O `supabase migration list` não reflete o estado real do banco.

**Progresso:**
- [x] Migration `20260402200000_delivery_status.sql` aplicada em produção via `supabase db push` (06/04/2026)
- [x] CHECK constraint de `notifications.status` atualizado para incluir `delivered` e `read`
- [x] Bug da migration fixado (`DROP CONSTRAINT IF EXISTS` por nome em vez de DO block com pattern matching)
- [x] `supabase migration list` mostra todas as 7 migrations com timestamps local e remote sincronizados

**Acceptance Criteria restantes:**
- [x] `supabase/config.toml` criado com as configurações corretas do projeto
- [x] Scripts em `db/*.sql` convertidos para migrations numeradas (ou documentados como baseline)
- [x] Processo de aplicação de nova migration documentado em `supabase/docs/migrations-guide.md`

---

### Story 3.5 — Implementar Smoke Tests para Fluxos Críticos ✅ DONE

**Executor:** @dev (Dex) + @qa (Quinn)
**Effort:** ~8h
**Debt IDs:** SYS-H2, SYS-H3
**Status:** Done — verificado em 06/04/2026

**Resultado:** 12 smoke tests criados com Node.js built-in test runner (zero dependências de runtime). 5 suites cobrindo calendário, DB anon, send-whatsapp, zoom-attendance, admin panel. ESLint configurado com flat config. GitHub Actions atualizado: job `test` (lint + smoke) precede job `deploy`. Todos os 12 testes passaram localmente e CI está configurado para bloquear deploy em caso de falha.

**Acceptance Criteria:**
- [x] Smoke test cobrindo calendário público: página carrega, HTML válido, Supabase config presente
- [x] Smoke test cobrindo envio WhatsApp: Edge Function responde (não 500), JSON válido
- [x] Smoke test cobrindo login admin: painel carrega (200), Auth endpoint responde
- [x] Smoke test cobrindo geração de link Zoom: zoom-attendance reachable (não 500)
- [x] GitHub Actions executa os testes automaticamente no push para `main`
- [x] Build falha se qualquer smoke test falhar (job `deploy` tem `needs: test`)
- [x] Linting (ESLint) configurado com flat config, passando em `js/`
- [x] `README.md` atualizado com instruções de como rodar os testes localmente

---

### Story 3.6 — Feedback Visual para Ações Críticas no Admin ✅ DONE

**Executor:** @dev (Dex)
**Effort:** ~3h
**Debt ID:** UX-NEW-A1
**Status:** Done — verificado em 06/04/2026

**Resultado:** Feedback visual implementado em todas as ações críticas do admin. `saveClassV2()` ganhou loading state (botão desabilitado + "Salvando...") com restauração em todos os paths de retorno. `saveAll()` mostra contagem de registros salvos. `sendNotification()` exibe nome do cohort no toast e estados intermediários (processing, delivered). Botão "📋 Copiar" adicionado ao campo Zoom Link — aparece apenas quando há link, copia para clipboard com feedback "✓ Copiado!".

**Acceptance Criteria:**
- [x] Toast de sucesso exibido após envio de WhatsApp para turma (com nome do cohort)
- [x] Toast de erro exibido com mensagem clara quando envio falha
- [x] Estado de loading (botão desabilitado + "Salvando...") durante envio — sem double-submit
- [x] Feedback visual após marcação de presença em lote (quantos registros salvos)
- [x] Feedback visual após geração de link Zoom (link copiável com botão "📋 Copiar" + feedback "✓ Copiado!")
- [x] Feedback consistente com o padrão visual existente (sem nova biblioteca de componentes)

---

## Success Criteria

- [ ] Zero credenciais hardcoded em qualquer arquivo do repositório
- [ ] CORS restrito — nenhuma Edge Function aceita origem `*`
- [ ] Schema completo da tabela `classes` documentado e versionado como migration
- [ ] `supabase migration list` reflete o estado real do banco de produção
- [ ] 100% dos fluxos críticos com smoke test cobrindo o happy path
- [ ] CI bloqueia merge se testes falharem
- [ ] Admin fornece feedback visual claro para todas as ações com side effects

---

## Effort Summary

| Story | Executor | Horas |
|-------|----------|-------|
| 3.1 — Credenciais para Env Vars | @dev | ~3h |
| 3.2 — Restringir CORS | @dev | ~1h |
| 3.3 — Schema e RLS de `classes` | @data-engineer | ~4h |
| 3.4 — Migrations Supabase CLI | @data-engineer | ~4h |
| 3.5 — Smoke Tests + Linting | @dev + @qa | ~8h |
| 3.6 — Feedback Visual Admin | @dev | ~3h |
| **TOTAL** | | **~23h** |

> Nota: o esforço total do EPIC-003 é ~23h (stories 3.1–3.6). O custo de R$ 6.150 no metadata inclui margem para contexto, revisão e deploys intermediários.

---

## Recommended Execution Order

```
Story 3.1 (credenciais) → Story 3.2 (CORS) → Story 3.4 (migrations CLI)
                                                      ↓
                                          Story 3.3 (schema classes)
                                                      ↓
                                      Story 3.5 (testes) → Story 3.6 (UX)
```

Stories 3.1 e 3.2 devem ser executadas primeiro pois eliminam o risco imediato. Story 3.4 deve preceder 3.3 para que o schema de `classes` seja criado já no sistema de migrations correto.

---

*EPIC-003 criado por @pm (Morgan) | AIOX Framework v2.0 | 06/04/2026*
