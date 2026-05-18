// ═══════════════════════════════════════════════════════════════════════════
// admin-send-group-once — Manual ad-hoc sender for one group message.
//
// Body: { group_jid: string, text: string, cohort_id?: string }
// Auth: requires service_role bearer.
//
// Logs to whatsapp_group_messages on success.
// ═══════════════════════════════════════════════════════════════════════════

import { sendEvolutionGroupText } from "../_shared/evolution-group.ts";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  // Auth via shared secret in header (env mismatch w/ SRK is known issue)
  const adminToken = Deno.env.get("ADMIN_ONE_SHOT_TOKEN") ?? "";
  const auth = req.headers.get("x-admin-token") ?? "";
  if (!adminToken || auth !== adminToken) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: { group_jid?: string; text?: string; cohort_id?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const groupJid = (body.group_jid ?? "").trim();
  const text = (body.text ?? "").trim();
  if (!groupJid || !text) return json({ error: "missing_fields" }, 400);

  const r = await sendEvolutionGroupText(groupJid, text);
  if (!r.success) return json({ ok: false, error: r.error }, 502);

  return json({ ok: true, message_id: r.messageId });
});
