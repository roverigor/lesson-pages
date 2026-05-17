# P3 — NPS Post-Class Dispatcher (Zoom-End Trigger)

**Status:** Draft
**Date:** 2026-05-17
**Author:** @aiox-master autonomous
**Depends on:** P2 (anonymous group form — `survey/grupo/{token}` + `survey/aluno/{token}` landing pages, `nps_class_links` table, `submit-survey-group` edge function)
**Blocks deploy of:** itself + P2 production gate

---

## 1. Goals

Disparar pesquisa NPS automaticamente ao final de cada aula, sem ação manual.

- **Trigger primário:** evento Zoom `meeting.ended` (webhook já existe em `supabase/functions/zoom-webhook/index.ts`).
- **Dois canais simultâneos:**
  - **Grupo** (Evolution API): mensagem única no `whatsapp_group_jid` do cohort com link `survey/grupo/{token}` — modo anônimo, opção nome.
  - **DM individual** (Meta Cloud API template): mensagem por aluno presente com link `survey/aluno/{token}` — modo atribuído.
- **Cooldown e gate** para evitar spam quando aulas se sobrepõem ou aluno reaparece em múltiplas turmas.
- **Validação de presença** para PS Advanced/Fundamentals (baixa assistência crônica → não envia DM pra quem não estava na aula).
- **Visibilidade no dashboard** de envios (P4 já cobre via `dispatch_history_unified` VIEW — adicionar `nps_class_links` ali no deploy).

---

## 2. Non-Goals

- Pré-aula intent capture ("vai participar?" sim/não) — escopo do **P1 (futuro)**.
- Reenvio manual via UI — pode usar fluxo de retry existente do dashboard P4.
- Customizar conteúdo por aluno (segmentação avançada).
- Suporte a outros providers (apenas Meta + Evolution já configurados).

---

## 3. Trigger Architecture

### 3.1. Cadeia de gatilho

```
Zoom emit meeting.ended
       ↓
zoom-webhook (existe) → upsert zoom_host_sessions(released_at) + insert zoom_import_queue(process_after = now+5min)
       ↓
(consumer da queue importa participants → sync_staff_attendance_from_zoom)
       ↓
[NEW] após import bem-sucedido, RPC enqueue_nps_class_dispatch(class_id, cohort_id, session_date)
       ↓
[NEW] cron `dispatch-class-nps` (*/5 min) consome nps_class_dispatch_jobs pending
       ↓
       ├── Evolution group send → grupo do cohort (1 msg)
       └── Meta DM template send → cada aluno (attendance='present' OR cohort.dispatch_mode='all_enrolled')
```

### 3.2. Identificação da aula

Usa lookup já estabelecido em `sync_staff_attendance_from_zoom`:

1. `classes.zoom_meeting_id = rec.zoom_meeting_id` (direto — PS Advanced/Fundamentals)
2. `class_cohort_access` bridge via `zoom_meetings.cohort_id`
3. `zoom_meetings.class_id` (legacy)

Se class_id não resolve → job marcado `skipped_no_class`, alerta Slack.

### 3.3. Gating de envio

- **Mode DM:**
  - **Cohorts mentoradas T1..Tn:** envia pra todos `students WHERE cohort_id = X AND active AND NOT is_mentor` (não depende de presença — turma fechada).
  - **PS Advanced/Fundamentals:** envia somente pra `students` que aparecem em `attendance WHERE class_id=X AND lesson_date=session_date AND status IN ('present','partial')`.
- **Mode Group:** sempre envia se cohort tem `whatsapp_group_jid` ativo. Único link por grupo por aula (sem token individual).
- **Cooldown global:** se cohort recebeu NPS group/DM nas últimas 12h (configurável via `core_config.nps_cohort_cooldown_hours`), pula esta rodada e loga.
- **Feriados:** `is_brazilian_holiday(session_date)` → cancela job (existe).

---

## 4. Data Model

### 4.1. `nps_class_dispatch_jobs`

Queue de jobs a processar.

```sql
CREATE TABLE nps_class_dispatch_jobs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id        UUID REFERENCES classes(id),
  cohort_id       UUID REFERENCES cohorts(id) NOT NULL,
  session_date    DATE NOT NULL,
  zoom_meeting_id TEXT,                                    -- snapshot for audit
  status          TEXT NOT NULL DEFAULT 'pending',
                  -- pending | in_progress | sent | partial | skipped | failed
  scheduled_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),       -- now() + 5min by default
  started_at      TIMESTAMPTZ,
  finished_at     TIMESTAMPTZ,
  group_send_status TEXT,                                  -- sent | skipped | failed | not_applicable
  group_send_error  TEXT,
  group_evolution_message_id TEXT,
  dm_sent_count     INT DEFAULT 0,
  dm_failed_count   INT DEFAULT 0,
  dm_skipped_count  INT DEFAULT 0,
  total_eligible_students INT,
  error_detail    TEXT,
  variant_id      TEXT,                                    -- round-robin variant chosen
  metadata        JSONB DEFAULT '{}'::jsonb,
  created_at      TIMESTAMPTZ DEFAULT NOW(),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

-- idempotency: prevent duplicate dispatch for same class/session
CREATE UNIQUE INDEX uq_nps_job_per_class_session
  ON nps_class_dispatch_jobs (cohort_id, COALESCE(class_id, '00000000-0000-0000-0000-000000000000'::uuid), session_date)
  WHERE status NOT IN ('skipped','failed');

CREATE INDEX idx_nps_job_pending_due
  ON nps_class_dispatch_jobs (status, scheduled_at)
  WHERE status = 'pending';
```

### 4.2. Reuse `nps_class_links` (já criado em P2)

P2 já tem:
- `nps_class_links(id, token, mode, cohort_id, class_id, session_date, response_count, ...)`
- `class_nps_responses(token_id, score, comment, name_optional, ...)`

P3 só **insere** rows aqui — mode='group' (1 por job) e mode='dm' (N por job).

### 4.3. Message variants table (round-robin)

```sql
CREATE TABLE nps_message_variants (
  id              TEXT PRIMARY KEY,                         -- e.g. 'group_v1', 'dm_v1'
  channel         TEXT NOT NULL CHECK (channel IN ('group','dm')),
  body_template   TEXT NOT NULL,                            -- {{class_name}}, {{cohort_name}}, {{link}}
  meta_template_name TEXT,                                  -- only for dm
  active          BOOLEAN DEFAULT true,
  weight          INT DEFAULT 1,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE nps_variant_rotation_state (
  channel         TEXT PRIMARY KEY,
  last_variant_id TEXT REFERENCES nps_message_variants(id),
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);
```

Seed inicial: 3 variants group + 3 variants dm (mensagens diferentes mantendo intenção).

### 4.4. Config flag

`core_config` table (já existe?): `nps_cohort_cooldown_hours INT DEFAULT 12`, `nps_dispatch_enabled BOOLEAN DEFAULT false` (gate humano — default OFF, ativar manualmente).

Se não existir `core_config`, criar mini-tabela `nps_dispatch_config(key, value)`.

---

## 5. Components

### 5.1. RPC `enqueue_nps_class_dispatch(p_class_id, p_cohort_id, p_session_date)`

- Resolve cohort_id se não passado (via `class_cohort_access`).
- Verifica feriado.
- Verifica cooldown.
- Verifica `nps_dispatch_enabled = true`.
- Insere job com `scheduled_at = NOW() + INTERVAL '5 min'` (configurable).
- Idempotente via UNIQUE constraint.
- Retorna `{ job_id, enqueued: bool, reason: text }`.

### 5.2. Edge function `dispatch-class-nps`

Análoga a `dispatch-class-reminders`:

```
POST /dispatch-class-nps
  body: {} | { job_id, dry_run }
  - busca jobs pending WHERE scheduled_at <= NOW (limit 10 per run)
  - para cada job:
    1. Lock via UPDATE status='in_progress', started_at=NOW()
    2. Resolve students elegíveis (DM)
    3. Resolve cohort.whatsapp_group_jid (group)
    4. Escolhe variant via round-robin (RPC)
    5. Gera tokens (nps_class_links):
       - 1 mode='group' (sem student_id)
       - N mode='dm' (student_id + cohort_id)
    6. Envia group via Evolution
    7. Envia DM em loop com 10s throttle via Meta template
    8. Atualiza job counts + status final (sent | partial | failed)
    9. Posta resumo Slack interno (#dev-alerts)
```

Throttling: 10s entre DMs (igual `dispatch-survey` atual).
Limite por run: 50 DMs por execução pra não ultrapassar limites Meta. Se job tem >50, continua no próximo tick (`status='in_progress'` permanece, sends já enviados marcados `sent` em `nps_class_links`, retomada via `WHERE send_status='pending'`).

### 5.3. Hook no zoom-webhook ou consumer da queue

**Opção A (preferida):** após `zoom_import_queue` consumer rodar `sync_staff_attendance_from_zoom` com sucesso, ele mesmo chama `enqueue_nps_class_dispatch`.

**Opção B (fallback):** trigger SQL `AFTER UPDATE OF processed ON zoom_meetings WHEN OLD.processed=false AND NEW.processed=true` → chama RPC enqueue.

Preferência por **A** pra ter controle explícito + audit trail.

### 5.4. Cron

```sql
SELECT cron.schedule(
  'dispatch-class-nps-tick',
  '*/5 * * * *',
  $$
  SELECT net.http_post(
    url := 'https://gpufcipkajppykmnmdeh.functions.supabase.co/dispatch-class-nps',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.service_role_key', true)
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 60000
  );
  $$
);
```

### 5.5. Admin UI hooks

- **Dashboard P4** (`admin/envios`): adicionar `nps_class_links` ao `dispatch_history_unified` VIEW (já está incluída pela criação P2 — confirmar e mostrar source='nps_class_link' no filter).
- **Story painel:** página `admin/nps-monitor/` (out of scope desta spec, mas placeholder em runbook): tabela de jobs com status, botão "abort", "force-now", "skip cohort".

---

## 6. Security & Safety

### 6.1. External comms gate (CLAUDE.md)

**Default OFF.** Migration cria `nps_dispatch_enabled = false`. Ativação requer:
1. Review humano do template Meta aprovado (precisa estar em `meta_templates WHERE status='APPROVED'`).
2. Toggle manual via SQL ou UI: `UPDATE nps_dispatch_config SET value='true' WHERE key='nps_dispatch_enabled'`.
3. Smoke test em cohort de teste com 1-2 alunos.

### 6.2. Rate limiting

- 10s entre DMs (Meta best practice).
- Max 50 DMs por run (~8min de execução).
- Cron tick a cada 5min — se job tem 200 alunos, leva ~3-4 ticks pra completar.

### 6.3. Audit

`nps_class_dispatch_jobs` mantém histórico completo. `dispatch_history_unified` VIEW já agrega.

Slack alert post-job: `dispatched: N | failed: M | cohort: X | class: Y`.

### 6.4. PII em logs

Não logar phone numbers em texto puro. Hash SHA-256 quando necessário (já padrão em P2).

---

## 7. Failure Modes & Recovery

| Falha | Comportamento |
|-------|---------------|
| Cohort sem `whatsapp_group_jid` | `group_send_status='not_applicable'`, segue com DM |
| Aluno sem phone | conta como `dm_skipped`, segue |
| Meta API 4xx (template não aprovado) | `dm_failed_count++`, error_detail registrado, status='partial' se algum DM passou |
| Meta API 5xx | retry automático no próximo tick (mantém `pending` se ainda não iniciado, ou cria nova linha pendente em `nps_class_links` mantendo lógica resume) |
| Evolution API down | `group_send_status='failed'`, DMs continuam |
| Job perdido (zoom_import_queue não chegou) | manual `SELECT enqueue_nps_class_dispatch(...)` via SQL admin |
| Double dispatch | UNIQUE constraint bloqueia segunda chamada |

Retry usa flow P4 existente: dashboard mostra job failed, admin clica "retry" → reseta `status='pending'` via RPC `retry_dispatch('nps_class_dispatch', job_id, token)`.

---

## 8. Open Questions

1. **Múltiplas aulas no mesmo dia pro mesmo cohort?** (ex: PS sub-grupos) → unique constraint atual usa `(cohort, class_id, date)` então cada `class_id` distinto gera job próprio. OK.
2. **Aluno em N cohorts (PS bug conhecido):** se ele estava presente em PS aula de hoje, recebe DM 1x via `class_cohort_access` lookup. Garantir DISTINCT no SELECT.
3. **Variant assignment determinístico?** Round-robin global (state em `nps_variant_rotation_state`) vs random com seed=`job_id`. Spec assume round-robin.
4. **Survey existente legacy:** `surveys` + `survey_links` continuam pra dispatches manuais (admin envia survey nominada). P3 não substitui — é fluxo paralelo automatizado.

---

## 9. Acceptance Criteria

- [ ] AC1: Migrations idempotentes criam `nps_class_dispatch_jobs`, `nps_message_variants`, `nps_variant_rotation_state`, config flag.
- [ ] AC2: RPC `enqueue_nps_class_dispatch` insere job com `scheduled_at=NOW()+5min`, respeita cooldown e feriado, retorna {job_id, enqueued, reason}.
- [ ] AC3: Edge function `dispatch-class-nps` consome jobs `pending` com `scheduled_at<=NOW`, gera tokens, envia group + DM, atualiza counts.
- [ ] AC4: Flag `nps_dispatch_enabled=false` por default — function retorna no-op.
- [ ] AC5: Hook em consumer de `zoom_import_queue` chama enqueue após `sync_staff_attendance_from_zoom` OK.
- [ ] AC6: Cron `*/5 min` configurado, gated por flag.
- [ ] AC7: Dashboard P4 mostra dispatches com source='nps_class_link'.
- [ ] AC8: Slack alert resumo por job.
- [ ] AC9: Round-robin variant rotation funcional.
- [ ] AC10: Idempotência via UNIQUE constraint validada.

---

## 10. Implementation Estimate

8 tasks, ~3-4h focused work (file-only). Deploy gate humano obrigatório.
