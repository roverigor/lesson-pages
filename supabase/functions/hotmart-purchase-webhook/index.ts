// EPIC-016 Story 16.5 — Hotmart Purchase Webhook
// Recebe formato NATIVO Hotmart e converte pro schema normalizado pré inserir.
// Hotmart payload format: https://developers.hotmart.com/docs/en/v1/webhooks/

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface HotmartPayload {
  id?: string;
  event?: string;
  version?: string;
  data?: {
    purchase?: {
      transaction?: string;
      status?: string;
      order_date?: number;
      approved_date?: number;
      product?: {
        id?: number | string;
        name?: string;
      };
    };
    buyer?: {
      email?: string;
      name?: string;
      checkout_phone?: string;
      checkout_phone_code?: string;
    };
    product?: {
      id?: number | string;
      name?: string;
    };
    subscription?: {
      subscriber?: {
        code?: string;
      };
    };
  };
  hottok?: string;  // Hotmart auth token
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (req.method !== "POST") return new Response(JSON.stringify({ error: "POST only" }), { status: 405, headers: corsHeaders });

  try {
    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Auth via X-API-Key header (gerada via /cs/integrations Sources)
    const apiKey = req.headers.get("X-API-Key");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "X-API-Key header required" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const { data: validation, error: vErr } = await sb.rpc("validate_integration_api_key", { p_key: apiKey });
    if (vErr || !validation?.valid) {
      return new Response(JSON.stringify({ error: "invalid api key" }),
        { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const sourceId = validation.source_id;
    const sourceSlug = validation.slug;
    const payload: HotmartPayload = await req.json();

    // Aceita apenas eventos de compra aprovada (PURCHASE_APPROVED, PURCHASE_COMPLETE)
    const event = payload.event ?? "";
    const status = payload.data?.purchase?.status ?? "";
    if (!["PURCHASE_APPROVED", "PURCHASE_COMPLETE"].includes(event)
        && !["APPROVED", "COMPLETE"].includes(status.toUpperCase())) {
      return new Response(JSON.stringify({
        ok: true, status: "ignored",
        reason: `event=${event} status=${status} não é compra aprovada`
      }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Extrai dados normalizados do payload Hotmart
    const buyer = payload.data?.buyer ?? {};
    const product = payload.data?.product ?? payload.data?.purchase?.product ?? {};
    const purchase = payload.data?.purchase ?? {};

    const email = buyer.email?.trim().toLowerCase();
    const name = buyer.name?.trim();
    const phoneCode = buyer.checkout_phone_code?.replace(/\D/g, "") ?? "";
    const phoneNum = buyer.checkout_phone?.replace(/\D/g, "") ?? "";
    const phone = phoneCode + phoneNum;
    const productId = String(product.id ?? "");
    const transactionId = purchase.transaction ?? payload.id;

    // Validações data quality
    if (!email || !/^[^@]+@[^@]+\.[^@]+$/.test(email)) {
      return new Response(JSON.stringify({ error: "invalid buyer.email", payload_preview: { email } }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    if (!name || /^[0-9\s]+$/.test(name)) {
      return new Response(JSON.stringify({ error: "invalid buyer.name (required, alphabetical)" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    if (!productId) {
      return new Response(JSON.stringify({ error: "data.product.id required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }
    if (!transactionId) {
      return new Response(JSON.stringify({ error: "data.purchase.transaction OR top-level id required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Composite event ID pra dedup
    const compositeEventId = `${sourceSlug}:${transactionId}`;

    const { data: existing } = await sb.from("ac_purchase_events")
      .select("id").eq("ac_event_id", compositeEventId).maybeSingle();
    if (existing) {
      return new Response(JSON.stringify({ ok: true, status: "duplicate", event_id: existing.id }),
        { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Normaliza payload pro mesmo schema do generic webhook
    const normalizedPayload = {
      external_event_id: transactionId,
      customer: { email, name, phone: phone ? "+" + phone : null },
      product_external_id: productId,
      product_name: product.name,
      occurred_at: purchase.approved_date
        ? new Date(purchase.approved_date).toISOString()
        : (purchase.order_date ? new Date(purchase.order_date).toISOString() : new Date().toISOString()),
      source: "hotmart",
      raw_hotmart_payload: payload,
    };

    const { data: inserted, error: insErr } = await sb.from("ac_purchase_events").insert({
      ac_event_id: compositeEventId,
      source_id: sourceId,
      payload: normalizedPayload,
      status: "pending",
    }).select("id").single();

    if (insErr) throw insErr;

    // Atualiza counter
    await sb.rpc("increment_source_webhook_count", { p_source_id: sourceId, p_success: true }).catch(() => {});

    return new Response(JSON.stringify({
      ok: true,
      status: "queued",
      event_id: inserted.id,
      source: sourceSlug,
      customer: email,
      product: productId,
    }), { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } });

  } catch (e) {
    console.error("hotmart-purchase-webhook error:", e);
    return new Response(JSON.stringify({ error: String((e as Error).message ?? e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
