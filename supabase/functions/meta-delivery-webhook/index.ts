// ═══════════════════════════════════════════════════════════════════════════
// EPIC-015 Story 15.I — meta-delivery-webhook
//
// Recebe Meta Cloud API webhooks `messages.update` (delivery + read receipts).
//
// V1 SEM HMAC X-Hub-Signature-256 (META_APP_SECRET indisponível — decisão user).
// Mitigações ADR-016 §10:
//   - META_WEBHOOK_VERIFY_TOKEN para subscription
//   - UNIQUE meta_message_id em survey_links (idempotência)
//   - Schema validation rejeita malformados
//   - Reject meta_message_id sem matching survey_link
//   - Rate limit in-memory 100/min/IP
//
// Refs: NFR-17, EC-20 (race condition), AC-19
// ═══════════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const META_WEBHOOK_VERIFY_TOKEN = Deno.env.get("META_WEBHOOK_VERIFY_TOKEN") ?? "";

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// ─── Rate limit in-memory (V1) ─────────────────────────────────────────────
const rateLimitMap = new Map<string, { count: number; ts: number }>();
const RATE_LIMIT_PER_MIN = 100;
const RATE_LIMIT_WINDOW_MS = 60_000;

function isRateLimited(ip: string): boolean {
  const now = Date.now();
  const entry = rateLimitMap.get(ip);
  if (!entry || now - entry.ts > RATE_LIMIT_WINDOW_MS) {
    rateLimitMap.set(ip, { count: 1, ts: now });
    return false;
  }
  entry.count++;
  if (rateLimitMap.size > 1000) {
    // Cleanup older entries
    for (const [k, v] of rateLimitMap.entries()) {
      if (now - v.ts > RATE_LIMIT_WINDOW_MS) rateLimitMap.delete(k);
    }
  }
  return entry.count > RATE_LIMIT_PER_MIN;
}

// ─── Timing-safe string compare ────────────────────────────────────────────
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) {
    diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return diff === 0;
}

serve(async (req: Request) => {
  const url = new URL(req.url);

  // ── Warmup mode ──
  if (url.searchParams.get("warmup") === "1") {
    return new Response("ok", { status: 200, headers: CORS_HEADERS });
  }

  // ── CORS preflight ──
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  // ── GET — Meta subscription verify ──
  // Meta envia GET com hub.mode=subscribe + hub.verify_token + hub.challenge.
  // Devolvemos challenge se token bate.
  if (req.method === "GET") {
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");

    if (
      mode === "subscribe" &&
      token &&
      META_WEBHOOK_VERIFY_TOKEN &&
      timingSafeEqual(token, META_WEBHOOK_VERIFY_TOKEN)
    ) {
      console.log("[meta-webhook] subscription verified");
      return new Response(challenge ?? "ok", { status: 200, headers: CORS_HEADERS });
    }

    console.warn("[meta-webhook] subscription verify failed", { hasToken: !!token });
    return new Response("forbidden", { status: 403, headers: CORS_HEADERS });
  }

  // ── POST — webhook event ──
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  // Rate limit
  const ip = req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ?? "unknown";
  if (isRateLimited(ip)) {
    console.warn("[meta-webhook] rate limited:", ip);
    return jsonResponse({ error: "rate_limited" }, 429);
  }

  // Parse payload
  let payload: any;
  try {
    payload = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  // Extract statuses array (Meta WhatsApp Cloud API format)
  const statuses = payload?.entry?.[0]?.changes?.[0]?.value?.statuses ?? [];

  if (!Array.isArray(statuses)) {
    console.warn("[meta-webhook] no statuses in payload");
    return jsonResponse({ status: "ok", processed: 0 });
  }

  let processed = 0;
  let skipped = 0;

  for (const s of statuses) {
    const metaMessageId = s?.id;
    const status = s?.status;
    const timestampStr = s?.timestamp;

    if (!metaMessageId || !status) {
      skipped++;
      continue;
    }

    // Apenas tracking de delivered + read (sent já registrado em dispatch-survey)
    if (status !== "delivered" && status !== "read") {
      skipped++;
      continue;
    }

    const updateField = status === "delivered" ? "delivered_at" : "read_at";

    // Convert Meta timestamp (Unix seconds) → ISO
    const tsIso = timestampStr
      ? new Date(parseInt(timestampStr, 10) * 1000).toISOString()
      : new Date().toISOString();

    // UPDATE com guard idempotente (só atualiza se ainda nulo)
    const { data, error } = await sb
      .from("survey_links")
      .update({ [updateField]: tsIso })
      .eq("meta_message_id", metaMessageId)
      .is(updateField, null)
      .select("id");

    if (error) {
      console.error("[meta-webhook] db error:", error.message);
      continue;
    }

    if (!data || data.length === 0) {
      // Possíveis causas:
      //   - Mensagem não nossa (outra app no mesmo número)
      //   - Race condition: webhook delivery chegou antes de sent_at registrar (EC-20)
      //   - Já atualizado anteriormente
      console.log(JSON.stringify({
        event: "skip_no_match",
        meta_message_id: metaMessageId,
        status,
      }));
      skipped++;
      continue;
    }

    console.log(JSON.stringify({
      event: "tracked",
      meta_message_id: metaMessageId,
      status,
      link_id: data[0].id,
    }));
    processed++;
  }

  return jsonResponse({ status: "ok", processed, skipped });
});
