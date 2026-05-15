// ═══════════════════════════════════════════════════════════════════════════
// EPIC-015 Story 15.E — send-slack-alert
// Chamado por SQL function alert_slack_if_unhealthy() via pg_net.http_post.
// Envia alert via Slack DM usando _shared/slack.ts existente.
//
// Auth: service_role apenas (chamada interna do pg_cron).
// Refs: NFR-10, NFR-12, AC-18 spec.md
// ═══════════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { sendDM } from "../_shared/slack.ts";

const SLACK_IGOR = Deno.env.get("SLACK_IGOR_USER_ID") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function decodeJwtRole(token: string): string | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const payload = JSON.parse(atob(parts[1].replace(/-/g, "+").replace(/_/g, "/")));
    return payload?.role ?? null;
  } catch {
    return null;
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "method_not_allowed" }), {
      status: 405,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // Auth: service_role apenas (chamado por pg_net da SQL function)
  const authHeader = req.headers.get("Authorization");
  const token = authHeader?.startsWith("Bearer ") ? authHeader.slice(7) : "";
  if (decodeJwtRole(token) !== "service_role" && token !== SUPABASE_SERVICE_ROLE_KEY) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  let body: { message?: string; key?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  if (!body.message) {
    return new Response(JSON.stringify({ error: "missing_message" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  if (!SLACK_IGOR) {
    console.warn("[send-slack-alert] SLACK_IGOR_USER_ID not configured, skipping");
    return new Response(JSON.stringify({ skipped: true }), {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  try {
    const formattedMessage = body.key
      ? `🔔 *EPIC-015 Alert* [${body.key}]\n${body.message}`
      : body.message;

    await sendDM(SLACK_IGOR, formattedMessage);
    console.log(`[send-slack-alert] sent: ${body.key ?? 'no-key'}`);
    return new Response(JSON.stringify({ sent: true }), {
      status: 200,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (e) {
    console.error("[send-slack-alert] failed:", e);
    return new Response(JSON.stringify({
      error: "slack_failed",
      detail: e instanceof Error ? e.message : String(e),
    }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
