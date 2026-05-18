// submit-ps-rsvp — receives RSVP form submission, idempotent per token.
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function clientIp(req: Request): string {
  return req.headers.get("x-forwarded-for")?.split(",")[0].trim() ?? "unknown";
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: {
    token?: string;
    will_attend?: string;
    doubts_text?: string;
    project_phase?: string;
  };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }

  const token = (body.token ?? "").trim();
  const willAttend = (body.will_attend ?? "").trim();
  const doubtsText = (body.doubts_text ?? "").trim() || null;
  const projectPhase = (body.project_phase ?? "").trim() || null;

  if (!token) return json({ error: "missing_token" }, 400);
  if (!["yes", "no", "maybe"].includes(willAttend)) return json({ error: "invalid_will_attend" }, 400);

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: link, error: linkErr } = await sb
    .from("ps_rsvp_links")
    .select("id, class_id, student_id, session_date, expires_at")
    .eq("token", token)
    .maybeSingle();

  if (linkErr) return json({ error: "internal_error" }, 500);
  if (!link) return json({ error: "token_not_found" }, 404);
  if (new Date(link.expires_at).getTime() < Date.now()) return json({ error: "token_expired" }, 410);

  // Idempotent: if response exists, return success.
  const { data: existing } = await sb
    .from("ps_rsvp_responses")
    .select("id")
    .eq("link_id", link.id)
    .maybeSingle();
  if (existing) return json({ success: true, already: true });

  const ip = clientIp(req);
  const ipHash = await sha256Hex(`${ip}|${new Date().toISOString().slice(0, 10)}`);
  const userAgent = req.headers.get("user-agent")?.slice(0, 500) ?? null;

  const { error: insErr } = await sb.from("ps_rsvp_responses").insert({
    link_id: link.id,
    class_id: link.class_id,
    student_id: link.student_id,
    session_date: link.session_date,
    will_attend: willAttend,
    doubts_text: doubtsText,
    project_phase: projectPhase,
    ip_hash: ipHash,
    user_agent: userAgent,
  });
  if (insErr) return json({ error: "insert_failed", detail: insErr.message }, 500);

  await sb.from("ps_rsvp_links").update({ responded_at: new Date().toISOString() }).eq("id", link.id);

  return json({ success: true });
});
