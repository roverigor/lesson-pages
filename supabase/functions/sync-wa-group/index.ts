// ═══════════════════════════════════════
// Edge Function: sync-wa-group
// Fetches WhatsApp group members via Evolution API
// Returns phone list for cross-reference with students
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";

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

// ─── Phone normalization helper ───
function normalizePhone(raw: string): string {
  let phone = raw.replace("@s.whatsapp.net", "").replace(/\D/g, "");
  // Ensure BR country code
  if (phone.length === 10 || phone.length === 11) phone = "55" + phone;
  return phone;
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

  let body: { action?: string; cohort_id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // ── ACTION: auto_sync (Story 12.3 — EPIC-012) ─────────────────────
  // Called by pg_cron via service_role. Syncs ALL cohorts with whatsapp_group_jid.
  // Creates new students and student_cohorts links as needed.
  if (body.action === "auto_sync") {
    const sb = sbService();

    // Log start before any external I/O so crashes (Evolution offline, env missing)
    // still leave a breadcrumb in automation_runs.
    await sb.rpc("log_automation_step", {
      p_run_type: "wa_sync", p_step_name: "auto_sync_started",
      p_status: "success", p_processed: 0,
      p_metadata: { phase: "started" },
    }).then(({ error }) => { if (error) console.error("log_automation_step(start) error:", error); });

    try {
      if (!EVOLUTION_API_URL || !EVOLUTION_API_KEY || !EVOLUTION_INSTANCE) {
        throw new Error("Evolution API env vars missing (EVOLUTION_API_URL/KEY/INSTANCE)");
      }

      // Fetch all cohorts with WA group configured
      const { data: cohorts, error: cohortErr } = await sb
        .from("cohorts")
        .select("id, name, whatsapp_group_jid")
        .not("whatsapp_group_jid", "is", null);
      if (cohortErr) throw cohortErr;

      if (!cohorts?.length) {
        const { error: logErr0 } = await sb.rpc("log_automation_step", {
          p_run_type: "wa_sync", p_step_name: "auto_sync",
          p_status: "success", p_processed: 0,
          p_metadata: { reason: "no cohorts with whatsapp_group_jid" },
        });
        if (logErr0) console.error("log_automation_step error:", logErr0);
        return new Response(JSON.stringify({ ok: true, synced: 0, reason: "no_cohorts" }), {
          headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
        });
      }

    let totalProcessed = 0, totalCreated = 0, totalLinked = 0, totalFailed = 0;
    const cohortResults: Array<{ cohort: string; members: number; new_students: number; new_links: number; error?: string }> = [];

    for (const cohort of cohorts) {
      try {
        // Fetch WA group participants
        const url = `${EVOLUTION_API_URL}/group/participants/${EVOLUTION_INSTANCE}?groupJid=${cohort.whatsapp_group_jid}`;
        const res = await fetch(url, { headers: { apikey: EVOLUTION_API_KEY } });
        if (!res.ok) {
          const err = await res.text();
          cohortResults.push({ cohort: cohort.name, members: 0, new_students: 0, new_links: 0, error: `Evolution API ${res.status}: ${err}` });
          totalFailed++;
          continue;
        }

        const data = await res.json();
        const participants = (data.participants || []) as Array<{ phoneNumber?: string; id?: string; name?: string; admin?: string }>;
        let newStudents = 0, newLinks = 0;

        // Load existing students by phone for this cohort
        const { data: existingStudents } = await sb
          .from("students")
          .select("id, phone")
          .eq("cohort_id", cohort.id);

        const existingPhones = new Set((existingStudents || []).map(s => normalizePhone(s.phone || "")));

        // Load ALL students by phone (for cross-cohort linking)
        const { data: allStudents } = await sb
          .from("students")
          .select("id, phone, cohort_id");

        const studentByPhone: Record<string, { id: string; cohort_id: string | null }> = {};
        for (const s of (allStudents || [])) {
          const norm = normalizePhone(s.phone || "");
          if (norm) studentByPhone[norm] = { id: s.id, cohort_id: s.cohort_id };
        }

        for (const p of participants) {
          const rawPhone = (p.phoneNumber || p.id || "").replace("@s.whatsapp.net", "");
          const phone = normalizePhone(rawPhone);
          if (!phone || phone.length < 10) continue;

          totalProcessed++;

          if (existingPhones.has(phone)) continue; // Already in this cohort

          const existingStudent = studentByPhone[phone];

          if (existingStudent) {
            // Student exists in another cohort → link to this cohort via student_cohorts
            const { error: linkErr } = await sb
              .from("student_cohorts")
              .insert({ student_id: existingStudent.id, cohort_id: cohort.id })
              .select("id")
              .single();
            if (!linkErr) { newLinks++; totalLinked++; }
          } else {
            // New student → create
            const pushName = (p.name || "").trim() || `WA ${phone.slice(-4)}`;
            const { data: newStudent, error: insertErr } = await sb
              .from("students")
              .insert({
                name: pushName,
                phone,
                cohort_id: cohort.id,
                active: true,
              })
              .select("id")
              .single();

            if (!insertErr && newStudent) {
              newStudents++;
              totalCreated++;
              // Also link in student_cohorts
              await sb.from("student_cohorts")
                .insert({ student_id: newStudent.id, cohort_id: cohort.id });
              // Update local cache
              existingPhones.add(phone);
              studentByPhone[phone] = { id: newStudent.id, cohort_id: cohort.id };
            }
          }
        }

        cohortResults.push({ cohort: cohort.name, members: participants.length, new_students: newStudents, new_links: newLinks });
      } catch (e) {
        cohortResults.push({ cohort: cohort.name, members: 0, new_students: 0, new_links: 0, error: String(e) });
        totalFailed++;
      }
    }

    // Log to automation_runs
    const runStatus = totalFailed > 0 && totalCreated === 0 && totalLinked === 0 ? "error" : "success";
    const { error: logErr } = await sb.rpc("log_automation_step", {
      p_run_type: "wa_sync", p_step_name: "auto_sync",
      p_status: runStatus,
      p_processed: totalProcessed, p_created: totalCreated + totalLinked, p_failed: totalFailed,
      p_error: totalFailed > 0 ? `${totalFailed} cohorts failed` : null,
      p_metadata: { cohorts_synced: cohorts.length, cohort_results: cohortResults },
    });
    if (logErr) console.error("log_automation_step error:", logErr);

    return new Response(
      JSON.stringify({ ok: true, cohorts: cohorts.length, processed: totalProcessed, new_students: totalCreated, new_links: totalLinked, failed: totalFailed, details: cohortResults }),
      { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      console.error("auto_sync fatal:", msg);
      await sb.rpc("log_automation_step", {
        p_run_type: "wa_sync", p_step_name: "auto_sync",
        p_status: "error", p_processed: 0, p_failed: 1,
        p_error: msg,
        p_metadata: { phase: "fatal" },
      }).then(({ error }) => { if (error) console.error("log_automation_step(fatal) error:", error); });
      return new Response(JSON.stringify({ ok: false, error: msg }), {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }
  }

  // ── Manual sync (existing behavior — requires admin, unless action=list_only) ──
  if (body.action !== "list_only") {
    const isAdmin = await verifyAdmin(req.headers.get("Authorization"));
    if (!isAdmin) {
      return new Response(JSON.stringify({ error: "unauthorized" }), {
        status: 401,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }
  }

  if (!body.cohort_id) {
    return new Response(JSON.stringify({ error: "missing_cohort_id" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  const sb = sbService();

  // 1. Get cohort whatsapp_group_jid
  const { data: cohort, error: cohortErr } = await sb
    .from("cohorts")
    .select("id, name, whatsapp_group_jid")
    .eq("id", body.cohort_id)
    .single();

  if (cohortErr || !cohort) {
    return new Response(JSON.stringify({ error: "cohort_not_found" }), {
      status: 404,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  if (!cohort.whatsapp_group_jid) {
    return new Response(JSON.stringify({ error: "no_whatsapp_group", message: "Cohort has no whatsapp_group_jid configured" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // 2. Fetch group participants from Evolution API
  try {
    const url = `${EVOLUTION_API_URL}/group/participants/${EVOLUTION_INSTANCE}?groupJid=${cohort.whatsapp_group_jid}`;
    const res = await fetch(url, {
      headers: { apikey: EVOLUTION_API_KEY },
    });

    if (!res.ok) {
      const err = await res.text();
      return new Response(JSON.stringify({ error: "evolution_api_error", detail: err }), {
        status: 502,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const data = await res.json();
    const participants = data.participants || [];

    // Extract phone numbers (format: "5511999999999@s.whatsapp.net" → "+5511999999999")
    const members = participants.map((p: { phoneNumber?: string; name?: string; admin?: string }) => {
      const raw = (p.phoneNumber || "").replace("@s.whatsapp.net", "");
      return {
        phone: raw ? `+${raw}` : null,
        wa_name: p.name || null,
        is_admin: p.admin === "admin" || p.admin === "superadmin",
      };
    }).filter((m: { phone: string | null }) => m.phone);

    // 3. Cross-reference with students in this cohort
    const { data: students } = await sb
      .from("students")
      .select("id, name, phone, email")
      .eq("cohort_id", body.cohort_id)
      .eq("active", true);

    // Normalize phone for matching
    const normalize = (ph: string) => (ph || "").replace(/\D/g, "");
    const studentByPhone: Record<string, { id: string; name: string; email: string | null }> = {};
    for (const s of (students || [])) {
      if (s.phone) studentByPhone[normalize(s.phone)] = { id: s.id, name: s.name, email: s.email };
    }

    const result = members.map((m: { phone: string; wa_name: string | null; is_admin: boolean }) => {
      const norm = normalize(m.phone);
      const student = studentByPhone[norm];
      return {
        phone: m.phone,
        wa_name: m.wa_name,
        is_admin: m.is_admin,
        student_id: student?.id || null,
        student_name: student?.name || null,
        matched: !!student,
      };
    });

    // Also find students NOT in the WA group
    const waPhones = new Set(members.map((m: { phone: string }) => normalize(m.phone)));
    const notInGroup = (students || [])
      .filter(s => s.phone && !waPhones.has(normalize(s.phone)))
      .map(s => ({
        phone: s.phone,
        student_id: s.id,
        student_name: s.name,
        in_group: false,
      }));

    return new Response(
      JSON.stringify({
        ok: true,
        cohort_name: cohort.name,
        group_jid: cohort.whatsapp_group_jid,
        total_members: members.length,
        matched: result.filter((r: { matched: boolean }) => r.matched).length,
        unmatched: result.filter((r: { matched: boolean }) => !r.matched).length,
        not_in_group: notInGroup.length,
        members: result,
        students_not_in_group: notInGroup,
      }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(JSON.stringify({ error: "fetch_failed", detail: String(err) }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
