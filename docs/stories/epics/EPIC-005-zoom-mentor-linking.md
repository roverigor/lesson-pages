# EPIC-005 — Zoom Mentor Linking (ZML)

**Status:** Ready for Development  
**Criado por:** Morgan (@pm) + Aria (@architect)  
**Data:** 2026-04-07  
**Projeto:** lesson-pages — Academia Lendária

---

## Epic Goal

Permitir que todos os mentores, hosts e professores sejam vinculados à plataforma com seus nomes alternativos do Zoom, para que quando a Zoom API importar relatórios de participantes, o sistema os reconheça automaticamente — sem intervenção manual por meeting.

---

## Existing System Context

- **Stack:** HTML/CSS/JS vanilla + Supabase (PostgreSQL + Edge Functions)
- **Schema pronto:** `mentors.aliases TEXT[]` já existe com GIN index
- **Matching pronto:** `mark_mentor_participants()` usa aliases com 8 regras fuzzy
- **Edge function:** `zoom-attendance` já importa participantes e chama matching
- **Admin existente:** `/equipe/index.html` com senha — local natural para a UI

## O que já existe e pode ser reaproveitado

- `mentors.aliases TEXT[]` — schema pronto
- `mark_mentor_participants()` — função DB completa com suporte a aliases
- `mentor_unmatched_report` — action na zoom-attendance retorna não reconhecidos
- `/equipe/index.html` — admin de mentores com auth, padrão de cards estabelecido
- Supabase client com update de mentors já funcionando na equipe page

## Stories

| Story | Título | Complexidade | Executor |
|---|---|---|---|
| 5.1 | Pipeline feedback pós-importação | S | @dev |
| 5.2 | UI CRUD de aliases Zoom em /equipe | M | @dev |
| 5.3 | Seção "Vinculação Zoom" — candidatos não reconhecidos | M | @dev |

## Sequência recomendada

5.1 → 5.2 → 5.3

5.1 é backend puro e valida o pipeline antes de construir UI.
5.2 é independente e entrega valor imediato.
5.3 depende da nova action `zoom_mentor_candidates` criada em 5.1.
