// ═══════════════════════════════════════
// Edge Function: zoom-attendance
// Pulls meeting participants from Zoom API
// Saves to zoom_meetings + zoom_participants
// Matches participants with students
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "https://gpufcipkajppykmnmdeh.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ZOOM_CLIENT_ID = Deno.env.get("ZOOM_CLIENT_ID") ?? "DMb3dUSBQPuQDKnJv35Mig";
const ZOOM_CLIENT_SECRET = Deno.env.get("ZOOM_CLIENT_SECRET") ?? "GHTrUQ3hIvdCE7R8RBxAQywZzJwq1wFG";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function getSupabaseClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

async function getValidToken(sb: ReturnType<typeof getSupabaseClient>, zoomEmail: string): Promise<string | null> {
  const { data: token } = await sb.from("zoom_tokens")
    .select("*")
    .eq("zoom_email", zoomEmail)
    .eq("active", true)
    .single();

  if (!token) return null;

  // Check if expired
  if (new Date(token.expires_at) <= new Date()) {
    // Refresh
    const basicAuth = btoa(`${ZOOM_CLIENT_ID}:${ZOOM_CLIENT_SECRET}`);
    const res = await fetch("https://zoom.us/oauth/token", {
      method: "POST",
      headers: {
        "Authorization": `Basic ${basicAuth}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({
        grant_type: "refresh_token",
        refresh_token: token.refresh_token,
      }),
    });

    if (!res.ok) {
      await sb.from("zoom_tokens").update({ active: false }).eq("id", token.id);
      return null;
    }

    const newTokens = await res.json();
    const expiresAt = new Date(Date.now() + newTokens.expires_in * 1000).toISOString();

    await sb.from("zoom_tokens").update({
      access_token: newTokens.access_token,
      refresh_token: newTokens.refresh_token,
      expires_at: expiresAt,
    }).eq("id", token.id);

    return newTokens.access_token;
  }

  return token.access_token;
}

async function fetchMeetingParticipants(accessToken: string, meetingId: string) {
  // Use the report endpoint for past meetings
  const res = await fetch(
    `https://api.zoom.us/v2/report/meetings/${encodeURIComponent(meetingId)}/participants?page_size=300`,
    { headers: { "Authorization": `Bearer ${accessToken}` } }
  );

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Zoom API error ${res.status}: ${err}`);
  }

  return await res.json();
}

async function fetchPastMeetingDetails(accessToken: string, meetingId: string) {
  const res = await fetch(
    `https://api.zoom.us/v2/past_meetings/${encodeURIComponent(meetingId)}`,
    { headers: { "Authorization": `Bearer ${accessToken}` } }
  );

  if (!res.ok) return null;
  return await res.json();
}

function normalizePhone(phone: string): string {
  return phone.replace(/\D/g, "").replace(/^0+/, "");
}

async function matchParticipantsToStudents(
  sb: ReturnType<typeof getSupabaseClient>,
  participants: Array<{ name: string; email: string }>,
  cohortId: string | null
) {
  // Load students
  const query = sb.from("students").select("id, name, phone, cohort_id");
  if (cohortId) query.eq("cohort_id", cohortId);
  const { data: students } = await query;
  if (!students) return {};

  const matches: Record<string, string> = {}; // participant_email -> student_id

  for (const p of participants) {
    const pEmail = (p.email || "").toLowerCase();
    const pName = (p.name || "").toLowerCase().trim();

    // Match by name (fuzzy)
    for (const s of students) {
      const sName = (s.name || "").toLowerCase().trim();
      if (!sName || !pName) continue;

      // Exact name match
      if (sName === pName) {
        matches[pEmail || pName] = s.id;
        break;
      }

      // First name match (both have at least first name)
      const pFirst = pName.split(" ")[0];
      const sFirst = sName.split(" ")[0];
      if (pFirst.length > 2 && sFirst.length > 2 && pFirst === sFirst) {
        // Check last name too if available
        const pLast = pName.split(" ").pop() || "";
        const sLast = sName.split(" ").pop() || "";
        if (pLast === sLast || pName.includes(sFirst) || sName.includes(pFirst)) {
          matches[pEmail || pName] = s.id;
          break;
        }
      }
    }
  }

  return matches;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { meeting_id, zoom_email, cohort_id, class_id } = body;

    if (!meeting_id || !zoom_email) {
      return new Response(JSON.stringify({
        ok: false,
        error: "meeting_id and zoom_email required",
      }), { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    const sb = getSupabaseClient();

    // Get valid access token
    const accessToken = await getValidToken(sb, zoom_email);
    if (!accessToken) {
      return new Response(JSON.stringify({
        ok: false,
        error: `No valid Zoom token for ${zoom_email}. Mentor needs to re-authorize.`,
      }), { status: 401, headers: { ...corsHeaders, "Content-Type": "application/json" } });
    }

    // Fetch meeting details
    const meetingDetails = await fetchPastMeetingDetails(accessToken, meeting_id);

    // Fetch participants
    const participantsData = await fetchMeetingParticipants(accessToken, meeting_id);
    const participants = participantsData.participants || [];

    // Save meeting
    const { data: meeting, error: meetingError } = await sb.from("zoom_meetings").upsert({
      zoom_meeting_id: meeting_id,
      zoom_uuid: meetingDetails?.uuid || null,
      host_email: meetingDetails?.host_email || zoom_email,
      host_name: meetingDetails?.host || null,
      topic: meetingDetails?.topic || null,
      start_time: meetingDetails?.start_time || null,
      end_time: meetingDetails?.end_time || null,
      duration_minutes: meetingDetails?.duration || null,
      participants_count: participants.length,
      class_id: class_id || null,
      cohort_id: cohort_id || null,
    }, { onConflict: "zoom_uuid" }).select().single();

    if (meetingError) {
      return new Response(JSON.stringify({ ok: false, error: meetingError.message }), {
        status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    // Match participants to students
    const studentMatches = await matchParticipantsToStudents(
      sb,
      participants.map((p: Record<string, string>) => ({ name: p.name, email: p.user_email })),
      cohort_id || null
    );

    // Save participants
    let matched = 0;
    let unmatched = 0;

    for (const p of participants) {
      const key = p.user_email || (p.name || "").toLowerCase().trim();
      const studentId = studentMatches[key] || null;

      await sb.from("zoom_participants").insert({
        meeting_id: meeting.id,
        participant_name: p.name || null,
        participant_email: p.user_email || null,
        join_time: p.join_time || null,
        leave_time: p.leave_time || null,
        duration_minutes: p.duration ? Math.round(p.duration / 60) : null,
        student_id: studentId,
        matched: !!studentId,
      });

      if (studentId) matched++;
      else unmatched++;
    }

    // Mark meeting as processed
    await sb.from("zoom_meetings").update({ processed: true }).eq("id", meeting.id);

    return new Response(JSON.stringify({
      ok: true,
      meeting_id: meeting.id,
      topic: meeting.topic,
      participants_total: participants.length,
      matched,
      unmatched,
    }), {
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({
      ok: false,
      error: err instanceof Error ? err.message : "Unknown error",
    }), { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } });
  }
});
