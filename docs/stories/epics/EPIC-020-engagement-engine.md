# EPIC-020 — Probabilistic Engagement Engine

**Status:** Draft (aguardando revisão Aria → SM stories)
**Prioridade:** High
**PM:** Morgan (@pm)
**Criado:** 2026-05-05
**Spike report:** `docs/reports/spike-engagement-2026-05-05.md`
**ADR técnico:** `docs/architecture/ADR-017-engagement-scoring-engine.md`

---

## Objetivo

Construir engine probabilístico de engajamento que identifica alunos em risco de churn baseado em múltiplos sinais (presença Zoom + presença manual + respostas survey + cliques Meta). Substitui binário "ativo/inativo" por escore 0-100% confidence + buckets de ação. Habilita CS team a priorizar contato com alunos premium em risco antes do churn.

---

## Resultado de Negócio

| KPI | Baseline atual | Meta pós EPIC-020 |
|---|---|---|
| % alunos at-risk identificados antes de cancelar | ~0% (sem sistema) | >80% |
| Tempo CS detectar aluno em risco | dias/semanas (manual) | <24h (automatizado) |
| % falsos positivos at-risk | N/A | <15% |
| % falsos negativos | N/A | <10% |
| Taxa recuperação alunos contactados | TBD baseline | +30% |
| Cancelamentos pre-emptidos | TBD | +25% absoluto |
| Tempo CS triando lista at-risk | manual ~30min/dia | <5min/dia (dashboard ranqueado) |

---

## Contexto Técnico

### O que já existe (REUSO ~60%)

| Recurso | Localização | Reuso |
|---|---|---|
| Tabela `student_attendance` (com `source`, `zoom_meeting_id`, `duration_minutes`) | baseline_existing_schema | Source signal #1 |
| Tabela `survey_responses` | EPIC-015 schema | Source signal #2 |
| Fuzzy matching Zoom→aluno (jaroWinkler) | `js/admin/zoom.js` | Calibrar `signal_value` confidence |
| `zoom_absence_alerts` (schema construído, não ativado) | baseline | Ativar como sub-componente |
| pg_cron + pg_net + Supabase realtime | EPIC-015 | Worker scheduling |
| Hash router cs-portal + role-based UI | EPIC-015 | Mirror /cs/at-risk |
| Slack alert helper (`send_slack_alert`) | EPIC-015 (16.X) | Alertar buckets disengaged |

### O que precisa ser criado (~40%)

1. **3 tabelas novas:** `engagement_signals`, `student_engagement_scores`, `engagement_feedback` (ver ADR-017)
2. **2 SQL functions:** `recompute_engagement_scores()`, `compute_data_quality_flag()`
3. **2 pg_cron jobs:** daily score refresh + daily quality flag refresh
4. **2 edge functions:** `engagement-feedback-callback`, `engagement-export`
5. **UI dual:** `/admin/at-risk` + `/cs/at-risk` (mirror obrigatório)
6. **UI complementar:** "marcar presença manual" no /admin (acelera adoção do signal manual)
7. **Backfill script:** popular engagement_signals retroativamente 180d
8. **Data quality cleanup:** Story 020.0 (BLOQUEADOR)

---

## Stakeholders

| Papel | Pessoa | Responsabilidade |
|---|---|---|
| Product Owner | Igor Rover | Decisões de negócio, priorização |
| PM | Morgan (@pm) | Roadmap, scope |
| Architect | Aria (@architect) | Revisão ADR-017, decisões técnicas |
| Tech Lead | Dex (@dev) | Implementação |
| QA | Quinn (@qa) | Quality gates |
| Operação | Rogerio + Marllon (CS) | Validação UX, calibration loop, contato alunos |

---

## Stories propostas

| Story | Descrição | Tier | Effort |
|-------|-----------|------|--------|
| **20.0** | **Data Quality Cleanup (BLOQUEADOR)** | 🔴 P0 | S (2d) |
| 20.1 | Schema engagement_signals + score computed (worker pg_cron) | 🔴 P0 | M (3d) |
| 20.2 | Zoom evidence com confidence_score (refactor `student_attendance`) | 🔴 P0 | S (1d) |
| 20.3 | Multi-source aggregator (zoom + manual + survey + meta_click) | 🔴 P0 | M (3d) |
| 20.4 | At-Risk dashboard probabilístico (/admin + **/cs/at-risk**) | 🔴 P0 | M (3d) + S (1d cs) |
| 20.5 | Pulse check WhatsApp semanal + button reply parser | 🟡 P1 | M (3d) |
| 20.6 | Falso positivo feedback button (calibration loop) | 🟡 P1 | XS (4h) |
| 20.7 | Bucket-based actions (integra com 16.11 automation rules) | 🟡 P1 | S (1d) |
| 20.8 | UI manual attendance no /admin (acelera adoção signal manual) | 🟡 P1 | S (4h) |
| 20.9 | Calibration loop V1 (manual tuning weights via UI) | 🟢 P2 | S (1d) |
| 20.10 | Calibration loop V2 (auto-tune via outcomes — logistic regression) | 🟢 P3 | L (5d) |

**Total estimado:** ~24 dias dev (com mirror /cs/, exclui V2 ML que vai pra backlog)

---

## Princípios de design

### 1. Probabilístico, não binário
Substituir "ativo/inativo" por score 0-100% + buckets graduais. UI mostra "alta confiança at-risk" não "está inativo".

### 2. Multi-signal corroboration
Cada signal isolado pode ser falso. Múltiplos signals corroborando = confidence sobe não-linearmente.

### 3. Filter qualidade obrigatório
Sem cleanup data quality, modelo mostra falsos positivos. Story 020.0 é bloqueador.

### 4. CS rep é juiz final
Sistema sugere, humano decide ação. UI mostra TODOS sinais que levaram à classificação (transparência radical).

### 5. Aprender com erros
Cada falso positivo marcado pelo CS rep ajusta pesos. Calibration loop é fundamento.

### 6. Mirror /cs/ não-negociável
CS team é usuário primário. Toda dashboard tem versão /cs/ além de /admin/.

### 7. Cohort-aware
Cohorts curtos (Imersão 3 aulas) precisam regras diferentes de longos (Fundamental 12+ aulas). V1 hardcoded por tipo, V2 dinâmico.

---

## Riscos identificados

| Risco | Mitigação |
|---|---|
| Data quality dirty mascara real at-risk | Story 020.0 bloqueador P0 |
| Falsos positivos geram desconfiança CS team | Botão "marcar falso positivo" + transparência sinais (20.6) |
| Aluno ofendido com mensagem "está sumindo" | Anti-fatigue + tom cuidadoso pulse check (20.5) |
| Cohort de evento curto (Imersão) gera at-risk artificial | Cohort-aware weights V1 hardcoded |
| Zoom fuzzy match incorreto inflaciona attendance | Confidence score ponderado (20.2) |
| Worker pg_cron lento bloqueia outros jobs | Recompute parcial + index otimizado |
| LGPD: tracking de "engajamento" precisa transparência | Política privacy update + consent opt-in |

---

## Dependências

- **EPIC-016 Stories 16.7 (error reporting), 16.8 (audit log)** entregues antes — sem audit/log, debug do worker é cego
- **EPIC-016 Story 16.11 (NPS automation)** entregue paralelo — bucket-based actions (20.7) integra
- **EPIC-019 P0 (data layer)** entregue paralelo — materialized views compartilhadas
- **EPIC-018 Story 18.2 (journey worker)** consumirá engagement_score — dependência cruzada

---

## Acceptance Criteria do EPIC

- [ ] 7/10 stories P0+P1 entregues e em produção
- [ ] Engine computa scores diários para 100% alunos válidos
- [ ] Dashboard /cs/at-risk operacional pra CS team
- [ ] CS team contatou >50% dos alunos identificados na primeira semana pós-deploy
- [ ] Calibration loop ativo (>10 marcações falso positivo coletadas)
- [ ] Métricas baseline coletadas (% falsos positivos, taxa recuperação)
- [ ] Documentação README + ADR-017 atualizada
- [ ] Smoke tests + integração tests passing

---

## Roll-out plan

### Fase 1 (Semana 1) — Foundation
- 020.0 Data Quality Cleanup
- 020.1 Schema + score computed
- 020.2 Zoom confidence_score

### Fase 2 (Semana 2) — Aggregation + Dashboard
- 020.3 Multi-source aggregator
- 020.4 Dashboard /admin + /cs (mirror)
- 020.6 Feedback button

### Fase 3 (Semana 3) — Activation
- 020.5 Pulse check WhatsApp
- 020.7 Bucket actions (integra automation rules)
- 020.8 UI manual attendance
- Onboarding CS team

### Fase 4 (Mês 2+) — Optimization
- 020.9 Calibration V1
- 020.10 Calibration V2 (ML — opcional)

---

## Métricas de sucesso

- **Volume:** 130 alunos at-risk identificados (baseline spike) → triagem CS começa
- **Velocidade:** detecção <24h vs dias/semanas atual
- **Precisão:** >85% (recall + precision combinados) após 1 mês operação
- **Adoção CS:** >80% de alunos at-risk identificados são contatados em 7 dias
- **Outcome:** taxa recuperação contatados >30%
- **Calibração:** >50 feedback events coletados em 1º mês

---

## Próximos passos

1. **Aria (@architect) revisa ADR-017** — valida decisões técnicas
2. **SM (@sm) cria 11 story files detalhados** baseado neste epic + ADR
3. **PO (@po) valida stories via 10-point checklist**
4. **Dev (@dev) implementa Wave 1 (020.0 + 020.1 + 020.2)**
5. **CS team Rogerio + Marllon onboarding após Wave 2** — UX walkthrough + treinamento calibration loop
