# ADR-017 — Engagement Scoring Engine (Multi-Signal Probabilistic)

**Status:** Proposed
**Data:** 2026-05-05
**Autor:** Morgan (@pm) — propondo pra Aria (@architect) review
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

**Aguardando revisão Aria (@architect)** antes de pass to @sm para criar stories detalhadas.
