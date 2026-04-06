# Database Schema — lesson-pages

> **Gerado por:** @data-engineer (Brownfield Discovery — Fase 2)
> **Data:** 2026-04-01
> **Supabase Project:** gpufcipkajppykmnmdeh

---

## 1. Visao Geral

O banco possui **11+ tabelas** distribuidas em 4 schema files + 1 tabela (`classes`) referenciada mas sem schema file documentado.

### Schema Files

| Arquivo | Tabelas | Dominio |
|---------|---------|---------|
| `db/schema.sql` | attendance | Presenca de mentores |
| `db/students-schema.sql` | cohorts, students | Turmas e alunos |
| `db/notifications-schema.sql` | mentors, class_cohorts, class_mentors, notifications | Notificacoes WhatsApp |
| `db/zoom-schema.sql` | zoom_tokens, zoom_meetings, zoom_participants, student_nps | Zoom + NPS |
| **NAO EXISTE** | **classes** | **Aulas/encontros** |

---

## 2. Diagrama de Relacionamentos

```
                    ┌──────────────┐
                    │   cohorts    │
                    │──────────────│
                    │ id (PK)      │
                    │ name         │
                    │ whatsapp_jid │
                    │ zoom_link    │
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
     ┌────────▼──┐  ┌──────▼──────┐  ┌──▼───────────┐
     │ students  │  │class_cohorts│  │zoom_meetings │
     │───────────│  │─────────────│  │──────────────│
     │ cohort_id │→ │ cohort_id   │→ │ cohort_id    │→
     │ phone     │  │ class_id    │→ │ class_id     │→
     └─────┬─────┘  └──────┬──────┘  └──────┬───────┘
           │               │                │
           │        ┌──────▼──────┐  ┌──────▼──────────┐
           │        │  classes *  │  │zoom_participants │
           │        │─────────────│  │─────────────────│
           │        │ id (PK)     │  │ meeting_id      │→
           │        │ name        │  │ student_id      │→
           │        │ weekday     │  └─────────────────┘
           │        │ professor   │
           │        │ host        │
           │        └──────┬──────┘
           │               │
           │        ┌──────▼──────┐
           │        │class_mentors│
           │        │─────────────│
           │        │ class_id    │→
           │        │ mentor_id   │→
           │        └──────┬──────┘
           │               │
           │        ┌──────▼──────┐
           │        │  mentors    │
           │        │─────────────│
           │        │ id (PK)     │
           │        │ name        │
           │        │ phone       │
           │        │ role        │
           │        └──────┬──────┘
           │               │
           │        ┌──────▼──────────┐
           │        │ notifications   │
           │        │─────────────────│
           │        │ class_id        │→
           │        │ cohort_id       │→
           │        │ mentor_id       │→
           │        │ status (FSM)    │
           │        └─────────────────┘
           │
    ┌──────▼──────┐   ┌──────────────┐
    │ student_nps │   │ attendance   │
    │─────────────│   │──────────────│
    │ student_id  │→  │ lesson_date  │
    │ meeting_id  │→  │ teacher_name │
    │ score (0-10)│   │ status       │
    └─────────────┘   └──────────────┘

    ┌──────────────┐
    │ zoom_tokens  │
    │──────────────│
    │ mentor_id    │→
    │ zoom_email   │
    │ access_token │
    │ refresh_token│
    └──────────────┘

    * classes: tabela referenciada mas SEM schema file
```

---

## 3. Tabelas Detalhadas

### 3.1 attendance (Presenca de mentores)

| Coluna | Tipo | Constraints |
|--------|------|------------|
| id | UUID | PK, gen_random_uuid() |
| lesson_date | TEXT | NOT NULL |
| course | TEXT | NOT NULL |
| teacher_name | TEXT | NOT NULL |
| role | TEXT | DEFAULT 'Professor' |
| status | TEXT | CHECK (present/absent) |
| substitute_name | TEXT | nullable |
| notes | TEXT | nullable |
| recorded_by | UUID | FK → auth.users |
| recorded_at | TIMESTAMPTZ | DEFAULT now() |
| updated_at | TIMESTAMPTZ | DEFAULT now() |

**Indexes:** lesson_date, status, teacher_name
**RLS:** Read=authenticated, Write=admin (jwt metadata)
**Unique:** (lesson_date, course, teacher_name)

### 3.2 cohorts (Turmas)

| Coluna | Tipo | Constraints |
|--------|------|------------|
| id | UUID | PK |
| name | TEXT | UNIQUE |
| whatsapp_group_jid | TEXT | nullable |
| whatsapp_group_name | TEXT | nullable |
| zoom_link | TEXT | nullable |
| start_date | DATE | nullable |
| end_date | DATE | nullable |
| active | BOOLEAN | DEFAULT true |
| created_at | TIMESTAMPTZ | DEFAULT now() |

**Seed:** 5 cohorts (Fund T1/T2/T3, Adv T1/T2)

### 3.3 students (Alunos)

| Coluna | Tipo | Constraints |
|--------|------|------------|
| id | UUID | PK |
| name | TEXT | DEFAULT '' |
| phone | TEXT | NOT NULL |
| cohort_id | UUID | FK → cohorts (ON DELETE SET NULL) |
| is_mentor | BOOLEAN | DEFAULT false |
| active | BOOLEAN | DEFAULT true |
| created_at | TIMESTAMPTZ | DEFAULT now() |

**Unique:** (phone, cohort_id)
**Nota:** `name` tem DEFAULT '' — possivel que alunos sem nome existam

### 3.4 mentors (Mentores)

| Coluna | Tipo | Constraints |
|--------|------|------------|
| id | UUID | PK |
| name | TEXT | NOT NULL |
| phone | TEXT | UNIQUE |
| role | TEXT | CHECK (Professor/Host/Both) |
| active | BOOLEAN | DEFAULT true |
| created_at/updated_at | TIMESTAMPTZ | |

**Seed:** 14 mentores com telefones reais

### 3.5 classes (NAO DOCUMENTADA)

**ALERTA:** Esta tabela e referenciada por `class_cohorts`, `class_mentors`, `zoom_meetings`, e `notifications` mas NAO possui schema file. Campos inferidos do uso no codigo:
- id (UUID, PK)
- name (TEXT)
- weekday (INT)
- time_start (TEXT)
- time_end (TEXT)
- start_date (TEXT/DATE)
- end_date (TEXT/DATE)
- professor (TEXT, nullable)
- host (TEXT, nullable)
- color (TEXT, nullable)
- active (BOOLEAN)

### 3.6 class_cohorts (Bridge: Classes ↔ Cohorts)

| Coluna | Tipo | Constraints |
|--------|------|------------|
| id | UUID | PK |
| class_id | UUID | FK → classes (CASCADE) |
| cohort_id | UUID | FK → cohorts (CASCADE) |
| created_at | TIMESTAMPTZ | |

**Unique:** (class_id, cohort_id)

### 3.7 class_mentors (Bridge: Classes ↔ Mentors)

| Coluna | Tipo | Constraints |
|--------|------|------------|
| id | UUID | PK |
| class_id | UUID | FK → classes (CASCADE) |
| mentor_id | UUID | FK → mentors (CASCADE) |
| role | TEXT | CHECK (Professor/Host) |
| created_at | TIMESTAMPTZ | |

**Unique:** (class_id, mentor_id, role)

### 3.8 notifications (Notificacoes WhatsApp)

| Coluna | Tipo | Constraints |
|--------|------|------------|
| id | UUID | PK |
| type | TEXT | CHECK (5 tipos) |
| class_id, cohort_id, mentor_id | UUID | FKs nullable |
| target_type | TEXT | CHECK (group/individual/both) |
| target_phone, target_group_jid | TEXT | nullable |
| message_template, message_rendered | TEXT | |
| metadata | JSONB | DEFAULT '{}' |
| status | TEXT | CHECK (pending/processing/sent/partial/failed/cancelled) |
| error_message | TEXT | nullable |
| evolution_response | JSONB | nullable |
| sent_at | TIMESTAMPTZ | nullable |
| retry_count | INT | DEFAULT 0 |
| max_retries | INT | DEFAULT 3 |
| created_by | UUID | FK → auth.users |

**Status FSM:** pending → processing → sent/partial/failed/cancelled

### 3.9 zoom_tokens (OAuth tokens por mentor)

| Coluna | Tipo | Constraints |
|--------|------|------------|
| id | UUID | PK |
| mentor_id | UUID | FK → mentors (SET NULL) |
| zoom_email | TEXT | UNIQUE |
| access_token, refresh_token | TEXT | NOT NULL |
| expires_at | TIMESTAMPTZ | NOT NULL |
| scope | TEXT | nullable |
| active | BOOLEAN | DEFAULT true |

### 3.10 zoom_meetings (Reunioes Zoom)

| Coluna | Tipo | Constraints |
|--------|------|------------|
| id | UUID | PK |
| zoom_meeting_id | TEXT | NOT NULL |
| zoom_uuid | TEXT | UNIQUE |
| host_email, host_name, topic | TEXT | nullable |
| start_time, end_time | TIMESTAMPTZ | nullable |
| duration_minutes | INT | nullable |
| participants_count | INT | DEFAULT 0 |
| class_id | UUID | FK → classes (SET NULL) |
| cohort_id | UUID | FK → cohorts (SET NULL) |
| processed | BOOLEAN | DEFAULT false |

### 3.11 zoom_participants (Participantes)

| Coluna | Tipo | Constraints |
|--------|------|------------|
| id | UUID | PK |
| meeting_id | UUID | FK → zoom_meetings (CASCADE) |
| participant_name, participant_email | TEXT | nullable |
| join_time, leave_time | TIMESTAMPTZ | nullable |
| duration_minutes | INT | nullable |
| student_id | UUID | FK → students (SET NULL) |
| matched | BOOLEAN | DEFAULT false |

### 3.12 student_nps (NPS/CSAT)

| Coluna | Tipo | Constraints |
|--------|------|------------|
| id | UUID | PK |
| student_id | UUID | FK → students (SET NULL) |
| meeting_id | UUID | FK → zoom_meetings (SET NULL) |
| cohort_id | UUID | FK → cohorts (SET NULL) |
| score | INT | CHECK (0-10) |
| feedback | TEXT | nullable |
| tally_response_id, tally_form_id | TEXT | nullable |

---

## 4. RLS Policies

Todas as tabelas seguem o mesmo padrao:
- **Read:** `authenticated` → `true` (qualquer usuario autenticado le tudo)
- **Write:** `authenticated` → `(auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'`

**Excecao:** `notifications` tem read tambem restrito a admin.

---

## 5. Triggers

| Trigger | Tabela | Funcao |
|---------|--------|--------|
| attendance_updated_at | attendance | update_updated_at() |
| mentors_updated_at | mentors | update_updated_at() |
| notifications_updated_at | notifications | update_updated_at() |
| zoom_tokens_updated_at | zoom_tokens | update_updated_at() |
| zoom_meetings_updated_at | zoom_meetings | update_updated_at() |

---

*Documento gerado como parte do Brownfield Discovery — Fase 2*
