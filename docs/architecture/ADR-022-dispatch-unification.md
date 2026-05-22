# ADR-022 — Dispatch NPS Unification (dispatch-survey canonical + feature flag)

- **Status:** Proposed (drafting; aguarda apply prod + edge fn refactor follow-up)
- **Date:** 2026-05-22
- **Story:** [22.2 — Dispatch NPS Consolidation](../stories/22.2.story.md)
- **Epic:** [EPIC-022 — Painel Refactor](../epics/EPIC-022-painel-refactor.md) §S.022.2
- **Authors:** @architect (Aria), @dev (Dex via aiox-master)
- **Supersedes:** Nenhuma (primeira decisão formal sobre dispatch engine consolidation)
- **Migration:** `supabase/migrations/20260523010000_epic_022_s02_dispatch_unification.sql`
- **Depends on:** ADR-020 (RLS Hardening — app_config Tier 3 + is_dashboard_admin)

---

## Context

Discovery `01-architecture-map.md §4.1` identificou **3 caminhos paralelos** de dispatch NPS em produção:

| Path | Edge function | Schema/tabela | Trigger | Status |
|------|--------------|---------------|---------|--------|
| **A** | `dispatch-class-nps` | `nps_class_dispatch_jobs` + `nps_class_links` | cron 5m + manual | Ativo |
| **B** | `dispatch-survey` | `surveys` + `survey_responses` + `dispatch_history` | admin one-shot | Ativo (recente) |
| **C** | `send-whatsapp` | `notifications` + delivery_status | DB webhook (legacy) | Legacy |

**Problemas:**
- 3 schemas distintos → 3 lugares pra auditar entregas
- 3 dashboards (`nps-results`, `nps-monitor`, `envios`) inconsistentes
- Manutenção 3x: fix template Meta exige update em 3 lugares
- Cliente confuso: "qual dashboard consultar?"
- Path C (send-whatsapp) é legacy DB webhook — fluxo opaco

**Sistema EM PRODUÇÃO** com 1k+ alunos ativos + envios diários NPS. Refactor exige feature flag + rollback bidirecional + gate humano.

---

## Decision

### 1. dispatch-survey é canonical

| Critério | dispatch-survey | dispatch-class-nps | send-whatsapp |
|----------|:---------------:|:------------------:|:-------------:|
| Última atualização | 2026-05-22 | 2026-05-20 | 2026-04-22 |
| Throttle anti-rate-limit | ✅ 500ms | ❌ | ❌ |
| Hybrid Meta+Evolution | ✅ | ⚠️ | ⚠️ |
| Schema generic | ✅ surveys | ❌ nps-specific | ❌ notifications |
| dispatch_history rich (form_id, session_index) | ✅ | ❌ | ❌ |

**Decisão:** `dispatch-survey` mapeará `survey_type='nps_class'` → criar entries equivalentes em surveys + dispatch_history. Schema unificado.

### 2. Feature flag `nps_dispatch_engine` em app_config

```sql
INSERT INTO app_config (key, value) VALUES ('nps_dispatch_engine', 'legacy');
```

Valores: `'legacy'` (default seguro) | `'unified'`.

**Flip atômico via RPC** (não env var → muda sem redeploy):

```sql
SELECT set_nps_dispatch_engine('unified');  -- admin only
```

Default 'legacy' = path A continua funcionando. Sem flip = sem mudança comportamental.

### 3. RPC `set_nps_dispatch_engine(text)` — admin gated

- `SECURITY DEFINER` (bypassa RLS Tier 3 em app_config pra UPDATE)
- Gate: `is_dashboard_admin()` obrigatório
- Validação: `value IN ('legacy', 'unified')`
- Audit: INSERT em `audit_log` event_type='nps_engine_flip' com old_value + new_value + operator + audit_id

### 4. RPC helper `get_nps_dispatch_engine()` — público read

```sql
SELECT public.get_nps_dispatch_engine();  -- returns 'legacy' or 'unified'
```

Edge functions chamam esse RPC pra read flag value sem precisar select direct em app_config (mais rápido + cached pela SECURITY DEFINER).

### 5. Coluna `dispatch_type` enum em dispatch_history

```sql
ALTER TABLE dispatch_history ADD COLUMN dispatch_type text DEFAULT 'survey_generic'
  CHECK (dispatch_type IN ('nps_class', 'ps_rsvp', 'survey_generic', 'reminder'));
```

Permite agregar/filtrar dispatches por tipo. Rows existentes recebem 'survey_generic' (default conservador). Refactor edge fns vão setar tipo correto em INSERTs novos.

### 6. Rollback bidirecional first-class

```sql
-- Flip pra unified
SELECT set_nps_dispatch_engine('unified');

-- Bug detectado → rollback INSTANTÂNEO sem redeploy
SELECT set_nps_dispatch_engine('legacy');
```

Edge functions ambas continuam deployadas. Flag value determina qual rota.

### 7. Edge functions refactor — out-of-scope desta migration

Esta migration apenas schema + RPCs. Edge functions ficam **inalteradas** até refactor follow-up:

**Quando flag = 'unified':**
- `dispatch-survey` aceita `survey_type='nps_class'` (mapping schema)
- `dispatch-class-nps` lê flag, early return + log se 'unified'
- `send-whatsapp` marcado dormant + DROP TRIGGER notifications

**Quando flag = 'legacy':**
- Comportamento atual preservado (path A continua canonical)

Razão separação: rollback granular. Schema migration independente de edge fn refactor.

### 8. Smoke turma sentinela ANTES flip prod

Não-negotiable per Story 22.2 T9: dispatch-survey direct call com `survey_type='nps_class'` + class_id turma sentinela (low-stakes, ~5 alunos). Side-by-side compare com legacy path output. User aprova OU bloqueia flip.

### 9. Slack alert obrigatório no flip

Per memory `slack-always-on-dispatchers`: ausência Slack notify = sinal erro. RPC `set_nps_dispatch_engine` retorna `audit_id` pra UI (button caller) disparar Slack webhook com:
- Header: "NPS engine FLIP: {old} → {new}"
- Operator, timestamp, audit_id
- Quick rollback command pra reverter

### 10. Send-whatsapp legacy 30d safety window

Após flip → 'unified' + 30d sem reports incidente → DROP TRIGGER em notifications table desativando send-whatsapp.

`send-whatsapp` edge fn mantém deployada 30d adicionais (rollback ultimate emergency).

Após 60d total → drop edge fn + comment "DEPRECATED — replaced by dispatch-survey".

---

## Consequences

### Curto prazo (imediato pós-apply schema migration)

- ✅ Flag flag está em app_config (default 'legacy' — sem mudança comportamental)
- ✅ RPCs disponíveis pra chamada (admin UI button futuro + edge fn read)
- ✅ dispatch_type coluna disponível em dispatch_history (edge fns vão setar futuro)
- ⚠️ Edge functions NÃO atualizadas ainda — refactor follow-up
- ⚠️ Sem benefit imediato real — depend edge fn refactor + flip

### Longo prazo (pós-edge fn refactor + flip)

- **Single dispatch engine:** dispatch-survey lida com nps_class + ps_rsvp + survey_generic + reminder
- **Single schema:** surveys + dispatch_history + survey_links unifica
- **Maintenance 1x** vs 3x atual
- **Cliente claro:** 1 dashboard insights consolidado (depends 22.3)
- **Rollback < 5min:** RPC reverte sem redeploy

### Custos

- **Schema migration:** ADD COLUMN + INSERT row + CREATE 2 RPCs (low risk)
- **Storage:** dispatch_type column ~15 chars × N rows
- **Manutenção:** 2 RPCs + 1 flag + 1 CHECK constraint + 1 index
- **Edge fn refactor effort:** moderate (cross-cutting 3 edge fns + 1 trigger DROP)
- **Smoke sentinela:** 1 turma low-stakes pré-flip (manual)

---

## Alternatives considered

### Alternativa 1 — dispatch-class-nps continua canonical (path A)

Refactor dispatch-class-nps pra absorber funcionalidades dispatch-survey + send-whatsapp.

**Rejeitada:** dispatch-class-nps schema specific (nps_class_*). Generic ficaria over-engineered. dispatch-survey já tem generic schema.

### Alternativa 2 — Sem feature flag, refactor direto

Refactor edge fns + apagar legacy direct.

**Rejeitada:** rollback caro (redeploy + revert). Flag oferece flip < 5min sem code change.

### Alternativa 3 — Env var ao invés de app_config row

`Deno.env.get('NPS_ENGINE')` em edge fn.

**Rejeitada:** env var muda apenas em redeploy. app_config muda em SQL UPDATE (~10ms). Reactivity necessária pra rollback rápido.

### Alternativa 4 — Microservices (separar dispatch types em fn distintas)

dispatch-nps-class + dispatch-ps-rsvp + dispatch-survey-generic + dispatch-reminder.

**Rejeitada:** 4 fns vs 1 = 4x maintenance. Generic schema permite 1 fn handle múltiplos types.

### Alternativa 5 — Cron-based engine flag check

Cron job lê flag a cada minuto, decide qual fn invocar.

**Rejeitada:** added complexity. RPC inline na edge fn é mais simples + sem race conditions.

---

## Validation

### SQL validators

```sql
-- AC2: flag row existe
SELECT value FROM app_config WHERE key = 'nps_dispatch_engine';
-- expected: 'legacy' (default pós-apply schema migration)

-- AC3: RPC flip funciona
SELECT set_nps_dispatch_engine('unified');  -- admin only
SELECT get_nps_dispatch_engine();
-- expected: 'unified'

-- AC4: rollback
SELECT set_nps_dispatch_engine('legacy');
-- expected ok + audit_log entry com old='unified', new='legacy'

-- AC6: dispatch_type enum cobre 100% rows
SELECT count(*) FROM dispatch_history WHERE dispatch_type NOT IN ('nps_class','ps_rsvp','survey_generic','reminder');
-- expected: 0
```

### Smoke turma sentinela (manual — gate flip)

1. Identifica turma low-stakes (~5 alunos mock)
2. dispatch-survey direct invoke com `survey_type='nps_class'` + class_id sentinela
3. Compare entries em surveys + dispatch_history (unified) vs nps_class_links (legacy)
4. User aprova ou bloqueia flip prod

---

## Known limitations

1. **Schema migration sem edge fn refactor = sem benefit:** flag fica em app_config mas edge fns continuam path legacy. Refactor follow-up obrigatório pra realizar value.

2. **Flag race condition cross-cron:** se dispatch-class-nps cron tick acontecer no momento exato do flip, dispatch pode ocorrer em legacy mesmo flag='unified'. Mitigação: janela manutenção pra flip OU advisory lock (story update).

3. **send-whatsapp DROP TRIGGER risk:** se algum código não-mapeado escreve em `notifications` table esperando trigger, vai falhar silenciosamente pós-deprecation. Audit T1 cobre grep.

4. **30d safety window arbitrário:** se incidente aparecer dia 31, edge fn já dropada. Trade-off conservador 30d vs custo manutenção edge fn dormante.

---

## References

- Story 22.2: `docs/stories/22.2.story.md`
- Story 22.2 PO validation: `docs/stories/22.2.validation.md` (GO 9/10)
- Discovery 01-architecture-map §4.1
- Migration up: `supabase/migrations/20260523010000_epic_022_s02_dispatch_unification.sql`
- Migration down: `supabase/migrations/20260523010000_epic_022_s02_dispatch_unification.down.sql`
- Runbook (futuro): `docs/runbooks/22.2-nps-engine-flip.md` (drafting separado)
- Edge functions: `supabase/functions/{dispatch-survey,dispatch-class-nps,send-whatsapp}/`
- ADR-020 (RLS Hardening): app_config Tier 3
- ADR-021 (Identity Unification)
- ADR-023 (Webhook Canonical): pattern similar coluna + dedup
- Memory `slack-always-on-dispatchers`
- Memory `admin-one-shot-send-pattern`
- Constitution Article IV (No Invention): `.aiox-core/constitution.md`
- CLAUDE.md "Comunicação Externa NON-NEGOTIABLE" (flip = mudança comportamental crítica)

---

## Change Log

- 2026-05-22 @aiox-master — ADR-022 criado durante drafting code story 22.2 (T7)
- 2026-05-22 — Status: Proposed; aguarda apply prod (schema) + edge fn refactor follow-up + smoke sentinela + flip gate humano
