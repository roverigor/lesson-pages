// ═══════════════════════════════════════════════════════════════════════════
// EPIC-015 Story 15.B — ac-purchase-webhook (minimal-sync handler)
//
// Recebe eventos webhook ActiveCampaign (compras) e:
//   1. Valida HMAC X-AC-Signature
//   2. INSERT em ac_purchase_events com status='received'
//   3. Retorna 200 imediato (< 500ms warm, < 2s cold)
//
// Worker pg_cron (process_ac_purchase_events_batch) processa async.
// Refs: ADR-016 §3, FR-7, NFR-4 (idempotência), NFR-6 (<2s)
// ═══════════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { validateHmac, deriveAcEventId } from "../_shared/ac-utils.ts";
import { sendDM } from "../_shared/slack.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const AC_WEBHOOK_SECRET = Deno.env.get("AC_WEBHOOK_SECRET") ?? "";
const SLACK_IGOR = Deno.env.get("SLACK_IGOR_USER_ID") ?? "";

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-AC-Signature, Authorization",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

async function alertSlack(message: string): Promise<void> {
  if (!SLACK_IGOR) return;
  try {
    await sendDM(SLACK_IGOR, `🚨 [ac-purchase-webhook] ${message}`);
  } catch (e) {
    console.error("[slack] alert failed:", e);
  }
}

serve(async (req: Request) => {
  const start = performance.now();
  const url = new URL(req.url);

  // ── Warmup mode (chamado por pg_cron 4min para evitar cold start) ──
  if (url.searchParams.get("warmup") === "1") {
    return new Response("ok", { status: 200, headers: CORS_HEADERS });
  }

  // ── CORS preflight ──
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  // ── Method check ──
  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  // ── Read body + HMAC validation ──
  const sig = req.headers.get("X-AC-Signature") ??
              req.headers.get("X-Hook-Signature") ??
              req.headers.get("X-Webhook-Signature");
  const body = await req.text();

  if (!AC_WEBHOOK_SECRET) {
    console.error("[ac-webhook] AC_WEBHOOK_SECRET missing — secret não configurado");
    return jsonResponse({ error: "server_misconfigured" }, 500);
  }

  const hmacOk = await validateHmac(body, sig, AC_WEBHOOK_SECRET);
  if (!hmacOk) {
    console.error("[ac-webhook] HMAC invalid", { hasSig: !!sig });
    await alertSlack(`AC webhook HMAC inválido — possível tentativa de ataque (signature header: ${sig ? 'present' : 'missing'})`);
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  // ── Parse payload ──
  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(body);
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  // ── Extract idempotency key (OQ-5) ──
  const acEventId = deriveAcEventId(payload);
  if (!acEventId) {
    return jsonResponse({ error: "cannot_derive_event_id" }, 400);
  }

  // ── INSERT com idempotência via UNIQUE ac_event_id ──
  const { error } = await sb.from("ac_purchase_events").insert({
    ac_event_id: acEventId,
    payload,
    status: "received",
  });

  // PG error code 23505 = UNIQUE constraint violation = duplicate event
  if (error?.code === "23505") {
    const duration = Math.round(performance.now() - start);
    console.log(JSON.stringify({
      event: "duplicate",
      ac_event_id: acEventId,
      duration_ms: duration,
    }));
    return jsonResponse({ status: "duplicate", event_id: acEventId });
  }

  if (error) {
    console.error("[ac-webhook] db error:", error);
    return jsonResponse({ error: "db_error", detail: error.message }, 500);
  }

  // ── Success — log + return 200 imediato ──
  const duration = Math.round(performance.now() - start);
  console.log(JSON.stringify({
    event: "accepted",
    ac_event_id: acEventId,
    duration_ms: duration,
  }));

  return jsonResponse({ status: "accepted", event_id: acEventId });

  // Worker pg_cron processa em até 30s (ADR-016 §3).
});
