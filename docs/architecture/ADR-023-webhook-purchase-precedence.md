# ADR-023 — Webhook Purchase Precedence (AC > Hotmart > Generic + dedup_key)

- **Status:** Proposed (drafting; aguarda apply prod)
- **Date:** 2026-05-22
- **Story:** [22.5 — Webhook Purchase Canonical](../stories/22.5.story.md)
- **Epic:** [EPIC-022 — Painel Refactor](../epics/EPIC-022-painel-refactor.md) §S.022.5
- **Authors:** @architect (Aria), @dev (Dex via aiox-master)
- **Supersedes:** Nenhuma (primeira decisão formal sobre webhook purchase precedence)
- **Migration:** `supabase/migrations/20260522230000_epic_022_s05_webhook_canonical.sql`
- **Depends on:** ADR-020 (RLS Hardening — ac_purchase_events é exceção RLS, service_role only)

---

## Context

Discovery `01-architecture-map.md` §4.3 identificou 3 webhooks de compra em produção escrevendo na mesma tabela `ac_purchase_events` SEM precedência clara:

| Webhook | Fonte | Schema do payload | Status |
|---------|-------|--------------------|--------|
| `ac-purchase-webhook` | ActiveCampaign | `payload->contact->email` + `payload.product_id` + `payload.date` | Ativo — EPIC-015 |
| `hotmart-purchase-webhook` | Hotmart | `payload->buyer->email` + `payload.product.id` + `payload.purchase.order_date` | Ativo |
| `generic-purchase-webhook` | Fallback | `payload.email` + `payload.product_id` + `payload.purchase_date` | Ativo |

**Problemas observados:**
- Se Hotmart event fire `hotmart-*` E `generic-*` → 2 linhas pra mesma compra
- AC e Hotmart podem disparar simultaneamente pro mesmo aluno → race condition
- Coluna `source` não existe → impossível auditar qual webhook escreveu
- Sem dedup tupla → mesma compra pode aparecer N vezes em `student_imports` pós-processing

**Sistema EM PRODUÇÃO** com integrações AC + Hotmart ativas. Risco: cobrar 2x o mesmo aluno em fluxo automation, ou perder eventos silenciosamente.

---

## Decision

### 1. Precedência: AC > Hotmart > Generic

| Source | Role |
|--------|------|
| `ac` | **CANONICAL** — source-of-truth contratual (AL contrata AC pra automation) |
| `hotmart` | **FALLBACK** — eventos sem counterpart AC |
| `generic` | **DEPRECATED** — logging-only post-30d safety window |

**Por que AC canonical:**
- AC é a plataforma onde fluxos de automation rodam (email + nurturing + lifecycle)
- Hotmart é apenas gateway pagamento — não dispatch
- Generic é fallback histórico, raramente usado

### 2. Coluna `source` enum em `ac_purchase_events`

```sql
ALTER TABLE ac_purchase_events ADD COLUMN source text DEFAULT 'ac';
ALTER TABLE ac_purchase_events ADD CONSTRAINT chk_ac_purchase_source
  CHECK (source IN ('ac','hotmart','generic'));
```

Backfill rows existentes → `source = 'ac'` (origem mais comum legacy).

### 3. Coluna `purchase_dedup_key` derivada por source

Schema atual armazena tudo em `payload JSONB` — não há colunas `email`/`product_id`/`purchase_date` materializadas. Schema do payload **varia por source**.

**Solução:** função `extract_purchase_dedup_key(source, payload)` IMMUTABLE que extrai chave normalizada conforme source:

| Source | Path no payload |
|--------|-----------------|
| AC | `payload->contact->email` + `payload->product_id` + `payload->date` |
| Hotmart | `payload->buyer->email` + `payload->product->id` + `payload->purchase->order_date` |
| Generic | `payload->email` + `payload->product_id` + `payload->purchase_date` |

**Normalizações aplicadas:**
- Email: `lower(trim(...))` — case-insensitive dedup
- Date: `substring(date from 1 for 10)` — só YYYY-MM-DD (strip time)
- Retorna `NULL` se qualquer componente missing → caller decide tratar

**Trigger BEFORE INSERT/UPDATE** popula `purchase_dedup_key` automaticamente — webhook não precisa saber.

### 4. UNIQUE constraint DEFERRED (gate humano)

`UNIQUE(source, purchase_dedup_key)` fica em **migration follow-up separada**, gate pre-apply:

```sql
SELECT count(*) FROM (
  SELECT source, purchase_dedup_key, count(*) FROM ac_purchase_events
  WHERE purchase_dedup_key IS NOT NULL
  GROUP BY 1, 2 HAVING count(*) > 1
) dups;
-- expected: 0
```

**Razão deferred:** se prod tiver duplicates não-detectados antes, ALTER falha → migration trava. Separar minimiza blast radius.

Migration intermediária loga WARNING + audit_log entry se duplicates detectados, sem bloquear apply.

### 5. UNIQUE intra-source (não cross-source)

`UNIQUE(source, purchase_dedup_key)` — não `UNIQUE(purchase_dedup_key)` global.

**Razão:** mesmo aluno comprando mesmo produto via AC E via Hotmart é cenário legítimo:
- AC tracking marketing automation
- Hotmart processando pagamento
- 2 eventos distintos pra mesma compra business

Dedup cross-source é responsabilidade do edge function (UPSERT pattern com AC canonical override Hotmart se ambos chegam) — não constraint database.

### 6. Edge functions refactor (out-of-scope desta migration)

Esta migration apenas adiciona schema. Edge functions ficam **inalteradas** até refactor follow-up (responsabilidade @dev real durante implementação story 22.5):

- `ac-purchase-webhook` → UPSERT pattern (canonical override)
- `hotmart-purchase-webhook` → INSERT ON CONFLICT DO NOTHING (fallback)
- `generic-purchase-webhook` → logging-only (30d safety)

Razão: separar schema migration de edge fn refactor permite rollback granular.

### 7. Coluna source default 'ac' + NOT NULL pós-backfill

```sql
ADD COLUMN source text DEFAULT 'ac';
UPDATE ... SET source = 'ac' WHERE source IS NULL;  -- redundant mas explícito
ALTER COLUMN source SET NOT NULL;
```

Sequência permite migration safe:
1. Default 'ac' aplica em rows novos antes refactor edge fns
2. Backfill explícito audit trail
3. NOT NULL pós-backfill OK garantido

### 8. Idempotência via `ADD COLUMN IF NOT EXISTS`

Migration é rerun-safe. PG 15 suporta `ADD COLUMN IF NOT EXISTS`. CHECK + INDEX + TRIGGER usam DROP IF EXISTS + CREATE.

---

## Consequences

### Curto prazo (imediato pós-apply)

- ✅ Trigger popula `purchase_dedup_key` em todos INSERTs novos automaticamente
- ✅ Audit: queries podem agrupar/filtrar por `source` (3 caminhos visíveis)
- ✅ Backfill rows legacy recebe `source='ac'` (audit trail clean)
- ⚠️ Edge functions continuam escrevendo SEM `source` em INSERT — default 'ac' kicks in (sub-optimal mas seguro)
- ⚠️ Duplicates pré-existentes podem ser detectados (WARNING log)

### Longo prazo

- **Edge fn refactor** (follow-up): AC UPSERT, Hotmart fallback, Generic logging-only
- **UNIQUE constraint** (migration follow-up): após duplicates resolvidos
- **Cross-source dedup analytics**: `SELECT source, count(*) FROM ac_purchase_events GROUP BY 1` visível
- **Generic 410 Gone** (post-30d): edge fn retorna 410 instead of logging

### Custos

- **Storage:** 2 colunas TEXT extra × N rows = pequeno (~20 chars cada)
- **Latency:** Trigger overhead ~µs (função IMMUTABLE)
- **Manutenção:** 2 functions + 1 trigger + 1 CHECK + 1 INDEX
- **Lock:** `ALTER TABLE ADD COLUMN` adquire ACCESS EXCLUSIVE momentaneamente — janela manutenção sugerida

---

## Alternatives considered

### Alternativa 1 — UNIQUE constraint inline (não deferred)

Adicionar UNIQUE direto na migration up.

**Rejeitada:** se prod tem duplicates não-detectados pré-existentes, ALTER falha + migration trava. Deferred + gate é mais seguro.

### Alternativa 2 — Dedup `(email, product_id, purchase_date)` global (não por source)

UNIQUE cross-source.

**Rejeitada:** mesmo aluno comprando via AC E Hotmart é cenário legítimo. Cross-source dedup é responsabilidade edge fn, não constraint.

### Alternativa 3 — Materializar email/product_id/purchase_date como colunas separadas

ADD COLUMN email text, product_id text, purchase_date date + backfill cada.

**Rejeitada:** schema do payload varia por source. Materializar exige mapping function igual. Coluna única `purchase_dedup_key` (string concatenada) é mais simples + permite normalização (lowercase email, date strip).

### Alternativa 4 — Tabela separada `purchase_dedup_index`

Tabela secundária mapping (source, dedup_key) → ac_purchase_events.id.

**Rejeitada:** 4ª tabela. Trigger + coluna materializada resolve igual sem custo manutenção.

### Alternativa 5 — Generated column (PG 15 supporta STORED)

```sql
purchase_dedup_key text GENERATED ALWAYS AS (extract_purchase_dedup_key(source, payload)) STORED
```

**Rejeitada:** GENERATED em PG 15 NÃO suporta calls a non-IMMUTABLE funções diretamente, e validação é mais rígida. Trigger BEFORE oferece controle equivalente sem essa rigidez. Pattern consistente com 22.1 normalize_phone_e164.

---

## Validation

### SQL validators (AC7)

```sql
-- AC7.1: dedup_key populado em rows novos (post-trigger)
SELECT count(*) FROM ac_purchase_events
WHERE created_at > now() - interval '1 hour'
  AND purchase_dedup_key IS NULL
  AND payload IS NOT NULL;
-- expected: 0 (todos novos têm dedup_key se payload tinha keys necessárias)

-- AC7.2: source enum cobre 100% rows
SELECT count(*) FROM ac_purchase_events WHERE source NOT IN ('ac','hotmart','generic');
-- expected: 0

-- AC7.3: detectar duplicates pre-UNIQUE
SELECT source, purchase_dedup_key, count(*) FROM ac_purchase_events
WHERE purchase_dedup_key IS NOT NULL
GROUP BY 1, 2 HAVING count(*) > 1;
-- expected: 0 antes de adicionar UNIQUE constraint
```

### Smoke script (AC7)

`scripts/smoke-webhook-canonical.sh` — 7 cenários:
1. AC INSERT extrai dedup_key (com lowercase email + date trim)
2. Hotmart INSERT extrai dedup_key (schema diferente)
3. Generic INSERT extrai dedup_key
4. CHECK rejeita source inválido
5. Payload incompleto → dedup_key NULL
6. extract_purchase_dedup_key direct call (unit)
7. Migration idempotência (ADD COLUMN IF NOT EXISTS rerun)

---

## Known limitations

1. **Schema payload pode mudar:** se AC API v3 mudar `contact.email` → `customer.email`, função `extract_purchase_dedup_key` precisa update (não automatic). Trade-off: pinned em ADR.

2. **Email case-insensitive:** lowercase normalization assume email é case-insensitive (RFC 5321 permite case-sensitive local-part, mas práticas web normalizam). Se houver alunos com mesma user@ mas case diferente esperando ser distintos → conflict. Aceito: lowercase é norma global.

3. **Date trim a YYYY-MM-DD:** descarta timezone + time. Compra às 23:59 UTC vs 00:01 UTC dia seguinte podem ser tratadas como mesma "data" em fusos diferentes. Trade-off: dedup business-level (1 compra/dia/produto/cliente) > timestamp exato.

4. **Dedup_key NULL não bloqueia INSERT:** se payload não tem keys esperadas, dedup_key fica NULL. Row é aceita (audit trail), mas não conta pra UNIQUE quando aplicado. Risk: duplicates "fantasma" só visíveis via WHERE dedup_key IS NULL — exige monitoring.

---

## References

- Story 22.5: `docs/stories/22.5.story.md`
- Story 22.5 PO validation: `docs/stories/22.5.validation.md` (GO 9/10)
- Discovery 01-architecture-map: `docs/discovery/2026-05-22/01-architecture-map.md` §4.3
- Schema source: `supabase/migrations/20260505100000_epic015_schema.sql` (ac_purchase_events CREATE)
- ADR-020 (RLS Hardening): exceção ac_purchase_events
- ADR-021 (Identity Unification): pattern function IMMUTABLE + trigger BEFORE
- Migration up: `supabase/migrations/20260522230000_epic_022_s05_webhook_canonical.sql`
- Migration down: `supabase/migrations/20260522230000_epic_022_s05_webhook_canonical.down.sql`
- Smoke script: `scripts/smoke-webhook-canonical.sh`
- Edge functions: `supabase/functions/{ac,hotmart,generic}-purchase-webhook/`
- Constitution Article IV (No Invention): `.aiox-core/constitution.md`

---

## Change Log

- 2026-05-22 @aiox-master — ADR-023 criado durante drafting code story 22.5 (T7)
- 2026-05-22 — Status: Proposed; aguarda apply prod + edge fn refactor follow-up
