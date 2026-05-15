// ═══════════════════════════════════════════════════════════════════════════
// EPIC-015 Story 15.C — ac-report-dispatch (callback outbound AC)
//
// Após dispatch-survey enviar form com sucesso, esta function:
//   1. POST AC API com custom_field 'form_dispatched'
//   2. Retry exp 3x (1s/4s/16s) em 5xx
//   3. Persiste em ac_dispatch_callbacks
//   4. Slack alert se 3 retries esgotados
//
// Auth: service_role apenas (chamada interna do dispatch-survey).
// Refs: FR-11, NFR-5, AC-12, AC-13
// ═══════════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { sendDM } from "../_shared/slack.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const AC_API_URL = Deno.env.get("AC_API_URL") ?? ""; // ex: https://accountname.api-us1.com
const AC_API_KEY = Deno.env.get("AC_API_KEY") ?? "";
const SLACK_IGOR = Deno.env.get("SLACK_IGOR_USER_ID") ?? "";

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

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

async function verifyServiceRole(req: Request): Promise<boolean> {
  const authHeader = req.headers.get("Authorization");
  if (!authHeader?.startsWith("Bearer ")) return false;
  const token = authHeader.slice(7);
  return decodeJwtRole(token) === "service_role";
}

interface CallbackInput {
  link_id: string;
  ac_contact_id: string;
  custom_field_id: string;
  value: string;
}

async function postAcCustomField(
  contactId: string,
  fieldId: string,
  value: string,
): Promise<{ ok: boolean; status: number; error?: string }> {
  if (!AC_API_URL || !AC_API_KEY) {
    return { ok: false, status: 0, error: "ac_api_not_configured" };
  }

  try {
    const res = await fetch(
      `${AC_API_URL}/api/3/contacts/${contactId}/fieldValues`,
      {
        method: "POST",
        headers: {
          "Api-Token": AC_API_KEY,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          fieldValue: {
            contact: contactId,
            field: fieldId,
            value: value,
          },
        }),
      },
    );

    if (res.ok) return { ok: true, status: res.status };
    const errBody = await res.text().catch(() => "");
    return {
      ok: false,
      status: res.status,
      error: `${res.status} ${errBody.slice(0, 200)}`,
    };
  } catch (e) {
    return {
      ok: false,
      status: 0,
      error: e instanceof Error ? e.message : String(e),
    };
  }
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  // Auth: service_role apenas
  const isServiceRole = await verifyServiceRole(req);
  if (!isServiceRole) {
    return jsonResponse({ error: "unauthorized" }, 401);
  }

  let input: CallbackInput;
  try {
    input = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const { link_id, ac_contact_id, custom_field_id, value } = input;
  if (!link_id || !ac_contact_id || !custom_field_id || !value) {
    return jsonResponse({ error: "missing_fields" }, 400);
  }

  // ── Idempotência: já acked? ──
  const { data: existing } = await sb
    .from("ac_dispatch_callbacks")
    .select("acknowledged_by_ac")
    .eq("link_id", link_id)
    .eq("ac_contact_id", ac_contact_id)
    .maybeSingle();

  if (existing?.acknowledged_by_ac) {
    return jsonResponse({ status: "already_acknowledged" });
  }

  // ── Retry loop exponencial ──
  const delays = [1000, 4000, 16000]; // 1s, 4s, 16s
  let lastError = "";
  let attempt = 0;

  for (attempt = 1; attempt <= 3; attempt++) {
    const result = await postAcCustomField(ac_contact_id, custom_field_id, value);

    if (result.ok) {
      // SUCCESS
      await sb.from("ac_dispatch_callbacks").upsert({
        link_id,
        ac_contact_id,
        status: "ok",
        retries: attempt,
        last_attempt_at: new Date().toISOString(),
        acknowledged_by_ac: true,
        error_message: null,
      }, { onConflict: "link_id,ac_contact_id" });

      console.log(JSON.stringify({
        event: "callback_ok",
        link_id,
        ac_contact_id,
        attempt,
      }));
      return jsonResponse({ status: "ok", attempt });
    }

    lastError = result.error ?? `${result.status}`;

    // 4xx: não retry (erro de aplicação)
    if (result.status >= 400 && result.status < 500) {
      break;
    }

    // 5xx ou network: aguarda + retry
    if (attempt < 3) {
      await sleep(delays[attempt - 1]);
    }
  }

  // ── FAILED — todos retries esgotados (ou 4xx) ──
  await sb.from("ac_dispatch_callbacks").upsert({
    link_id,
    ac_contact_id,
    status: "failed",
    retries: attempt - 1,
    last_attempt_at: new Date().toISOString(),
    error_message: lastError.slice(0, 500),
    acknowledged_by_ac: false,
  }, { onConflict: "link_id,ac_contact_id" });

  // Slack alert
  if (SLACK_IGOR) {
    try {
      await sendDM(
        SLACK_IGOR,
        `❌ AC callback falhou link_id=${link_id} contact=${ac_contact_id}\nErro: ${lastError}`,
      );
    } catch (e) {
      console.error("[slack] alert failed:", e);
    }
  }

  console.error(JSON.stringify({
    event: "callback_failed",
    link_id,
    ac_contact_id,
    attempts: attempt - 1,
    error: lastError,
  }));

  return jsonResponse({ status: "failed", error: lastError, attempts: attempt - 1 }, 502);
});
