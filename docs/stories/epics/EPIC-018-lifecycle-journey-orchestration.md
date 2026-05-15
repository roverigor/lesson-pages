# EPIC-018 — Lifecycle Journey Orchestration

**Status:** Draft
**Prioridade:** Strategic (vision shift — CLM platform)
**PM:** Morgan (@pm)
**Criado:** 2026-05-05

---

## Objetivo

Construir engine de orquestração de jornadas que acompanha cada aluno premium ao longo de toda sua experiência de aprendizado (90 dias típicos), disparando touchpoints automáticos no momento certo. Substituir tocar aluno só na compra (1 de 10 momentos) por **plataforma de Customer Lifecycle Management** verticalizada pra educação.

---

## Resultado de Negócio

| KPI | Baseline atual | Meta |
|---|---|---|
| % alunos premium tocados em 10+ touchpoints | ~10% (só compra) | 100% |
| Tempo CS sabe que aluno está em risco | dias/semanas | <1h (real-time) |
| % detractors recuperados via flow auto | TBD | +50% |
| Renovação curso (LTV) | TBD baseline | +20% |
| NPS médio premium | TBD | +10 pontos |
| Indicações via refer-a-friend trigger | ~0 | +30% novas leads |

---

## Anatomia jornada premium (referência 90 dias)

| Dia | Trigger | Touchpoint | Survey/Template |
|-----|---------|-----------|----------------|
| 0 | Compra confirmada | Boas-vindas | Template Meta "Bem-vindo Premium" |
| 1 | +24h | Onboarding pulse | Survey 3 perguntas (expectativas) |
| 3 | Início módulo 1 detectado | Check-in inicial | Survey CSAT módulo 1 |
| 7 | Semana 1 completa | Pulse check | Survey 1 pergunta (escala 1-5) |
| 14 | NPS midpoint | NPS questionnaire | Survey NPS + razão |
| 21 | Inatividade 5d | Re-engagement | Template Meta "tudo bem?" |
| 30 | Mês 1 marco | Deep feedback | Survey CSAT completo |
| 45 | Conclusão módulo 3 | Conteúdo specifc | Survey por módulo |
| 60 | NPS rolling | NPS comparativo | Survey NPS (compara dia 14) |
| 90 | Graduation | Exit interview | Survey longa + indicação amigos |

---

## Engine architecture (resumo)

```
JOURNEY EDITOR (visual nodes UI)
  ↓
PER-STUDENT STATE TABLE (student_journey_states)
  ↓
JOURNEY WORKER (pg_cron 5min) ← TRIGGER SOURCES
  ↓                              (compra AC, Zoom, módulo, inatividade, time, manual, custom API)
ACTIONS (template Meta, survey dispatch, Slack alert, CS pendência)
```

---

## Stories

| Story | Descrição | Tier | Effort |
|-------|-----------|------|--------|
| **18.1** | Schema journey + nodes + per-student state | 🔴 P0 | M (3d) |
| **18.2** | Worker pg_cron (avalia state, executa actions) | 🔴 P0 | M (3d) |
| **18.3** | Visual journey editor (drag-drop simples) | 🔴 P0 | L (5d) |
| **18.4** | Pre-built journeys (Premium 90d, Standard 30d, Re-engagement) | 🔴 P0 | S (1d) |
| 18.5 | Trigger ingestion: Zoom + módulo concluído | 🟡 P1 | M (3d) |
| 18.6 | Per-student timeline UI (history + estado atual) | 🟡 P1 | M (3d) |
| 18.7 | Pause/resume/escalate (manual + auto on detractor) | 🟡 P1 | S (1d) |
| 18.8 | Anti-fatigue engine (frequency cap global + quiet hours) | 🟡 P1 | S (1d) |
| 18.9 | Lifecycle funnel dashboard (drop-off por step) | 🟢 P2 | M (3d) |
| 18.10 | Journey A/B testing (split cohort, comparar conversion) | 🟢 P2 | M (3d) |

**Total estimado:** ~38 dias dev (com mirror /cs/)

---

## Conceito "Service Tier" (introduzido com EPIC-018)

Aluno tem flag `service_tier` (premium/standard/basic):

| Atributo | Premium | Standard | Basic |
|----------|---------|----------|-------|
| Touchpoints/90d | 10 | 5 | 2 |
| AI personalization | ✓ | ✗ | ✗ |
| CS rep dedicado | ✓ | shared | ✗ |
| Health score computed | ✓ | ✓ | ✗ |
| Slack alert detractor | imediato | 24h | semanal |

---

## Dependências

- EPIC-015 templates Meta + dispatch infrastructure (já)
- EPIC-016 16.11 automation rules (foundation pra ações jornada)
- EPIC-017 17.10 closed-loop (compartilha actions engine)
- EPIC-019 schema enrichment (state context snapshot)
- EPIC-020 engagement_score (driver de decisões automáticas no journey)

---

## Riscos

| Risco | Mitigação |
|---|---|
| Aluno em vários journeys simultâneos = spam | Anti-fatigue 18.8 + frequency cap global |
| Worker falha → student trava no step | Audit log + retry + dead-letter (EPIC-016) |
| Visual editor complexo demais pra CS | V1 simples (linear); V2 branching (depois CS adoption) |
| Mudança em journey definition impacta alunos in-flight | Versionamento + opção "novos alunos só usam V2" |

---

## Stakeholders

- Igor Rover (PO + service_tier strategy)
- Morgan @pm (PM)
- Aria @architect (engine architecture review)
- UX (Uma) — visual editor design
- CS team — operadores principais

---

## Roll-out

- **Wave A (P0, 12d):** 18.1 + 18.2 + 18.3 + 18.4 — engine core + 1ª jornada premium ativa
- **Wave B (P1, 11d):** 18.5 + 18.6 + 18.7 + 18.8 — triggers ricos + UX completo
- **Wave C (P2, 6d):** 18.9 + 18.10 — analytics + experimentation

---

## Decisões pendentes

1. **Visual editor:** custom build OR adapter pra ferramenta open (n8n? React Flow lib?)
2. **State machine engine:** custom SQL OR XState? (XState provides battle-tested mas adiciona dependência)
3. **Branching V1:** linear simples OR já incluir if/else (tradeoff complexidade UI)
4. **Service tier classification:** manual flag OR automático baseado em ticket size compra?
