// ═══════════════════════════════════════
// Edge Function: zoom-attendance
// Pulls meeting participants from Zoom API (Server-to-Server)
// Saves to zoom_meetings + zoom_participants
// Matches participants with students
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const ZOOM_S2S_ACCOUNT_ID = Deno.env.get("ZOOM_S2S_ACCOUNT_ID") ?? "";
const ZOOM_S2S_CLIENT_ID = Deno.env.get("ZOOM_S2S_CLIENT_ID") ?? "";
const ZOOM_S2S_CLIENT_SECRET = Deno.env.get("ZOOM_S2S_CLIENT_SECRET") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://lesson-pages.vercel.app",
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
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10_000);
  try {
    const res = await fetch(`https://api.zoom.us/v2${path}`, {
      headers: { "Authorization": `Bearer ${token}` },
      signal: controller.signal,
    });
    if (!res.ok) {
      const err = await res.text();
      throw new Error(`Zoom API ${path}: ${res.status} ${err}`);
    }
    return res.json();
  } finally {
    clearTimeout(timeout);
  }
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
  let allParticipants: Record<string, unknown>[] = [];
  let nextToken = '';

  do {
    const url = `/past_meetings/${encoded}/participants?page_size=300${nextToken ? '&next_page_token=' + nextToken : ''}`;
    const data = await zoomGet(token, url);
    allParticipants = allParticipants.concat(data.participants || []);
    nextToken = data.next_page_token || '';
  } while (nextToken);

  return allParticipants;
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
// GUARDRAILS:
// 1. NEVER match by first name only — too many false positives
// 2. NEVER match mentors/staff (is_mentor=true) as students
// 3. Require first + last name match minimum
// 4. Filter bots, hosts, notetakers before matching
// 5. If multiple students match, prefer exact match, skip ambiguous
// 6. Email match takes priority over name match

const BOT_PATTERNS = /notetaker|fathom|read\.ai|fireflies|otter|bot\b|recording|reunio.*boa\s*vista|pedagogico.*academia|academia.*lend/i;

function normalize(str: string): string {
  return (str || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, "")
    .replace(/\s+/g, " ")
    .trim();
}

function isBot(name: string): boolean {
  return BOT_PATTERNS.test(name);
}

function matchStudents(
  participants: Array<{ name: string; email: string }>,
  students: Array<{ id: string; name: string; phone: string; email?: string; is_mentor?: boolean }>
): Record<string, string> {
  const matches: Record<string, string> = {};

  // Filter out mentors/staff from matching pool
  const eligibleStudents = students.filter(s => !s.is_mentor);

  // Build email lookup for priority matching
  const studentsByEmail: Record<string, string> = {};
  for (const s of eligibleStudents) {
    if (s.email) studentsByEmail[s.email.toLowerCase()] = s.id;
  }

  // Count first names to detect ambiguity
  const firstNameCount: Record<string, number> = {};
  for (const s of eligibleStudents) {
    const first = normalize(s.name).split(" ")[0];
    if (first) firstNameCount[first] = (firstNameCount[first] || 0) + 1;
  }

  for (const p of participants) {
    const pName = normalize(p.name);
    const pEmail = (p.email || "").toLowerCase().trim();

    // Skip bots and notetakers
    if (!pName || isBot(p.name)) continue;

    const key = pEmail || pName;

    // PRIORITY 1: Email match (most reliable)
    if (pEmail && studentsByEmail[pEmail]) {
      matches[key] = studentsByEmail[pEmail];
      continue;
    }

    const pParts = pName.split(/\s+/).filter(w => w.length > 1);
    if (pParts.length === 0) continue;

    let bestMatch: { id: string; score: number } | null = null;

    for (const s of eligibleStudents) {
      const sName = normalize(s.name);
      if (!sName) continue;
      const sParts = sName.split(/\s+/).filter(w => w.length > 1);
      if (sParts.length === 0) continue;

      // LEVEL 1: Exact full name match (score 100)
      if (pName === sName) {
        bestMatch = { id: s.id, score: 100 };
        break; // Perfect match, stop looking
      }

      // LEVEL 2: First name + last name match (score 80)
      // Both must have at least 2 parts
      if (pParts.length >= 2 && sParts.length >= 2) {
        const pFirst = pParts[0];
        const pLast = pParts[pParts.length - 1];
        const sFirst = sParts[0];
        const sLast = sParts[sParts.length - 1];

        if (pFirst === sFirst && pLast === sLast && pFirst.length >= 3 && pLast.length >= 3) {
          const score = 80;
          if (!bestMatch || score > bestMatch.score) {
            bestMatch = { id: s.id, score };
          }
          continue;
        }
      }

      // LEVEL 3: First name + any other name part match (score 60)
      // Only if first name is NOT ambiguous (unique in the student list)
      if (pParts.length >= 2 && sParts.length >= 2) {
        const pFirst = pParts[0];
        const sFirst = sParts[0];

        if (pFirst === sFirst && pFirst.length >= 4 && (firstNameCount[pFirst] || 0) === 1) {
          // Check if any other word matches
          const pRest = new Set(pParts.slice(1));
          const sRest = new Set(sParts.slice(1));
          const commonWords = [...pRest].filter(w => sRest.has(w) && w.length >= 3);

          if (commonWords.length > 0) {
            const score = 60;
            if (!bestMatch || score > bestMatch.score) {
              bestMatch = { id: s.id, score };
            }
          }
        }
      }

      // NO LEVEL 4: We do NOT match by first name only
    }

    // Only accept matches with score >= 60
    if (bestMatch && bestMatch.score >= 60) {
      matches[key] = bestMatch.id;
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

    // Load students for matching (include email and is_mentor for guardrails)
    const { data: students } = await (cohort_id
      ? sb.from("students").select("id, name, phone, email, is_mentor").eq("active", true).eq("cohort_id", cohort_id)
      : sb.from("students").select("id, name, phone, email, is_mentor").eq("active", true));

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

      // Filter out bots/notetakers — use centralized isBot() (P-034)
      const realParticipants = participants.filter((p: Record<string, string>) => !isBot(p.name || ""));

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

      // Save participants — single batch insert (P-006)
      const participantRows = realParticipants.map((p: Record<string, string | number>) => {
        const key = (p.user_email as string) || normalize(p.name as string);
        const studentId = studentMatches[key] || null;
        return {
          meeting_id: meeting.id,
          participant_name: (p.name as string) || null,
          participant_email: (p.user_email as string) || null,
          join_time: (p.join_time as string) || null,
          leave_time: (p.leave_time as string) || null,
          duration_minutes: p.duration ? Math.round((p.duration as number) / 60) : null,
          student_id: studentId,
          matched: !!studentId,
        };
      });

      if (participantRows.length > 0) {
        await sb.from("zoom_participants").insert(participantRows);
      }

      const matched = participantRows.filter(r => r.matched).length;
      const unmatched = participantRows.length - matched;

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
