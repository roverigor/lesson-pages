# ADR-016: Async Dispatch Strategy — Webhook AC + Cold Start Mitigation

**Status:** Accepted
**Date:** 2026-05-04
**Deciders:** @architect (Aria), informado por @qa (Quinn)
**Context:** EPIC-015 — Edge function `ac-purchase-webhook` + cold start risk
**Resolves:** Critique CRIT-5

---

## 1. Contexto

### Constraints

| Origem | Constraint |
|---|---|
| ActiveCampaign | Webhook timeout HTTP < 10s; reenvio agressivo se 5xx |
| NFR-6 | Webhook AC responde p95 < 2s |
| Supabase Edge Functions (Deno) | Cold start observado 500-1500ms; warm <50ms |
| Story 15.B | Handler precisa: HMAC validate → dedup → resolve student → resolve mapping → enqueue dispatch |
| CON-13/14 | Stack restrita a Supabase + VPS Contabo (sem Cloudflare Workers) |
| Volume | 1000 disparos/dia esperado (~0.7/min, mas com bursts em dias de campanha) |
| Reliability | NFR-4 idempotência + NFR-10 alert se fail rate > 10% |

### Problema

Worst-case sequência síncrona:
- Cold start: 1500ms
- HMAC validate: 5ms
- INSERT ac_purchase_events: 50ms (network round trip)
- SELECT student by email: 30ms
- INSERT student (se novo): 50ms
- SELECT ac_product_mappings: 30ms
- INSERT student_cohorts: 30ms
- INSERT survey_recipients + survey_links: 60ms
- Enqueue dispatch (HTTP call para outra edge function): 800ms cold start + 30ms

**Total worst-case: ~2585ms** → estoura NFR-6 < 2s.

Se enviarmos `pending` p/ dispatch sync (não async), pior ainda — pode chegar a 12s+ → AC timeout → reenvio massivo → idempotência sob estresse.

## 2. Opções Consideradas

### Opção A — Warm-up Cron Only

Cron `pg_cron` chama webhook synthetic a cada 4 minutos para manter função quente.

**Pró:**
- Simples — 1 linha pg_cron
- Reduz cold start a ~50ms

**Contra:**
- Custo: 360 invocações/dia adicionais
- Não resolve o trabalho síncrono pesado (~1000ms mesmo warm)
- Falha se Supabase reciclar contêiner entre warm-ups
- Não escala para múltiplas edge functions

### Opção B — Minimal-Sync Handler + pg_cron Worker

Webhook só:
1. Valida HMAC
2. INSERT em `ac_purchase_events` com status='received'
3. Retorna 200

`pg_cron` job a cada 30s:
1. SELECT FROM ac_purchase_events WHERE status='received' FOR UPDATE SKIP LOCKED LIMIT 50
2. Para cada evento: resolve student, mapping, criar survey_links, enqueue dispatch
3. UPDATE status='processed'

**Pró:**
- Webhook handler responde em <500ms warm, <2s cold (só HMAC + INSERT) — NFR-6 atendido
- Worker tem 30s entre execuções → tolerância a falhas; retries fáceis
- SKIP LOCKED permite múltiplos workers paralelos no futuro sem reescrita
- Idempotência via UNIQUE ac_event_id já garantida no INSERT
- Custo zero adicional (pg_cron é grátis no Supabase Pro)

**Contra:**
- Latência total event → dispatch aumenta ~30s (acceptable para onboarding)
- Adds complexidade de stateful worker (estado em DB)
- Erros no worker precisam alerta separado

### Opção C — Cloudflare Worker Frontend

Webhook AC bate em CF Worker (cold start ~5ms), que valida e proxy para Supabase Edge Function.

**Pró:**
- Cold start eliminado

**Contra:**
- Quebra CON-13 (stack Supabase-only)
- Adds Cloudflare account + secrets management
- Mais 1 ponto de falha
- Custo CF Workers free tier OK mas adicionado

### Opção D — Aceitar p95 < 5s

Atualizar NFR-6 para 5s e operar sem mitigação.

**Pró:**
- Zero trabalho extra

**Contra:**
- AC timeout 10s — margem fica curta
- Em pico simultâneo (várias compras AC) cold starts em série → cascateamento
- NFR-6 escrito = compromisso; relaxar = perda de qualidade

## 3. Decisão

**Adotamos Hybrid — Opção B (primary) + Opção A (safety net).**

### Arquitetura Final

```
┌──────────────────┐
│  ActiveCampaign  │
└────────┬─────────┘
         │ POST webhook (HMAC X-AC-Signature)
         ▼
┌──────────────────────────────────────┐
│  Edge Function: ac-purchase-webhook  │
│  (minimal-sync handler)              │
│                                      │
│  1. Validar HMAC                     │
│  2. INSERT ac_purchase_events        │
│     (status='received')              │
│     ON CONFLICT (ac_event_id) DO     │
│     NOTHING                          │
│  3. Return 200 + event_id            │
│                                      │
│  Tempo total p95: <500ms warm,       │
│                   <2s cold           │
└────────┬─────────────────────────────┘
         │
         │ persist
         ▼
┌──────────────────────────────────────┐
│  PostgreSQL: ac_purchase_events       │
│  status='received'                   │
└────────┬─────────────────────────────┘
         │
         │ pg_cron polled every 30s
         ▼
┌──────────────────────────────────────┐
│  pg_cron: process_ac_events          │
│  (SQL function ou plpython3u)        │
│                                      │
│  SELECT ... FOR UPDATE SKIP LOCKED   │
│  WHERE status='received'             │
│  LIMIT 50                            │
│                                      │
│  Para cada event:                    │
│  1. UPSERT student                   │
│  2. Lookup ac_product_mappings       │
│  3a. HIT → INSERT student_cohorts +  │
│       INSERT survey_recipients +     │
│       INSERT survey_links            │
│       → INVOKE dispatch-survey       │
│  3b. MISS → INSERT pending_*         │
│       → Slack notify                 │
│  4. UPDATE status='processed'        │
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│  pg_cron: warmup-edge-functions      │
│  (every 4min, parallel safety net)   │
│                                      │
│  HTTP HEAD ac-purchase-webhook       │
│  HTTP HEAD ac-report-dispatch        │
│  HTTP HEAD meta-delivery-webhook     │
│  (synthetic, sem trabalho real)      │
└──────────────────────────────────────┘
```

### Schema Adicional

```sql
-- Eventos AC com workflow
ALTER TABLE ac_purchase_events
  ADD COLUMN status TEXT NOT NULL DEFAULT 'received'
    CHECK (status IN ('received','processing','processed','failed','duplicate')),
  ADD COLUMN processing_started_at TIMESTAMPTZ,
  ADD COLUMN processed_at TIMESTAMPTZ,
  ADD COLUMN retry_count INT NOT NULL DEFAULT 0,
  ADD COLUMN last_error TEXT;

CREATE INDEX idx_ac_events_pending
  ON ac_purchase_events (created_at)
  WHERE status = 'received';

-- Worker pg_cron
SELECT cron.schedule(
  'process-ac-events',
  '*/30 * * * * *',  -- every 30 seconds
  $$
    SELECT process_ac_purchase_events_batch();
  $$
);

-- Warm-up cron
SELECT cron.schedule(
  'warmup-edge-functions',
  '*/4 * * * *',  -- every 4 minutes
  $$
    SELECT net.http_get(url := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/ac-purchase-webhook?warmup=1');
    SELECT net.http_get(url := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/ac-report-dispatch?warmup=1');
    SELECT net.http_get(url := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/meta-delivery-webhook?warmup=1');
  $$
);
```

### Worker SQL Function (pseudocódigo)

```sql
CREATE OR REPLACE FUNCTION process_ac_purchase_events_batch()
RETURNS TABLE(processed_count INT, failed_count INT) AS $$
DECLARE
  evt RECORD;
  proc_count INT := 0;
  fail_count INT := 0;
BEGIN
  FOR evt IN
    SELECT id, payload
    FROM ac_purchase_events
    WHERE status = 'received'
      AND retry_count < 3
    ORDER BY created_at
    LIMIT 50
    FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      UPDATE ac_purchase_events
        SET status = 'processing',
            processing_started_at = now()
        WHERE id = evt.id;

      -- Resolve student (find by email | create)
      -- Lookup ac_product_mappings
      -- Either: insert student_cohorts + survey_recipients + survey_links + invoke dispatch-survey
      -- Or: insert pending_student_assignments + slack alert

      UPDATE ac_purchase_events
        SET status = 'processed',
            processed_at = now()
        WHERE id = evt.id;

      proc_count := proc_count + 1;
    EXCEPTION WHEN OTHERS THEN
      UPDATE ac_purchase_events
        SET status = 'received',
            retry_count = retry_count + 1,
            last_error = SQLERRM
        WHERE id = evt.id;
      fail_count := fail_count + 1;
    END;
  END LOOP;

  RETURN QUERY SELECT proc_count, fail_count;
END;
$$ LANGUAGE plpgsql;
```

### Webhook Handler (Pseudocódigo Edge Function)

```typescript
serve(async (req) => {
  // Warm-up early-exit
  const url = new URL(req.url);
  if (url.searchParams.get("warmup") === "1") {
    return new Response("ok", { status: 200 });
  }

  // 1. HMAC validation (~5ms)
  const sig = req.headers.get("X-AC-Signature");
  const body = await req.text();
  if (!validateHmac(body, sig, AC_WEBHOOK_SECRET)) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  // 2. Parse + extract ac_event_id
  const payload = JSON.parse(body);
  const acEventId = payload.event_id || `${payload.order_id}_${payload.contact_id}`;

  // 3. INSERT (idempotente via UNIQUE constraint)
  const { error } = await sb.from("ac_purchase_events").insert({
    ac_event_id: acEventId,
    payload,
    status: "received"
  });

  // ON CONFLICT: silent dedup, retorna 200
  if (error?.code === "23505") {
    return jsonResponse({ status: "duplicate", event_id: acEventId }, 200);
  }
  if (error) {
    return jsonResponse({ error: "db_error" }, 500);
  }

  // 4. Return 200 imediato
  return jsonResponse({ status: "accepted", event_id: acEventId }, 200);
});
```

## 4. Métricas Esperadas

| Métrica | Antes (sync naive) | Após (Hybrid) |
|---|---|---|
| Webhook p95 cold | ~2.5s ❌ | ~1.5s ✅ |
| Webhook p95 warm | ~1s ⚠️ | ~150ms ✅ |
| AC timeout risk | Alto | Mínimo |
| Latência event → dispatch | <2s | ~30s ⚠️ aceitável |
| Throughput simultâneo | 1 evento/s | 50 eventos/30s = 100/min ✅ |
| Cold start invocations/dia | 0 | 360 (warm-up) |

## 5. Trade-offs Aceitos

| Trade-off | Justificativa |
|---|---|
| +30s latência event → dispatch | Onboarding não exige tempo real (<5min é meta de negócio) |
| Stateful worker em pg_cron | Simples, observável via `cron.job_run_details`, sem infra extra |
| 360 warm-ups/dia | Custo desprezível no plano Supabase Pro |
| Worker single-instance V1 | Backpressure via SKIP LOCKED; escalar se >1000 eventos/min |

## 6. Observabilidade Obrigatória (NFR-10)

```sql
-- View de saúde
CREATE VIEW ac_integration_health AS
SELECT
  date_trunc('hour', created_at) AS hour,
  status,
  COUNT(*) AS count,
  AVG(EXTRACT(EPOCH FROM (processed_at - created_at))) AS avg_latency_seconds
FROM ac_purchase_events
WHERE created_at > now() - INTERVAL '24 hours'
GROUP BY hour, status
ORDER BY hour DESC;

-- Alert pg_cron
SELECT cron.schedule(
  'alert-ac-health',
  '*/15 * * * *',
  $$
    SELECT alert_slack_if_unhealthy();
  $$
);
```

`alert_slack_if_unhealthy()` envia DM Slack se:
- Fail rate últimas 1h > 10%
- Eventos `received` há > 5min (worker travado)
- Worker last_error count > 5 últimas 1h

## 7. Rollback Plan

Se Opção B falhar em produção:
1. Disable pg_cron job `process-ac-events`
2. Recompilar webhook handler com lógica completa síncrona (código já existe em branch `epic-015-sync-fallback`)
3. Aceitar NFR-6 degradado para < 5s temporariamente
4. Investigar root cause; ressuscitar worker

## 8. Implementation Notes

### Story 15.B (`ac-purchase-webhook`)
- Implementação: minimal-sync handler conforme §3 pseudocódigo
- Tests: HMAC valid/invalid, dedup, payload malformado, warmup mode

### Story 15.A (Schema)
- Migration adiciona colunas workflow + index parcial + 2 cron jobs
- View `ac_integration_health` na mesma migration

### Story 15.E (Observabilidade)
- Função `alert_slack_if_unhealthy()` + cron 15min
- Slack notify via existing `_shared/slack.ts`

### Story Não Listada Anteriormente — 15.L: Worker Function

**Adicionar nova story:**

| # | Story | Repo | Tamanho |
|---|---|---|---|
| 15.L | SQL Function `process_ac_purchase_events_batch()` + pg_cron schedule | lesson-pages | M |

Posicionamento: depende de 15.A (schema), bloqueia 15.B production-ready (sem worker, eventos travam em `status='received'`).

## 9. References

- Spec: `docs/stories/EPIC-015-cs-area/spec/spec.md` §4.4 + §4.6
- Critique: `docs/stories/EPIC-015-cs-area/spec/critique.json` CRIT-5
- Supabase pg_cron: https://supabase.com/docs/guides/database/extensions/pg_cron
- Supabase pg_net: https://supabase.com/docs/guides/database/extensions/pg_net
- AC webhook docs: TBD validar Story 15.0 (OQ-1, OQ-2)

---

## 10. Adendo 2026-05-04 — Decisões Discovery (Story 15.0)

### Volume real validado

User confirmou volume **200 compras/mês** (~7 disparos/dia, picos ~30/dia em campanhas), business high-ticket. ASM-13 original (1000/dia) **errada**.

**Implicação na arquitetura:** Folga gigantesca em todo o pipeline. Worker pg_cron com batch=50 a cada 30s tem capacidade > 100x do volume real. **Mantém arquitetura mesma** porque:
- Idempotência ainda obrigatória (NFR-4)
- Cold start mitigation continua relevante para responsividade individual
- Async preserva NFR-6 (<2s webhook response)
- Volume futuro pode crescer 10x sem reescrita

### META Stack — Pattern Existente Mantido (Decisão User 2026-05-04)

User confirmou que toda integração Meta atual em produção (4 edge functions: `dispatch-survey`, `send-whatsapp`, `send-whatsapp-reminder`, `zoom-attendance`) opera com **apenas 2 secrets**: `META_PHONE_NUMBER_ID` + `META_API_KEY`. Pattern funciona, foi validado em prod.

**Story 15.I `meta-delivery-webhook` adota mesmo pattern + 1 secret novo:**

| Secret | Função | Status |
|---|---|---|
| `META_PHONE_NUMBER_ID` | Identificador phone (já em prod) | Configurado |
| `META_API_KEY` | Bearer auth para envio outbound (já em prod) | Configurado |
| `META_WABA_ID` | WhatsApp Business Account ID (Story 15.8 templates dinâmicos) | Provided 2026-05-04 |
| `META_WEBHOOK_VERIFY_TOKEN` | Verify subscription Meta (challenge GET hub.verify_token) | Provided 2026-05-04 |
| ~~`META_APP_SECRET`~~ | ~~HMAC X-Hub-Signature-256~~ | **Não usado V1 — alinhado com pattern atual** |

**Validação webhook Meta delivery (V1 sem HMAC):**
- `META_WEBHOOK_VERIFY_TOKEN` valida subscription inicial Meta (challenge GET — única vez no setup)
- Payload schema validation rejeita malformados
- `UNIQUE meta_message_id` constraint deduplica replay
- Reject `meta_message_id` sem matching `survey_link` existente
- Rate limit 100/min por IP na edge function
- Slack alert se taxa de delivery webhooks anômala (>10x normal)

**Risco aceito (volume 200/mês reduz superfície):** atacante que descobrir URL pública pode tentar marcar `survey_links.delivered_at`/`read_at` incorretamente. Sem perda de dados, sem comprometimento de tokens/keys.

**Future work opcional:** Adicionar HMAC validation se `META_APP_SECRET` for provisionado futuramente. Ajuste local em Story 15.I sem refactor do worker.

### Cardinalidade ac_product_mappings — N:1

User confirmou OQ-11: **N:1** (vários produtos AC podem mapear para a mesma cohort + survey). Schema atual já suporta naturalmente — `ac_product_id UNIQUE` permanece, `cohort_id`/`survey_id` podem repetir entre rows. ASM-19 atualizada.
