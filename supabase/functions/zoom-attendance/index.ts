// ═══════════════════════════════════════
// Edge Function: zoom-attendance
// Pulls meeting participants from Zoom API (Server-to-Server)
// Saves to zoom_meetings + zoom_participants
// Matches participants with students
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "https://gpufcipkajppykmnmdeh.supabase.co";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const ZOOM_S2S_ACCOUNT_ID = Deno.env.get("ZOOM_S2S_ACCOUNT_ID") ?? "rZnbgAqlTeKMsfyWwJ9AHw";
const ZOOM_S2S_CLIENT_ID = Deno.env.get("ZOOM_S2S_CLIENT_ID") ?? "wZ_C6smTrq7mxitAKMcA";
const ZOOM_S2S_CLIENT_SECRET = Deno.env.get("ZOOM_S2S_CLIENT_SECRET") ?? "7A6OATaB3m5jmEfS2VSRwwqzd5nlmasT";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function getSupabaseClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// ─── Zoom S2S Auth ───

async function getS2SToken(): Promise<string> {
  const basicAuth = btoa(`${ZOOM_S2S_CLIENT_ID}:${ZOOM_S2S_CLIENT_SECRET}`);
  const res = await fetch(
    `https://zoom.us/oauth/token?grant_type=account_credentials&account_id=${ZOOM_S2S_ACCOUNT_ID}`,
    {
      method: "POST",
      headers: { "Authorization": `Basic ${basicAuth}` },
    }
  );

  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Zoom S2S auth failed: ${err}`);
  }

  const data = await res.json();
  return data.access_token;
}

// ─── Zoom API Helpers ───

async function zoomGet(token: string, path: string) {
  const res = await fetch(`https://api.zoom.us/v2${path}`, {
    headers: { "Authorization": `Bearer ${token}` },
  });
  if (!res.ok) {
    const err = await res.text();
    throw new Error(`Zoom API ${path}: ${res.status} ${err}`);
  }
  return res.json();
}

async function getMeetingInstances(token: string, meetingId: string) {
  try {
    const data = await zoomGet(token, `/past_meetings/${meetingId}/instances`);
    return data.meetings || [];
  } catch {
    return [];
  }
}

async function getMeetingParticipants(token: string, meetingUUID: string) {
  // UUID must be double-encoded if it contains / or //
  const encoded = encodeURIComponent(encodeURIComponent(meetingUUID));
  const data = await zoomGet(token, `/past_meetings/${encoded}/participants?page_size=300`);
  return data.participants || [];
}

async function getPastMeetingDetails(token: string, meetingUUID: string) {
  const encoded = encodeURIComponent(encodeURIComponent(meetingUUID));
  try {
    return await zoomGet(token, `/past_meetings/${encoded}`);
  } catch {
    return null;
  }
}

// ─── Student Matching ───

function normalize(str: string): string {
  return (str || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, "")
    .trim();
}

function matchStudents(
  participants: Array<{ name: string; email: string }>,
  students: Array<{ id: string; name: string; phone: string }>
): Record<string, string> {
  const matches: Record<string, string> = {};

  for (const p of participants) {
    const pName = normalize(p.name);
    if (!pName || pName.match(/notetaker|fathom|read\.ai|fireflies|otter/i)) continue;

    for (const s of students) {
      const sName = normalize(s.name);
      if (!sName) continue;

      // Exact match
      if (pName === sName) {
        matches[p.email || pName] = s.id;
        break;
      }

      // First + last name match
      const pParts = pName.split(/\s+/);
      const sParts = sName.split(/\s+/);
      if (pParts[0] === sParts[0] && pParts.length > 1 && sParts.length > 1) {
        const pLast = pParts[pParts.length - 1];
        const sLast = sParts[sParts.length - 1];
        if (pLast === sLast) {
          matches[p.email || pName] = s.id;
          break;
        }
      }

      // First name only (if unique enough, 4+ chars)
      if (pParts[0].length >= 4 && pParts[0] === sParts[0]) {
        matches[p.email || pName] = s.id;
        break;
      }
    }
  }

  return matches;
}

// ─── Main Handler ───

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json();
    const { meeting_id, cohort_id, class_id } = body;

    if (!meeting_id) {
      return new Response(
        JSON.stringify({ ok: false, error: "meeting_id required" }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    const sb = getSupabaseClient();
    const token = await getS2SToken();

    // Get past instances of this meeting
    const instances = await getMeetingInstances(token, meeting_id);

    if (!instances.length) {
      // Try as a single meeting UUID directly
      const details = await getPastMeetingDetails(token, meeting_id);
      if (details) {
        instances.push({ uuid: details.uuid, start_time: details.start_time });
      }
    }

    if (!instances.length) {
      return new Response(
        JSON.stringify({ ok: false, error: "No past meeting instances found. Meeting may still be live or not yet ended." }),
        { status: 404, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      );
    }

    // Load students for matching
    const studentQuery = sb.from("students").select("id, name, phone").eq("active", true);
    if (cohort_id) studentQuery.eq("cohort_id", cohort_id);
    const { data: students } = await studentQuery;

    const results = [];

    for (const instance of instances) {
      const uuid = instance.uuid;

      // Check if already processed
      const { data: existing } = await sb.from("zoom_meetings")
        .select("id")
        .eq("zoom_uuid", uuid)
        .single();

      if (existing) {
        results.push({ uuid, status: "already_processed", id: existing.id });
        continue;
      }

      // Get meeting details
      const details = await getPastMeetingDetails(token, uuid);

      // Get participants
      let participants;
      try {
        participants = await getMeetingParticipants(token, uuid);
      } catch (err) {
        results.push({ uuid, status: "error", error: String(err) });
        continue;
      }

      // Filter out bots/notetakers
      const realParticipants = participants.filter((p: Record<string, string>) => {
        const name = (p.name || "").toLowerCase();
        return !name.includes("notetaker") &&
               !name.includes("fathom") &&
               !name.includes("read.ai") &&
               !name.includes("fireflies") &&
               !name.includes("otter");
      });

      // Save meeting
      const { data: meeting, error: meetingError } = await sb.from("zoom_meetings").insert({
        zoom_meeting_id: meeting_id,
        zoom_uuid: uuid,
        host_email: details?.host_email || "pedagogico@academialendaria.ai",
        host_name: details?.host || null,
        topic: details?.topic || null,
        start_time: details?.start_time || instance.start_time || null,
        end_time: details?.end_time || null,
        duration_minutes: details?.duration || null,
        participants_count: realParticipants.length,
        class_id: class_id || null,
        cohort_id: cohort_id || null,
      }).select().single();

      if (meetingError) {
        results.push({ uuid, status: "error", error: meetingError.message });
        continue;
      }

      // Match participants to students
      const studentMatches = matchStudents(
        realParticipants.map((p: Record<string, string>) => ({
          name: p.name || "",
          email: p.user_email || "",
        })),
        students || []
      );

      // Save participants
      let matched = 0;
      let unmatched = 0;

      for (const p of realParticipants) {
        const key = p.user_email || normalize(p.name);
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

      // Mark as processed
      await sb.from("zoom_meetings").update({ processed: true }).eq("id", meeting.id);

      results.push({
        uuid,
        status: "processed",
        meeting_id: meeting.id,
        topic: meeting.topic,
        participants: realParticipants.length,
        matched,
        unmatched,
      });
    }

    return new Response(
      JSON.stringify({ ok: true, meeting_id, instances: results }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );

  } catch (err) {
    return new Response(
      JSON.stringify({ ok: false, error: err instanceof Error ? err.message : "Unknown error" }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    );
  }
});
