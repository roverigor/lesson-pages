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

  let body: { cohort_id?: string };
  try {
    body = await req.json();
  } catch {
    return new Response(JSON.stringify({ error: "invalid_json" }), {
      status: 400,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
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
