// ═══════════════════════════════════════
// Edge Function: dispatch-survey
// Admin-only — generates tokens + sends WhatsApp to all students in cohort
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";

const BASE_URL = "https://painel.igorrover.com.br";

// ── Throttle config (anti-ban WhatsApp) ──
const BATCH_SIZE = 50;                     // messages per batch
const BATCH_PAUSE_MS = 3 * 60 * 1000;     // 3 min pause between batches
const MIN_DELAY_MS = 8_000;               // min delay between messages
const MAX_DELAY_MS = 15_000;              // max delay between messages

function randomDelay(): number {
  return MIN_DELAY_MS + Math.floor(Math.random() * (MAX_DELAY_MS - MIN_DELAY_MS));
}

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
  const remoteJid = phone.replace(/\D/g, "") + "@s.whatsapp.net";
  try {
    const res = await fetch(`${EVOLUTION_API_URL}/message/sendText/${EVOLUTION_INSTANCE}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: EVOLUTION_API_KEY },
      body: JSON.stringify({ number: remoteJid, text: message }),
    });
    return res.ok;
  } catch {
    return false;
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

  // Auth check
  const isAdmin = await verifyAdmin(req.headers.get("Authorization"));
  if (!isAdmin) {
    return new Response(JSON.stringify({ error: "unauthorized" }), {
      status: 401,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  let body: { survey_id?: string };
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

  // 2. Fetch students in cohort (or class via class_cohorts)
  let students: { id: string; name: string; phone: string }[] = [];

  if (survey.cohort_id) {
    const { data } = await client
      .from("students")
      .select("id, name, phone")
      .eq("cohort_id", survey.cohort_id)
      .eq("active", true)
      .eq("is_mentor", false);
    students = data ?? [];
  } else if (survey.class_id) {
    // Get cohorts linked to this class, then students in those cohorts
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
        .eq("is_mentor", false);
      students = data ?? [];
    }
  }

  if (students.length === 0) {
    return new Response(JSON.stringify({ error: "no_students_found" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // 3. Upsert survey_links (one token per student, skip if already exists)
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000).toISOString();
  const linkInserts = students.map((s) => ({
    survey_id: survey.id,
    student_id: s.id,
    expires_at: expiresAt,
  }));

  await client
    .from("survey_links")
    .upsert(linkInserts, { onConflict: "survey_id,student_id", ignoreDuplicates: true });

  // 4. Fetch all tokens (including previously generated)
  const { data: links } = await client
    .from("survey_links")
    .select("student_id, token")
    .eq("survey_id", survey.id);

  const tokenMap = new Map<string, string>(
    (links ?? []).map((l: { student_id: string; token: string }) => [l.student_id, l.token])
  );

  // 5. Send WhatsApp messages with throttling (anti-ban cadence)
  let dispatched = 0;
  let skipped = 0;
  let batchCount = 0;

  for (let i = 0; i < students.length; i++) {
    const student = students[i];

    if (!student.phone) {
      skipped++;
      continue;
    }

    const token = tokenMap.get(student.id);
    if (!token) {
      skipped++;
      continue;
    }

    const link = `${BASE_URL}/avaliacao/responder?token=${token}`;
    const firstName = student.name.split(" ")[0];
    const intro = survey.intro_text?.trim();
    const message =
      `Olá *${firstName}*! 👋\n\n` +
      (intro ? `${intro}\n\n` : `Sua opinião é muito importante para nós.\n\n`) +
      `Responda em 1 minuto: ${link}\n\n_Academia Lendária_ 🚀`;

    const sent = await sendWhatsApp(student.phone, message);
    if (sent) {
      dispatched++;
      batchCount++;
    } else {
      skipped++;
    }

    // Batch pause: every BATCH_SIZE successful sends, pause longer
    if (batchCount >= BATCH_SIZE && i < students.length - 1) {
      console.log(`[dispatch-survey] Batch of ${BATCH_SIZE} sent. Pausing ${BATCH_PAUSE_MS / 1000}s...`);
      await sleep(BATCH_PAUSE_MS);
      batchCount = 0;
    } else if (i < students.length - 1) {
      // Random delay between messages (8-15s)
      await sleep(randomDelay());
    }
  }

  // 6. Mark survey as active + set dispatched_at
  await client
    .from("surveys")
    .update({ status: "active", dispatched_at: new Date().toISOString() })
    .eq("id", survey.id);

  return new Response(
    JSON.stringify({ success: true, dispatched, skipped, total: students.length }),
    { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
  );
});
