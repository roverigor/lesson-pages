# ADR-027 — Delivery Routing Provider Column (Evolution | Meta)

- **Status:** Proposed (drafting; aguarda apply prod)
- **Date:** 2026-05-22
- **Story:** [22.9 — Delivery Routing Provider Column](../stories/22.9.story.md)
- **Epic:** [EPIC-022 — Painel Refactor](../epics/EPIC-022-painel-refactor.md) §S.022.9
- **Authors:** @architect (Aria), @dev (Dex via aiox-master)
- **Supersedes:** Nenhuma (primeira decisão formal sobre delivery routing explicito)
- **Migration:** `supabase/migrations/20260523000000_epic_022_s09_delivery_provider.sql`
- **Depends on:** ADR-020 (RLS Hardening — notifications é Tier 2 admin read + service write)

---

## Context

Discovery `01-architecture-map.md` §4.4 identificou que 2 webhooks delivery (`delivery-webhook` Evolution + `meta-delivery-webhook` Meta) logam status na mesma tabela `notifications` **sem coluna provider**.

`dispatch-retry` edge function (DLQ retry processor) precisa decidir qual API chamar (Evolution vs Meta) pra cada row pendente. Sem coluna `provider`, heurística atual infere via:

- ID format check: se começa com `wamid.*` → Meta, else → Evolution
- Array check: se `evolution_message_ids` populated → Evolution

**Problemas heurística:**
- Frágil: se Meta API muda format ID, heurística quebra silenciosamente
- Falsos negativos: row sem nenhum ID populated → fallback ambíguo
- Tempo runtime: cada retry faz parse adicional
- Falha não-observada: retry pelo provider errado simplesmente falha + entra DLQ infinito

**Schema atual notifications (gap):**
- `evolution_message_ids TEXT[]` — adicionado em 20260402200000_delivery_status.sql
- `meta_message_id` — **NÃO existe** em notifications (existe em ps_rsvp_links + survey_links)
- Sem coluna `provider` discriminating

**Sistema EM PRODUÇÃO** com hybrid dispatch (Evolution groups + Meta DMs). Falha silenciosa em retry causa entregas perdidas sem alert.

---

## Decision

### 1. Coluna `provider` enum em `notifications`

```sql
ALTER TABLE notifications ADD COLUMN provider text DEFAULT 'evolution';
ALTER TABLE notifications ADD CONSTRAINT chk_notifications_provider
  CHECK (provider IN ('evolution','meta'));
```

Decisão coluna-driven (não heurística runtime): `dispatch-retry` lê `notification.provider` direto, route condicional sem parse.

### 2. Coluna `meta_message_id` (gap fix)

Pareia `evolution_message_ids` existente:

```sql
ALTER TABLE notifications ADD COLUMN meta_message_id text;
CREATE UNIQUE INDEX idx_notifications_meta_message
  ON notifications (meta_message_id)
  WHERE meta_message_id IS NOT NULL;
```

Sparse UNIQUE (NULL múltiplos OK, valor único) — correlação webhook delivery 1-to-1 com Meta.

### 3. 2-step migration (ADD com DEFAULT → backfill → NOT NULL)

**Step 1 (esta migration):**
1. ADD COLUMN provider DEFAULT 'evolution' (não-NULL imediato pra novos rows)
2. ADD COLUMN meta_message_id
3. Backfill heurística rows existentes
4. Validation gate (zero NULL)
5. NOT NULL constraint **deferred** pra Step 2

**Step 2 (migration follow-up):**
- `ALTER COLUMN provider SET NOT NULL`
- Apenas após review humano dos ambíguos (audit log entries)

**Razão deferred:** garantir review humano antes constraint rígida. Se heurística defaultou ambíguos como 'evolution' incorretamente, oportunidade pra corrigir manualmente.

### 4. Heurística backfill 3-tier

```
1. evolution_message_ids NOT NULL AND array_length > 0 → 'evolution'
2. meta_message_id NOT NULL → 'meta'
3. Ambíguo (nenhum) → DEFAULT 'evolution' + audit log + Slack alert futuro
```

**Por que evolution default:**
- Migração `20260402200000_delivery_status.sql` introduziu `evolution_message_ids` ANTES de Meta DMs serem implementadas
- Rows pré-Meta híbrido só podiam ser Evolution
- Default 'evolution' é conservador (Meta é integration mais nova)

**Audit log ambíguo:**
- Event type `notifications_provider_backfill_ambiguous`
- Payload: count + sample 5 rows (id, type, status, created_at)
- Flag `requires_review: true` pra triagem manual

### 5. RPC `backfill_notifications_provider()` SECURITY DEFINER + service_role only

```sql
GRANT EXECUTE ... TO service_role;
REVOKE EXECUTE ... FROM authenticated, anon;
```

Razão: RLS Tier 2 bloquearia UPDATE direct. SECURITY DEFINER bypassa RLS pra execução cron/script. Service_role only pra evitar admin acidental rodar.

### 6. Edge functions refactor (out-of-scope desta migration)

Esta migration apenas schema. Edge functions ficam **inalteradas** até refactor follow-up (responsabilidade @dev real story 22.9 T5/T6):

- `dispatch-retry` → ler `notification.provider`, route condicional Evolution/Meta
- 5 dispatchers (dispatch-survey, dispatch-class-nps, etc) → gravar `provider` em todo INSERT

Razão: separar schema migration de edge fn refactor permite rollback granular.

### 7. Idempotência via `ADD COLUMN IF NOT EXISTS` + `DROP CONSTRAINT IF EXISTS`

Migration rerun-safe. PG 15 suporta IF NOT EXISTS em colunas. Constraints/indexes usam DROP + CREATE pattern.

### 8. Validation gate (T6) força backfill completo

```sql
IF (SELECT count(*) FROM notifications WHERE provider IS NULL) > 0 THEN
  RAISE EXCEPTION 'Backfill failed: % rows still NULL';
END IF;
```

Falha rápido se backfill não cobriu todos rows. Step 2 NOT NULL só roda se gate passa.

---

## Consequences

### Curto prazo (imediato pós-apply)

- ✅ Rows novos têm `provider` populated automaticamente (DEFAULT 'evolution' + edge fns vão precisar UPDATE futuro)
- ✅ Rows legacy backfilled via heurística (evolution_message_ids OR meta_message_id OR fallback)
- ✅ `meta_message_id` available pra Meta webhook correlation
- ⚠️ Edge functions atuais NÃO escrevem `provider` em INSERTs (default kicks in — sub-optimal mas seguro)
- ⚠️ `dispatch-retry` continua com heurística atual (refactor follow-up necessário pra benefit real)

### Longo prazo

- **Edge fn refactor:** 5 dispatchers atualizados pra gravar `provider` em INSERT; dispatch-retry refactored coluna-driven
- **Step 2 NOT NULL:** após review humano dos ambíguos, força provider sempre populated
- **Observability:** dashboards podem filtrar/agrupar por provider (`SELECT provider, count(*) FROM notifications GROUP BY 1`)
- **Retry reliability:** zero retries pelo provider errado

### Custos

- **Storage:** 2 colunas (~15 chars cada) × N rows
- **Latency:** trigger overhead zero (apenas DEFAULT em INSERT)
- **Manutenção:** 1 RPC + 1 CHECK + 2 INDEX
- **Lock:** ALTER TABLE ADD COLUMN ACCESS EXCLUSIVE momentâneo — janela manutenção sugerida

---

## Alternatives considered

### Alternativa 1 — NOT NULL inline (single-step migration)

`ADD COLUMN provider text NOT NULL DEFAULT 'evolution'`.

**Rejeitada:** se DEFAULT errado pra rows existentes, sem oportunidade review. 2-step com gate humano é mais seguro.

### Alternativa 2 — provider derivado via GENERATED column

```sql
provider text GENERATED ALWAYS AS (
  CASE WHEN evolution_message_ids IS NOT NULL THEN 'evolution'
       WHEN meta_message_id IS NOT NULL THEN 'meta'
       ELSE 'evolution' END
) STORED
```

**Rejeitada:** GENERATED em PG 15 com CASE complexo é frágil. Reaplica em todo UPDATE de qualquer coluna. Pattern coluna real + trigger BEFORE (se necessário) é mais maintainable.

### Alternativa 3 — Tabela separada `delivery_routing`

Tabela ponte (notification_id, provider, external_id).

**Rejeitada:** introduz 4ª tabela. Coluna inline resolve igual sem overhead JOIN.

### Alternativa 4 — Heurística runtime preservada (sem coluna)

Continuar com `dispatch-retry` parsing ID format.

**Rejeitada:** problema raiz — frágil + falsos negativos + sem observability. Coluna explicita resolve definitivamente.

### Alternativa 5 — Múltiplos provider values (whatsapp_business_evolution, whatsapp_business_meta, sms, email)

Enum mais granular pra futuro.

**Rejeitada:** YAGNI. AL hoje só usa Evolution + Meta. Adicionar valores futuro = ALTER CHECK constraint (low cost).

---

## Validation

### SQL validators

```sql
-- Zero NULL provider pós-backfill (Step 1)
SELECT count(*) FROM notifications WHERE provider IS NULL;
-- expected: 0

-- Distribuição provider
SELECT provider, count(*) FROM notifications GROUP BY 1;
-- esperado: evolution majority + meta minority

-- Ambíguos audit log entries
SELECT count(*), max(created_at) FROM audit_log
WHERE event_type = 'notifications_provider_backfill_ambiguous';
-- esperado: 0-1 entries (1x backfill execution)
```

### Smoke script

`scripts/smoke-delivery-provider.sh` — 7 cenários:
1. Schema columns existem (provider + meta_message_id)
2. CHECK constraint rejeita value inválido
3. evolution_message_ids row → backfill 'evolution'
4. meta_message_id row → backfill 'meta'
5. row sem identificadores → default 'evolution' + audit ambíguo
6. UNIQUE meta_message_id sparse (multi-NULL OK + valor único rejected)
7. Migration idempotência (rerun ADD COLUMN IF NOT EXISTS)

---

## Known limitations

1. **Heurística fallback evolution:** rows pre-Meta era só evolution, mas se MIGRATION rodou após Meta API live + rows criados sem `meta_message_id` populated (race condition no edge fn) → false positive. Mitigação: audit log + Slack alert + Step 2 deferred.

2. **dispatch-retry sem refactor = sem benefit:** se migration aplicada mas edge fn não refatorada, schema fica unused. Story 22.9 T5 cobre refactor — não-bloqueante mas perde value.

3. **Cross-channel provider:** AL hoje só Evolution + Meta WhatsApp. Se futuramente adicionar SMS/Email, CHECK constraint precisa ALTER + valores enum. Aceito (YAGNI).

4. **Meta_message_id pre-existente fora notifications:** ps_rsvp_links + survey_links já têm meta_message_id próprio. Não consolidamos — cada tabela mantém seu (correlation acontece via JOIN downstream).

---

## References

- Story 22.9: `docs/stories/22.9.story.md`
- Story 22.9 PO validation: `docs/stories/22.9.validation.md` (GO 9/10)
- Discovery 01-architecture-map: `docs/discovery/2026-05-22/01-architecture-map.md` §4.4
- Schema notifications: `supabase/migrations/20260402175137_notifications_schema.sql`
- evolution_message_ids: `supabase/migrations/20260402200000_delivery_status.sql`
- meta_message_id pattern: `supabase/migrations/20260519010000_ps_rsvp_meta_migration.sql`
- ADR-020 (RLS Hardening): notifications Tier 2
- ADR-021 (Identity Unification): pattern function IMMUTABLE + trigger
- ADR-023 (Webhook Canonical): pattern coluna + heurística + audit ambíguo (similar)
- Migration up: `supabase/migrations/20260523000000_epic_022_s09_delivery_provider.sql`
- Migration down: `supabase/migrations/20260523000000_epic_022_s09_delivery_provider.down.sql`
- Smoke script: `scripts/smoke-delivery-provider.sh`
- Edge functions: `supabase/functions/dispatch-retry/`, `delivery-webhook/`, `meta-delivery-webhook/`
- Constitution Article IV (No Invention): `.aiox-core/constitution.md`

---

## Change Log

- 2026-05-22 @aiox-master — ADR-027 criado durante drafting code story 22.9 (T8)
- 2026-05-22 — Status: Proposed; aguarda apply prod (Step 1) + Step 2 NOT NULL follow-up + edge fn refactor
