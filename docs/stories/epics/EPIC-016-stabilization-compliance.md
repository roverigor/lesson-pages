# EPIC-016 — Stabilization & Compliance

**Status:** Draft
**Prioridade:** High
**PM:** Morgan (@pm)
**Criado:** 2026-05-05

---

## Objetivo

Estabilizar EPIC-015 entregue + adicionar foundation operacional crítica (audit, LGPD, retry, error reporting, observability). Resolver gaps UX descobertos pós-deploy (preview template Meta, criar template via UI). Habilitar generic webhook pra plataformas além de ActiveCampaign.

---

## Resultado de Negócio

| KPI | Baseline | Meta |
|---|---|---|
| % erros usuário com contexto reportado | 0% | >80% |
| Tempo CS sabe que houve falha pipeline | dias | <5min (Slack alert) |
| Conformidade LGPD (opt-out + export + anonim) | parcial | 100% |
| Webhooks falhos com retry automático | 0% | 100% (3 retries) |
| Plataformas integráveis além AC | 1 | ilimitado (generic) |
| Tempo CS criar template Meta | 30min (sair pra Business Manager) | <5min (UI in-app) |

---

## Stories

| Story | Descrição | Tier | Effort |
|-------|-----------|------|--------|
| 16.1 | Preview template Meta (modal body+vars+buttons) | 🔴 P0 | S (4h) |
| 16.3 | Form criar template Meta + edge function POST API | 🔴 P0 | M (3d) |
| 16.4 | Status polling Meta template (pgcron 1min) | 🔴 P0 | S (4h) |
| 16.7 | Error reporting widget sidebar + Slack alert | 🔴 P0 | M (3d) |
| 16.8 | Audit log (actor, action, before/after) + UI | 🔴 P0 | M (2d) |
| 16.9 | Compliance LGPD (consent + export + anonimize) | 🔴 P0 | M (3d) |
| 16.10 | Webhook retry + dead-letter queue | 🔴 P0 | S (1d) |
| 16.5 | Generic purchase-webhook + sources table | 🟡 P1 | M (5d) |
| 16.6 | UI API key generator + docs page | 🟡 P1 | S (1d) |
| 16.11 | NPS-triggered automation rules engine | 🟡 P1 | L (5d) |
| 16.12 | Customer journey timeline UI por aluno | 🟡 P1 | S (1d) |
| 16.13 | Survey analytics dashboard (KPIs + gráficos) | 🟡 P1 | M (3d) |
| 16.14 | Bulk operations (multi-select + actions batch) | 🟡 P1 | S (1d) |

**Total estimado:** ~31 dias dev (com mirror /cs/)

---

## Princípios

- Mirror /cs/ obrigatório em todas UI stories
- Audit log captura mudanças via trigger PG (não wrappers manuais)
- LGPD: opt-out respeitado em worker dispatch (skip se revoked)
- Retry com backoff exponencial: 5min/30min/2h
- Generic webhook normaliza schema entre plataformas

---

## Dependências

- EPIC-015 stabilizado (já em produção)
- Slack workspace configurado (já)
- Meta Business Manager API access (já configurado via secrets)

---

## Riscos

| Risco | Mitigação |
|---|---|
| Audit log infla DB rapidamente | Particionamento por mês + retention 6m |
| LGPD anonimize quebra agregações | Soft-anonimize: mantém ID, mascara PII |
| Generic webhook vira vetor de spam/DoS | Rate limit por API key + HMAC validation |

---

## Stakeholders

- Igor Rover (PO)
- Morgan @pm (PM)
- Aria @architect (technical review)
- CS team (Rogerio + Marllon — usuários primários)

---

## Roll-out

- **Wave 1 (4d):** 16.1 + 16.4 + 16.7 + 16.10 (quick wins + compliance básico)
- **Wave 2 (5d):** 16.3 + 16.8 + 16.12 (criação templates + observability + UX)
- **Wave 3 (6d):** 16.9 + 16.13 + 16.14 + 16.6 (compliance plena + analytics + bulk + API)
- **Wave 4 (8d):** 16.5 + 16.11 (generic webhook + automation rules)
