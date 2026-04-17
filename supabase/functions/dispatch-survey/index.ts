// ═══════════════════════════════════════
// Edge Function: dispatch-survey
// Admin-only — generates tokens + sends WhatsApp in safe chunks
// Tracks sent status per student to allow resume after interruption
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { sendDM } from "../_shared/slack.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

// Meta WhatsApp Cloud API
const META_PHONE_NUMBER_ID = Deno.env.get("META_PHONE_NUMBER_ID") ?? "";
const META_API_KEY = Deno.env.get("META_API_KEY") ?? "";

// Fallback: Evolution API (legacy)
const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";

const BASE_URL = "https://painel.igorrover.com.br";

// ── SAFE throttle: 10s between messages ──
const DELAY_MS = 10_000;

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function sbService() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function verifyAdmin(authHeader: string | null): Promise<boolean> {
  if (!authHeader?.startsWith("Bearer ")) return false;
  const token = authHeader.slice(7);
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const { data: { user } } = await client.auth.getUser(token);
  return user?.user_metadata?.role === "admin";
}

async function sendWhatsApp(phone: string, message: string): Promise<boolean> {
  const digits = phone.replace(/\D/g, "");

  // Prefer Meta Cloud API
  if (META_PHONE_NUMBER_ID && META_API_KEY) {
    try {
      const res = await fetch(
        `https://graph.facebook.com/v21.0/${META_PHONE_NUMBER_ID}/messages`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${META_API_KEY}`,
          },
          body: JSON.stringify({
            messaging_product: "whatsapp",
            to: digits,
            type: "text",
            text: { body: message },
          }),
        }
      );
      if (res.ok) return true;
      const errBody = await res.text();
      console.error(`Meta WA API error: ${res.status} ${errBody}`);
      return false;
    } catch (e) {
      console.error("Meta WA API exception:", e);
      return false;
    }
  }

  // Fallback: Evolution API
  if (EVOLUTION_API_URL && EVOLUTION_API_KEY) {
    try {
      const res = await fetch(`${EVOLUTION_API_URL}/message/sendText/${EVOLUTION_INSTANCE}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: EVOLUTION_API_KEY },
        body: JSON.stringify({ number: digits + "@s.whatsapp.net", text: message }),
      });
      return res.ok;
    } catch {
      return false;
    }
  }

  console.error("No WhatsApp provider configured");
  return false;
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

  const isAdmin = await verifyAdmin(req.headers.get("Authorization"));
  if (!isAdmin) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  let body: {
    survey_id?: string;
    custom_message?: string;
    prepare_only?: boolean;
    limit?: number;
  };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  if (!body.survey_id) {
    return new Response(JSON.stringify({ error: "missing_survey_id" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  const client = sbService();

  // 1. Fetch survey
  const { data: survey, error: surveyErr } = await client
    .from("surveys")
    .select("*")
    .eq("id", body.survey_id)
    .single();

  if (surveyErr || !survey) {
    return new Response(JSON.stringify({ error: "survey_not_found" }), {
      status: 404,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  if (survey.status === "closed") {
    return new Response(JSON.stringify({ error: "survey_closed" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // 2. Fetch students
  let students: { id: string; name: string; phone: string }[] = [];

  if (survey.cohort_id) {
    const { data } = await client
      .from("students")
      .select("id, name, phone")
      .eq("cohort_id", survey.cohort_id)
      .eq("active", true)
      .eq("is_mentor", false)
      .order("name");
    students = data ?? [];
  } else if (survey.class_id) {
    const { data: bridges } = await client
      .from("class_cohorts")
      .select("cohort_id")
      .eq("class_id", survey.class_id);
    const cohortIds = (bridges ?? []).map((b: { cohort_id: string }) => b.cohort_id);
    if (cohortIds.length > 0) {
      const { data } = await client
        .from("students")
        .select("id, name, phone")
        .in("cohort_id", cohortIds)
        .eq("active", true)
        .eq("is_mentor", false)
        .order("name");
      students = data ?? [];
    }
  }

  if (students.length === 0) {
    return new Response(JSON.stringify({ error: "no_students_found" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // 3. Upsert survey_links (idempotent)
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
  const linkInserts = students.map((s) => ({
    survey_id: survey.id,
    student_id: s.id,
    expires_at: expiresAt,
  }));

  await client
    .from("survey_links")
    .upsert(linkInserts, { onConflict: "survey_id,student_id", ignoreDuplicates: true });

  // Count already sent and pending
  const { count: totalSent } = await client
    .from("survey_links")
    .select("id", { count: "exact", head: true })
    .eq("survey_id", survey.id)
    .eq("send_status", "sent");

  const { count: totalPending } = await client
    .from("survey_links")
    .select("id", { count: "exact", head: true })
    .eq("survey_id", survey.id)
    .eq("send_status", "pending");

  // ── PREPARE_ONLY: create links, return counts ──
  if (body.prepare_only) {
    await client
      .from("surveys")
      .update({ status: "active", dispatched_at: new Date().toISOString() })
      .eq("id", body.survey_id);

    return new Response(
      JSON.stringify({
        success: true,
        total: students.length,
        already_sent: totalSent ?? 0,
        pending: totalPending ?? 0,
        prepared: true,
      }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  }

  // ── CHUNK MODE: send only pending links ──
  const limit = body.limit ?? 3;

  // Fetch next batch of PENDING links with student data
  const { data: pendingLinks } = await client
    .from("survey_links")
    .select("id, student_id, token")
    .eq("survey_id", survey.id)
    .eq("send_status", "pending")
    .order("created_at")
    .limit(limit);

  if (!pendingLinks || pendingLinks.length === 0) {
    return new Response(
      JSON.stringify({
        success: true,
        dispatched: 0,
        skipped: 0,
        chunk_total: 0,
        total: students.length,
        already_sent: totalSent ?? 0,
        pending: 0,
        has_more: false,
      }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  }

  // Build student lookup
  const studentMap = new Map<string, { name: string; phone: string }>();
  students.forEach((s) => studentMap.set(s.id, { name: s.name, phone: s.phone }));

  let dispatched = 0;
  let skipped = 0;

  for (let i = 0; i < pendingLinks.length; i++) {
    const pl = pendingLinks[i];
    const student = studentMap.get(pl.student_id);

    if (!student?.phone) {
      // Mark as skipped (no phone)
      await client
        .from("survey_links")
        .update({ send_status: "skipped", sent_at: new Date().toISOString() })
        .eq("id", pl.id);
      skipped++;
      continue;
    }

    const link = `${BASE_URL}/avaliacao/responder?token=${pl.token}`;
    const rawName = (student.name || "").trim();
    const firstName = (!rawName || /^\d+$/.test(rawName)) ? "aluno" : rawName.split(" ")[0];

    let message: string;
    if (body.custom_message?.trim()) {
      message = body.custom_message
        .replace(/\{nome\}/g, firstName)
        .replace(/\{link\}/g, link);
    } else {
      const intro = survey.intro_text?.trim();
      message =
        `Olá *${firstName}*! 👋\n\n` +
        (intro ? `${intro}\n\n` : `Sua opinião é muito importante para nós.\n\n`) +
        `Responda em 1 minuto: ${link}\n\n_Academia Lendária_ 🚀`;
    }

    const sent = await sendWhatsApp(student.phone, message);

    if (sent) {
      await client
        .from("survey_links")
        .update({ send_status: "sent", sent_at: new Date().toISOString() })
        .eq("id", pl.id);
      dispatched++;
    } else {
      await client
        .from("survey_links")
        .update({ send_status: "failed", sent_at: new Date().toISOString() })
        .eq("id", pl.id);
      skipped++;
    }

    // Safe delay between messages
    if (i < pendingLinks.length - 1) {
      await sleep(DELAY_MS);
    }
  }

  // Recount pending
  const { count: remainingPending } = await client
    .from("survey_links")
    .select("id", { count: "exact", head: true })
    .eq("survey_id", survey.id)
    .eq("send_status", "pending");

  const hasMore = (remainingPending ?? 0) > 0;

  // Notify Igor via Slack DM with dispatch results
  const SLACK_IGOR = Deno.env.get("SLACK_IGOR_USER_ID") ?? "";
  if (SLACK_IGOR && dispatched > 0) {
    try {
      const statusEmoji = skipped > 0 ? "⚠️" : "✅";
      await sendDM(
        SLACK_IGOR,
        `${statusEmoji} *Dispatch Survey*\n\n` +
        `📋 Pesquisa: ${survey.title || survey.id.slice(0, 8)}\n` +
        `✅ Enviados: ${dispatched}\n` +
        `⏭️ Pulados: ${skipped}\n` +
        `📬 Pendentes: ${remainingPending ?? 0}\n` +
        `${hasMore ? "⏳ Ainda há pendentes — continue o dispatch." : "🏁 Todos enviados!"}`
      );
    } catch (e) {
      console.error("Slack notification failed:", e);
    }
  }

  return new Response(
    JSON.stringify({
      success: true,
      dispatched,
      skipped,
      chunk_total: pendingLinks.length,
      total: students.length,
      already_sent: (totalSent ?? 0) + dispatched,
      pending: remainingPending ?? 0,
      has_more: hasMore,
    }),
    { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
  );
});
