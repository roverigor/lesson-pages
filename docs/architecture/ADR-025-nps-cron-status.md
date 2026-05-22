# ADR-025 — NPS Cron Status (Dormant vs Forgotten + UI Button Gate)

- **Status:** Draft (skeleton — aguarda audit data + classificação)
- **Date:** 2026-05-22
- **Story:** [22.7 — NPS Cron Status Audit](../stories/22.7.story.md)
- **Epic:** [EPIC-022 — Painel Refactor](../epics/EPIC-022-painel-refactor.md) §S.022.7
- **Authors:** @architect (Aria), @aiox-master (Orion)
- **Supersedes:** Nenhuma (primeira decisão formal sobre cron status NPS)
- **Reference:** `.claude/CLAUDE.md "Comunicação Externa — NON-NEGOTIABLE"`

---

## Context

Migrations no codebase contêm `-- SELECT cron.schedule(...)` comentados em jobs NPS. Estado ambíguo:

- **Cenário A — Dormante intencional:** comentário foi decisão consciente (gate humano + risco prod)
- **Cenário B — Esquecido:** comentário deixado durante refactor sem decisão arquitetural

**Risco crítico:** Se for B e alguém descomentar sem revisar → disparo massivo pra 1k+ alunos prod sem aprovação. Violação CLAUDE.md "Comunicação Externa NON-NEGOTIABLE".

**Audit tool:** `scripts/audit-nps-crons.sh` gera 2 outputs:
- `docs/22.7-cron-inventory.md` — listagem completa
- `docs/22.7-30d-report.md` — dispatches efetivos vs esperados

---

## Decision

### 1. PROIBIDO reativar cron silenciosamente

**NON-NEGOTIABLE per CLAUDE.md "Comunicação Externa":**

> "NUNCA execute ação que envia mensagem real (WhatsApp/Email/SMS/Slack push externo a aluno/cliente/lead) sem autorização humana explícita no momento da execução."

Reativar cron NPS = automatizar envios massivos sem gate per-execution = direta violação.

### 2. Mecanismo de reativação = UI Button (não cron.schedule)

Pra qualquer dispatch NPS pós-investigation, mecanismo único é **UI button explícito** em `/admin/dispatch` (post-22.3) ou `/admin/nps-monitor` (interim).

**Características obrigatórias:**
- Botão exige clique humano (não cron periodic)
- Preview lista destinatários + content template ANTES execução
- Confirmação modal com count + sample 5 destinatários
- Dry-run checkbox (envia 0 mensagens reais)
- Audit log entry obrigatório (operator + recipients + timestamp)
- Slack alert startup + final
- Autorização literal user (citação textual de mensagem) no ADR pra reativações específicas

### 3. Classificação por cron (skeleton — preencher pós-audit)

Tabela placeholder. Audit tool gera dados pra preencher:

| Cron | Schedule | Status (active/dormant) | Classificação | Razão | Action |
|------|----------|------------------------|---------------|-------|--------|
| TBD | TBD | TBD | TBD | TBD | TBD |
| TBD | TBD | TBD | TBD | TBD | TBD |

**Após review do `docs/22.7-cron-inventory.md`:**
- "Intencional (dormante)" → adicionar comment SQL na migration original
- "Esquecido" → propor UI button gate (NÃO descomentar cron)
- "A decidir" → escalate user pra direção arquitetural

### 4. Comment SQL pattern (dormante intencional)

Para crons classificados "Dormante intencional", adicionar inline comment SQL na migration original (ou criar `_annotations.sql` se imutável):

```sql
-- DORMANT BY DESIGN ref ADR-025.
-- Do NOT uncomment without re-running gate review per CLAUDE.md
-- "Comunicação Externa NON-NEGOTIABLE".
-- Reactivation mechanism: UI button in /admin/dispatch only.
-- SELECT cron.schedule(...);  -- ← keep commented
```

### 5. Audit log event types

Eventos dedicados pra trace forense:
- `nps_manual_dispatch` — clique UI button
- `nps_manual_dispatch_dryrun` — clique com dry-run
- `nps_cron_classified_dormant` — durante audit (manifest entry)
- `nps_cron_classified_forgotten` — durante audit
- `nps_cron_uncomment_blocked` — se alguém tentar bypass via migration (gate hook)

### 6. Relatório 30d como input pré-classificação

`docs/22.7-30d-report.md` cross-references:
- Dispatches esperados (crons ativos × frequency)
- Dispatches efetivos (audit_log + dispatch_history rows)
- Diff > 10% → anomalia → investigar pre-classificar

### 7. Sem reativação cron via migration

Migrations NPS futuras com `cron.schedule` ativo (não-comentado) DEVEM:
- Conter citação literal user autorizando essa reativação específica
- Cross-ref ADR atualizado documentando decisão
- Slack alert auto no apply migration

Se gate hook detectar `cron.schedule` ativo em PR sem citação → BLOQUEIA merge.

---

## Consequences

### Curto prazo (imediato pós-audit)

- ✅ Inventário completo de TODOS crons NPS (visibility)
- ✅ Relatório 30d dispatches efetivos (baseline observability)
- ✅ Classificação Intencional/Esquecido/A decidir documentada
- ✅ Comment SQL "DORMANT BY DESIGN" em migrations originais (defensive doc)
- ⚠️ Se UI button não implementado ainda (depends 22.3), reativações ficam paused

### Longo prazo

- **Defense-in-depth:** múltiplos layers (UI button + dry-run + Slack + audit + ADR autorização)
- **Audit trail:** event types dedicados permitem forensic post-incident
- **Compliance:** alignment CLAUDE.md → externalize via ADR formal

### Custos

- **Investigation time:** audit + classificação manual (~1 dia)
- **UI button effort:** depends Story 22.3 (`/admin/dispatch`) ou interim em `/admin/nps-monitor`
- **Operator friction:** modal confirmação dupla é UX overhead — aceito pra risk Critical

---

## Alternatives considered

### Alternativa 1 — Reativar cron com gate via env var

`if (env.NPS_CRON_ENABLED === 'true') schedule; else skip;`

**Rejeitada:** env var não-gated por user clique. Operator que sobe env var = bypass humano accidental. UI button mantém clique → confirmação → audit chain.

### Alternativa 2 — Cron rodando mas envia pra "modo sandbox"

Cron sempre rodando, mas só dispara real se `app_config.nps_live = true`.

**Rejeitada:** mesma falha — `app_config.nps_live = true` não é gated por user clique. Confunde dev/test/prod state.

### Alternativa 3 — Sem cron, sempre manual

Eliminar conceito cron NPS — admin sempre dispara manual.

**Aceita parcialmente:** pra hoje (state atual), sim. Long-term, se demand crescer + ROI manual baixar, reconsiderar — mas obriga novo ADR pra reativar conceito cron.

### Alternativa 4 — Slack-based approval workflow

Cron prepara dispatch batch + manda Slack message "Reply YES to send". Admin reply YES → dispara.

**Rejeitada:** Slack reply não tem trace UI/audit equivalente. Modal confirmation visual + count + sample é mais discoverable.

---

## Validation

### Audit script outputs

Run `bash scripts/audit-nps-crons.sh` gera:
- `docs/22.7-cron-inventory.md` (T1 — listagem completa)
- `docs/22.7-30d-report.md` (T2 — dispatches 30d)

### Negative grep verification

Pós-classificação completa, validar:

```bash
# Zero cron.schedule ativo (não-comentado) em migrations NPS
grep -rn "^[^-]*cron\.schedule" supabase/migrations/ | grep -iE "nps|dispatch_class_nps"
# Expected: 0 (ou linhas com comment "DORMANT BY DESIGN")
```

### Test case (se UI button implementado)

Turma sentinela (1 aluno mock):
1. Admin clica "Disparar NPS manual" em `/admin/dispatch`
2. Modal preview lista 1 aluno + content template
3. Modal confirmation com count=1 + sample
4. Slack alert "NPS manual dispatch START"
5. 1 message enviada via Meta DM
6. Slack alert "NPS manual dispatch COMPLETE"
7. Audit log entry com operator email + recipients + dry_run=false

---

## Known limitations

1. **Audit script depends PG cron extension:** `pg_cron.job` query falha se extension não instalada local. Roda contra prod com token cofre.

2. **30d report retroactive:** se audit_log não tinha event_type='nps_*_dispatch' pre-22.7, dados limitados. Workaround: olhar dispatch_history rows.

3. **Discovery audit pode ter mais crons não-mapeados:** grep `cron.schedule` em migrations cobre o conhecido. Crons criados via psql direct (sem migration) ficam fora — depend audit pg_cron.job query.

4. **UI button gate depends Story 22.3:** se 22.3 não pronta, interim em `/admin/nps-monitor` adiciona feature em página deprecated (refactor depois).

---

## References

- Story 22.7: `docs/stories/22.7.story.md`
- Story 22.7 PO validation: `docs/stories/22.7.validation.md` (GO 10/10)
- Audit script: `scripts/audit-nps-crons.sh`
- CLAUDE.md "Comunicação Externa NON-NEGOTIABLE"
- ADR-020 (RLS Hardening): audit_log Tier 2
- ADR-021 (Identity Unification)
- ADR-023 (Webhook Canonical)
- Memory `slack-always-on-dispatchers`
- Memory `admin-one-shot-send-pattern`
- Constitution Article IV (No Invention): `.aiox-core/constitution.md`

---

## Change Log

- 2026-05-22 @aiox-master — ADR-025 skeleton criado durante drafting code story 22.7 (T4)
- TBD @architect — Preencher classificação por cron após `bash scripts/audit-nps-crons.sh`
- TBD @architect — Atualizar status Draft → Accepted pós-classificação completa
