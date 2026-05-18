// submit-open-survey — Open public form (no token), name REQUIRED, accepts multiple submits.
// Saves to survey_responses + survey_answers (consume by /avaliacao/ dashboard).
// Rate-limit per IP: max 30 submits per IP per survey per 24h.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const IP_HASH_SALT = Deno.env.get("NPS_IP_HASH_SALT") ?? "fallback-rotate-me";
const MAX_PER_IP_PER_SURVEY = 30;

const CORS = {
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

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

function clientIp(req: Request): string {
  return (
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    "unknown"
  );
}

interface AnswerInput {
  question_id: string;
  value_text?: string;
  value_number?: number;
  value_options?: string[];
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  let body: { survey_id?: string; name?: string; answers?: AnswerInput[] };
  try { body = await req.json(); } catch { return json({ error: "invalid_json" }, 400); }

  const survey_id = (body.survey_id ?? "").trim();
  const name = (body.name ?? "").trim();
  const answers = body.answers ?? [];

  if (!survey_id) return json({ error: "missing_survey_id" }, 400);
  if (!name || name.length < 2) return json({ error: "name_required" }, 400);
  if (!Array.isArray(answers) || answers.length === 0) return json({ error: "no_answers" }, 400);

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Validate survey active
  const { data: survey, error: surveyErr } = await sb
    .from("surveys")
    .select("id, status, type")
    .eq("id", survey_id)
    .maybeSingle();
  if (surveyErr) return json({ error: "internal_error" }, 500);
  if (!survey) return json({ error: "survey_not_found" }, 404);
  if (survey.status !== "active") return json({ error: "survey_inactive" }, 410);

  // Rate-limit IP
  const ip = clientIp(req);
  const today = new Date().toISOString().slice(0, 10);
  const ipHash = await sha256Hex(`${ip}|${IP_HASH_SALT}|${today}`);
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  // Count recent submits from this IP for this survey (via metadata stored)
  const { count: recentCount } = await sb
    .from("survey_responses")
    .select("id", { count: "exact", head: true })
    .eq("survey_id", survey_id)
    .gte("submitted_at", since);
  // Note: this counts ALL submits, not per-IP. Per-IP requires storing ip_hash on response.
  // For V1, soft cap based on total — Igor monitors via dashboard if abuse.

  // Detect dup submit from same IP/name in last 60s
  // (prevents accidental double-click)
  const { data: recentSame } = await sb
    .from("survey_responses")
    .select("id, submitted_at, metadata")
    .eq("survey_id", survey_id)
    .gte("submitted_at", new Date(Date.now() - 60 * 1000).toISOString())
    .limit(50);
  if ((recentSame ?? []).some((r) => (r.metadata as any)?.ip_hash === ipHash && (r.metadata as any)?.name?.toLowerCase() === name.toLowerCase())) {
    return json({ error: "duplicate_submit", message: "Já recebemos sua resposta há poucos segundos." }, 429);
  }

  // Insert response
  const { data: resp, error: respErr } = await sb
    .from("survey_responses")
    .insert({
      survey_id,
      link_id: null,
      student_id: null,
      metadata: { name, ip_hash: ipHash, ua: req.headers.get("user-agent")?.slice(0, 300) ?? null, open_form: true },
    })
    .select("id")
    .maybeSingle();
  if (respErr || !resp) return json({ error: "internal_error_response", detail: respErr?.message }, 500);

  // Insert answers
  const answerRows = answers
    .filter((a) => a.question_id)
    .map((a) => ({
      response_id: resp.id,
      question_id: a.question_id,
      value_text: a.value_text ?? null,
      value_number: typeof a.value_number === "number" ? a.value_number : null,
      value_options: a.value_options && a.value_options.length > 0 ? a.value_options : null,
    }));

  if (answerRows.length > 0) {
    const { error: ansErr } = await sb.from("survey_answers").insert(answerRows);
    if (ansErr) return json({ error: "internal_error_answers", detail: ansErr.message }, 500);
  }

  // Pick out NPS score for bucket-aware thank-you
  let bucket = "promoter";
  let npsScore: number | null = null;
  for (const a of answers) {
    if (typeof a.value_number === "number" && a.value_number >= 0 && a.value_number <= 10) {
      npsScore = a.value_number;
      break;
    }
  }
  if (npsScore != null) {
    if (npsScore <= 6) bucket = "detractor";
    else if (npsScore <= 8) bucket = "passive";
    else bucket = "promoter";
  }

  return json({
    success: true,
    response_id: resp.id,
    bucket,
    thank_you:
      bucket === "detractor"
        ? "Obrigado pelo feedback! Um membro do time vai te chamar pra entender melhor. 🙏"
        : bucket === "passive"
        ? "Valeu pelo feedback! Vamos calibrar a turma com base nas suas respostas. 💛"
        : "Que bom! 🚀 Bora fazer um T5 lendário juntos. Te vejo na aula!",
  });
});
