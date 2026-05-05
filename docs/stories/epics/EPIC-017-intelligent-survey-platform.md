# EPIC-017 — Intelligent Survey Platform

**Status:** Draft
**Prioridade:** Strategic (vision shift)
**PM:** Morgan (@pm)
**Criado:** 2026-05-05

---

## Objetivo

Repositionar o produto de "ferramenta de NPS dispatch" para **plataforma inteligente de feedback contínuo**. Transformar formulários estáticos em **forms inteligentes** (conditional logic, multi-step, branching) + **AI triage automatizada** de respostas free-text + **closed-loop automation** (resposta → ação). Diferenciador competitivo vs SaaS genéricos.

---

## Resultado de Negócio

| KPI | Baseline | Meta |
|---|---|---|
| Survey completion rate | TBD (medir antes) | +50% |
| Tempo CS triando resposta | ~2min/resp = 6h/sem | <30s/resp = 1.5h/sem (-75%) |
| % detractors c/ follow-up <24h | TBD | 100% (automatizado) |
| Tempo resposta → ação concreta | 3 dias | <1h |
| NPS médio rolling 30d | TBD baseline | +5 pontos |
| Templates únicos em uso | 3 (NPS/CSAT/Onboarding) | 15+ |
| Custo IA por resposta triada | N/A | <R$0,02 (Haiku 4.5) |

---

## 7 pilares

| Pilar | Stories |
|-------|---------|
| A. Form intelligence (branching, multi-step, save&resume) | 17.1, 17.2 |
| B. Smart text questions (voz, imagem, transcrição) | 17.3 |
| C. AI triage respostas (sentiment, themes, auto-tag) | 17.4 |
| D. Adaptive dispatch (timing, frequency, re-engagement) | 17.6, 17.7 |
| E. Living templates (library, A/B test) | 17.5, 17.8 |
| F. Closed-loop automation (resp → ação) | 17.10 |
| G. Personalização IA (mensagem dinâmica) | 17.11 |

---

## Stories

| Story | Descrição | Tier | Effort |
|-------|-----------|------|--------|
| **17.1** | Conditional logic (branching questions) | 🔴 P0 | M (3d) |
| **17.4** | AI sentiment + auto-tag respostas (Claude API) | 🔴 P0 | M (3d) |
| **17.8** | Template library + clone + presets | 🔴 P0 | S (1d) |
| **17.12** | Survey test mode (envia pra si antes produção) | 🔴 P0 | XS (4h) |
| 17.2 | Multi-step forms + progress bar + save & resume | 🟡 P1 | M (3d) |
| 17.3 | Voz/imagem input + transcrição automática (Whisper) | 🟡 P1 | M (3d) |
| 17.7 | Frequency capping global + re-engagement flow | 🟡 P1 | S (1d) |
| 17.10 | Closed-loop automation engine v2 | 🟡 P1 | L (5d) |
| 17.5 | A/B testing entre versões | 🟢 P2 | M (3d) |
| 17.6 | Adaptive dispatch timing (best-hour aprende) | 🟢 P2 | M (3d) |
| 17.9 | Cross-survey analytics (trends, themes, word cloud) | 🟢 P2 | M (3d) |
| 17.11 | AI personalization message (Claude greeting custom) | 🟢 P2 | M (3d) |

**Total estimado:** ~42 dias dev (com mirror /cs/)

---

## Custo operacional IA (Wave A em produção)

- **Sentiment + auto-tag:** 200 respostas/mês × 1500 tokens × Haiku 4.5 = ~R$30/mês
- **Whisper transcrição áudio:** 200 áudios × 30s média × $0.006/min = ~R$15/mês
- **Personalização (futuro):** 200 dispatches × 800 tokens × Haiku = ~R$15/mês
- **Total estimado:** ~R$60/mês full Wave A+B+C

---

## Dependências

- EPIC-016 Story 16.7 (error reporting) — log AI calls failures
- EPIC-016 Story 16.8 (audit log) — track AI decisions
- EPIC-019 P0 (data layer) — schema enrichment pra tags
- Anthropic API key configured (já tem OpenAI; adicionar Anthropic)

---

## Riscos

| Risco | Mitigação |
|---|---|
| AI sentiment hallucina categoria errada | Threshold confidence + CS pode override + audit log |
| Custo IA explode com volume crescente | Hard limits + alert quando próximo budget mensal |
| Form complexo (multi-step) reduz completion rate | A/B testing pra validar gain real |
| Voz/imagem PII em armazenamento | LGPD compliance Story 16.9 + signed URLs |
| Personalização parecer "creepy" | Tom cuidadoso + opt-out + transparency |

---

## Stakeholders

- Igor Rover (PO + budget AI)
- Morgan @pm (PM)
- Aria @architect (technical review IA integration)
- Dara @data-engineer (schema embeddings + sentiment storage)
- CS team (validação UX inteligência)

---

## Roll-out

- **Wave A (P0, 8d):** 17.1 + 17.4 + 17.8 + 17.12 — foundation inteligência
- **Wave B (P1, 12d):** 17.2 + 17.3 + 17.7 + 17.10 — automação completa
- **Wave C (P2, 12d):** 17.5 + 17.6 + 17.9 + 17.11 — optimization + diferenciadores

---

## Decisões pendentes

1. **Provider IA primário:** Anthropic (consistência com Claude Code) OR OpenAI (já configurado)
2. **Storage áudio/imagem:** Supabase Storage (LGPD-compliant) OR external S3
3. **Embedding model:** OpenAI text-embedding-3-small ($0.02/1M) OR open-source via Replicate
4. **A/B testing engine:** custom OR usar GrowthBook self-hosted
