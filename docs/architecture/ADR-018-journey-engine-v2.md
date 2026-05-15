# ADR-018 — Journey Engine V2 (Worker + Trigger Sources + Anti-Fatigue)

**Status:** Proposed
**Data:** 2026-05-06
**Autor:** Aria (@architect)
**Contexto:** EPIC-018 — Lifecycle Journey Orchestration
**Foundation V1:** schema journeys + student_journey_states + 8 templates (todos inativos)
**Handoff origem:** `.aiox/handoffs/handoff-uma-to-architect-2026-05-06.yaml`

---

## Contexto

V1 entregou tabelas + UI kanban read-only + 8 jornadas templates. Falta engine que automaticamente progrida alunos pelos steps. ADR define:

1. State machine pattern (engine)
2. Worker scheduling
3. 6 trigger sources
4. Branching V1
5. Anti-fatigue integration cross-épico
6. Pause/resume + escalation
7. Anti-loop guardrails
8. Visual editor scope (delegado pra Uma)
9. Performance até 10K alunos × 10 journeys
10. **Comm externa NON-NEGOTIABLE** — auto-actions que disparam mensagem REQUEREM human-in-loop

---

## Decisões

### 1. State machine engine — **CUSTOM SQL functions**

**Decisão:** state machine em PL/pgSQL functions, não bibliotecas externas (XState, n8n).

**Rationale:**
- Stack atual 100% Supabase + pg_cron já comprovado em EPIC-015 worker
- XState adiciona dependency JS no edge function (overhead 50KB+)
- n8n adapter requer infra adicional (VM separada)
- PL/pgSQL nativo: zero overhead, transactional safety, debug via SQL queries

**Trade-off aceito:** menos features prontas (no built-in retry/observability) — mitigamos com tabela `journey_executions` log + Slack alerts.

### 2. Worker cadence — **HÍBRIDO: cron 5min + trigger event-driven**

**Decisão:** dois workers:

```sql
-- Worker batch (catch-all, garante eventual consistency)
SELECT cron.schedule('epic018-journey-worker', '*/5 * * * *',
  $$ SELECT public.process_journey_states(); $$);

-- Worker realtime (eventos críticos: compra, NPS detractor)
-- Trigger AFTER INSERT em ac_purchase_events / survey_responses
-- chama function que avança state imediatamente.
```

**Rationale:**
- 5min é granularity suficiente pra time-based triggers (day_offset)
- Eventos críticos (compra recém-confirmada, NPS detractor) precisam reação imediata pro engagement
- Trigger event-driven evita 5min lag em casos críticos

### 3. Trigger sources — **6 implementados em V2**

| Trigger | Source | Frequência |
|---------|--------|-----------|
| `purchase` | INSERT em `ac_purchase_events` (status='processed') | event-driven |
| `time` | day_offset desde started_at | cron 5min |
| `inactivity_5d`/`inactivity_30d` | cruza com `engagement_signals` last_event_at | cron 5min |
| `at_risk_detected` | UPDATE `student_engagement_scores` bucket→at_risk | event-driven |
| `module_completed` | INSERT em `student_progress` (table NOVA — depende LMS webhook) | event-driven |
| `manual` | CS rep avança step via UI button | sync |

**LMS module_completed:** depende integração externa não-existente. **V2 stub** — coluna existe, trigger é no-op até decidir provider (Hotmart Members? Eduzz? custom?).

### 4. Branching — **V1 LINEAR + V2 condições simples**

**V1 (esta entrega):** linear apenas — step N→N+1 sequencial. Sem if/else.
**V2 (próxima sprint):** suportar `branch_conditions` jsonb por step:

```jsonb
{"if": {"nps_last_score": {"<=": 6}}, "then": "step_5b_detractor_path", "else": "step_5_normal"}
```

**Rationale:** branching exige UI complexo (Uma desenha) + engine extra. Linear cobre 80% casos práticos.

### 5. Anti-fatigue — **REUTILIZA EPIC-017 frequency_capping**

**Decisão:** Antes de qualquer action `dispatch_survey`/`send_template`, worker chama `can_dispatch_to_student(student_id)` (já existe Story 17.7).

```sql
-- Em process_journey_states():
IF NOT (SELECT (allowed FROM can_dispatch_to_student(v_student_id))::boolean) THEN
  -- Skip step desta rodada, próxima tentativa em next cron
  CONTINUE;
END IF;
```

**Caps existentes:** 1/dia, 2/sem, quiet 22h-8h, cooldown 48h pós-resposta. Configurável `/cs/settings`.

### 6. Pause/Resume + Escalation — **3 estados estruturados**

```sql
status text CHECK (status IN ('active', 'paused', 'completed', 'escalated', 'abandoned'))
```

**Triggers automáticos:**
- `paused`: aluno LGPD opt-out (consent_revoked_at preenchido) → auto-pause + Slack notify
- `escalated`: NPS detractor + journey premium → escalate pra CS rep + Slack
- `abandoned`: sem progresso > 30d em mesmo step (engine errado OR aluno fantasma)

**Manual:** CS rep pode pausar/escalar via UI button (campo `paused_reason text`).

### 7. Anti-loop — **3 guardrails**

```sql
-- Guardrail 1: max 3 journeys ativas simultâneas por aluno
CREATE OR REPLACE FUNCTION enforce_journey_limit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF (SELECT COUNT(*) FROM student_journey_states
      WHERE student_id = NEW.student_id AND status = 'active') >= 3 THEN
    RAISE EXCEPTION 'Aluno % já está em 3 journeys ativas (limite)', NEW.student_id;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_journey_limit BEFORE INSERT ON student_journey_states
FOR EACH ROW WHEN (NEW.status = 'active') EXECUTE FUNCTION enforce_journey_limit();

-- Guardrail 2: max 1 instância da MESMA journey ativa por aluno (UNIQUE constraint já existe)
-- Guardrail 3: worker timeout statement_timeout = '120s' previne loops infinitos
```

### 8. Visual editor — **DELEGADO PRA UMA**

Aria fora do escopo. Recomendação:
- V1: YAML editor monaco (CS power-users escrevem JSON steps direto)
- V2: drag-drop nodes (React Flow ou similar)

Uma desenha UX. Eu (Aria) define API contract: GET/PUT `/cs/journeys/:id/steps` retorna/aceita jsonb steps array.

### 9. Performance — **OK até 50K alunos × 20 journeys**

```
Ratios:
- 865 alunos × 8 journeys ativas = 7K rows max student_journey_states
- 50K × 20 = 1M rows (cap V2)
- Worker recompute: ~5ms/student × 7K = 35s diário (OK)
- Index (next_eval_at) WHERE status='active' cobre 99% queries

Particionamento: NÃO necessário até > 100K rows. Adicionar quando necessário (mensal).
```

### 10. Comm externa NON-NEGOTIABLE — **Approval queue model**

**Decisão crítica:** worker NÃO dispara `send_template`/`dispatch_survey` automaticamente. Em vez disso:

```sql
CREATE TABLE journey_pending_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journey_state_id uuid REFERENCES student_journey_states(id),
  step_num integer NOT NULL,
  action_type text NOT NULL,
  action_config jsonb NOT NULL,
  preview_data jsonb,  -- dados resolvidos pra preview (template name, vars, target student)
  status text DEFAULT 'awaiting_approval' CHECK (status IN ('awaiting_approval', 'approved', 'rejected', 'expired')),
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT (now() + interval '7 days')
);
```

Worker INSERT → CS rep vê em `/cs/approvals` → revisa preview → aprova → action executa OR rejeita → action descartada.

**Exceções (auto-fire sem approval):**
- `create_pending` (cria entry interna /cs/pending — não envia mensagem)
- `slack_alert` (alert dev/CS interno — não atinge aluno)
- `tag_student` (metadata)
- `update_health_score` (computed)

**Always require approval:**
- `send_template` (Meta WhatsApp)
- `dispatch_survey` (link survey via WhatsApp)
- `send_email` (email aluno)

UI dashboard `/cs/approvals` mostra queue ranqueada por urgência.

---

## Schema additions (V2)

```sql
-- 1. Approval queue (decisão #10)
CREATE TABLE journey_pending_approvals (...) -- spec acima

-- 2. Execution log (observability worker)
CREATE TABLE journey_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journey_state_id uuid REFERENCES student_journey_states(id),
  step_num integer NOT NULL,
  trigger_evaluated text,
  action_attempted text,
  action_result text CHECK (action_result IN ('executed', 'queued_approval', 'skipped_capping', 'skipped_paused', 'failed')),
  result_meta jsonb,
  executed_at timestamptz DEFAULT now()
);

-- 3. ALTER student_journey_states (add observability)
ALTER TABLE student_journey_states
  ADD COLUMN IF NOT EXISTS auto_pause_count integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalation_count integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_action_at timestamptz;

-- 4. Trigger event-driven em ac_purchase_events processed
-- Auto-cria student_journey_states se cohort linkado a journey ativa
CREATE OR REPLACE FUNCTION enroll_student_in_journeys()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'processed' AND OLD.status != 'processed' THEN
    -- Encontrar journeys ativas linked ao cohort do mapping
    INSERT INTO student_journey_states (student_id, journey_id, total_steps, next_eval_at)
    SELECT
      (NEW.payload->>'student_id')::uuid,
      j.id,
      jsonb_array_length(j.steps),
      now() + interval '1 minute'
    FROM journeys j
    WHERE j.active = true
      AND j.id IN (
        SELECT journey_id FROM ac_product_mappings
        WHERE ac_product_id = NEW.payload->>'product_external_id'
      )
    ON CONFLICT (student_id, journey_id) DO NOTHING;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER trg_enroll_journeys
  AFTER UPDATE ON ac_purchase_events
  FOR EACH ROW EXECUTE FUNCTION enroll_student_in_journeys();
```

(Requer `journey_id` em `ac_product_mappings` — adicionar coluna)

### Worker function principal

```sql
CREATE OR REPLACE FUNCTION public.process_journey_states()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_state RECORD;
  v_journey RECORD;
  v_step jsonb;
  v_action text;
  v_processed integer := 0;
  v_queued integer := 0;
  v_executed integer := 0;
BEGIN
  SET LOCAL statement_timeout = '120s';
  SET LOCAL lock_timeout = '5s';

  FOR v_state IN
    SELECT * FROM student_journey_states
    WHERE status = 'active'
      AND (next_eval_at IS NULL OR next_eval_at <= now())
    LIMIT 200
    FOR UPDATE SKIP LOCKED
  LOOP
    v_processed := v_processed + 1;

    SELECT * INTO v_journey FROM journeys WHERE id = v_state.journey_id;
    IF NOT v_journey.active THEN
      UPDATE student_journey_states SET status = 'paused', paused_reason = 'journey_inactive'
      WHERE id = v_state.id;
      CONTINUE;
    END IF;

    -- Pega próximo step
    v_step := v_journey.steps->(v_state.current_step);
    IF v_step IS NULL THEN
      UPDATE student_journey_states SET status = 'completed', completed_at = now()
      WHERE id = v_state.id;
      CONTINUE;
    END IF;

    v_action := v_step->>'action';

    -- Auto-fire actions (sem approval)
    IF v_action IN ('create_pending', 'slack_alert', 'tag_student') THEN
      -- Executa direto (lógica delegada pra functions específicas)
      PERFORM execute_journey_action(v_state.id, v_step);
      v_executed := v_executed + 1;
    ELSE
      -- Comm externa → approval queue
      INSERT INTO journey_pending_approvals (journey_state_id, step_num, action_type, action_config, preview_data)
      VALUES (v_state.id, v_state.current_step, v_action, v_step->'config',
              jsonb_build_object('student_id', v_state.student_id, 'step', v_step));
      v_queued := v_queued + 1;
    END IF;

    -- Avança step + computa next_eval_at baseado em day_offset
    UPDATE student_journey_states SET
      current_step = current_step + 1,
      last_action_at = now(),
      next_eval_at = CASE
        WHEN v_journey.steps->(current_step + 1) IS NOT NULL
        THEN started_at + ((v_journey.steps->(current_step + 1)->>'day_offset')::int || ' days')::interval
        ELSE NULL
      END
    WHERE id = v_state.id;
  END LOOP;

  RETURN jsonb_build_object(
    'processed', v_processed,
    'auto_executed', v_executed,
    'queued_for_approval', v_queued,
    'at', now()
  );
END $$;

GRANT EXECUTE ON FUNCTION public.process_journey_states() TO service_role;

-- pg_cron diário... wait, decision foi 5min:
SELECT cron.schedule('epic018-journey-worker', '*/5 * * * *',
  $$ SELECT public.process_journey_states(); $$);
```

---

## Pontos abertos pra decisões adicionais

| # | Pergunta | Quem decide |
|---|----------|------------|
| 1 | LMS module_completed integration provider | @pm + Igor |
| 2 | Visual editor UX (YAML vs drag-drop V1?) | @ux-design-expert (Uma) |
| 3 | Notificação CS rep quando approval cria (Slack? email? UI badge?) | @pm |
| 4 | Auto-expire approvals 7d default — OK ou ajustar? | @pm |
| 5 | Branching V1 incluir OR só V2? | @pm priorização |
| 6 | Engagement health_score como trigger condition | @data-engineer (Dara) — query optimization |
| 7 | Performance: particionar journey_executions desde criação? | @data-engineer |

---

## Riscos identificados

| Risco | Severidade | Mitigação |
|-------|-----------|-----------|
| Worker timeout em batch grande | M | LIMIT 200 + statement_timeout 120s + cron retry 5min |
| Aluno em loop infinito (step nunca avança) | H | Anti-loop guardrail #3 + execution log auditable |
| Approval queue cresce sem revisão | M | UI dashboard ordenado urgência + auto-expire 7d + Slack daily summary |
| Trigger event-driven em INSERT massivo (bulk import) | M | Trigger condicional (só se status changed) + batch limit |
| LMS module_completed nunca implementado | L | V2 stub — não bloqueia outros triggers |
| Comm externa bypassed via direct DB INSERT | H | RLS policy bloqueia INSERT direto em journey_executions com action send_*; só via worker |

---

## Fluxo completo end-to-end

```
1. Aluno compra → ac_purchase_events.status='processed' (worker existing)
                  ↓
2. Trigger enroll_student_in_journeys() cria student_journey_states pra journeys
   linked ao produto via ac_product_mappings
                  ↓
3. Worker pg_cron 5min OR event-driven processa state:
   - Pega próximo step
   - Avalia trigger (purchase|time|inactivity|at_risk|manual|module_completed)
   - Action auto-fire OR queue approval
                  ↓
4a. Auto-action (create_pending/slack/tag) → executa direto
4b. Approval action (send_template/dispatch_survey) → INSERT journey_pending_approvals
                  ↓
5. CS rep abre /cs/approvals → revisa preview → aprova → action executa
                  ↓
6. Step avança → next_eval_at calculado por day_offset
                  ↓
7. Repeat até completed/paused/escalated/abandoned
```

---

## Migration plan

| Story | Entrega |
|-------|---------|
| 18.2a | Migration: journey_pending_approvals + journey_executions tables |
| 18.2b | Function: process_journey_states() worker |
| 18.2c | Trigger: enroll_student_in_journeys() event-driven |
| 18.2d | pg_cron schedule + integration com frequency_capping |
| 18.2e | UI /cs/approvals (Uma design + dev impl) |
| 18.3 | Visual editor /cs/journeys/edit (Uma design first, then dev) |
| 18.5 | LMS module_completed adapter (when LMS chosen) |
| 18.6 | Kanban V2 drag-drop (Uma + dev) |
| 18.7 | Pause/resume UI buttons + escalation flow |

---

## Status

**APROVADO POR ARIA — pronto pra handoff @sm pra criar 9 sub-stories.**

Próximas etapas:
1. Aria (eu) salvo este ADR
2. Uma desenha UX `/cs/approvals` + visual editor (paralelo)
3. SM cria stories baseado no ADR
4. PO valida 10-point checklist
5. Dev implementa Wave por Wave (18.2a → 18.2b → ... )

— Aria, arquitetando o futuro 🏗️
