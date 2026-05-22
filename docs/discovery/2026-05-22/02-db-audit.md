# DB Audit — painel.academialendaria.ai
> Discovery Parte 1 — 2026-05-22 — by @data-engineer (Dara)

## 1. Stats Gerais
- **Total migrations:** 200
- **Total tabelas criadas:** 84
- **Com RLS habilitado:** 45 tabelas (53%)
- **SEM RLS:** 39 tabelas (47%)
- **Última migration:** `20260522010300_nps_results_by_survey_refactor.sql`
- **Período coberto:** ~50 dias (2026-04-02 a 2026-05-22)

---

## 2. Domínios de Tabelas

| Domínio | Qtd | Tabelas Principais | Propósito |
|---------|-----|------|----------|
| **Class/Aula** | 7 | `classes`, `class_cohorts`, `class_mentors`, `class_nps_responses`, `class_reminder_*` (3), `class_recording_*` (2) | Gestão de aulas, lembretes, gravações Zoom |
| **NPS/Survey** | 5+13 | `nps_class_*`, `nps_message_variants`, `nps_dispatch_*`, `survey_*` (5), `class_nps_responses` | Pesquisa de satisfação + dispatch de links |
| **Student/Aluno** | 4 | `students`, `student_imports`, `student_cohorts`, `student_attendance`, `student_journey_states` | Registro, importação e tracking de alunos |
| **Cohort/Turma** | 2 | `cohorts`, `cohort_sessions` | Agrupamento de aulas por período |
| **Zoom** | 4 | `zoom_meetings`, `zoom_participants`, `zoom_tokens`, `zoom_chat_messages`, `zoom_host_sessions` | Integração Zoom |
| **WhatsApp** | 2 | `wa_group_members`, `whatsapp_group_messages` | Integração com grupos WhatsApp |
| **AC (ActiveCampaign)** | 3 | `ac_purchase_events`, `ac_dispatch_callbacks`, `ac_product_mappings` | Webhook de compras + sync AC |
| **Engagement/Dispatch** | 5 | `engagement_daily_ranking`, `engagement_feedback`, `engagement_signals`, `dispatch_link_opens`, `dispatch_retry_audit` | Tracking de engagement + delivery logs |
| **Journey/Automação** | 4 | `journeys`, `journey_executions`, `journey_pending_approvals`, `automation_rules`, `automation_runs` | Automações de jornada do aluno |
| **PS-RSVP** | 3 | `ps_rsvp_links`, `ps_rsvp_responses`, `ps_rsvp_variants` | Sistema de confirmação de presença |

---

## 3. 🔴 Overlaps de Identidade Detectados

### 3.1 **CRÍTICO: Triple-identity de Aluno**

Três tabelas diferentes representam "pessoa que consome aula":

| Tabela | Schema | Source | Ciclo de vida | Phone key |
|--------|--------|--------|---------------|-----------|
| `students` | `id`, `phone`, `cohort_id`, `is_mentor`, `active` | CSV manual + manual entries | Criação manual, sem soft-delete | Único por `(phone, cohort_id)` |
| `student_imports` | `id`, `cohort_id`, `phone`, `email`, `product`, `source='csv/ac'` | AC webhook via `ac_purchase_events` | Nunca deletado (audit trail) | Sem constraint de unicidade |
| `wa_group_members` | `id`, `cohort_id`, `phone`, `wa_name` | Sync automático de grupos WA (cron) | Soft-update via `synced_at` | Único por `(cohort_id, phone)` |

**Problema:** Aluno chega por 3 caminhos, nenhum garantidamente sincronizado:
- CSV → `students` (criação manual via admin)
- AC compra → `student_imports` → precisa manual merge para `students`
- WA group → `wa_group_members` → qual `student_id` usar?

**Risco:** Mesmo telefone em 3 tabelas ≠ garantia de FK. `dispatch_link_opens`, `nps_class_links` não sabem qual `student_id` usar.

**Source of truth atual:** Nenhum. `students` é "primary", mas `student_imports` é "audit log" do AC e `wa_group_members` é "espelho do WhatsApp". Sem reconciliação automática.

---

### 3.2 **CRÍTICO: Phone Format Inconsistente**

| Tabela | Formato | Normalização |
|--------|---------|--------------|
| `students.phone` | Não especificado | `normalize_student_phones()` RPC (20260409050000), mas sem trigger automático |
| `student_imports.phone` | JSONB bruto de AC | Sem normalização; pode ter "+55", "0x", espaços |
| `wa_group_members.phone` | Format WA API | Presumivelmente normalizado, mas não validado |
| `zoom_participants.phone` | Campo opcional de sync Zoom | Raro, não confiável |

**Risco:** `.phone = '+5511987654321'` em uma tabela ≠ `.phone = '11987654321'` em outra. JOINs por phone falham silenciosamente.

---

### 3.3 **CRÍTICO: Dual Identity Turma (Cohort vs Class)**

| Entidade | Tabelas | Como diferem |
|----------|---------|-------------|
| **Turma (temporada)** | `cohorts` | Período (ex: "T4-2026"), agrupa múltiplas aulas |
| **Aula (sessão)** | `classes` | Uma data/horário específico, sem FK obrigatório para cohort |
| **Join table** | `class_cohorts` | Many-to-many, permite 1 aula em múltiplas turmas |

**Problema:** `class_cohorts` criada tardiamente (20260516). Antes disso, `classes.cohort_id` (agora deprecated). Queries legado ainda usam ambos.

**Exemplo de dívida:** `public.get_weekly_attendance()` referencia `p_cohort_id` → precisa saber se busca aulas via `class_cohorts` ou `classes.cohort_id`.

---

## 4. 🔴 Paths Múltiplos pra Mesma Entidade

### Caminho 1: Aluno via CSV Manual
```
ADMIN UPLOAD CSV → students (direct INSERT)
                 → student_audit_log (trigger)
```

### Caminho 2: Aluno via AC Compra
```
AC webhook (ac_purchase_events)
  → payload JSONB (name, email, phone, product)
  → student_imports (audit record)
  → ??? (alguém precisa rodar merge_students(primary_id, [secondary_ids]))
  → students (upsert final)
```

### Caminho 3: Aluno via WhatsApp Group
```
WA group sync (cron 20260514000020)
  → wa_group_members (synced_at)
  → ??? (qual student_id é este?)
  → nenhuma FK obrigatória para students
```

### Caminho 4: "Mentor" (Staff) via Zoom
```
Zoom class attendance
  → zoom_participants (participant_name, email, phone)
  → staff table
  → mentors table (unificado com staff em 20260417130000)
  → class_mentors (FK)
```

**Risco:** Cada caminho gera registros órfãos. `find_duplicate_students()` RPC detecta, mas merge é manual via admin.

---

## 5. Tabelas Órfãs ou Suspeitas

| Tabela | Última escrita provável | Status | Suspeita |
|--------|--------|--------|----------|
| `oauth_states` | Cleanup cron (20260410100000) | Housekeeping OK | Não |
| `pending_student_assignments` | ? | Nunca mencionada em migrations recentes | **ÓRFÃ?** |
| `lesson_abstracts` | 20260407020000 seed | Stale | Read-only? |
| `notification_queue` | 20260417110000 criação | Nenhuma query visível | **ÓRFÃ?** |
| `meta_templates`, `meta_pricing` | 20260516020000 schema | Part of dispatch infra? | Pouco clara |
| `alert_history` | ? | Não aparece em migrations recentes | **ÓRFÃ?** |
| `automation_runs` | 20260414010000 | Pode estar orphaned vs `journey_executions` | Overlap? |

---

## 6. RLS Gaps — 39 Tabelas SEM RLS

**Tabelas críticas SEM RLS:**
- `ac_purchase_events` — lê compras AC (não contém dados de usuário direto, mas sensível)
- `ac_dispatch_callbacks` — webhooks internos (OK sem RLS)
- `class_cohort_access`, `class_cohorts`, `class_mentors` — relações públicas? (⚠️ talvez deveria limitar por mentor login)
- `classes` — podem ser privadas por curso (⚠️)
- `cohorts` — contexto de turma (⚠️)
- `attendance`, `mentor_attendance` — relatórios sensíveis (🔴 **deveria ter RLS**)
- `pending_student_assignments` — dados de aluno (🔴)
- `ps_rsvp_links`, `ps_rsvp_responses`, `ps_rsvp_variants` — rastreamento (⚠️ tem RLS em 20260522010000, mas recente)
- `public.class_nps_responses` — respostas de NPS (⚠️ dados de aluno)
- `public.class_reminder_*` (3 tabelas) — scheduling (⚠️)
- `public.cohort_sessions` — tem RLS recentemente (20260522010000)

**Soft-delete inconsistência:**
- `cohort_sessions` usa `deleted_at` (TIMESTAMPTZ)
- Maioria usa `active` BOOLEAN
- Alguns não têm nenhum marker de deleção (hard delete)

---

## 7. Recomendações Top 5 de Consolidação DB

### #1 **MERGE: students + student_imports + wa_group_members**
**Ação:** Criar tabela unificada `person` ou `student_canonical`:
- PK: `id` (UUID)
- Denormalizar: `phone` (normalized E.164)
- FK: `cohort_id`, `source` enum ('csv', 'ac', 'wa', 'zoom')
- Soft-delete: `deleted_at`
- Auditoria: `created_via`, `last_synced_at`

**Migração:**
- `students` → `person` (source='csv')
- `student_imports` → `person_audit` (nova tabela, referência imutável)
- `wa_group_members` → `person` (source='wa', sync trigger)

**Timeline:** 2-3 sprints (data migration + trigger testing)

---

### #2 **FIX: Phone Normalization Obrigatória**
**Ação:** 
- Trigger on INSERT/UPDATE em `students`, `student_imports`, `wa_group_members`
- UDF `normalize_phone_e164()` (já existe, expand)
- Constraint UNIQUE em phone normalizado (não `phone` bruto)

**Migrations needed:**
- Backfill existing phones via RPC
- Add constraint `UNIQUE(normalized_phone, cohort_id)`
- Update FKs em `dispatch_link_opens`, `nps_class_links` para usar `normalized_phone`

---

### #3 **CONSOLIDATE: class_cohorts + classes.cohort_id**
**Ação:**
- Deprecate `classes.cohort_id` (add deprecation comment)
- Migrate existing data para `class_cohorts` (many-to-many)
- Update queries em `get_weekly_attendance()`, `get_present_students()` para usar `class_cohorts`
- Add RLS em `class_cohorts` (por mentor)

---

### #4 **DROP: Tabelas Órfãs**
**Ação:**
- `pending_student_assignments` — verificar dependências, DROP se unused
- `notification_queue` — aparenta ser backup legacy de `notification_schedules`. Unificar.
- `alert_history` — verificar com product. Se unused, arquivar/drop.

**Risk:** Baixo se migrations descrevem "drop", alto se apenas abanodadas.

---

### #5 **RLS Enforcement: Add RLS Missing**
**Prioridade:**
1. `attendance` / `mentor_attendance` — add RLS por `cohort_id` (mentor só vê suas turmas)
2. `classes` — add RLS por `cohort_id`
3. `class_nps_responses` — add RLS por responder autenticado
4. `ps_rsvp_*` — add RLS completar (iniciado em 20260522)

---

## 8. Open Questions

1. **Source of truth de aluno:** Qual é canonical `student_id`?
   - `students.id` (CSV)?
   - Precisamos de surrogate key em `student_imports` → `students`?

2. **Phone normalization:** E.164 ou outro formato?
   - Região assume BR (+55)?
   - Precisa suportar internacional?

3. **AC sync:** Frequência e idempotência?
   - `ac_purchase_events` semanal? Diário?
   - Há garantia de não duplicate em `student_imports`?

4. **WA group:** Qual nome de campo usar?
   - `wa_group_members.wa_name` é "display name" (pode mudar)?
   - Matching logic com `students.name`?

5. **Migrations futuras:** Policy para migrations?
   - Sempre FKs? Sempre RLS?
   - Naming convention para tables (public.* vs unqualified)?

6. **Orphaned tables:** Confirmar status:
   - Quem usa `pending_student_assignments`?
   - É `notification_queue` dead code?

---

**Status:** ⚠️ Sistema operacional, mas com dívida técnica alta em identidade de aluno. Recomenda-se iniciar #1 (merge tabelas) em próximo epic.
