# ADR-019: `cohort_sessions` Tabela Explícita — Source of Truth pra Ordem das Aulas

## Status

**Proposed** — 2026-05-22 — @data-engineer (Dara)

## Contexto

Hoje a ordem das aulas por cohort ("Aula 01", "Aula 02", "Aula NN") é **inferida em runtime** contando entries em `zoom_meetings` antes de uma data de referência. Cobre múltiplos dashboards e relatórios:

- `nps_results_by_survey` RPC (labels "Por formulário/sessão")
- `nps-class-report-daily` edge function (relatório MD enviado pro grupo WA)
- `dispatch-class-nps` edge function (rotula notificações)
- `admin/envios` (label aula)
- `admin/nps-results` (label sessions)

### Lógica atual (após hotfix 2026-05-22)

```sql
SELECT COUNT(DISTINCT (zm.start_time AT TIME ZONE 'America/Sao_Paulo')::date) + 1
FROM zoom_meetings zm
WHERE zm.class_id = X AND zm.cohort_id = Y
  AND COALESCE(zm.participants_count, 0) >= 10
  AND COALESCE(zm.duration_minutes, 0) >= 60
  AND (zm.start_time AT TIME ZONE 'America/Sao_Paulo')::date < session_date
```

### Problemas

1. **`zoom_meetings` é fonte errada** — webhook Zoom registra EXECUÇÃO, não PLANEJAMENTO.
2. **Heurísticas falham:**
   - `participants≥10` quebra pra turma pequena (private cohort 6 alunos)
   - `duration≥60` quebra pra workshop 45min
   - Mentor session com 12 alunos passa filtro mas não é aula regular
3. **Sem snapshot histórico** — se cohort remarcar aulas, labels históricas mudam retroativamente → quebra audit trail.
4. **Inconsistência multi-dashboard** — cada lugar reimplementa heurística → drift inevitável.
5. **Bug recente (2026-05-21):** Advanced T2 mostrava "Aula 09" quando era "Aula 07" — confiança em dashboards quebrada.

## Decisão

**Criar tabela `cohort_sessions` como source of truth explícita pra ordem das aulas planejadas por cohort. Snapshot do `session_number` em `nps_class_links` no momento do dispatch garante imutabilidade histórica.**

### Schema decidido

```sql
CREATE TABLE cohort_sessions (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cohort_id              UUID NOT NULL REFERENCES cohorts(id) ON DELETE CASCADE,
  session_number         INT  NOT NULL CHECK (session_number > 0),
  class_id               UUID REFERENCES classes(id) ON DELETE SET NULL,
  planned_date           DATE,
  actual_zoom_meeting_id UUID REFERENCES zoom_meetings(id) ON DELETE SET NULL,
  status                 TEXT NOT NULL DEFAULT 'planned'
                              CHECK (status IN ('planned','live','done','cancelled')),
  notes                  TEXT,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at             TIMESTAMPTZ,
  CONSTRAINT cohort_sessions_unique UNIQUE (cohort_id, session_number)
);

ALTER TABLE nps_class_links
  ADD COLUMN session_number_snapshot INT;
```

### Resolução de `session_index` em RPC

```sql
-- Order de resolução (graceful fallback):
COALESCE(
  lnk.session_number_snapshot,            -- 1. Snapshot do dispatch (imutável)
  cs.session_number,                       -- 2. cohort_sessions table (atual)
  -- 3. Heurística legacy (apenas pra dados antigos sem snapshot ou tabela)
  (SELECT COUNT(DISTINCT (zm.start_time AT TIME ZONE 'America/Sao_Paulo')::date)
   FROM zoom_meetings zm
   WHERE zm.class_id = X AND zm.cohort_id = Y
     AND zm.participants_count >= 10 AND zm.duration_minutes >= 60
     AND (zm.start_time AT TIME ZONE 'America/Sao_Paulo')::date < session_date)
)
```

## Alternativas consideradas

### Alternativa A — `class_cohorts.session_number` (proposta inicial @pm)

**Rejeitada.** `class_cohorts` é M:N puro. Mesma `class` reutilizada em múltiplos cohorts → adicionar `session_number` lá viola normalização ou força desnormalização (mesma row precisaria múltiplos valores).

### Alternativa B — Heurística zoom_meetings + sanity check

**Rejeitada.** Apenas band-aid sobre band-aid. Não resolve causa raiz (fonte errada de verdade). Continua frágil + sem snapshot histórico.

### Alternativa C — Tabela `cohort_sessions` (escolhida)

**Adotada.** Separa preocupações:
- `cohort_sessions` = plano (curriculum order)
- `zoom_meetings` = execução (webhook real)
- Linkagem explícita via `actual_zoom_meeting_id` quando aula acontece

Vantagens:
- Múltiplos cohorts mesma class — sem conflito de session_number
- Cancelar/remarcar = update status, mantém histórico
- Snapshot imutável em `nps_class_links` pra label histórica
- Source of truth única consumida por todos dashboards

### Alternativa D — Computed column / materialized view

**Rejeitada.** Materialized view daria performance mas não resolve fonte (continua heurística). Computed column tem mesma fragilidade.

## Consequências

### Positivas

- **Eliminação de heurísticas frágeis** — ordem das aulas é explícita
- **Audit trail histórico** — snapshot imutável em `nps_class_links`
- **Consistência multi-dashboard** — fonte única, todos consomem mesma RPC
- **Suporta planejamento futuro** — aulas planejadas mas ainda sem zoom_meeting (pré-cohort)
- **Cancelamento sem perder histórico** — soft delete + status='cancelled'

### Negativas

- **Custo de manutenção** — admin precisa popular tabela manual (ou via backfill)
- **Backfill arriscado** — 7 cohorts ativos precisam revisão manual
- **Mudança breaking parcial** — RPC sinatura nova, mas fallback legacy mantém compat
- **Trigger sync** — `auto_set_zoom_meeting_class_id` precisa estender pra sync com cohort_sessions

### Neutras

- **Adiciona 1 tabela** — overhead mínimo, indexes cobrem queries esperadas
- **Coluna nova em `nps_class_links`** — nullable, sem impacto pra rows antigas

## Implementação

Detalhada em **Story 22.0** (`docs/stories/22.0.story.md`).

Sequência migrations:
1. `20260522010000_cohort_sessions_table.sql`
2. `20260522010100_nps_links_session_snapshot.sql`
3. `20260522010200_zoom_meeting_class_trigger_update.sql`
4. `20260522010300_nps_results_by_survey_refactor.sql`

Backfill via script manual (não migration): `scripts/cohort_sessions_backfill.sql`.

## Métricas de sucesso

- ✅ Bug "Aula 09 → Aula 07" não recorre quando zoom_meeting fantasma aparece
- ✅ Label histórica de respostas antigas NÃO muda se cohort remarcar
- ✅ Dashboards nps-results, envios, daily-report convergem na mesma label
- ✅ Admin consegue editar order/data via UI sem rodar SQL manual

## Trade-offs aceitos

- Manutenção manual de `cohort_sessions` (overhead operacional) em troca de correctness + audit trail
- Backfill com revisão humana (risco de erro) em troca de não perder dados históricos

## Referências

- Hotfix tático: `supabase/migrations/20260521010000_nps_by_survey_group_by_dispatch.sql`
- Story de implementação: `docs/stories/22.0.story.md`
- Handoff: `.aiox/handoffs/handoff-pm-to-data-engineer-2026-05-22.yaml`
- Bug original: dashboard mostrando "Aula 09 Cohort Advanced T2" em 21/05 quando real era "Aula 07"
