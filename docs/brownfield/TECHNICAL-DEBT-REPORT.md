# TECHNICAL DEBT REPORT — lesson-pages

> **Relatorio Executivo — Brownfield Discovery**
> **Data:** 2026-04-13
> **Preparado por:** @analyst (Alex) + @pm (Morgan)

---

## Resumo Executivo

O sistema **lesson-pages** e um painel educacional funcional em producao servindo 7 turmas com ~490 alunos CSV, 15 membros de equipe e integracoes com Zoom, WhatsApp e OpenAI. A stack e HTML/JS vanilla + Supabase, deployado via Docker em VPS.

O sistema cresceu organicamente de uma pagina simples para **22 paginas HTML e 36 tabelas**. Esse crescimento rapido deixou debito tecnico que agora impacta a velocidade de desenvolvimento e a confiabilidade.

### Score Geral

| Dimensao | Score | Notas |
|----------|-------|-------|
| Funcionalidade | **8/10** | Cobre bem o fluxo operacional |
| Manutencao | **4/10** | Duplicacao massiva, monolitos |
| Seguranca | **6/10** | RLS presente mas inconsistente; 1 key exposta |
| Escalabilidade | **5/10** | Supabase escala, mas frontend nao |
| UX | **6/10** | Design premium, navegacao fragmentada |
| Dados | **5/10** | Dualidade de tabelas causa confusao |

### Top 3 Riscos

1. **Service role key commitada** — bypass total de RLS exposto no repo (correcao: 1h)
2. **Dualidade students/student_imports** — bloqueia features futuras, causa contagens erradas
3. **Monolito turma/detalhe.html** — 2.358 linhas, impossivel manter

### Top 3 Oportunidades

1. **Unificar CSS/JS compartilhado** — reduz 10 implementacoes duplicadas para 1
2. **Merge staff/mentors** — elimina sincronizacao manual de aliases
3. **Modularizar turma/detalhe** — permite reusar tabs em outras paginas

---

## Epic Proposto: EPIC-DEBT — Reducao de Debito Tecnico

### Sprint 1 — Quick Wins (2h)

| Story | Tipo | Esforco |
|-------|------|---------|
| S1.1: Remover service_role key da migration SQL | Security fix | 30min |
| S1.2: Restringir RLS de student_imports e wa_group_members | Security fix | 30min |
| S1.3: Remover indexes duplicados de class_mentors e lesson_abstracts | Cleanup | 30min |
| S1.4: Padronizar import de js/config.js em todas as paginas | Cleanup | 30min |

### Sprint 2 — Fundacao (1 dia)

| Story | Tipo | Esforco |
|-------|------|---------|
| S2.1: Extrair CSS compartilhado (login overlay, toast) | Refactor | 2h |
| S2.2: Unificar utils.js (showToast, nameMatch, generateDates, MENTOR_COLORS) | Refactor | 2h |
| S2.3: Merge staff → mentors (adicionar email/category em mentors, eliminar staff) | Schema + frontend | 4h |

### Sprint 3 — Refatoracao Core (3 dias)

| Story | Tipo | Esforco |
|-------|------|---------|
| S3.1: Unificar students + student_imports (view + backfill + migrar FKs) | Schema migration | 2 dias |
| S3.2: Modularizar turma/detalhe.html (extrair CSS, tabs em modulos JS) | Refactor | 1 dia |

### Sprint 4 — UX (2 dias)

| Story | Tipo | Esforco |
|-------|------|---------|
| S4.1: Substituir iframes no admin por views inline | Refactor | 1.5 dias |
| S4.2: Auditar e remover paginas obsoletas | Cleanup | 0.5 dia |

### Backlog (oportunistico)

| Story | Tipo |
|-------|------|
| B1: Documentar tabelas com schema pronto sem dados | Docs |
| B2: Desabilitar Realtime/Storage nao utilizados | Config |
| B3: Decidir modelo multi-turma (student_cohorts vs cohort_id) | Arquitetura |
| B4: Migrar survey_links FK para student_imports | Schema |

---

## Metricas de Sucesso

Apos completar Sprints 1-4:

| Metrica | Antes | Depois |
|---------|-------|--------|
| Tabelas de "alunos" | 2 (students + student_imports) | 1 (student_imports com FKs) |
| Tabelas de "equipe" | 2 (staff + mentors) | 1 (mentors) |
| Implementacoes de showToast | 10 | 1 |
| LOC de turma/detalhe.html | 2.358 | ~300 (HTML) + modulos |
| Views em iframe no admin | 4 | 0 |
| Service role key exposta | 1 | 0 |
| Tabelas com RLS inconsistente | 2 | 0 |

---

*Relatório gerado por @analyst (Alex) + @pm (Morgan) — Brownfield Discovery Fases 9-10*
