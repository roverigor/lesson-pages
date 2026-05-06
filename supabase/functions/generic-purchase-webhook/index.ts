// EPIC-016 Story 16.5 — Generic Purchase Webhook
// Aceita POST normalizado de qualquer plataforma (Hotmart, Eduzz, Kiwify, custom CRM).
// Valida via X-API-Key header → integration_sources.
// Cria entry em ac_purchase_events (mesmo pipeline AC), com source_id setado.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface PurchasePayload {
  external_event_id: string;
  customer: {
    email: string;
    name?: string;
    phone?: string;
  };
  product_external_id: string;
  occurred_at?: string;
  metadata?: Record<string, unknown>;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type, x-api-key",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "POST only" }), { status: 405, headers: corsHeaders });

  try {
    const apiKey = req.headers.get("X-API-Key");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "X-API-Key header required" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Validate API key
    const { data: validation, error: vErr } = await sb.rpc("validate_integration_api_key", { p_key: apiKey });
    if (vErr || !validation?.valid) {
      return new Response(JSON.stringify({ error: "invalid api key" }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const sourceId = validation.source_id;
    const sourceSlug = validation.slug;

    const payload: PurchasePayload = await req.json();

    // Validate payload basic
    if (!payload.external_event_id || !payload.customer?.email || !payload.product_external_id) {
      return new Response(
        JSON.stringify({ error: "required: external_event_id, customer.email, product_external_id" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Validate email format
    if (!/^[^@]+@[^@]+\.[^@]+$/.test(payload.customer.email)) {
      return new Response(JSON.stringify({ error: "invalid email format" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Reject if no name (data quality — Story 20.0)
    if (!payload.customer.name || /^[0-9\s]+$/.test(payload.customer.name) || payload.customer.name.trim() === "") {
      return new Response(JSON.stringify({ error: "customer.name required (alphabetical, not empty)" }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Idempotência: chave composta source_slug + external_event_id
    const compositeEventId = `${sourceSlug}:${payload.external_event_id}`;

    const { data: existing } = await sb.from("ac_purchase_events").select("id").eq("ac_event_id", compositeEventId).maybeSingle();
    if (existing) {
      return new Response(JSON.stringify({ ok: true, status: "duplicate", event_id: existing.id }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const { data: inserted, error: insErr } = await sb.from("ac_purchase_events").insert({
      ac_event_id: compositeEventId,
      source_id: sourceId,
      payload: payload,
      status: "pending",
    }).select("id").single();

    if (insErr) throw insErr;

    // Atualiza counter do source
    await sb.rpc("increment_source_webhook_count", { p_source_id: sourceId, p_success: true }).catch(() => {});

    return new Response(
      JSON.stringify({ ok: true, status: "queued", event_id: inserted.id, source: sourceSlug }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (e) {
    console.error("generic-purchase-webhook error:", e);
    return new Response(
      JSON.stringify({ error: String((e as Error).message ?? e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
