// EPIC-016 Story 16.3 — Create Meta Template via Graph API
// Submete novo template pra Meta Business Manager pra aprovação.
// NÃO envia mensagem pra usuário final — só registra metadata pra approval.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

interface TemplateRequest {
  name: string;
  language: string;
  category: 'MARKETING' | 'UTILITY' | 'AUTHENTICATION';
  body_text: string;
  body_example_values?: string[];
  button_text?: string;
  button_url?: string;
  button_url_example?: string;
}

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    const META_API_KEY = Deno.env.get("META_API_KEY");
    const META_WABA_ID = Deno.env.get("META_WABA_ID");
    const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
    const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

    if (!META_API_KEY || !META_WABA_ID) {
      return new Response(JSON.stringify({ error: "META_API_KEY or META_WABA_ID not configured" }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const body: TemplateRequest = await req.json();

    if (!body.name || !body.language || !body.category || !body.body_text) {
      return new Response(JSON.stringify({ error: "required: name, language, category, body_text" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Conta placeholders no body ({{1}}, {{2}}, etc.)
    const bodyParamsCount = (body.body_text.match(/\{\{(\d+)\}\}/g) ?? []).length;

    // Build components Meta API format
    const components: any[] = [
      {
        type: "BODY",
        text: body.body_text,
        ...(body.body_example_values && body.body_example_values.length > 0
          ? { example: { body_text: [body.body_example_values] } }
          : {}),
      }
    ];

    if (body.button_text && body.button_url) {
      components.push({
        type: "BUTTONS",
        buttons: [{
          type: "URL",
          text: body.button_text,
          url: body.button_url,
          ...(body.button_url_example ? { example: [body.button_url_example] } : {}),
        }],
      });
    }

    // Submeter à Meta Graph API
    const metaResp = await fetch(
      `https://graph.facebook.com/v18.0/${META_WABA_ID}/message_templates`,
      {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${META_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          name: body.name,
          language: body.language,
          category: body.category,
          components,
        }),
      }
    );

    const metaJson = await metaResp.json();

    if (!metaResp.ok) {
      console.error("Meta API error:", metaJson);
      return new Response(
        JSON.stringify({ error: "meta_api_error", meta_response: metaJson }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Insert local meta_templates (status do Meta retorno)
    const { error: dbErr } = await sb.from("meta_templates").upsert({
      name: body.name,
      language: body.language,
      category: body.category,
      body_params_count: bodyParamsCount,
      button_count: body.button_text ? 1 : 0,
      status: metaJson.status?.toLowerCase() ?? 'pending',
    }, { onConflict: 'name,language' });

    if (dbErr) console.error("DB upsert error:", dbErr);

    return new Response(
      JSON.stringify({
        ok: true,
        meta_template_id: metaJson.id,
        meta_status: metaJson.status,
        category: metaJson.category,
        message: "Template submetido à Meta. Aprovação geralmente em minutos. Use sync-meta-templates pra refresh status.",
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (e) {
    console.error("create-meta-template error:", e);
    return new Response(
      JSON.stringify({ error: String((e as Error).message ?? e) }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
