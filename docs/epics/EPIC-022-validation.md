# EPIC-022 — PO Validation
> Validador: @po (Pax) — 2026-05-22
> Epic: `/home/rover/lesson-pages/docs/epics/EPIC-022-painel-refactor.md`
> Discovery base: `01-architecture-map.md`, `02-db-audit.md`, `03-ux-audit.md`

## Verdict
**GO** — com 3 fixes obrigatórios pré-drafting da primeira P0 story (S.022.4).

## Score 10-point

| # | Item | Pass | Nota |
|---|------|------|------|
| 1 | Título claro e objetivo | ✅ | "Painel Refactor: Consolidação Backend + Foundation" — direto, sem ambiguidade |
| 2 | Descrição completa | ✅ | Problema bem articulado (§Problema, linhas 14-18) — quantifica débito (32 fns, 47% sem RLS, 200 migrations, 3 paths NPS) |
| 3 | AC testáveis nas 8 stories | ⚠️ | 7/8 stories com AC mensuráveis. S.022.7 AC fraco (sem GIVEN/WHEN/THEN, só "ADR criado"). Nenhuma story usa formato Given/When/Then explícito — mas critérios são em sua maioria binários/verificáveis |
| 4 | Escopo bem definido (IN/OUT) | ✅ | §Escopo IN (9 itens) + §Escopo OUT (7 itens explícitos) — DS, frontend, novas features, Evolution→Meta migration TODOS fora |
| 5 | Dependências mapeadas | ✅ | §Dependências (linhas 237-245) com ordem recomendada + relação com DS track paralelo |
| 6 | Estimativa de complexidade S/M/L | ✅ | Todas 8 stories estimadas: 2L, 4M, 2S |
| 7 | Valor de negócio claro | ⚠️ | Implícito ("parar de empilhar features e consolidar") mas FALTA quantificação ROI/timeline em §Objetivo. "Em até 6 semanas" é cronograma, não business value. Sem custo de manutenção atual vs target |
| 8 | Riscos documentados | ✅ | Risco por story + §Risco maior global (linhas 247-256) com checklist obrigatório (dry-run, idempotência, rollback, Slack alert, smoke test, feature flag, aprovação humana) |
| 9 | Critérios de Done por story | ✅ | Cada story tem AC numerados + riscos + estimativa. Faltam "Definition of Done" explícitos (testes, docs, monitoring) mas AC funcionam como proxy |
| 10 | Alinhamento com discovery | ✅ | Cada story referencia seção específica de discovery (§3.1, §3.2, §4.1, §6, etc) — rastreabilidade 100% |

**Total: 8/10** ✅ (limite GO ≥7)

---

## Issues por story

### S.022.1 — Unificar identidade do aluno (P0)
- ✅ AC fortes, ref discovery 02-db-audit §3.1, §3.2 batem
- ⚠️ **AC #1 ambíguo:** "100% phones em `students.normalized_phone` no formato E.164" — qual escopo? Apenas linhas com `phone IS NOT NULL`? Ou inclui `student_imports`/`wa_group_members` também? Discovery §3.2 cita as 3 tabelas mas AC fala só de `students`. **Sugestão:** "100% phones nas 3 tabelas (students, student_imports, wa_group_members) onde phone IS NOT NULL no formato E.164"
- ⚠️ **AC #4 dependente de método:** "`find_duplicate_students()` RPC retorna 0 duplicates" — assume que RPC existe e funciona pré-backfill. Confirmar se RPC já existe (db-audit menciona em §4 mas não como ativo).
- ⚠️ **Riscos:** "manter coluna `phone` original 30 dias" é prudente mas não define cleanup window. **Sugestão:** explicitar migration final de drop em sprint X+2.
- ✅ Estimativa L razoável (trigger + backfill + view + constraint + ADR)

### S.022.2 — Consolidar dispatch NPS (P0)
- ✅ AC #2 ("flip atômico via admin RPC") + AC #3 (rollback bidirecional) + AC #5 (Slack alert) cobrem rollback corretamente
- ✅ Riscos cita "Aprovação humana NON-NEGOTIABLE antes do flip" — alinhado com CLAUDE.md regra Comunicação Externa
- ⚠️ **AC #1 não-testável diretamente:** "`dispatch-survey` aceita tipo `nps_class` e gera entries equivalentes a `dispatch-class-nps`" — "equivalentes" precisa ser definido. **Sugestão:** "Para mesmo input (cohort_id, class_id, message_variant), ambos engines geram mesma quantidade de entries com mesmos student_ids destinatários"
- ⚠️ **Gap de AC:** Falta AC sobre métricas de paridade (throughput, error rate). Critical pra confiança no flip.
- ✅ Estimativa L razoável

### S.022.3 — Consolidar dashboards NPS (P0)
- ✅ AC binários e mensuráveis
- ⚠️ **AC #5 mal redigido:** "Zero RPCs novos — apenas reorganização de UI" é constraint, não AC verificável. **Sugestão:** mover pra §O que como restrição de escopo; criar AC verificável tipo "Todas RPCs chamadas em `/admin/dispatch` e `/admin/insights` já existem no DB antes desta story"
- ⚠️ **Risco faltando:** Migração de sessão/auth — se URLs mudarem, tokens armazenados em `localStorage` podem precisar revalidação. Não mencionado.
- ✅ Estimativa M razoável

### S.022.4 — RLS gap fix (P0 segurança)
- ✅ AC fortes com smoke tests específicos (#3, #4)
- ✅ Alinhamento com discovery 02-db-audit §6
- ⚠️ **AC #1 vago:** "100% tabelas críticas (Tier 1+2) com RLS habilitado" — não lista tabelas explícitas. Discovery cita ~10 tabelas críticas. **Sugestão:** anexar lista nominal das tabelas Tier 1 e Tier 2 na story, com count exato (ex: "12 tabelas Tier 1 + 18 tabelas Tier 2 = 30 tabelas com RLS habilitado").
- ⚠️ **Risco subestimado:** "RLS muito restritiva pode quebrar queries existentes" precisa plano de teste mais robusto. **Sugestão:** AC adicional "Suite de smoke test cobre todos endpoints admin que tocam tabelas Tier 1+2 — 0 falhas pós-apply"
- ✅ Estimativa M razoável (provavelmente apertado dado scope; considerar M-L)

### S.022.5 — Webhook purchase canonical (P1)
- ✅ AC #1 testa dedup explicitamente
- ✅ AC #3 timeline clara (30 days)
- ⚠️ **AC #2 não-testável:** "Precedência documentada" é entregável de doc, não código. **Sugestão:** "Quando AC e Hotmart emitirem evento pra mesmo `(email, product_id, purchase_date)`, `ac_purchase_events.source` registra valor com prioridade (AC > Hotmart > Generic) e dedup gera apenas 1 linha"
- ⚠️ **Risco faltando:** Hotmart paga separadamente de AC — perder evento Hotmart durante 30-day safety window pode ter consequência financeira (cliente não vê compra). Não mitigado.
- ⚠️ Dependência em S.022.1 (phone normalizado) não está marcada explicitamente em §Dependências, embora purchase event tenha phone. Confirmar.
- ✅ Estimativa M razoável

### S.022.6 — Cleanup dual-identity turma (P1)
- ✅ AC #1 verificável via grep
- ✅ AC #3 verificável via SQL count
- ✅ AC #4 (rollback documentado) explícito
- ⚠️ **Risco bem citado** ("Drop de coluna em prod") mas falta menção a **PostgreSQL views/RPCs com SECURITY DEFINER** que possam referenciar `classes.cohort_id`. Discovery 02-db-audit §3.3 menciona `get_weekly_attendance()` mas pode haver outras.
- ✅ Estimativa M razoável

### S.022.7 — Audit NPS cron disabled (P2)
- ❌ **AC fracos.** Apenas 1 critério substantivo ("ADR criado") — não testa o COMPORTAMENTO do sistema pós-decisão. **Sugestão obrigatória:** adicionar AC tipo:
  - "Se decisão = Opção A: 1 dispatch de teste em turma sentinela passa por gate Slack approval"
  - "Se decisão = Opção B: comment explícito na migration 20260517010400 documenta dormante"
  - "Logs Supabase dos últimos 30 dias auditados — relatório de dispatches NPS esperados vs efetivos anexado ao ADR"
- ⚠️ **Risco faltando:** Re-ativar cron sem revisão de conteúdo dos templates atuais = violação direta de CLAUDE.md "Comunicação Externa". **Risco crítico não mencionado.**
- ✅ Estimativa S razoável

### S.022.8 — Tabelas órfãs cleanup (P2)
- ✅ AC simples e verificáveis
- ⚠️ **AC #2 condicional sem critério:** "Se drop: backup snapshot antes" — qual mecanismo de backup? `pg_dump`? Supabase native? **Sugestão:** "Backup via `pg_dump` exportado pra `docs/architecture/backups/YYYYMMDD-table-name.sql` antes de DROP"
- ⚠️ **Risco faltando:** `notification_queue` pode ter trigger ativo. Discovery 02-db-audit §5 marca como ÓRFÃ? mas com `?` — incerteza. **Sugestão:** AC adicional "Audit revela 0 triggers/RPCs ativos referenciando tabela antes de deprecate/drop"
- ✅ Estimativa S razoável

---

## Gaps vs discovery

Achados de discovery que ficaram **fora** do Epic:

### 🔴 GAPS CRÍTICOS
1. **Delivery status sem provider enum** (01-architecture-map §4.4, recomendação §5.4): 2 webhooks (delivery-webhook + meta-delivery-webhook) logam na mesma `delivery_status` SEM coluna `provider`. `dispatch-retry` pode retry pelo path errado. **Não há story endereçando isso.** Recomendação discovery era P2/M. Sugiro **adicionar S.022.9 — Delivery status provider routing**.

2. **`send-whatsapp-reminder` dormant** (01-architecture-map tabela §2 Dispatch/Send): Função marcada como "Dormant — unused?" mas não há decisão registrada. S.022.2 só fala de `send-whatsapp` legacy, não de `send-whatsapp-reminder`. **Gap menor mas precisa decisão.**

3. **Constraint `UNIQUE(normalized_phone, cohort_id)`** (S.022.1 AC implícito, db-audit §7 #2): Discovery menciona como ação. Story 1 cita no §O que mas **AC #4 testa duplicates via RPC, não constraint DB**. Se RPC falhar mas constraint passar, false negative. Sugiro AC adicional explícito.

### 🟡 GAPS MENORES
4. **Soft-delete inconsistência** (02-db-audit §6): Algumas tabelas usam `deleted_at`, outras `active`, outras nada. Não é endereçado em nenhuma story. Pode ficar pra epic futuro mas merece menção em §Escopo OUT.

5. **`automation_runs` overlap com `journey_executions`** (02-db-audit §5): Marcado como "Overlap?" — não está em S.022.8 (que cobre só 3 tabelas órfãs explícitas). **Adicionar à lista de S.022.8** ou criar nota.

6. **Acessibilidade quick wins** (03-ux-audit §6): 7 issues A11y identificados (inputs sem label, botões sem aria-label, contrast). Não há story endereçando — Epic explicitamente exclui frontend redesign (Escopo OUT linha 41), o que cobre isso. ✅ OK como justificado.

7. **Source-of-truth doc** (Escopo IN linha 34): Item listado mas **nenhuma story explícita** cria `docs/architecture/source-of-truth.md`. Distribuído implicitamente entre stories (ADRs em S.022.1, S.022.5, S.022.7) mas falta o doc consolidado. Sugiro criar como AC de S.022.1 ou story standalone.

---

## Fixes obrigatórios

Pré-drafting da primeira P0 story (@sm pegando S.022.4):

### F1 — Adicionar S.022.9 (Delivery status provider routing)
Gap crítico em discovery 01-architecture-map §4.4. Sem isso, `dispatch-retry` continua com bug latente que pode retry wrong path silenciosamente. Story: M, P1.

### F2 — Fortalecer AC da S.022.7
Risco de violação CLAUDE.md "Comunicação Externa" se cron NPS for re-ativado sem AC explícito de gate humano + revisão de template. AC atual ("ADR criado") é insuficiente.

### F3 — Listar nominalmente tabelas Tier 1+2 na S.022.4
AC #1 ("100% tabelas críticas Tier 1+2") é não-mensurável sem lista. Anexar na story (pode ser appendix) — discovery 02-db-audit §6 fornece base.

---

## Recomendações nice-to-have

### N1 — Quantificar business value em §Objetivo
Adicionar métricas tipo "Tempo médio de debug de envio falho cai de X dias pra Y horas" ou "Onboarding de novo dev passa de Z semanas pra W". Score #7 sobe de ⚠️ para ✅.

### N2 — Padronizar AC em formato Given/When/Then
Não é mandatório (AC atuais funcionam) mas melhoraria testabilidade automated. Stories S.022.2 e S.022.5 ganhariam mais.

### N3 — Definition of Done global por story
Header padrão tipo:
```
## Definition of Done
- [ ] AC todos verificados
- [ ] Migration idempotente testada (2x rerun = 0 diff)
- [ ] Rollback verificado em snapshot
- [ ] Slack alert configurado
- [ ] Docs atualizados (ADR ou source-of-truth.md)
- [ ] @qa gate PASS
```

### N4 — Consolidar source-of-truth.md como story standalone
Item de Escopo IN (linha 34) sem owner explícito. Sugiro tornar AC da S.022.1 ou criar S.022.10 (S, P2).

### N5 — Adicionar coluna no inventário UX (03-ux-audit §1)
S.022.3 deveria documentar mapping completo de URLs antigas → novas. Não está no AC.

---

## Decisão final

**[GO]** — Epic está sólido (8/10) com rastreabilidade discovery excelente, escopo IN/OUT bem definido, e tratamento de riscos production-aware (dry-run, idempotência, rollback, gate humano). Pode prosseguir pra @sm drafting da S.022.4 (RLS gap, primeira P0 sem dependências).

**Condicionantes:**
1. F1 (criar S.022.9 Delivery status) e F2 (fortalecer S.022.7 AC) devem ser feitos antes do @sm pegar S.022.7 ou S.022.9 — mas **NÃO bloqueiam S.022.4** (primeira P0 em paralelo).
2. F3 (lista nominal Tier 1+2 em S.022.4) **DEVE estar resolvido antes** do @sm draftar S.022.4. @architect (Aria) ou @data-engineer (Dara) anexa lista à story.
3. Recomendações nice-to-have podem ser absorvidas pelo @sm durante drafting individual ou ficar pra retrospectiva pós-epic.

**Sequência recomendada:**
1. @data-engineer (Dara) anexa lista nominal Tier 1+2 → S.022.4 (1-2h work)
2. @sm draftar S.022.4 com lista nominal embedded
3. @pm cria S.022.9 (delivery routing) — Epic update minor
4. Em paralelo: @dev pega S.022.4 RLS
