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
    confirmed_name?: string;
    no_reason?: string;
    team_message?: string;
  };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }

  const token = (body.token ?? "").trim();
  const willAttend = (body.will_attend ?? "").trim();
  const doubtsText = (body.doubts_text ?? "").trim() || null;
  const projectPhase = (body.project_phase ?? "").trim() || null;
  const confirmedName = (body.confirmed_name ?? "").trim().slice(0, 120) || null;
  const noReason = (body.no_reason ?? "").trim().slice(0, 2000) || null;
  const teamMessage = (body.team_message ?? "").trim().slice(0, 2000) || null;

  if (!token) return json({ error: "missing_token" }, 400);
  if (!["yes", "no"].includes(willAttend)) return json({ error: "invalid_will_attend" }, 400);

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

  // Group placeholder bypass — links compartilhados aceitam N respostas.
  // Detecção via students.phone LIKE 'group_placeholder_%'.
  const { data: linkStudent } = await sb
    .from("students")
    .select("phone")
    .eq("id", link.student_id)
    .maybeSingle();
  const linkPhoneRaw = linkStudent?.phone ?? "";
  const isGroupPlaceholder = linkPhoneRaw.startsWith("group_placeholder_");

  if (!isGroupPlaceholder) {
    // Idempotência 1: mesmo link já respondido.
    const { data: existing } = await sb
      .from("ps_rsvp_responses")
      .select("id")
      .eq("link_id", link.id)
      .maybeSingle();
    if (existing) return json({ success: true, already: true });

    // Idempotência 2 (cross-link): mesmo phone já respondeu nessa session_date
    // via OUTRO student_id (aluno cadastrado em múltiplos cohorts gera N
    // student rows → N links → sem isso, 3 DMs ao mesmo phone = 3 respostas).
    const normalized = linkPhoneRaw.replace(/\D/g, "");
    if (normalized) {
      const { data: phoneTwins } = await sb
        .from("students")
        .select("id")
        .eq("phone", linkPhoneRaw);
      const twinIds = (phoneTwins ?? []).map((s: { id: string }) => s.id);
      if (twinIds.length > 1) {
        const { data: twinResp } = await sb
          .from("ps_rsvp_responses")
          .select("id")
          .in("student_id", twinIds)
          .eq("session_date", link.session_date)
          .limit(1)
          .maybeSingle();
        if (twinResp) {
          await sb.from("ps_rsvp_links")
            .update({ responded_at: new Date().toISOString() })
            .eq("id", link.id);
          return json({ success: true, already: true, dedup: "phone_twin" });
        }
      }
    }
  }

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
    confirmed_name: confirmedName,
    no_reason: noReason,
    team_message: teamMessage,
    ip_hash: ipHash,
    user_agent: userAgent,
  });
  if (insErr) return json({ error: "insert_failed", detail: insErr.message }, 500);

  await sb.from("ps_rsvp_links").update({ responded_at: new Date().toISOString() }).eq("id", link.id);

  return json({ success: true });
});
