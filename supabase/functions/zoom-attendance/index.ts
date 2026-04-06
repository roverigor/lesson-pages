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

const ALLOWED_ORIGINS = [
  "https://lesson-pages.vercel.app",
  "https://calendario.igorrover.com.br",
];

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.includes(origin)
      ? origin
      : ALLOWED_ORIGINS[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

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

// Remove suffixes like " - 65 98111-6464" or " - BNI Alquimia" and phone-like patterns
function cleanParticipantName(raw: string): string {
  // Remove everything after " - " (space-dash-space) — often phone or location
  let cleaned = raw.replace(/\s+-\s+.+$/, "").trim();
  // Remove standalone phone number patterns (5+ consecutive digits with optional separators)
  cleaned = cleaned.replace(/\s*[\+\(]?\d[\d\s\(\)\-\.]{4,}\d\s*/g, " ").trim();
  return cleaned;
}

// ─── Jaro-Winkler similarity (pure TypeScript, no deps) ───
function jaroWinkler(s1: string, s2: string): number {
  if (s1 === s2) return 1.0;
  const len1 = s1.length;
  const len2 = s2.length;
  if (len1 === 0 || len2 === 0) return 0.0;

  const matchDist = Math.max(Math.floor(Math.max(len1, len2) / 2) - 1, 0);
  const s1Matches = new Array(len1).fill(false);
  const s2Matches = new Array(len2).fill(false);

  let matches = 0;
  let transpositions = 0;

  for (let i = 0; i < len1; i++) {
    const start = Math.max(0, i - matchDist);
    const end = Math.min(i + matchDist + 1, len2);
    for (let j = start; j < end; j++) {
      if (s2Matches[j] || s1[i] !== s2[j]) continue;
      s1Matches[i] = true;
      s2Matches[j] = true;
      matches++;
      break;
    }
  }

  if (matches === 0) return 0.0;

  let k = 0;
  for (let i = 0; i < len1; i++) {
    if (!s1Matches[i]) continue;
    while (!s2Matches[k]) k++;
    if (s1[i] !== s2[k]) transpositions++;
    k++;
  }

  const jaro =
    (matches / len1 + matches / len2 + (matches - transpositions / 2) / matches) / 3;

  // Winkler prefix bonus (up to 4 chars)
  let prefix = 0;
  for (let i = 0; i < Math.min(4, Math.min(len1, len2)); i++) {
    if (s1[i] === s2[i]) prefix++;
    else break;
  }

  return jaro + prefix * 0.1 * (1 - jaro);
}

// Compare full normalized names using Jaro-Winkler; returns similarity [0..1]
function fuzzyNameSimilarity(pName: string, sName: string): number {
  // Full string comparison
  const full = jaroWinkler(pName, sName);
  if (full >= 0.92) return full;

  // Token-level: compare first tokens and last tokens independently
  const pParts = pName.split(/\s+/);
  const sParts = sName.split(/\s+/);
  if (pParts.length < 2 || sParts.length < 2) return full;

  const firstSim = jaroWinkler(pParts[0], sParts[0]);
  const lastSim = jaroWinkler(pParts[pParts.length - 1], sParts[sParts.length - 1]);

  // Both tokens must be highly similar
  if (firstSim >= 0.88 && lastSim >= 0.88) {
    return (firstSim + lastSim) / 2;
  }

  return full;
}

interface MatchResult {
  matches: Record<string, string>;
  nearMatches: Record<string, { candidateName: string; candidateId: string; score: number }>;
}

function matchStudents(
  participants: Array<{ name: string; email: string }>,
  students: Array<{ id: string; name: string; phone: string; email?: string; is_mentor?: boolean }>
): MatchResult {
  const matches: Record<string, string> = {};
  const nearMatches: Record<string, { candidateName: string; candidateId: string; score: number }> = {};

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
    // Apply name cleaning before normalization (removes phone/suffix noise)
    const cleaned = cleanParticipantName(p.name);
    const pName = normalize(cleaned);
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

    let bestMatch: { id: string; score: number; name: string } | null = null;

    for (const s of eligibleStudents) {
      const sName = normalize(s.name);
      if (!sName) continue;
      const sParts = sName.split(/\s+/).filter(w => w.length > 1);
      if (sParts.length === 0) continue;

      // LEVEL 1: Exact full name match (score 100)
      if (pName === sName) {
        bestMatch = { id: s.id, score: 100, name: s.name };
        break;
      }

      // LEVEL 2: First name + last name exact match (score 80)
      if (pParts.length >= 2 && sParts.length >= 2) {
        const pFirst = pParts[0];
        const pLast = pParts[pParts.length - 1];
        const sFirst = sParts[0];
        const sLast = sParts[sParts.length - 1];

        if (pFirst === sFirst && pLast === sLast && pFirst.length >= 3 && pLast.length >= 3) {
          const score = 80;
          if (!bestMatch || score > bestMatch.score) {
            bestMatch = { id: s.id, score, name: s.name };
          }
          continue;
        }
      }

      // LEVEL 3: First name (unique) + any other word match (score 60)
      if (pParts.length >= 2 && sParts.length >= 2) {
        const pFirst = pParts[0];
        const sFirst = sParts[0];

        if (pFirst === sFirst && pFirst.length >= 4 && (firstNameCount[pFirst] || 0) === 1) {
          const pRest = new Set(pParts.slice(1));
          const sRest = new Set(sParts.slice(1));
          const commonWords = [...pRest].filter(w => sRest.has(w) && w.length >= 3);

          if (commonWords.length > 0) {
            const score = 60;
            if (!bestMatch || score > bestMatch.score) {
              bestMatch = { id: s.id, score, name: s.name };
            }
          }
        }
      }

      // LEVEL 4: Fuzzy Jaro-Winkler (score 70, threshold >= 0.85)
      // Applied only when participant has at least 2 name parts
      if (pParts.length >= 2 && sParts.length >= 2 && (!bestMatch || bestMatch.score < 70)) {
        const similarity = fuzzyNameSimilarity(pName, sName);
        if (similarity >= 0.85) {
          const score = Math.round(similarity * 70); // maps [0.85..1.0] → [59..70]
          if (!bestMatch || score > bestMatch.score) {
            bestMatch = { id: s.id, score, name: s.name };
          }
        } else if (similarity >= 0.75 && (!bestMatch)) {
          // Near-match: record but don't accept
          const prev = nearMatches[key];
          if (!prev || similarity > prev.score) {
            nearMatches[key] = { candidateName: s.name, candidateId: s.id, score: Math.round(similarity * 100) / 100 };
          }
        }
      }
    }

    if (bestMatch && bestMatch.score >= 60) {
      matches[key] = bestMatch.id;
    }
  }

  return { matches, nearMatches };
}

// ─── Zoom Reports API: list all meetings for a user in a date range ───

// Uses /v2/metrics/meetings (requires dashboard_meetings:read:admin scope)
// Returns all past meetings in date range regardless of host
async function listDashboardMeetings(
  token: string,
  from: string,
  to: string
): Promise<Array<{ id: string; uuid: string; topic: string; host: string; start_time: string; end_time: string; duration: number; participants: number }>> {
  let allMeetings: Array<{ id: string; uuid: string; topic: string; host: string; start_time: string; end_time: string; duration: number; participants: number }> = [];
  let nextToken = "";

  do {
    const url = `/metrics/meetings?type=past&from=${from}&to=${to}&page_size=300${nextToken ? "&next_page_token=" + nextToken : ""}`;
    const data = await zoomGet(token, url);
    allMeetings = allMeetings.concat(data.meetings || []);
    nextToken = data.next_page_token || "";
  } while (nextToken);

  return allMeetings;
}

// ─── Main Handler ───

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders(req) });
  }

  try {
    const body = await req.json();
    const { action, meeting_id, cohort_id, class_id } = body;

    // ── ACTION: debug_scopes ──────────────────────────────────────────
    // Tests multiple Zoom API endpoints to identify which scopes are active.
    if (action === "debug_scopes") {
      const token = await getS2SToken();
      const tests = [
        { scope: "user:read:admin",                    endpoint: "/users/me" },
        { scope: "meeting:read:list_meetings:admin",   endpoint: "/users/me/meetings?type=previous_meetings&page_size=1" },
        { scope: "report:read:user",                   endpoint: "/report/users/me/meetings?from=2026-04-01&to=2026-04-07&page_size=1" },
        { scope: "report:read:admin",                  endpoint: "/report/users/me/meetings?from=2026-04-01&to=2026-04-07&page_size=1" },
        { scope: "dashboard_meetings:read:admin",      endpoint: "/metrics/meetings?type=past&page_size=1&from=2026-04-01&to=2026-04-07" },
        { scope: "recording:read:list_user_recordings:admin", endpoint: "/users/me/recordings?from=2026-04-01&to=2026-04-07&page_size=1" },
      ];

      const results: Record<string, { ok: boolean; status?: number; error?: string }> = {};
      for (const t of tests) {
        try {
          const res = await fetch(`https://api.zoom.us/v2${t.endpoint}`, {
            headers: { "Authorization": `Bearer ${token}` },
          });
          if (res.ok) {
            results[t.scope] = { ok: true };
          } else {
            const body = await res.json().catch(() => ({}));
            results[t.scope] = { ok: false, status: res.status, error: body.message || res.statusText };
          }
        } catch (e) {
          results[t.scope] = { ok: false, error: String(e) };
        }
      }
      return new Response(
        JSON.stringify({ ok: true, scope_tests: results }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: list_meetings ──────────────────────────────────────────
    // Uses Zoom Reports API to discover all meetings for the host in a date range.
    // Does NOT require knowing the meeting_id in advance.
    // body: { action: "list_meetings", user_id: "me"|email, from: "YYYY-MM-DD", to: "YYYY-MM-DD" }
    if (action === "list_meetings") {
      const {
        user_id = "me",
        from = new Date(Date.now() - 90 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10),
        to = new Date().toISOString().slice(0, 10),
      } = body as { user_id?: string; from?: string; to?: string };

      const token = await getS2SToken();
      // Use Dashboard Metrics API (dashboard_meetings:read:admin scope)
      const meetings = await listDashboardMeetings(token, from, to);

      // Deduplicate by meeting_id (recurring meetings appear once per instance)
      const byMeetingId: Record<string, { id: string; topic: string; host: string; instances: number; latest: string; total_participants: number }> = {};
      for (const m of meetings) {
        const mid = String(m.id);
        if (!byMeetingId[mid]) {
          byMeetingId[mid] = { id: mid, topic: m.topic, host: m.host || "", instances: 0, latest: m.start_time, total_participants: 0 };
        }
        byMeetingId[mid].instances += 1;
        byMeetingId[mid].total_participants += m.participants || 0;
        if (m.start_time > byMeetingId[mid].latest) byMeetingId[mid].latest = m.start_time;
      }

      const summary = Object.values(byMeetingId).sort((a, b) => b.latest.localeCompare(a.latest));

      return new Response(
        JSON.stringify({ ok: true, from, to, total_raw: meetings.length, meetings: summary }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: rematch_all ───────────────────────────────────────────
    // Re-runs matching on all zoom_participants where matched=false.
    // Uses the improved fuzzy algorithm. Updates student_id + matched in bulk.
    // body: { action: "rematch_all", cohort_id?: string }
    if (action === "rematch_all") {
      const sb = getSupabaseClient();

      // Load all active students
      const { data: students } = await (cohort_id
        ? sb.from("students").select("id, name, phone, email, is_mentor").eq("active", true).eq("cohort_id", cohort_id)
        : sb.from("students").select("id, name, phone, email, is_mentor").eq("active", true));

      if (!students?.length) {
        return new Response(
          JSON.stringify({ ok: false, error: "No students found" }),
          { status: 400, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      // Load all unmatched participants in pages of 500
      let totalProcessed = 0;
      let totalMatched = 0;
      let page = 0;
      const pageSize = 500;

      while (true) {
        const query = sb
          .from("zoom_participants")
          .select("id, participant_name, participant_email, meeting_id")
          .eq("matched", false)
          .not("participant_name", "is", null)
          .range(page * pageSize, (page + 1) * pageSize - 1);

        const { data: unmatched, error } = await query;
        if (error || !unmatched?.length) break;

        // Run matching on this page
        const { matches } = matchStudents(
          unmatched.map(p => ({ name: p.participant_name || "", email: p.participant_email || "" })),
          students
        );

        // Build update list
        const toUpdate: Array<{ id: string; student_id: string }> = [];
        for (const p of unmatched) {
          const key = p.participant_email || normalize(cleanParticipantName(p.participant_name || ""));
          const studentId = matches[key];
          if (studentId) toUpdate.push({ id: p.id, student_id: studentId });
        }

        // Update matched records individually (Supabase doesn't support bulk update by id list easily)
        for (const u of toUpdate) {
          await sb.from("zoom_participants")
            .update({ student_id: u.student_id, matched: true })
            .eq("id", u.id);
        }

        totalProcessed += unmatched.length;
        totalMatched += toUpdate.length;
        if (unmatched.length < pageSize) break;
        page++;
      }

      return new Response(
        JSON.stringify({ ok: true, processed: totalProcessed, newly_matched: totalMatched }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: transfer_to_attendance ────────────────────────────────
    // Copies matched zoom_participants into student_attendance table.
    // Skips duplicates via ON CONFLICT (student_id, class_date, zoom_meeting_id).
    // body: { action: "transfer_to_attendance", cohort_id?: string }
    if (action === "transfer_to_attendance") {
      const sb = getSupabaseClient();

      // Fetch matched participants with their meeting start_time and cohort_id
      const { data: participants, error } = await sb
        .from("zoom_participants")
        .select("id, student_id, duration_minutes, meeting_id, zoom_meetings(id, start_time, cohort_id)")
        .eq("matched", true)
        .not("student_id", "is", null);

      if (error) {
        return new Response(
          JSON.stringify({ ok: false, error: error.message }),
          { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      let inserted = 0;
      let skipped = 0;

      // Build rows for student_attendance
      const rows = (participants || [])
        .filter(p => {
          const meeting = p.zoom_meetings as { id: string; start_time: string; cohort_id: string | null } | null;
          return meeting?.start_time;
        })
        .map(p => {
          const meeting = p.zoom_meetings as { id: string; start_time: string; cohort_id: string | null };
          const classDate = meeting.start_time.slice(0, 10); // YYYY-MM-DD
          return {
            student_id: p.student_id,
            class_date: classDate,
            cohort_id: meeting.cohort_id || cohort_id || null,
            zoom_meeting_id: meeting.id,
            zoom_participant_id: p.id,
            source: "zoom",
            duration_minutes: p.duration_minutes || null,
          };
        });

      // Apply optional cohort filter
      const filteredRows = cohort_id
        ? rows.filter(r => r.cohort_id === cohort_id)
        : rows;

      // Insert in batches of 100 using upsert (ignore conflicts)
      const batchSize = 100;
      for (let i = 0; i < filteredRows.length; i += batchSize) {
        const batch = filteredRows.slice(i, i + batchSize);
        const { error: insertErr, count } = await sb
          .from("student_attendance")
          .upsert(batch, { onConflict: "student_id,class_date,zoom_meeting_id", ignoreDuplicates: true })
          .select("id", { count: "exact", head: true });

        if (insertErr) {
          skipped += batch.length;
        } else {
          inserted += count || 0;
          skipped += batch.length - (count || 0);
        }
      }

      return new Response(
        JSON.stringify({ ok: true, total: filteredRows.length, inserted, skipped }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    if (!meeting_id) {
      return new Response(
        JSON.stringify({ ok: false, error: "meeting_id required" }),
        { status: 400, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    const sb = getSupabaseClient();
    const token = await getS2SToken();

    // Get past instances of this meeting
    // Uses Zoom Reports API first (goes back 6 months), falls back to past_meetings API (≈30 days)
    let instances: Array<{ uuid: string; start_time?: string }> = [];

    // Try Zoom Reports API first — more reliable for historical data
    try {
      const from = new Date(Date.now() - 180 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);
      const to = new Date().toISOString().slice(0, 10);
      const reportData = await zoomGet(token, `/report/meetings/${meeting_id}/participants?page_size=1`).catch(() => null);
      // If past_meetings/instances works (recent), use it
      const instData = await zoomGet(token, `/past_meetings/${meeting_id}/instances`).catch(() => null);
      if (instData?.meetings?.length) {
        instances = instData.meetings;
      }
    } catch {
      // ignore, will try fallback below
    }

    // Fallback: try as direct UUID
    if (!instances.length) {
      const details = await getPastMeetingDetails(token, meeting_id);
      if (details) {
        instances.push({ uuid: details.uuid, start_time: details.start_time });
      }
    }

    if (!instances.length) {
      return new Response(
        JSON.stringify({ ok: false, error: "No past meeting instances found. Meeting may still be live or not yet ended." }),
        { status: 404, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // Process at most `batch_size` instances per call to avoid WORKER_LIMIT
    // Caller can paginate by passing `offset` (default 0)
    const { offset = 0, batch_size = 3 } = body as { offset?: number; batch_size?: number };
    const totalInstances = instances.length;
    instances = instances.slice(offset, offset + batch_size);

    // Load students for matching (include email and is_mentor for guardrails)
    const { data: students } = await (cohort_id
      ? sb.from("students").select("id, name, phone, email, is_mentor").eq("active", true).eq("cohort_id", cohort_id)
      : sb.from("students").select("id, name, phone, email, is_mentor").eq("active", true));

    // Process instances in parallel with concurrency limit of 2 (reduced to avoid WORKER_LIMIT)
    async function processInstance(instance: { uuid: string; start_time?: string }) {
      const uuid = instance.uuid;

      const { data: existing } = await sb.from("zoom_meetings")
        .select("id").eq("zoom_uuid", uuid).single();
      if (existing) return { uuid, status: "already_processed", id: existing.id };

      const details = await getPastMeetingDetails(token, uuid);
      let participants: Record<string, string | number>[];
      try {
        participants = await getMeetingParticipants(token, uuid);
      } catch (err) {
        return { uuid, status: "error", error: String(err) };
      }

      const realParticipants = participants.filter((p) => !isBot((p.name as string) || ""));

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

      if (meetingError) return { uuid, status: "error", error: meetingError.message };

      const { matches: studentMatches, nearMatches } = matchStudents(
        realParticipants.map((p) => ({ name: (p.name as string) || "", email: (p.user_email as string) || "" })),
        students || []
      );

      const participantRows = realParticipants.map((p) => {
        const pEmail = (p.user_email as string) || "";
        const key = pEmail || normalize(cleanParticipantName((p.name as string) || ""));
        const studentId = studentMatches[key] || null;
        return {
          meeting_id: meeting.id,
          participant_name: (p.name as string) || null,
          participant_email: pEmail || null,
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

      await sb.from("zoom_meetings").update({ processed: true }).eq("id", meeting.id);

      const matched = participantRows.filter(r => r.matched).length;
      return {
        uuid,
        status: "processed",
        meeting_id: meeting.id,
        topic: meeting.topic,
        participants: realParticipants.length,
        matched,
        unmatched: participantRows.length - matched,
        near_matches: Object.keys(nearMatches).length,
      };
    }

    // Process sequentially to avoid WORKER_LIMIT on Supabase edge functions
    const results = [];
    for (const instance of instances) {
      const settled = await Promise.allSettled([processInstance(instance)]);
      for (const r of settled) {
        results.push(r.status === "fulfilled" ? r.value : { uuid: "unknown", status: "error", error: String((r as PromiseRejectedResult).reason) });
      }
    }

    const nextOffset = offset + batch_size;
    const hasMore = nextOffset < totalInstances;

    return new Response(
      JSON.stringify({
        ok: true,
        meeting_id,
        total_instances: totalInstances,
        offset,
        batch_size,
        has_more: hasMore,
        next_offset: hasMore ? nextOffset : null,
        instances: results,
      }),
      { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
    );

  } catch (err) {
    return new Response(
      JSON.stringify({ ok: false, error: err instanceof Error ? err.message : "Unknown error" }),
      { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
    );
  }
});
