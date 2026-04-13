# Database Audit — lesson-pages (Brownfield Discovery Fase 2)

> **Data:** 2026-04-13
> **Agente:** @data-engineer (Dara)
> **Supabase:** gpufcipkajppykmnmdeh (Postgres 17.6)

---

## 1. Resumo do Schema

- **36 tabelas** + 1 view (`class_schedule_view`)
- **50 migrations** aplicadas (2026-04-02 a 2026-04-13)
- **~5.000 rows** no total (sistema pequeno/medio)
- **4 pg_cron jobs** ativos
- **1 pg_net trigger** (notify-whatsapp-on-pending)

---

## 2. Debito Tecnico do Banco

### D1 — Dualidade students vs student_imports (CRITICO)

| Aspecto | `students` (legado) | `student_imports` (CSV) |
|---------|--------------------|-----------------------|
| Rows | 777 | 490 |
| Criacao | Primeira tabela do sistema | Adicionada em 2026-04-11 |
| Funcao | FK target para zoom_participants, survey_links, student_attendance, etc. | Fonte da verdade para alunos pagantes |
| Problemas | Duplicatas, mentores misturados, alunos inativos | Nenhum FK aponta para ela |

**14 tabelas fazem FK para `students.id`:**
zoom_participants, survey_links, student_attendance, student_cohorts, student_nps, zoom_absence_alerts, zoom_link_audit, class_recording_notifications, zoom_chat_messages, engagement_daily_ranking, whatsapp_group_messages, survey_responses

**Nenhuma tabela faz FK para `student_imports.id`.**

**Impacto:** O frontend foi corrigido para ler de `student_imports`, mas o banco continua com `students` como entidade central. Qualquer nova feature que precise linkar dados a alunos enfrenta a pergunta: "qual tabela uso?"

**Recomendacao:** Migrar `student_imports` para ser a tabela primaria com FKs, ou criar uma view unificada que sirva como camada de abstracao.

### D2 — student_cohorts vs students.cohort_id (ALTO)

Coexistem dois modelos de matricula:
- `students.cohort_id` (FK direta — 1:1)
- `student_cohorts` (tabela de juncao — N:N, 869 rows)

Nao ha clareza sobre qual e o modelo oficial. O frontend usa `student_imports.cohort_id` (1:1).

### D3 — staff vs mentors (ALTO)

Duas tabelas quase identicas para a mesma entidade:

| Campo | `staff` | `mentors` |
|-------|---------|-----------|
| name | Sim | Sim |
| phone | Sim | Sim |
| email | Sim | Nao |
| category/role | category | role |
| aliases | Sim | Sim |
| active | Sim | Sim |
| Rows | 15 | 15 |

`mentors` e FK target de `class_mentors`, `zoom_tokens`, `mentor_attendance`, `notifications`.
`staff` nao e FK de nenhuma tabela — usada apenas para display e matching.

Aliases sao sincronizados manualmente no frontend (staff.save → mentors.update).

### D4 — Indexes Duplicados (BAIXO)

- `class_mentors`: `class_mentors_class_id_mentor_id_role_weekday_valid_from_key` e `class_mentors_cycle_unique` sao a mesma constraint
- `lesson_abstracts`: `idx_lesson_abstracts_slug` e `lesson_abstracts_slug_key` ambos indexam `slug`

### D5 — RLS Inconsistente (MEDIO)

| Tabela | Politica | Deveria ser |
|--------|----------|-------------|
| `student_imports` | authenticated full access | Admin-only (como students) |
| `wa_group_members` | authenticated full access | Admin-only |
| `zoom_chat_messages` | Service role all | Admin read + service write |
| `engagement_daily_ranking` | Service role all | Admin read + service write |

### D6 — Tabelas Orfas/Sem Uso (BAIXO)

6 tabelas com schema completo mas 0 rows em producao:
- `engagement_daily_ranking`
- `zoom_chat_messages`
- `whatsapp_group_messages`
- `class_materials`
- `class_recording_notifications`
- `mentor_attendance`

Funcoes e pg_cron jobs existem para popular essas tabelas, mas aparentemente nao estao rodando ou nao ha dados de entrada.

---

## 3. Foreign Keys — Grafo de Dependencias

```
cohorts ←── class_cohorts ──→ classes
   ↑              ↑
   ├── students    ├── class_mentors ──→ mentors
   ├── student_imports                      ↑
   ├── wa_group_members                     ├── zoom_tokens
   ├── notifications                        ├── mentor_attendance
   ├── surveys                              └── notifications
   ├── zoom_meetings
   └── student_nps
   
students ←── zoom_participants
         ←── survey_links
         ←── student_attendance
         ←── student_cohorts
         ←── student_nps
         ←── zoom_absence_alerts
         ←── zoom_link_audit
         ←── class_recording_notifications
         ←── zoom_chat_messages
         ←── engagement_daily_ranking
         ←── whatsapp_group_messages
         ←── survey_responses

surveys ←── survey_questions
        ←── survey_links ←── survey_responses ←── survey_answers
```

**Observacao critica:** `student_imports` nao tem nenhuma FK apontando para ela. Toda a rede de relacionamentos usa `students` como hub.

---

## 4. pg_cron Jobs

| Job | Schedule | Funcao |
|-----|----------|--------|
| Notificacoes agendadas | 11:00 UTC diario | Dispara notificacoes WA pendentes |
| Alertas de ausencia | 21:00 UTC diario | Verifica alunos com ausencias consecutivas |
| Zoom import queue | A cada 2 min | Processa fila de importacao de reunioes |
| Engagement ranking | 02:00 UTC diario | Calcula ranking de engajamento noturno |

---

## 5. Functions/Procedures no DB

- `dedup_zoom_participants()` — Remove duplicatas por meeting_id + nome
- `propagate_zoom_links()` — Propaga student_id entre participantes com mesmo nome
- `merge_students()` — Merge de alunos duplicados
- `normalize_student_phones()` — Normaliza telefones
- `get_present_students()` — Retorna alunos presentes por reuniao
- `auto_rematch_on_alias_update()` — Trigger: rematcha zoom ao atualizar aliases
- `nightly_engagement_ranking()` — Calcula ranking diario

---

*Documento gerado por @data-engineer (Dara) — Brownfield Discovery Fase 2*
