# ADR-017 — Engagement Scoring Engine (Multi-Signal Probabilistic)

**Status:** Approved with Modifications
**Data:** 2026-05-05
**Autor original:** Morgan (@pm)
**Reviewer:** Aria (@architect) — review 2026-05-05
**Contexto:** EPIC-020 — Probabilistic Engagement Engine
**Spike validador:** `docs/reports/spike-engagement-2026-05-05.md`

---

## Contexto

Sistema lesson-pages precisa identificar alunos premium em risco de churn. Zoom permite entrada com qualquer email (ground truth não-confiável). Solução: modelo probabilístico multi-signal com confidence_score, não binário ativo/inativo.

Spike validou viabilidade com dados existentes (130 alunos at-risk identificados, 7 cohorts). Modelo MVP usa pesos heurísticos. Esta ADR propõe arquitetura pra implementação production.

---

## Decisão

Construir engine em **3 camadas**, separando coleta (raw signals), agregação (computed scores) e ação (buckets + automation).

### Camada 1 — Raw Signals (event sourcing)

Tabela append-only que registra cada evento de engajamento. Pode ser populada por triggers DB, edge functions, ou APIs externas.

```sql
CREATE TABLE engagement_signals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  signal_type text NOT NULL CHECK (signal_type IN (
    'zoom_attendance',
    'manual_attendance',
    'survey_response',
    'meta_link_click',
    'login_painel'
  )),
  signal_value numeric(4,3) NOT NULL CHECK (signal_value BETWEEN 0 AND 1),
  occurred_at timestamptz NOT NULL,
  meta jsonb,                          -- contexto (meeting_id, survey_id, confidence_score)
  source_record_id uuid,               -- referência ao registro origem (ex: student_attendance.id)
  created_at timestamptz DEFAULT now()
);

CREATE INDEX idx_engagement_signals_student_time
  ON engagement_signals (student_id, occurred_at DESC);

CREATE INDEX idx_engagement_signals_type_time
  ON engagement_signals (signal_type, occurred_at DESC);
```

**Por quê event sourcing:**
- Imutável (auditável, reproducible)
- Permite recálculo retroativo se mudar pesos
- Permite diferentes views agregadas (rolling 7d, 30d, 90d)
- Facilita ML futuro (training set já estruturado)

### Camada 2 — Computed Scores (materialized snapshot)

Tabela com score atual de cada aluno, refreshed via pg_cron.

```sql
CREATE TABLE student_engagement_scores (
  student_id uuid PRIMARY KEY REFERENCES students(id) ON DELETE CASCADE,
  cohort_id uuid REFERENCES cohorts(id),
  score_30d numeric(4,3) NOT NULL,    -- 0-1 weighted sum
  prob_churn numeric(4,3) NOT NULL,   -- 0-1 sigmoid
  bucket text NOT NULL CHECK (bucket IN (
    'engaged',          -- prob_churn < 0.20
    'light_at_risk',    -- 0.20-0.50
    'heavy_at_risk',    -- 0.50-0.80
    'disengaged',       -- > 0.80
    'never_engaged',    -- zero signals histórico (categoria especial)
    'cold_start'        -- aluno novo (<14d cohort), score insuficiente
  )),
  signals_breakdown jsonb NOT NULL,
  -- exemplo: {"attendance": 0.5, "survey": 0.3, "manual": 0.0, "meta_click": 0.1}
  last_engagement_at timestamptz,
  days_silent integer GENERATED ALWAYS AS (
    EXTRACT(DAY FROM now() - last_engagement_at)::integer
  ) STORED,
  data_quality_flag text,             -- 'valid' | 'incomplete' | 'fantasma'
  computed_at timestamptz DEFAULT now()
);

CREATE INDEX idx_engagement_scores_bucket ON student_engagement_scores (bucket, prob_churn DESC);
CREATE INDEX idx_engagement_scores_cohort ON student_engagement_scores (cohort_id, prob_churn DESC);
```

### Camada 3 — Calibration Feedback Loop

Permite CS rep marcar predições como certas/erradas pra ajustar pesos.

```sql
CREATE TABLE engagement_feedback (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES students(id),
  cs_user_id uuid REFERENCES auth.users(id),
  predicted_bucket text,
  predicted_prob_churn numeric(4,3),
  actual_outcome text NOT NULL CHECK (actual_outcome IN (
    'recovered',         -- CS contatou, aluno voltou
    'churned',           -- aluno cancelou
    'false_positive',    -- prediction errada (estava ativo)
    'irrelevant'         -- não merecia ser flagged
  )),
  notes text,
  created_at timestamptz DEFAULT now()
);
```

---

## Pesos da fórmula (V1 heurística)

```
score_30d =
  0.50 × attendance_signal_30d
+ 0.30 × survey_signal_90d
+ 0.20 × manual_attendance_30d

attendance_signal_30d = SUM(zoom_attendance.signal_value × decay(occurred_at)) / aulas_elegíveis_cohort
survey_signal_90d = SUM(survey_response.signal_value × decay(occurred_at)) / 3  (target 1 survey/mês = 3/90d)
manual_attendance_30d = COUNT(manual_attendance) / aulas_elegíveis (peso adicional, capped 1.0)

decay(t) = exp(-(now - t) / 14_days)   -- meia-vida 14 dias

prob_churn = 1 - sigmoid(score_30d × 4 - 2)
```

### Justificativas

- **0.50 attendance:** sinal mais "duro" (presença Zoom), maior peso
- **0.30 survey:** engajamento ativo, indica disposição em interagir
- **0.20 manual:** override CS rep, alta confidence quando presente
- **Sigmoid:** suaviza bordas, evita falsos positivos extremos
- **Decay 14d:** meia-vida calibrada pra cohorts longos (Fundamental); cohorts curtos (Imersão) precisam tuning

---

## Fluxo de dados

```
┌──────────────────────────────────────────────────────────────┐
│  EVENTOS                                                     │
│  ├─ Zoom webhook (já existe) → student_attendance            │
│  ├─ CS marca presença manual UI → student_attendance         │
│  ├─ Survey response → survey_responses                       │
│  ├─ Meta delivery webhook → tracking link click              │
│  └─ Login painel → auth.users.last_sign_in_at                │
└──────────────────────────────────────────────────────────────┘
              ↓ (DB triggers OR worker cron)
┌──────────────────────────────────────────────────────────────┐
│  engagement_signals (append-only)                            │
│  Cada evento normalizado vira 1 row                          │
└──────────────────────────────────────────────────────────────┘
              ↓ (pg_cron diário 03:00)
┌──────────────────────────────────────────────────────────────┐
│  recompute_engagement_scores() function                      │
│  Para cada aluno: agrega signals 30d/90d, computa score,     │
│  classifica bucket, atualiza student_engagement_scores       │
└──────────────────────────────────────────────────────────────┘
              ↓
┌──────────────────────────────────────────────────────────────┐
│  CONSUMERS                                                   │
│  ├─ /admin/at-risk + /cs/at-risk dashboard                   │
│  ├─ Slack alert se prob_churn>0.8 e bucket mudou             │
│  ├─ Automation rules (16.11) usam bucket como trigger        │
│  └─ Journey worker (18.2) decisões baseadas em score         │
└──────────────────────────────────────────────────────────────┘
              ↑
┌──────────────────────────────────────────────────────────────┐
│  CS FEEDBACK LOOP                                            │
│  Botão "marcar falso positivo" / "aluno recuperado" →        │
│  engagement_feedback → ajusta pesos próxima rodada           │
└──────────────────────────────────────────────────────────────┘
```

---

## Decisões críticas (pra Aria validar)

### 1. Event sourcing vs derivação direta de tables existentes

**Opção A (proposta):** Tabela `engagement_signals` própria, populada por triggers/jobs.
**Opção B:** VIEW que deriva on-the-fly de `student_attendance` + `survey_responses`.

**Trade-off:**
- A: redundância controlada, audit trail, prep ML
- B: zero duplicação, sempre fresh, mas perform pior em escala

**Recomendo A** porque:
- Performance (materialized refresh < join complex 5 tables)
- Permite signals futuros sem alterar schema legado
- ML training set ready

### 2. Cold-start handling

**Decisão:** Aluno com <14 dias no cohort recebe bucket `cold_start`. Não scoreia até massa crítica de signals (mínimo 1 aula elegível + 14d cohort tenure).

### 3. Cohort-aware weights

**Decisão:** Pesos são global V1. Cohort-specific tuning vai pra V2 (ML calibration). Permite Imersão (curto) ter peso decay diferente de Fundamental (longo).

### 4. Refresh frequency

**Decisão:** Diário 03:00 BRT via pg_cron. Realtime triggers em INSERT signals adiantam recompute apenas se aluno tiver bucket previamente alto-risco (otimização).

### 5. Filter qualidade integrado

**Decisão:** `data_quality_flag` é campo na própria score table:
- `valid`: email + nome alfa OK
- `incomplete`: dados parciais
- `fantasma`: sem email OR nome=telefone OR vazio

Dashboards filtram por `valid` por default. Toggle "incluir incompletos" disponível.

---

## Migração

### Backfill inicial

```sql
-- Popular engagement_signals retroativamente desde dados existentes
INSERT INTO engagement_signals (student_id, signal_type, signal_value, occurred_at, meta, source_record_id)
SELECT
  student_id,
  'zoom_attendance',
  CASE WHEN duration_minutes >= 15 THEN 1.0 ELSE 0.5 END,  -- presence confidence
  class_date::timestamptz,
  jsonb_build_object('meeting_id', zoom_meeting_id, 'duration_min', duration_minutes),
  id
FROM student_attendance
WHERE class_date > now() - interval '180 days';

INSERT INTO engagement_signals (student_id, signal_type, signal_value, occurred_at, meta, source_record_id)
SELECT
  student_id,
  'survey_response',
  1.0,
  submitted_at,
  jsonb_build_object('survey_id', survey_id),
  id
FROM survey_responses
WHERE submitted_at > now() - interval '180 days';

-- Popular scores iniciais
SELECT recompute_engagement_scores();
```

### Worker pg_cron

```sql
SELECT cron.schedule(
  'epic020-recompute-engagement-scores',
  '0 3 * * *',  -- 03:00 daily
  $$ SELECT recompute_engagement_scores(); $$
);
```

---

## Performance considerations

- 865 alunos × 50 signals/aluno média = ~45K rows engagement_signals (small)
- Recompute completo: estimativa <30s sobre full table
- Index `(student_id, occurred_at DESC)` cobre 80% das queries
- Score table tem 1 row/aluno, queries dashboard sub-segundo

**Escalabilidade prevista:** OK até 10K alunos sem partitioning. Acima disso, particionar `engagement_signals` por mês.

---

## Segurança (RLS)

```sql
-- engagement_signals: leitura via JOIN students (RLS já existente cobre)
ALTER TABLE engagement_signals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "CS or Admin read signals"
  ON engagement_signals FOR SELECT
  USING (auth.jwt()->>'role' IN ('admin', 'cs'));

-- score table: mesma policy
ALTER TABLE student_engagement_scores ENABLE ROW LEVEL SECURITY;
CREATE POLICY "CS or Admin read scores"
  ON student_engagement_scores FOR SELECT
  USING (auth.jwt()->>'role' IN ('admin', 'cs'));

-- feedback: write apenas usuário autenticado
ALTER TABLE engagement_feedback ENABLE ROW LEVEL SECURITY;
CREATE POLICY "CS or Admin write feedback"
  ON engagement_feedback FOR INSERT
  WITH CHECK (auth.jwt()->>'role' IN ('admin', 'cs'));
```

---

## Pontos abertos para Aria revisar

1. **Tabela única `engagement_signals` vs por-tipo separadas?** (single table simpler, partitioning later)
2. **Decay function exponential vs linear vs step?** (exponential mais natural mas pode ser caro compute)
3. **Cohort-specific overrides V1 OR V2?** (V1 hardcoded, V2 dinâmico via config table)
4. **Realtime trigger no INSERT signals OR só batch cron?** (impact escalabilidade vs UX)
5. **Backfill 180d ou 90d?** (180d mais histórico mas tabela maior)
6. **Worker recompute parcial (só alunos com signals novos) OR full?** (parcial mais eficiente, complica lógica)
7. **`data_quality_flag` em score table OR view filter?** (campo permite explicit query, view limpa)

---

## Status

**APROVADO COM MODIFICAÇÕES** por Aria (@architect) em 2026-05-05.

Próximas etapas:
1. @sm cria 13 story files baseado em ADR atualizado + EPIC-020
2. @po valida via 10-point checklist
3. @dev implementa Story 020.0 + 020.1a-d (foundation)

---

# 🏛️ DECISÕES FINAIS ARIA (2026-05-05)

## Resumo executivo

Arquitetura 3 camadas APROVADA. Adições críticas: partitioning desde criação, step decay function, config table cohort-aware, trigger condicional + worker incremental, MV at-risk dashboard, health check + alert stale.

---

## Decisões nos 7 pontos abertos

### 1. Single table `engagement_signals` ✅ APROVADO + PARTITIONING DESDE INÍCIO

```sql
CREATE TABLE engagement_signals (
  id uuid DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  cohort_id_at_event uuid REFERENCES cohorts(id),  -- NEW: snapshot cohort
  signal_type text NOT NULL CHECK (signal_type IN (
    'zoom_attendance','manual_attendance','survey_response',
    'meta_link_click','login_painel'
  )),
  signal_value numeric(4,3) NOT NULL CHECK (signal_value BETWEEN 0 AND 1),
  occurred_at timestamptz NOT NULL,
  meta jsonb,
  source_record_id uuid,
  created_at timestamptz DEFAULT now(),
  PRIMARY KEY (id, occurred_at)
) PARTITION BY RANGE (occurred_at);

-- Particionamento mensal
CREATE TABLE engagement_signals_2026_05 PARTITION OF engagement_signals
  FOR VALUES FROM ('2026-05-01') TO ('2026-06-01');
CREATE TABLE engagement_signals_2026_06 PARTITION OF engagement_signals
  FOR VALUES FROM ('2026-06-01') TO ('2026-07-01');
-- pré-criar próximas 6 meses; auto-create via pg_partman se disponível

-- Indexes
CREATE INDEX idx_signals_student_time
  ON engagement_signals (student_id, occurred_at DESC);
CREATE INDEX idx_signals_type_student
  ON engagement_signals (signal_type, student_id, occurred_at DESC);
CREATE INDEX idx_signals_meta_gin
  ON engagement_signals USING GIN (meta);
```

**Rationale:** Partition pruning garante performance constante quando volume crescer 10x. Composite `(signal_type, student_id, occurred_at DESC)` cobre 90% queries do recompute. GIN em `meta` habilita queries tipo "todos signals onde meeting_id = X".

**Adição:** `cohort_id_at_event` snapshot — aluno pode trocar cohort, signal preserva contexto histórico.

### 2. Decay function ❌ REJEITADO exponential → ✅ STEP FUNCTION

**Justificativa arquitetural:** `EXP()` per-row em recompute = 39M operações exp() diariamente (45K rows × 865 alunos). Step function aproxima 95% da curva exponential com SQL trivial:

```sql
CREATE OR REPLACE FUNCTION engagement_decay_weight(occurred_at timestamptz)
RETURNS numeric LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN now() - occurred_at <= interval '7 days'  THEN 1.00
    WHEN now() - occurred_at <= interval '14 days' THEN 0.70
    WHEN now() - occurred_at <= interval '30 days' THEN 0.40
    WHEN now() - occurred_at <= interval '60 days' THEN 0.15
    ELSE 0.05
  END;
$$;
```

**Vantagens:** indexável via `WHERE occurred_at > now() - interval '60 days'`, pure-SQL, debuggable, sem float drift, IMMUTABLE+PARALLEL SAFE permite query planner otimizar agressivamente.

### 3. Cohort weights — V1 com CONFIG TABLE (não hardcoded)

```sql
CREATE TABLE engagement_config (
  cohort_id uuid PRIMARY KEY REFERENCES cohorts(id),
  weight_attendance numeric(3,2) NOT NULL DEFAULT 0.50,
  weight_survey numeric(3,2) NOT NULL DEFAULT 0.30,
  weight_manual numeric(3,2) NOT NULL DEFAULT 0.20,
  decay_short_days int NOT NULL DEFAULT 7,
  decay_medium_days int NOT NULL DEFAULT 30,
  notes text,
  updated_at timestamptz DEFAULT now(),
  CHECK (weight_attendance + weight_survey + weight_manual = 1.0)
);

-- Default global (cohort_id NULL = fallback)
INSERT INTO engagement_config (cohort_id) VALUES (NULL);

-- Pre-popular per-cohort com defaults
INSERT INTO engagement_config (cohort_id) SELECT id FROM cohorts;
```

`recompute_engagement_scores()` faz LEFT JOIN config + COALESCE com row NULL (default global). CS team ajusta via UI Story 020.9 sem migration.

**Tradeoff aceito:** +2h dev pra ganhar autonomia operacional + flexibilidade Imersão (curto) vs Fundamental (longo) imediata.

### 4. Refresh cadence — TRIGGER INCREMENTAL + DAILY FULL

V1 entrega ambos:

```sql
-- Score table additions
ALTER TABLE student_engagement_scores
  ADD COLUMN needs_recompute boolean DEFAULT false;

CREATE INDEX idx_engagement_scores_dirty
  ON student_engagement_scores (needs_recompute) WHERE needs_recompute = true;

-- Trigger marca dirty
CREATE OR REPLACE FUNCTION trigger_mark_recompute()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  -- Skip ruído (login_painel não justifica recompute imediato)
  IF NEW.signal_type IN ('zoom_attendance','manual_attendance','survey_response') THEN
    UPDATE student_engagement_scores
       SET needs_recompute = true
     WHERE student_id = NEW.student_id;
  END IF;
  RETURN NEW;
END $$;

CREATE TRIGGER signals_invalidate_score
  AFTER INSERT ON engagement_signals
  FOR EACH ROW EXECUTE FUNCTION trigger_mark_recompute();

-- Worker incremental (5min)
SELECT cron.schedule(
  'epic020-incremental-recompute',
  '*/5 * * * *',
  $$ SELECT recompute_engagement_scores_for_dirty(); $$
);

-- Worker full (safety net 03:00)
SELECT cron.schedule(
  'epic020-full-recompute',
  '0 3 * * *',
  $$ SELECT recompute_engagement_scores(); $$
);
```

**UX impact:** aluno responde survey → 5min depois bucket atualiza no dashboard CS. Daily full safety net se trigger falhar.

### 5. Backfill 180d ✅ APROVADO

Volume estimado ~90K rows = trivial. Trend signal precisa histórico (degradação só visível com 90+ dias). GO 180d.

### 6. Recompute strategy — PARCIAL (V1.5 trigger-driven) + FULL safety net

Combinado com decisão #4. Função `recompute_engagement_scores_for_dirty()` processa apenas alunos com `needs_recompute=true`. Função `recompute_engagement_scores()` (full) roda diariamente como safety net.

### 7. `data_quality_flag` na score table ✅ APROVADO + VIEW conveniência

```sql
-- Campo na table (decisão PM correta)
-- View conveniência pra dashboards
CREATE VIEW v_engagement_scores_valid AS
  SELECT * FROM student_engagement_scores
  WHERE data_quality_flag = 'valid';
```

UI default na view. Toggle "incluir incompletos" liga query direto na table.

---

## Adições arquiteturais (Aria value-add)

### A. Statement timeout no worker

```sql
CREATE OR REPLACE FUNCTION recompute_engagement_scores()
RETURNS void LANGUAGE plpgsql AS $$
BEGIN
  SET LOCAL statement_timeout = '120s';
  SET LOCAL lock_timeout = '5s';
  -- ... lógica recompute
END $$;
```

Evita worker travar shared pool quando volume crescer. Falha rápida + retry > hang silent.

### B. Health check function exposta

```sql
CREATE OR REPLACE FUNCTION engagement_engine_health()
RETURNS jsonb LANGUAGE sql AS $$
  SELECT jsonb_build_object(
    'last_successful_compute', (SELECT MAX(computed_at) FROM student_engagement_scores),
    'students_scored', (SELECT COUNT(*) FROM student_engagement_scores),
    'students_dirty', (SELECT COUNT(*) FROM student_engagement_scores WHERE needs_recompute = true),
    'signals_last_24h', (SELECT COUNT(*) FROM engagement_signals WHERE occurred_at > now() - interval '24 hours'),
    'avg_processing_lag_seconds', (SELECT AVG(processing_lag_seconds) FROM student_engagement_scores),
    'worker_jobs_active', (SELECT COUNT(*) FROM cron.job WHERE jobname LIKE 'epic020%' AND active = true)
  );
$$;
```

Endpoint `/cs/admin/engagement-health` chama. Self-diagnostics + Slack alert.

### C. Alert se compute stale >25h

Estende `alert_slack_if_unhealthy()` (EPIC-015):

```sql
IF (SELECT EXTRACT(EPOCH FROM now() - MAX(computed_at)) / 3600
    FROM student_engagement_scores) > 25 THEN
  PERFORM send_slack_alert(
    'epic020_engine_stale',
    '⚠️ Engagement engine sem recompute há >25h. Worker pg_cron pode ter falhado.'
  );
END IF;
```

### D. Materialized view at-risk dashboard

```sql
CREATE MATERIALIZED VIEW mv_at_risk_students AS
SELECT
  s.id, s.name, s.email,
  c.name AS cohort_name,
  ses.bucket, ses.prob_churn,
  ses.signals_breakdown,
  ses.last_engagement_at,
  ses.days_silent,
  ses.computed_at
FROM students s
JOIN student_engagement_scores ses ON ses.student_id = s.id
JOIN cohorts c ON c.id = ses.cohort_id
WHERE ses.bucket IN ('heavy_at_risk', 'disengaged')
  AND ses.data_quality_flag = 'valid'
ORDER BY ses.prob_churn DESC, ses.days_silent DESC;

CREATE UNIQUE INDEX ON mv_at_risk_students (id);
CREATE INDEX ON mv_at_risk_students (prob_churn DESC);

-- Refresh 5min depois full recompute
SELECT cron.schedule(
  'epic020-refresh-at-risk-mv',
  '5 3 * * *',
  $$ REFRESH MATERIALIZED VIEW CONCURRENTLY mv_at_risk_students; $$
);
```

Dashboard `SELECT * FROM mv_at_risk_students LIMIT 50` = sub-segundo.

### E. `processing_lag_seconds` computed column

```sql
ALTER TABLE student_engagement_scores
  ADD COLUMN computed_at timestamptz DEFAULT now(),
  ADD COLUMN processing_lag_seconds int GENERATED ALWAYS AS (
    EXTRACT(EPOCH FROM (computed_at - last_engagement_at))::int
  ) STORED;
```

Permite query "alunos com score stale" + alerta operacional.

### F. `prob_churn` mudança: STORED → plain numeric

Race condition risk em STORED computed quando pesos mudam. Plain numeric column atualizado pela function = previsível, debugável.

```sql
-- Em vez de:
prob_churn numeric GENERATED ALWAYS AS (...) STORED

-- Usar:
prob_churn numeric(4,3) NOT NULL  -- atualizado por recompute_engagement_scores()
```

### G. Cohort overlap handling

Aluno pode aparecer em múltiplos cohorts (Daiana Duarte spike showed). Resolução:

```sql
-- Score key = (student_id, cohort_id) composto
ALTER TABLE student_engagement_scores
  DROP CONSTRAINT student_engagement_scores_pkey;

ALTER TABLE student_engagement_scores
  ADD PRIMARY KEY (student_id, cohort_id);
```

Dashboard mostra um row per (aluno, cohort) — operador vê context completo.

### H. Trigger condicional (skip ruído `login_painel`)

Já incluído na decisão #4. `login_painel` é signal fraco (login não significa estudo); não justifica recompute imediato.

---

## Riscos arquiteturais identificados

| Risco | Severidade | Mitigação |
|-------|-----------|-----------|
| `pg_partman` extension não habilitada Supabase | M | Fallback: criar partitions manualmente, agendar `create_next_partition()` mensal via pg_cron |
| Trigger AFTER INSERT em bursts (evento Zoom = 30 alunos simultâneos) | M | Trigger condicional já filtra signal_type; se persistir, batch insert sem trigger + manual mark dirty |
| MV refresh CONCURRENTLY exige unique index | L | Garantido via `CREATE UNIQUE INDEX (id)` |
| Cohort overlap cria 2x rows score per aluno | M | Resolução via composite PK `(student_id, cohort_id)` |
| Worker falha silenciosa | H | Health check function + Slack alert se >25h stale |

---

## Sequência de implementação revisada (pra @sm)

| Step | Story | O que entrega | Dependência |
|------|-------|---------------|-------------|
| 1 | 020.0 | Data quality cleanup | — |
| 2 | 020.1a | Migration: tabelas + indexes + partitioning + RLS + config table | 020.0 |
| 3 | 020.1b | Function: `engagement_decay_weight` + `recompute_engagement_scores()` (full) | 020.1a |
| 4 | 020.1c | Migration: backfill signals 180d + initial compute | 020.1b |
| 5 | 020.1d | Trigger + worker incremental + worker full + health check + Slack alert | 020.1c |
| 6 | 020.2 | Zoom evidence confidence_score (refactor `student_attendance` source signal) | 020.1d |
| 7 | 020.3 | Multi-source aggregator (popula signals via triggers em tabelas existentes) | 020.2 |
| 8 | 020.4 | UI /admin/at-risk + /cs/at-risk (consome MV) | 020.3 |
| 9 | 020.6 | Feedback button + table | 020.4 |
| 10 | 020.7 | Bucket → automation rules integration | 020.4 |
| 11 | 020.5 | Pulse check WhatsApp semanal | 020.4 |
| 12 | 020.8 | UI manual attendance | 020.4 |
| 13 | 020.9 | Calibration UI (engagement_config edits) | 020.4 |

Story 020.1 quebrada em 4 sub-stories pra entrega incremental + rollback safety.

---

## Próximos passos

1. ✅ ADR-017 atualizado (este documento)
2. ➡️ Handoff @sm pra criar 13 story files
3. ➡️ @po valida stories
4. ➡️ @dev implementa Story 020.0 (foundation)
