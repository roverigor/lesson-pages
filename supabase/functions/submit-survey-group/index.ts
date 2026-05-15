// ═══════════════════════════════════════════════════════════════════════════
// submit-survey-group — Public endpoint to submit anonymous NPS responses.
//
// Request body:
//   {
//     "token":         string (required),
//     "nps_score":     number 0-10 (required),
//     "comment":       string (optional),
//     "name_provided": string (optional, only honored when link.mode='group')
//   }
//
// Validates token, rate-limits by ip_hash (5 / 24h), inserts response, bumps counter.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const IP_HASH_SALT = Deno.env.get("NPS_IP_HASH_SALT") ?? "fallback-rotate-me";
const MAX_SUBMITS_PER_IP_24H = 5;

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function clientIp(req: Request): string {
  return (
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    "unknown"
  );
}

function dailySaltSuffix(): string {
  return new Date().toISOString().slice(0, 10);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  let body: {
    token?: string;
    nps_score?: number;
    comment?: string;
    name_provided?: string;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const token = (body.token ?? "").trim();
  const nps_score = body.nps_score;
  const comment = (body.comment ?? "").trim() || null;
  const nameProvided = (body.name_provided ?? "").trim() || null;

  if (!token) return jsonResponse({ error: "missing_token" }, 400);
  if (
    typeof nps_score !== "number" ||
    !Number.isInteger(nps_score) ||
    nps_score < 0 ||
    nps_score > 10
  ) {
    return jsonResponse({ error: "invalid_nps_score" }, 400);
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const { data: link, error: linkErr } = await sb
    .from("nps_class_links")
    .select("id, class_id, cohort_id, mode, student_id, expires_at")
    .eq("token", token)
    .maybeSingle();

  if (linkErr) return jsonResponse({ error: "internal_error" }, 500);
  if (!link) return jsonResponse({ error: "token_not_found" }, 404);
  if (new Date(link.expires_at).getTime() < Date.now()) {
    return jsonResponse({ error: "token_expired" }, 410);
  }

  const ip = clientIp(req);
  const ipHash = await sha256Hex(`${ip}|${IP_HASH_SALT}|${dailySaltSuffix()}`);
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const { count: recentCount, error: countErr } = await sb
    .from("class_nps_responses")
    .select("id", { count: "exact", head: true })
    .eq("ip_hash", ipHash)
    .gte("submitted_at", since);

  if (countErr) return jsonResponse({ error: "internal_error" }, 500);
  if ((recentCount ?? 0) >= MAX_SUBMITS_PER_IP_24H) {
    return jsonResponse({ error: "rate_limited" }, 429);
  }

  const userAgent = req.headers.get("user-agent")?.slice(0, 500) ?? null;

  const { error: insertErr } = await sb.from("class_nps_responses").insert({
    link_id: link.id,
    class_id: link.class_id,
    cohort_id: link.cohort_id,
    mode: link.mode,
    student_id: link.mode === "dm" ? link.student_id : null,
    nps_score,
    comment,
    name_provided: link.mode === "group" ? nameProvided : null,
    ip_hash: ipHash,
    user_agent: userAgent,
  });

  if (insertErr) return jsonResponse({ error: "internal_error" }, 500);

  await sb.rpc("increment_nps_link_response_count", { p_link_id: link.id }).then(() => {});

  return jsonResponse({
    success: true,
    thank_you: "Obrigado pelo feedback! Sua opinião é fundamental.",
  });
});
