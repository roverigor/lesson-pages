# 02-db-audit.md — Corrections (post-investigation)

> Investigation realizada durante drafting code Story 22.6 (2026-05-22).
> Discovery findings refinados após audit grep no codebase real.

---

## Correção 1 — §3.3 "Dual Identity Turma" (classes.cohort_id deprecated)

### Afirmação original (incorreta)

> "`classes.cohort_id` deprecated coexistindo com `class_cohorts` (M:N novo). Queries antigas vs novas inconsistentes."

### Realidade verificada

`classes.cohort_id` **não existe** no schema atual:

- Baseline `20260402190833_baseline_existing_schema.sql:80-100` define `classes` table com colunas: `id, name, weekday, time_start, time_end, date, professor, host, color, zoom_link, active, created_at, updated_at`
- ALTER TABLE classes posteriores adicionam: `type, start_date, end_date, zoom_meeting_id, kind, reminder_enabled`
- **Nenhuma migration adiciona `cohort_id` em `classes`**

### Verificação grep

```bash
grep -rn "classes\.cohort_id\|c\.cohort_id" supabase/functions/ admin/ js/
# Resultado: 0 matches específicos
```

Refs a `cohort_id` em migrations apontam pra:
- `students.cohort_id` (baseline schema)
- `student_cohorts.cohort_id` (M:N students↔cohorts)
- `class_cohorts.cohort_id` (M:N classes↔cohorts) ✓ correto
- `class_cohort_access.cohort_id` (access control M:N)
- `zoom_meetings.cohort_id` (FK direta)
- `student_nps.cohort_id` (snapshot cohort em NPS responses)

### Impacto

- **Story 22.6** ficou SUPERSEDED-BY-INVESTIGATION (sem trabalho técnico necessário)
- Sistema já está no estado "pós-cleanup" assumido pelo Discovery
- Queries usam `class_cohorts` JOIN consistentemente

### Possível origem do erro Discovery

Hipóteses:
1. Confusion com `class_cohort_access.cohort_id` (que sim existe e é uma layer adicional access control)
2. Migration `20260514120000_backfill_class_cohort_pairs.sql` (popula `class_cohorts` a partir de outras refs) pode ter sugerido erroneamente que veio de `classes.cohort_id`
3. Histórico antigo (pré-baseline) que foi limpo antes do discovery

### Correção sugerida no §3.3 original

Reformular para:

> ### 3.3 **Multi-Path Resolution Turma → Aula**
>
> Relação cohort ↔ class resolvida via:
> - `class_cohorts` (M:N principal — `class_id`, `cohort_id`, `weekday`)
> - `class_cohort_access` (access control — `class_id`, `cohort_id`, `access_until`)
> - `class_mentors.weekday` (calendário multi-day per memory `multi-day-classes-schema`)
>
> **Risco menor que previamente sugerido:** queries precisam apenas saber qual JOIN usar (`class_cohorts` pra match básico, `class_cohort_access` pra ACL). Não há "coluna deprecated" pra dropar.

---

## Próximas correções (a confirmar)

- §4.3 webhook precedence: confirmado correto (3 webhooks ativos sem coluna source) — Story 22.5 endereça
- §4.4 delivery routing: confirmado correto (notifications sem provider, dispatch-retry heurística) — Story 22.9 endereça
- §5 tabelas órfãs: ainda pendente investigação concreta — Story 22.8

---

## Change Log
- 2026-05-22 @aiox-master — Correção §3.3 criada após T1 grep audit confirmou `classes.cohort_id` não existe
