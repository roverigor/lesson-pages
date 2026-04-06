// ═══════════════════════════════════════
// Edge Function: submit-survey
// Public endpoint — token-based, no auth required
// Saves student survey response to student_nps
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

function sb() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
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

  let body: { token?: string; score?: number; feedback?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  const { token, score, feedback } = body;

  if (!token || score === undefined || score === null) {
    return new Response(JSON.stringify({ error: "missing_fields" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  const client = sb();

  // 1. Validate token
  const { data: link, error: linkErr } = await client
    .from("survey_links")
    .select("id, survey_id, student_id, used_at, surveys(id, type, cohort_id, class_id, status)")
    .eq("token", token)
    .single();

  if (linkErr || !link) {
    return new Response(JSON.stringify({ error: "token_invalid" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  if (link.used_at) {
    return new Response(JSON.stringify({ error: "token_already_used" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  const survey = link.surveys as {
    id: string;
    type: string;
    cohort_id: string | null;
    class_id: string | null;
    status: string;
  } | null;

  if (!survey || survey.status === "draft") {
    return new Response(JSON.stringify({ error: "survey_unavailable" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // 2. Validate score range
  const maxScore = survey.type === "nps" ? 10 : 5;
  const minScore = survey.type === "nps" ? 0 : 1;
  if (score < minScore || score > maxScore || !Number.isInteger(score)) {
    return new Response(JSON.stringify({ error: "score_out_of_range" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // 3. Insert response
  const { error: insertErr } = await client.from("student_nps").insert({
    survey_id: survey.id,
    survey_type: survey.type,
    student_id: link.student_id,
    cohort_id: survey.cohort_id,
    score,
    feedback: feedback?.trim() || null,
    responded_at: new Date().toISOString(),
  });

  if (insertErr) {
    console.error("Insert error:", insertErr);
    return new Response(JSON.stringify({ error: "save_failed" }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // 4. Mark token as used
  await client
    .from("survey_links")
    .update({ used_at: new Date().toISOString() })
    .eq("id", link.id);

  return new Response(JSON.stringify({ success: true }), {
    status: 200,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
});
