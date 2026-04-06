# Technical Debt Assessment — FINAL
> lesson-pages | 2026-04-06 | v1.0
> Consolidado por @architect (Aria) a partir de: technical-debt-DRAFT.md, db-specialist-review.md, ux-specialist-review.md, qa-review.md

---

## Executive Summary

| Indicador | Valor |
|---|---|
| Total de débitos mapeados | 30 |
| Críticos | 5 |
| Altos | 12 |
| Médios | 9 |
| Baixos | 4 |
| Esforço total estimado | ~92h |
| Custo estimado (R$150/h) | ~R$ 13.800 |
| Débitos resolvidos recentemente (desde 01/04) | 5 |
| Gate QA | APPROVED COM RESSALVAS |

### Contexto
O lesson-pages é um sistema funcional que opera em produção com usuários reais (mentores e participantes). O stack — Vanilla HTML/CSS/JS + Supabase + Docker/Nginx/VPS — entregou valor rapidamente, mas acumulou débitos técnicos durante crescimento acelerado. Os débitos **não impedem a operação atual**, mas representam riscos crescentes de segurança, integridade de dados e manutenibilidade.

### Débitos Resolvidos (referência)
| ID | Resolução | Data |
|---|---|---|
| SYS-C1 | SERVICE_ROLE_KEY removida do frontend | Abr/2026 |
| SYS-H4 | CDN versions pinadas | Abr/2026 |
| EPIC-001 | Sistema de notificações WhatsApp operacional | Abr/2026 |
| EPIC-002 | Agendamento pg_cron operacional | Abr/2026 |
| CONFIG | js/config.js criado (centraliza anon key) | Abr/2026 |

---

## Inventário Completo

### Críticos — resolver em até 1 semana

| ID | Débito | Área | Horas | Ação Requerida |
|---|---|---|---|---|
| SYS-C2 | Credenciais Zoom hardcoded nas Edge Functions (client_id, secret, S2S credentials) | Segurança | 2h | Mover para Supabase Secrets / env vars |
| SYS-C3 | Evolution API credentials hardcoded (URL, API key, instância) nas Edge Functions | Segurança | 2h | Mover para Supabase Secrets / env vars |
| DB-NEW-C2 | `notifications.status` CHECK constraint não inclui `delivered` e `read` — delivery-webhook falha silenciosamente | DB/Integridade | 1h | Migration: ALTER TABLE + nova constraint |
| DB-NEW-C1 | `notifications.evolution_message_ids` e `delivered_at` sem DDL — usadas pelo delivery-webhook sem migration documentada | DB/Rastreabilidade | 2h | Migration formal; se colunas já existem, usar `ADD COLUMN IF NOT EXISTS` |
| UX-C1* | `admin.html` com 2844 linhas — monolito JS/CSS inline (*crítico para manutenção, não para usuário final) | Frontend | 20h | Separar em módulos JS por domínio (Fase 3) |

*UX-C1 é classificado como crítico para manutenibilidade, não para segurança. Não bloqueia Fase 1.

### Altos — resolver em até 1 mês

| ID | Débito | Área | Horas | Ação Requerida |
|---|---|---|---|---|
| SYS-C5 | CORS `Access-Control-Allow-Origin: *` em todas as Edge Functions | Segurança | 1h | Mapear origens legítimas; restringir para lista explícita |
| DB-C1 | `classes` sem schema file (tabela central) | DB | 3h | Escrever DDL completo com RLS, índices e constraints |
| DB-M1 | Sem migrations versionadas (SQL avulsos, não Supabase CLI) | DB | 4h | Migrar todos os arquivos para `supabase/migrations/` versionados |
| DB-R2 | `classes` sem RLS documentada | DB/Segurança | 1h | Implementar políticas RLS junto com DB-C1 |
| DB-NEW-A2 | Sem auditoria de divergências schema documentado vs. produção | DB | 1h | `supabase db diff` antes de qualquer migration nova |
| UX-H1 | Zero consistência visual — cada página tem CSS independente | Frontend | 16h | Design system unificado com tokens já existentes |
| UX-H2 | `abstracts/index.html` ~4800 linhas hardcoded | Frontend | 8h | Mover conteúdo para Supabase; renderizar via JS |
| UX-H3 | Sem estados de loading padronizados | Frontend | 4h | Componente spinner reutilizável + padrão de uso |
| UX-H4 | Sem error handling visual padronizado | Frontend | incluído em UX-H3 | Toast/alert component reutilizável |
| UX-NEW-A1 | Ausência de feedback visual para ações críticas (WhatsApp, presença) | Frontend | 3h | Feedback inline nos botões de ação |
| SYS-H1 | Sem build system (sem npm, sem bundler, sem minificação) | Infra | 8h | Adicionar npm + script de build básico |
| SYS-H2 | Zero testes (nenhum test file, nenhum test runner) | Qualidade | 8h | Smoke tests para fluxos críticos |

### Médios — resolver em 1-3 meses

| ID | Débito | Área | Horas | Ação Requerida |
|---|---|---|---|---|
| DB-NEW-M1 | `notification_schedules` sem schema file documentado | DB | 1h | Escrever DDL formal |
| DB-S1 | `attendance.lesson_date` como TEXT em vez de DATE | DB | 2h | Migration com backfill (após auditoria de formato) |
| DB-S2 | `attendance.teacher_name` desnormalizado | DB | 4h | Adicionar FK para mentors; manter coluna legada como GENERATED durante transição |
| DB-S3 | `classes.professor`/`host` TEXT legados | DB | incluído em DB-C1 | Deprecar após confirmar que `class_mentors` é usado em todos os lugares |
| DB-R1 | RLS sem roles intermediários (apenas admin write) | DB | 3h | Políticas scoped por mentor para suas próprias turmas |
| DB-R3 | `zoom_tokens` acessível a qualquer admin | DB | 2h | RLS scoped por mentor_id |
| UX-M2 | Responsividade não garantida | Frontend | 4h | Audit de breakpoints + fixes por página |
| UX-M3 | Páginas duplicadas (`aios-install` vs `aiox-install`) | Frontend | 1h | Decidir canônica, redirecionar, remover duplicata |
| UX-NEW-A2 | Sem confirmação antes de ações destrutivas no admin | Frontend | 2h | Modal de confirmação reutilizável |
| SYS-H3 | Sem linting/formatting | Qualidade | 2h | ESLint + Prettier com config mínima |
| SYS-H5 | JS/CSS inline por página, sem módulos compartilhados | Frontend | incluído em UX-H1 | Resolvido com design system |

### Baixos — backlog

| ID | Débito | Área | Horas | Ação Requerida |
|---|---|---|---|---|
| DB-NEW-L1 | `notification_schedules.last_triggered_at` sem índice | DB | 0.5h | `CREATE INDEX` simples |
| DB-I1 | Sem índice em `notifications.processed_at` | DB | 0.5h | `CREATE INDEX` simples |
| DB-NEW-A1 | Falta de constraints `NOT NULL`/`DEFAULT` explícitos em colunas novas | DB | 0.5h | Incluir na migration de DB-NEW-C1 |
| UX-M4 | Backup files no repo | Frontend | 0.5h | `git rm` dos arquivos de backup |

---

## Matriz de Priorização Final

```
ALTO IMPACTO / BAIXO ESFORÇO — Quick Wins (fazer primeiro)
┌─────────────────────────────────────────────────────────┐
│  SYS-C2 (2h)   SYS-C3 (2h)   DB-NEW-C2 (1h)           │
│  DB-R2 (1h)    SYS-C5* (1h)  DB-NEW-A2 (1h)           │
└─────────────────────────────────────────────────────────┘
*SYS-C5 requer mapeamento prévio de origens

ALTO IMPACTO / ALTO ESFORÇO — Investimentos Estratégicos
┌─────────────────────────────────────────────────────────┐
│  UX-C1 (20h)   UX-H1 (16h)   DB-M1 (4h)               │
│  SYS-H1 (8h)   SYS-H2 (8h)   UX-H2 (8h)              │
└─────────────────────────────────────────────────────────┘

BAIXO IMPACTO / BAIXO ESFORÇO — Automatizar/Delegar
┌─────────────────────────────────────────────────────────┐
│  DB-NEW-L1 (0.5h)  DB-I1 (0.5h)  UX-M4 (0.5h)        │
│  SYS-H3 (2h)       UX-M3 (1h)                         │
└─────────────────────────────────────────────────────────┘

BAIXO IMPACTO / ALTO ESFORÇO — Postergar / Avaliar ROI
┌─────────────────────────────────────────────────────────┐
│  DB-S2 (4h)    DB-R1 (3h)    DB-R3 (2h)               │
└─────────────────────────────────────────────────────────┘
```

---

## Plano de Resolução por Fases

### Fase 0 — Diagnóstico (antes de tudo, 1 dia, ~2h)

**Pré-requisito bloqueante para Fase 1** (levantado pelo QA Review):

| Ação | Responsável | Resultado Esperado |
|---|---|---|
| `supabase db diff` contra produção | @data-engineer | Lista de divergências entre schema documentado e estado real |
| Inspecionar logs Edge Functions (últimos 7 dias) | @devops | Confirmar se delivery-webhook está gerando erros de constraint violation |
| Mapear origens que chamam as Edge Functions | @data-engineer | Lista de domínios para whitelist do CORS |

> Sem esta fase, migrations da Fase 1 correm risco de conflito com alterações manuais em produção.

---

### Fase 1 — Segurança + Schema Crítico (1 semana, ~12h)

**Objetivo:** eliminar riscos de segurança ativos e restaurar integridade do sistema de notificações.

| Ordem | ID | Débito | Horas | Critério de Aceitação |
|---|---|---|---|---|
| 1 | SYS-C2 | Zoom credentials → env vars | 2h | Edge Functions funcionam; nenhuma credencial no código |
| 2 | SYS-C3 | Evolution API credentials → env vars | 2h | idem |
| 3 | DB-NEW-C2 | CHECK constraint notifications.status | 1h | UPDATE para `delivered`/`read` executa sem erro |
| 4 | DB-NEW-C1 | Migration colunas evolution_message_ids + delivered_at | 2h | Delivery-webhook registra confirmações de entrega |
| 5 | DB-C1 + DB-R2 | DDL + RLS para tabela `classes` | 4h | Schema documentado; políticas RLS aplicadas |
| 6 | SYS-C5 | CORS restrito a origens legítimas | 1h | Edge Functions rejeitam origens não autorizadas |

**Total Fase 1:** ~12h | R$ 1.800

---

### Fase 2 — Fundação DB + Qualidade (2-3 semanas, ~30h)

**Objetivo:** estabelecer rastreabilidade do schema e base mínima de qualidade.

| Ordem | ID | Débito | Horas |
|---|---|---|---|
| 1 | DB-M1 | Migrations versionadas (Supabase CLI) | 4h |
| 2 | DB-NEW-M1 | Schema notification_schedules | 1h |
| 3 | DB-S1 | lesson_date TEXT → DATE | 2h |
| 4 | SYS-H2 | Smoke tests para fluxos críticos | 8h |
| 5 | SYS-H1 | Build system npm básico | 8h |
| 6 | SYS-H3 | ESLint + Prettier | 2h |
| 7 | UX-H3/H4 | Loading + error states padronizados | 4h |
| 8 | DB-NEW-L1, DB-I1, DB-NEW-A1, UX-M4 | Backlog baixo esforço | 2h |

**Total Fase 2:** ~31h | R$ 4.650

---

### Fase 3 — Frontend + UX (4-6 semanas, ~48h)

**Objetivo:** reduzir débito de manutenibilidade e melhorar experiência do admin.

| Ordem | ID | Débito | Horas |
|---|---|---|---|
| 1 | UX-NEW-A1 + UX-NEW-A2 | Feedback de ações críticas + confirmações | 5h |
| 2 | UX-H1 + UX-M1 | Design system unificado (tokens → CSS) | 16h |
| 3 | UX-C1 | Refactor admin.html em módulos | 20h |
| 4 | UX-H2 | Abstracts DB-driven | 8h |
| 5 | UX-M2, UX-M3 | Responsividade + duplicatas | 5h |

**Total Fase 3:** ~54h | R$ 8.100

> UX-C1 deve ser executado com smoke tests antes e depois (dependência de SYS-H2).

---

## Riscos e Mitigações

| Risco | Probabilidade | Impacto | Mitigação |
|---|---|---|---|
| Migration DB-NEW-C2 conflita com constraint manual em produção | ALTA | ALTO | Fase 0 obrigatória; usar `DROP CONSTRAINT IF EXISTS` na migration |
| Correção de CORS quebra callback da Evolution API | MÉDIA | CRÍTICO | Mapear origens antes; testar em staging primeiro |
| Refactor admin.html introduz regressão em fluxo de presença | MÉDIA | ALTO | Smoke tests obrigatórios antes do refactor (SYS-H2 primeiro) |
| Conversão lesson_date com dados mal-formatados | MÉDIA | MÉDIO | `SELECT DISTINCT lesson_date FROM attendance` antes da migration |
| Credenciais em logs mesmo após mover para env vars | BAIXA | ALTO | Code review das mensagens de erro das Edge Functions |
| DB-S2 (teacher_name → FK) quebra queries existentes | BAIXA | ALTO | Manter coluna legada como GENERATED ALWAYS AS durante transição |

---

## Critérios de Sucesso

### Ao final da Fase 1
- [ ] Zero credenciais hardcoded no código (verificável via `grep` no repositório)
- [ ] Delivery-webhook registra confirmações de entrega WhatsApp sem erros
- [ ] Schema da tabela `classes` documentado e com RLS aplicada
- [ ] `supabase db diff` retorna diff vazio para as tabelas alteradas na Fase 1

### Ao final da Fase 2
- [ ] `supabase migration list` mostra histórico completo e consistente
- [ ] Smoke tests cobrem: marcação de presença, envio de notificação, agendamento
- [ ] `npm run lint` passa sem erros
- [ ] `npm run build` gera assets minificados

### Ao final da Fase 3
- [ ] `admin.html` tem menos de 200 linhas (apenas shell HTML + imports)
- [ ] Todas as páginas usam as mesmas variáveis CSS (design tokens)
- [ ] Conteúdo de abstracts editável via admin sem tocar em código
- [ ] Smoke tests passam após refactor do admin (sem regressões)
- [ ] Responsividade validada em mobile (375px) e tablet (768px)

---

## Débitos Fora de Escopo

Os seguintes itens foram identificados mas não são recomendados para resolução neste ciclo:

| Item | Motivo |
|---|---|
| Migração de stack (ex: Next.js, build system completo) | Esforço de reescrita não justificado pelo volume atual de usuários; o vanilla JS funciona |
| TypeScript | Custo de migração alto; benefício marginal sem build system estabelecido primeiro |
| DB-S2 completo (normalização teacher_name) | Risco de regressão alto; tabela `attendance` tem dados em produção; postergado para após DB-M1 estabilizar |
| Testes de integração completos | Smoke tests são suficientes para o volume atual; testes de integração requerem infraestrutura adicional (CI com Supabase local) |
| CDN própria para assets estáticos | Vercel já serve os assets com edge caching; custo adicional não justificado agora |

---

## Referências

- `docs/reviews/db-specialist-review.md` — @data-engineer (Dara)
- `docs/reviews/ux-specialist-review.md` — @ux-design-expert (Uma)
- `docs/reviews/qa-review.md` — @qa (Quinn)
- Commits relevantes: `feat: add WhatsApp delivery confirmation tracking`, `feat(epic-002): story 2.2 — scheduling UI in admin panel`
