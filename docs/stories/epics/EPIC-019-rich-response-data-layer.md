# EPIC-019 — Rich Response Data Layer

**Status:** Draft
**Prioridade:** Foundation (potencializa todos outros épicos)
**PM:** Morgan (@pm)
**Criado:** 2026-05-05

---

## Objetivo

Transformar `survey_responses` + `survey_answers` de silos crus em **motor de decisão**. Adicionar 4 camadas: contexto (snapshot), enriquecimento (tags + sentiment + embeddings), agregações (materialized views), decision views (at-risk, promoters, anomalies). Dados ricos viram fundação pra EPIC-017 (AI triage), EPIC-018 (journey decisions), EPIC-020 (engagement scoring).

---

## Resultado de Negócio

| KPI | Baseline | Meta |
|---|---|---|
| Tempo responder "quais cohorts piorando?" | 30min query manual | 1 click dashboard |
| Tempo identificar tema "preço" nas respostas | grep manual 200 respostas | <5s embedding search |
| Decisões data-driven vs feeling | <20% (estimado) | >80% |
| Materialized views refresh latency | N/A | <30s incremental |
| Cohort health score precisão | N/A | calibrado mensalmente |

---

## Arquitetura 3 camadas

```
┌─────────────────────────────────────────────────────────────┐
│  RAW (OLTP — write-heavy, RLS)                              │
│  survey_responses, survey_answers, students, cohorts        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  ENRICHED (computed/derived — workers atualizam)            │
│  response_metadata: device, channel, completion_time        │
│  response_events: started_at, abandoned_at, resumed_at      │
│  response_tags: AI-generated (sentiment, theme, urgency)    │
│  response_embeddings: pgvector pra similarity search        │
│  student_health_scores: composto NPS+engagement+attendance  │
│  response_context_snapshot: state-at-moment imutável        │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│  ANALYTICAL (materialized views — refresh cron)             │
│  mv_nps_rolling_30d_per_cohort                              │
│  mv_csat_by_module                                          │
│  mv_completion_funnel                                       │
│  mv_response_heatmap (dia × hora × taxa)                    │
│  mv_cohort_health_dashboard                                 │
│  mv_at_risk_students                                        │
│  mv_promoter_advocates                                      │
│  mv_anomaly_signals                                         │
└─────────────────────────────────────────────────────────────┘
```

---

## Stories

| Story | Descrição | Camada | Tier | Effort |
|-------|-----------|--------|------|--------|
| **19.1** | Schema enrichment (response_metadata + events + tags) | Enriched | 🔴 P0 | M (3d) |
| **19.2** | Snapshot context na resposta (state-at-moment imutável) | Enriched | 🔴 P0 | S (1d) |
| **19.3** | Materialized views suite (NPS/CSAT/completion/heatmap) | Analytical | 🔴 P0 | M (3d) |
| **19.4** | Cohort health score + student health score (computed) | Enriched | 🔴 P0 | M (3d) |
| **19.5** | Decision views (at-risk, promoters, anomaly) | Analytical | 🔴 P0 | S (1d) |
| 19.6 | Anomaly detection + Slack alert (variação >X%) | Analytical | 🟡 P1 | S (1d) |
| 19.7 | Time-series trend per student (NPS evolution) | Enriched | 🟡 P1 | M (3d) |
| 19.8 | Embeddings respostas free-text (pgvector + similarity UI) | Enriched | 🟡 P1 | M (3d) |
| 19.9 | Export pipeline (snapshot daily + webhook out) | Consumers | 🟡 P1 | M (3d) |
| 19.10 | Data dictionary auto-gerado + PII tagging | Governance | 🟢 P2 | S (1d) |
| 19.11 | dbt-style staging/marts layer | Architecture | 🟢 P2 | L (5d) |
| 19.12 | Internal BI dashboard (Metabase embed OR custom) | Consumers | 🟢 P2 | M (3d) |

**Total estimado:** ~35 dias dev

---

## Snapshot context (Story 19.2 — fundamental)

```sql
response_context_snapshot {
  response_id,
  student_id,
  cohort_id_at_response,
  journey_step_at_response,
  days_since_purchase,
  modules_completed_count,
  zoom_attendance_pct,
  nps_previous,
  health_score_at_response,
  device, browser, channel,
  completion_time_seconds,
  template_meta_used,
  triggered_by_automation_id
}
```

**Por quê imutável:** se aluno mudar cohort 2 sem depois, resposta original mantém estado da época. Sem isso, análise histórica fica corrompida.

---

## Embeddings (Story 19.8 — diferencial)

- OpenAI `text-embedding-3-small` (1536d) ou similar
- Custo: 200 respostas/mês × 200 tokens média = ~R$0.001/mês (insignificante)
- Casos de uso: similarity search, clustering automático temas, busca semântica

---

## Dependências

- EPIC-015 schema base (já)
- pgvector extension Supabase (nativo, ativar)
- EPIC-016 16.7 (error reporting) — log workers failures
- OpenAI API key (já configurado pra survey responses analytics)

---

## Riscos

| Risco | Mitigação |
|---|---|
| Materialized views ficam stale | Refresh incremental via pg_cron + alerta latency |
| Embeddings custo escala | Hard cap mensal + monitoring |
| PII em response_context_snapshot vaza em export | PII tagging Story 19.10 + auto-mask em export |
| Dados duplicados (snapshot vs raw) confunde | Single source of truth = raw; snapshot é cache |

---

## Stakeholders

- Igor Rover (PO + budget IA)
- Morgan @pm (PM)
- Dara @data-engineer (PRINCIPAL — schema design + dbt-style layer)
- Aria @architect (revisão arquitetura 3 camadas)

---

## Roll-out

- **Wave 1 P0 (11d):** 19.1 + 19.2 + 19.3 + 19.4 + 19.5 — foundation completa
  - Bloqueia EPIC-017 (precisa schema enrichment)
  - Bloqueia EPIC-020 (precisa health_score)
- **Wave 2 P1 (10d):** 19.6 + 19.7 + 19.8 + 19.9 — diferenciadores
- **Wave 3 P2 (9d):** 19.10 + 19.11 + 19.12 — governance + BI

---

## Decisões pendentes

1. **Materialized views refresh:** incremental (pg_cron pequeno) OR full daily? (incremental complica, performance)
2. **Embedding model:** OpenAI ($0.02/1M) OR self-hosted via Replicate/HuggingFace?
3. **dbt vs custom:** dbt-core mais maduro mas overhead infra. Custom mais simples mas menos features (Wave 3)
4. **Export pipeline:** webhook out OR Supabase data API direto (clientes leem sem ETL)?
