# Technical Debt Assessment — lesson-pages (Brownfield Fases 4-8)

> **Data:** 2026-04-13
> **Consolidado por:** @architect (Aria) com revisoes de @data-engineer e @ux-design-expert
> **QA Gate:** APPROVED (todos os debitos validados, dependencias mapeadas)

---

## Classificacao de Debitos

| Severidade | Criterio | Acao |
|-----------|---------|------|
| **CRITICO** | Bloqueia features futuras ou causa bugs em producao | Resolver no proximo sprint |
| **ALTO** | Aumenta custo de manutencao significativamente | Resolver em 2-3 sprints |
| **MEDIO** | Incomoda mas nao bloqueia | Resolver oportunisticamente |
| **BAIXO** | Nice to have | Backlog |

---

## Debitos Priorizados

### CRITICOS (resolver agora)

#### TD-01: Unificar students + student_imports

**Problema:** Duas tabelas de alunos coexistem. `students` (777 rows, legada) e FK target de 14 tabelas. `student_imports` (490 rows, CSV) e a fonte da verdade para o frontend. O frontend ja foi migrado, mas o banco nao.

**Impacto:** Qualquer nova feature (ranking, engajamento, relatorios) precisa decidir "qual tabela?" — e a resposta nunca e clara.

**Solucao proposta:**
1. Criar coluna `student_imports.legacy_student_id UUID` para mapear 1:1
2. Backfill via match por nome+telefone
3. Criar view `v_students` que une ambas
4. Migrar FKs progressivamente (zoom_participants primeiro)
5. Ao final, `students` vira tabela historica

**Esforco:** Grande (2-3 dias) | **Risco:** Alto (FKs, funcoes, triggers)

#### TD-02: Service role key exposta em migration SQL

**Problema:** `supabase/migrations/20260402183513_webhook_notify_whatsapp.sql` contem a service_role key commitada no repositorio.

**Impacto:** Qualquer pessoa com acesso ao repo pode bypassar RLS completamente.

**Solucao:** Reescrever trigger para ler key de `app_config` (padrao ja adotado em migrations mais recentes). Rotacionar a key apos a correcao.

**Esforco:** Pequeno (1h) | **Risco:** Baixo

### ALTOS (proximo sprint)

#### TD-03: Eliminar dualidade staff vs mentors

**Problema:** Duas tabelas quase identicas (15 rows cada). `mentors` e FK de class_mentors, zoom_tokens, etc. `staff` e usada para display e matching Zoom/WA. Aliases sao sincronizados manualmente no frontend.

**Solucao:** Adicionar `email` e `category` em `mentors`. Eliminar `staff`. Atualizar frontend para usar `mentors` diretamente.

**Esforco:** Medio (4h) | **Risco:** Baixo

#### TD-04: Extrair CSS/JS compartilhado

**Problema:** Login overlay, showToast, nameMatch, generateDates, MENTOR_COLORS duplicados em 6-10 lugares cada.

**Solucao:**
1. `templates/login-overlay.css` — ja existe, fazer todas as paginas importar
2. `templates/utils.js` — ja existe, unificar todas as funcoes e importar
3. `js/config.js` — ja existe, remover hardcoded URL/key de 6 paginas
4. Unificar MENTOR_COLORS (usar array de 15 cores em todos os lugares)

**Esforco:** Medio (3-4h) | **Risco:** Baixo

#### TD-05: Refatorar turma/detalhe.html (monolito 2.358 LOC)

**Problema:** Maior arquivo funcional do projeto. CSS + HTML + 9 tabs de logica em um unico arquivo. Impossivel testar, manter ou reusar.

**Solucao:**
1. Extrair CSS para `turma/detalhe.css`
2. Extrair tabs em modulos: `turma/js/presenca.js`, `turma/js/wa.js`, `turma/js/equipe.js`, etc.
3. HTML base reduzido para ~200 linhas

**Esforco:** Grande (1 dia) | **Risco:** Medio (muitas interdependencias)

#### TD-06: Substituir iframes no admin por views inline

**Problema:** 4 views do admin (alunos, presenca, aulas, relatorio) sao carregadas via iframe. Causa scroll duplo, URL nao muda, sessao desconectada, back button quebrado.

**Solucao:** Migrar para SPA completa — cada view como modulo JS carregado on-demand (mesmo padrao de staff, classes, zoom).

**Esforco:** Grande (1-2 dias) | **Risco:** Medio

#### TD-07: RLS de student_imports e wa_group_members

**Problema:** Politica "authenticated full access" — qualquer usuario logado pode ler/escrever.

**Solucao:** Restringir para admin-only (mesmo padrao de `students`).

**Esforco:** Pequeno (30min) | **Risco:** Baixo

### MEDIOS (oportunistico)

#### TD-08: Tabelas com 0 rows — DECISAO: MANTER ✅

6 tabelas com 0 rows, TODAS referenciadas no codigo frontend ou planejadas para EPIC-012:
- `engagement_daily_ranking` → `aluno/perfil.html` (grafico engajamento, cron nightly)
- `zoom_chat_messages` → `aluno/perfil.html` (atividade chat Zoom)
- `whatsapp_group_messages` → `aluno/perfil.html` (atividade WA, delivery-webhook)
- `class_materials` → `aulas/index.html` (upload/download de materiais)
- `class_recording_notifications` → EPIC-012 Story 12.4 (notificacao automatica)
- `mentor_attendance` → `equipe/`, `relatorio/`, `perfil/` (presenca mentores)

**Auditoria (2026-04-14):** Vazias porque pipelines de dados nao foram ativados ainda (pre-requisito: `cohorts.whatsapp_group_jid`). Nenhuma acao necessaria.

#### TD-09: Eliminar indexes duplicados

`class_mentors` e `lesson_abstracts` tem indexes redundantes.

**Acao:** DROP dos duplicados.

#### TD-10: Realtime desabilitado, Storage mantido ✅

**Auditoria (2026-04-14):**
- **Realtime:** Nenhum uso no frontend (sem `.subscribe()`, `.channel()`). Desabilitado em `config.toml`.
- **Storage:** Usado por `aulas/index.html` — bucket `class-materials` para upload de materiais didaticos. Mantido habilitado.

#### TD-11: Remover paginas de conteudo obsoletas

`analise-interna/` (9.075 LOC), `cohort-fundamentals-c3/`, aulas individuais — verificar se ainda sao acessadas.

#### TD-12: student_cohorts (N:N) — DECISAO: MANTER ✅

Tabela de juncao com 869 rows. O frontend usa `student_imports.cohort_id` (1:1) para display, mas `student_cohorts` e ativamente usada por:
- `merge_students` RPC (consolidacao de cohorts ao mesclar duplicados)
- EPIC-012 (auto-sync WA → students)

**Auditoria (2026-04-14):** unique constraint `(student_id, cohort_id)` presente, indexes OK, RLS admin-only write, 0 orphans. Nenhuma acao necessaria.

---

## Matriz de Dependencias

```
TD-01 (students unification) → precisa ser resolvido ANTES de:
  └── Qualquer nova feature de ranking/engajamento
  └── Migrar survey_links para student_imports
  └── Eliminar student_cohorts (TD-12)

TD-03 (staff/mentors merge) → independente, pode ser feito em paralelo

TD-04 (extrair CSS/JS) → precisa ser feito ANTES de:
  └── TD-05 (refatorar turma/detalhe.html)
  └── TD-06 (substituir iframes)

TD-02 (service role key) → independente, URGENTE
TD-07 (RLS) → independente, rapido
```

---

## Recomendacao de Sequencia

| Sprint | Debitos | Esforco Total | Status |
|--------|---------|---------------|--------|
| **Sprint 1 (urgente)** | TD-02 (key), TD-07 (RLS), TD-09 (indexes) | ~2h | ✅ DONE |
| **Sprint 2 (fundacao)** | TD-04 (CSS/JS compartilhado), TD-03 (staff/mentors) | ~1 dia | ✅ DONE |
| **Sprint 3 (refatoracao)** | TD-05 (turma/detalhe split), TD-01 (students — backlog) | ~3 dias | ✅ DONE (TD-01 adiado) |
| **Sprint 4 (UX)** | TD-06 (fix iframe UX), TD-11 (paginas obsoletas) | ~2 dias | ✅ DONE |
| **Backlog** | TD-08 (manter), TD-10 (realtime off), TD-12 (manter) | Oportunistico | ✅ Todos decididos |
| **Adiado** | TD-01 (students unification) | Grande | Decisao do PO: CSV e fonte da verdade |

---

*Documento consolidado — Brownfield Discovery Fases 4-8*
*QA Gate: APPROVED*
