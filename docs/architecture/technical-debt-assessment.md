# Technical Debt Assessment — lesson-pages

> **Fase:** Brownfield Discovery — Fase 8 (Documento Final)
> **Gerado por:** @architect (Aria) — consolidação de system-architecture.md + db-specialist-review.md + ux-specialist-review.md + qa-review.md
> **Data:** 2026-04-06
> **Projeto:** lesson-pages (Plataforma Educacional AIOS Avançado — Cohort 2026)
> **QA Gate:** APROVADO COM RESSALVAS CRÍTICAS (ver Seção 7)

---

## Resumo Executivo

O lesson-pages é uma plataforma educacional funcional construída em Vanilla HTML/CSS/JS com Supabase como backend. O sistema entrega valor real em produção: notificações WhatsApp, controle de presença via Zoom, agendamento automático via pg_cron e gestão de turmas operam hoje.

O crescimento foi orgânico e acelerado (2 epics em 4 dias), gerando uma camada de débito técnico que, se não endereçada, escalará o custo de cada mudança futura. O assessment identifica **2 débitos críticos** (ambos de segurança — credenciais expostas), **8 débitos altos**, **14 débitos médios** e **4 débitos baixos**, totalizando **28 itens catalogados** com estimativa de **90 horas de resolução** a R$ 13.500.

**Reclassificação aplicada (2026-04-06):** Os débitos DB-NEW-C1 e DB-NEW-C2 foram reclassificados de CRÍTICO para MÉDIO após confirmação de que a migration `20260402200000_delivery_status.sql` existe no repositório com as colunas `evolution_message_ids`, `delivered_at` e o CHECK constraint atualizado. O débito real é confirmar que `supabase db push` foi executado em produção.

**Condição pré-Fase 1 (QA Gate):** Antes de iniciar qualquer migration, executar `supabase db diff` em produção e verificar empiricamente se o delivery-webhook está operando (logs de Edge Function dos últimos 7 dias).

---

## 1. Inventário Consolidado de Débitos

### 1.1 CRÍTICO — Risco de segurança imediato

| ID | Área | Débito | Horas | Prioridade |
|---|---|---|---|---|
| **SYS-C2** | Segurança | Credenciais Zoom hardcoded em `zoom-oauth` e `zoom-attendance` | 2h | P0 |
| **SYS-C3** | Segurança | `EVOLUTION_API_KEY` hardcoded em `send-whatsapp` e `delivery-webhook` | 1h | P0 |

**Total crítico: 2 débitos — 3 horas — R$ 450**

---

### 1.2 ALTO — Débito estrutural que impede evolução

| ID | Área | Débito | Horas | Prioridade |
|---|---|---|---|---|
| **SYS-C5** | Segurança | CORS `*` em Edge Functions — qualquer origem pode disparar envios WhatsApp | 1h + mapeamento | P1 |
| **SYS-C4** | Sistema | `admin.html` inicializa Supabase com anon key inline, não usa `js/config.js` | 1h | P1 |
| **DB-C1** | Banco | `classes` sem schema file — tabela central sem DDL, RLS ou índices documentados | 3h | P1 |
| **DB-M1** | Banco | Sem migrations versionadas — arquivos SQL avulsos, impossível reproduzir ambiente ou rollback | 4h | P1 |
| **DB-R2** | Banco | `classes` sem RLS documentada — tabela central potencialmente exposta | 1h | P1 |
| **DB-NEW-A2** | Banco | Ausência de auditoria de alterações manuais — necessário `supabase db diff` antes de qualquer migration | 1h | P1 |
| **UX-C1** | Frontend | `admin.html` com 2844 linhas — monolito JS/CSS inline — cada bugfix leva 2-3x mais | 20h | P1 |
| **UX-NEW-A1** | Frontend | Sem feedback visual para ações críticas (envio WhatsApp, marcação de presença) | 3h | P1 |

**Total alto: 8 débitos — 34 horas — R$ 5.100**

---

### 1.3 MÉDIO — Qualidade e manutenibilidade

| ID | Área | Débito | Horas | Prioridade |
|---|---|---|---|---|
| **DB-NEW-C1** | Banco | Confirmar aplicação da migration `delivery_status` em produção — `evolution_message_ids` e `delivered_at` precisam estar no schema de produção | 0.5h | P2 |
| **DB-NEW-C2** | Banco | Confirmar que CHECK constraint de `notifications.status` inclui `delivered` e `read` em produção — migration existe mas pode não ter sido aplicada | 0.5h | P2 |
| **DB-NEW-M1** | Banco | `notification_schedules` sem schema file documentado | 1h | P2 |
| **DB-S1** | Banco | `attendance.lesson_date` como TEXT em vez de DATE — impede queries de range e validação | 2h | P2 |
| **DB-S2** | Banco | `attendance.teacher_name` desnormalizado — risco de inconsistência; impede joins eficientes | 4h | P2 |
| **DB-S3** | Banco | `classes.professor`/`host` como TEXT legados — `class_mentors` já resolve via FK | incl. DB-C1 | P3 |
| **DB-R1** | Banco | RLS sem roles intermediários — mentores não podem gerenciar apenas suas próprias turmas | 3h | P3 |
| **DB-R3** | Banco | `zoom_tokens` acessível a qualquer admin — deveria ser scoped por mentor | 2h | P3 |
| **DB-NEW-A1** | Banco | Ausência de constraints `NOT NULL` e `DEFAULT` explícitos nas colunas novas de notificações | 0.5h | P3 |
| **SYS-M1** | Sistema | Supabase JS versão `@2` sem pin de minor/patch | 0.5h | P2 |
| **SYS-M2** | Sistema | Sem ambiente de staging — deploy vai direto para produção | 2h | P3 |
| **SYS-M3** | Sistema | Páginas duplicadas (`ps-10-02-2026/` e `ps-pronto-socorro/`; `aios-install/` e `aiox-install/`) | 1h | P3 |
| **UX-H1** | Frontend | Zero consistência visual — cada página tem CSS independente; design tokens não aplicados | 16h | P2 |
| **UX-H2** | Frontend | `abstracts/index.html` ~4800 linhas hardcoded — atualização de conteúdo exige editar HTML | 8h | P2 |
| **UX-H3** | Frontend | Sem estados de loading padronizados — usuário não sabe se ação foi processada | 4h | P2 |
| **UX-H4** | Frontend | Sem error handling visual padronizado — erros silenciosos ou apenas no console | incl. UX-H3 | P2 |
| **UX-M2** | Frontend | Responsividade não garantida — mentores acessam via mobile | 4h | P3 |
| **UX-M3** | Frontend | Páginas duplicadas no frontend (`aios-install` vs `aiox-install`) | 1h | P3 |
| **UX-NEW-A2** | Frontend | Sem confirmação antes de ações destrutivas no admin | 2h | P3 |

**Total médio: 19 débitos — 52 horas — R$ 7.800** *(após ajuste dos débitos DB-NEW-C1 e DB-NEW-C2 de crítico para médio)*

---

### 1.4 BAIXO — Manutenção e otimização

| ID | Área | Débito | Horas | Prioridade |
|---|---|---|---|---|
| **DB-NEW-L1** | Banco | `notification_schedules.last_triggered_at` sem índice — pg_cron consulta essa coluna | 0.5h | P4 |
| **DB-I1** | Banco | Sem índice em `notifications.processed_at` | 0.5h | P4 |
| **UX-M4** | Frontend | Backup files no repo (`*.backup.*`) | 0.5h | P4 |
| **SYS-H3** | Sistema | Sem linting nem formatação automatizada (ESLint, Prettier) | 2h | P4 |

**Total baixo: 4 débitos — 3.5 horas — R$ 525**

---

## 2. Resumo por Área

| Área | Críticos | Altos | Médios | Baixos | Total Horas |
|---|---|---|---|---|---|
| Segurança / Sistema | 2 | 2 | 2 | 1 | ~10h |
| Banco de Dados | 0 | 4 | 11 | 2 | ~23.5h |
| Frontend / UX | 0 | 2 | 6 | 1 | ~58h |
| **Total** | **2** | **8** | **19** | **4** | **~90h** |

**Custo estimado total: R$ 13.500** (base R$ 150/h)

> Reservar 20% de buffer para débitos descobertos durante `supabase db diff` (DB-NEW-A2).

---

## 3. Plano de Resolução por Fases

### Pré-Fase 1 — Diagnóstico Obrigatório (antes de qualquer migration)

**Ação 1:** Executar `supabase db diff` em produção e documentar todas as divergências.
**Ação 2:** Inspecionar logs do Supabase Edge Functions para erros de constraint violation nos últimos 7 dias (verificar se `delivery-webhook` está falhando silenciosamente).
**Ação 3:** Mapear todas as origens legítimas que chamam as Edge Functions (necessário antes de restringir CORS — SYS-C5).

---

### Fase 1 — Segurança + Schema Crítico (Semana 1)

**Objetivo:** Eliminar riscos de segurança imediatos e confirmar integridade do schema em produção.

| Débito | Ação | Responsável | Estimativa |
|---|---|---|---|
| DB-NEW-C1 + DB-NEW-C2 | Confirmar aplicação da migration `20260402200000_delivery_status.sql` via `supabase migration list`; se não aplicada, executar `supabase db push` | @data-engineer | 1h |
| SYS-C2 | Mover credenciais Zoom para `supabase secrets set ZOOM_CLIENT_ID`, `ZOOM_CLIENT_SECRET`, `ZOOM_ACCOUNT_ID`; atualizar Edge Functions para `Deno.env.get()` | @dev | 2h |
| SYS-C3 | Mover `EVOLUTION_API_KEY` para `supabase secrets set`; atualizar `send-whatsapp` e `delivery-webhook` | @dev | 1h |
| SYS-C4 | Refatorar inicialização do Supabase em `admin.html` para usar `window.SUPABASE_CONFIG` | @dev | 1h |
| SYS-C5 | Restringir CORS para domínios mapeados; adicionar validação de token caller | @dev | 1-2h |

**Gate de saída Fase 1:** Todos os testes listados na Seção 5.1 passam.

---

### Fase 2 — Migrations e DB (Semana 1-2)

**Objetivo:** Estabelecer rastreabilidade de schema e corrigir tipos críticos.

| Débito | Ação | Estimativa |
|---|---|---|
| DB-NEW-A2 | Documentar output do `supabase db diff` no assessment | 1h |
| DB-C1 + DB-R2 | Criar schema file completo para `classes` com DDL, RLS e índices | 4h |
| DB-M1 | Migrar arquivos SQL avulsos para migrations versionadas Supabase CLI | 4h |
| DB-NEW-M1 | Documentar schema de `notification_schedules` | 1h |
| DB-S1 | Migration para converter `attendance.lesson_date` de TEXT para DATE (com auditoria prévia de dados) | 2h |
| SYS-M1 | Pinar Supabase JS para versão minor/patch específica | 0.5h |

**Gate de saída Fase 2:** `supabase db push` em staging executa sem erros; `supabase migration list` mostra histórico completo.

---

### Fase 3 — Frontend (Semana 2-3)

**Objetivo:** Melhorar manutenibilidade e UX do admin sem introduzir regressões.

| Débito | Ação | Estimativa |
|---|---|---|
| UX-NEW-A1 | Adicionar feedback visual (spinner + confirmação) para envio WhatsApp e presença | 3h |
| UX-H3 + UX-H4 | Criar pattern de loading states e error handling padronizado | 4h |
| UX-M3 + SYS-M3 | Consolidar páginas duplicadas; redirecionar URLs legadas | 2h |
| UX-M4 | Remover backup files do repositório | 0.5h |
| UX-NEW-A2 | Modal de confirmação para ações destrutivas | 2h |

**Gate de saída Fase 3:** Smoke test completo de presença + notificação WhatsApp passa sem regressão.

---

### Fase 4 — Refatoração Estrutural (Semana 3-4, planejamento dedicado)

**Objetivo:** Resolver débitos de alto esforço que requerem planejamento de story dedicada.

| Débito | Ação | Estimativa |
|---|---|---|
| UX-H1 + UX-M1 | Criar `css/design-system.css` com tokens existentes + componentes base | 16h |
| UX-C1 | Quebrar `admin.html` em módulos JS separados — `admin-presenca.js`, `admin-notificacoes.js`, `admin-turmas.js` | 20h |
| UX-H2 | Migrar conteúdo de `abstracts/index.html` para tabela Supabase com template mínimo | 8h |
| UX-M2 | Garantir responsividade em todas as páginas | 4h |

**Gate de saída Fase 4:** Admin funciona end-to-end após componentização; página abstracts renderiza a partir do banco.

---

### Fase 5 — Normalização e Backlog (Semana 4+)

| Débito | Ação | Estimativa |
|---|---|---|
| DB-S2 | Normalizar `teacher_name` para FK com view de compatibilidade durante transição | 4h |
| DB-R1 + DB-R3 | Implementar RLS com roles scoped por mentor; isolar `zoom_tokens` | 5h |
| DB-NEW-A1 + DB-NEW-L1 + DB-I1 | Constraints `NOT NULL`/`DEFAULT` + índices | 1.5h |
| SYS-M2 | Criar branch `staging` + deploy separado no Vercel | 2h |
| SYS-H3 | Adicionar ESLint + Prettier com pre-commit hook | 2h |

---

## 4. Dependências Entre Débitos

```
supabase db diff (DB-NEW-A2)
    └── antes de qualquer migration da Fase 1-2

DB-NEW-C2 (CHECK constraint)
    └── antes de → DB-NEW-C1 (adicionar colunas)

DB-C1 (schema classes)
    └── desbloqueia → UX-H2 (abstracts DB-driven)

DB-M1 (migrations versionadas)
    └── facilita → UX-C1 (admin refactor expõe queries implícitas)

SYS-C5 (CORS)
    └── depende de → mapeamento de origens legítimas (Pré-Fase 1)

UX-C1 (admin refactor)
    └── após → Fase 1 (segurança) resolvida
```

---

## 5. Critérios de Aceitação por Fase

### 5.1 Após Fase 1 — Segurança + Schema

**SYS-C2/C3 (credenciais):**
- [ ] Edge Functions `zoom-oauth`, `zoom-attendance`, `send-whatsapp` e `delivery-webhook` operam normalmente após mover credenciais para env vars
- [ ] Nenhuma credencial aparece em logs de erro ou responses da API
- [ ] Variáveis estão definidas no Supabase Dashboard (prod)

**DB-NEW-C2 (CHECK constraint — confirmação):**
- [ ] `UPDATE notifications SET status = 'delivered'` executa sem erro de constraint
- [ ] `UPDATE notifications SET status = 'read'` executa sem erro de constraint
- [ ] Delivery webhook registra confirmações de entrega visíveis na tabela

**DB-NEW-C1 (colunas — confirmação):**
- [ ] `evolution_message_ids` aceita array e persiste corretamente
- [ ] `delivered_at` aceita TIMESTAMPTZ e persiste corretamente
- [ ] Webhook de confirmação popula ambas as colunas

### 5.2 Após Fase 2 — Migrations e DB

- [ ] `supabase db push` em staging executa sem erros
- [ ] `supabase migration list` mostra histórico completo e consistente
- [ ] `supabase db diff` retorna diff vazio após aplicar todas as migrations
- [ ] Todos os registros existentes de `lesson_date` convertidos sem perda

### 5.3 Após Fase 3 — Frontend

- [ ] Fluxo de marcação de presença funciona end-to-end
- [ ] Envio de notificação WhatsApp retorna feedback visual ao admin
- [ ] Ações destrutivas têm modal de confirmação
- [ ] Nenhuma regressão em funcionalidades existentes (smoke test completo)

### 5.4 Após Fase 4 — Refatoração Estrutural

- [ ] Admin funciona end-to-end após componentização
- [ ] Conteúdo de abstracts renderizado a partir do banco, idêntico ao hardcoded anterior
- [ ] Página abstracts carrega em menos de 2s (evitar N+1 queries)
- [ ] Admin consegue atualizar conteúdo sem editar código

---

## 6. Riscos Cruzados

| Risco | Áreas Afetadas | Probabilidade | Impacto | Mitigação |
|---|---|---|---|---|
| Migration DB-NEW-C2 colidindo com estado manual em produção | DB + Notificações | ALTA | ALTO | Executar `db diff` antes; usar `ALTER TABLE ... DROP CONSTRAINT IF EXISTS` |
| Refactor `admin.html` introduzindo regressão no fluxo de presença | UX + DB | MÉDIA | ALTO | Criar smoke tests antes do refactor; testar fluxo completo após |
| Correção de CORS quebrando callback da Evolution API | Segurança + WhatsApp | MÉDIA | CRÍTICO | Mapear todas as origens antes de restringir `*` |
| Conversão `lesson_date` TEXT→DATE com dados mal-formatados | DB + Frontend | MÉDIA | MÉDIO | Auditoria prévia: `SELECT DISTINCT lesson_date FROM attendance` |
| Normalização `teacher_name` quebrando queries existentes | DB + Frontend | BAIXA | ALTO | Manter coluna legada com view de compatibilidade durante transição |
| Credenciais Zoom/Evolution em logs de erro mesmo após mover para env vars | Segurança | BAIXA | ALTO | Garantir que mensagens de erro não interpolam variáveis de ambiente |

---

## 7. Status do QA Gate

**Resultado:** APROVADO COM RESSALVAS CRÍTICAS

O assessment está aprovado para seguir para planejamento de resolução. As três condições abaixo devem ser atendidas antes do início da Fase 1:

1. **Executar `supabase db diff` em produção** e documentar todas as divergências encontradas. Resultado deve ser adicionado como seção neste documento.
2. **Verificar empiricamente se o delivery-webhook está falhando** — inspecionar logs do Supabase Edge Functions para erros de constraint violation nos últimos 7 dias.
3. **Mapear origens legítimas** que chamam as Edge Functions antes de planejar a correção de CORS (SYS-C5).

---

## 8. Próximos Passos Imediatos

1. **Hoje:** Executar `supabase migration list` para confirmar status de `20260402200000_delivery_status.sql` em produção (DB-NEW-C1 + DB-NEW-C2)
2. **Hoje:** Inspecionar logs do Supabase Dashboard → Edge Functions → `delivery-webhook` (últimos 7 dias)
3. **Dia 1-2:** Iniciar Fase 1 com SYS-C2 + SYS-C3 (mover credenciais para env vars — menor risco, maior impacto de segurança)
4. **Dia 2-3:** Após `supabase db diff`, planejar e executar migrations da Fase 2
5. **Semana 2:** Criar story dedicada para UX-C1 (admin refactor) com smoke tests como gate de entrada

---

## 9. Histórico de Revisões

| Data | Versão | Mudança | Autor |
|---|---|---|---|
| 2026-04-06 | v1.0 | Documento inicial — consolidação das fases 1-8 do Brownfield Discovery | @architect (Aria) |
| 2026-04-06 | v1.1 | Reclassificação de DB-NEW-C1 e DB-NEW-C2 de CRÍTICO para MÉDIO após confirmação de existência da migration `20260402200000_delivery_status.sql`. Total de críticos reduzido de 4 para 2. | @architect (Aria) |

---

*Documento gerado por @architect (Aria) — Synkra AIOX Brownfield Discovery v1.0*
*Próxima revisão recomendada: após execução da Fase 1 ou em 2026-04-13*
