// ═══════════════════════════════════════
// Edge Function: submit-survey
// Public endpoint — token-based, no auth required
// Saves to survey_responses + survey_answers
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

function getClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

type AnswerPayload = {
  question_id: string;
  value_text?: string | null;
  value_number?: number | null;
  value_options?: string[] | null;
};

type Body = {
  token?: string;
  answers?: AnswerPayload[];
};

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

  let body: Body;
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  const { token, answers } = body;

  if (!token || !answers || !Array.isArray(answers)) {
    return new Response(JSON.stringify({ error: "missing_fields" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  const client = getClient();

  // 1. Validate token
  const { data: link, error: linkErr } = await client
    .from("survey_links")
    .select("id, survey_id, student_id, used_at, surveys(id, type, status)")
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

  const survey = link.surveys as { id: string; type: string; status: string } | null;
  if (!survey || survey.status === "draft") {
    return new Response(JSON.stringify({ error: "survey_unavailable" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // 2. Create survey_response
  const { data: response, error: respErr } = await client
    .from("survey_responses")
    .insert({
      survey_id: survey.id,
      link_id: link.id,
      student_id: link.student_id ?? null,
      submitted_at: new Date().toISOString(),
    })
    .select("id")
    .single();

  if (respErr || !response) {
    console.error("survey_responses insert error:", respErr);
    return new Response(JSON.stringify({ error: "save_failed" }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // 3. Insert survey_answers
  if (answers.length > 0) {
    const answerRows = answers
      .filter(a => a.question_id && a.question_id !== "__legacy__" && a.question_id !== "__legacy_fu__")
      .map(a => ({
        response_id:   response.id,
        question_id:   a.question_id,
        value_text:    a.value_text    ?? null,
        value_number:  a.value_number  ?? null,
        value_options: a.value_options ?? null,
      }));

    if (answerRows.length > 0) {
      const { error: answErr } = await client.from("survey_answers").insert(answerRows);
      if (answErr) {
        console.error("survey_answers insert error:", answErr);
        // Don't fail the whole submission — mark token used anyway
      }
    }
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
