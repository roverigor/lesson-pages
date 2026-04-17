// ═══════════════════════════════════════
// Edge Function: zoom-attendance
// Pulls meeting participants from Zoom API (Server-to-Server)
// Saves to zoom_meetings + zoom_participants
// Matches participants with students
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { sendApprovalMessage, sendDM, sendMessage } from "../_shared/slack.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const ZOOM_S2S_ACCOUNT_ID = Deno.env.get("ZOOM_S2S_ACCOUNT_ID") ?? "";
const ZOOM_S2S_CLIENT_ID = Deno.env.get("ZOOM_S2S_CLIENT_ID") ?? "";
const ZOOM_S2S_CLIENT_SECRET = Deno.env.get("ZOOM_S2S_CLIENT_SECRET") ?? "";
const OPENAI_API_KEY = Deno.env.get("OPENAI_API_KEY") ?? "";

const ALLOWED_ORIGINS = [
  "https://lesson-pages.vercel.app",
  "https://calendario.igorrover.com.br",
  "https://painel.igorrover.com.br",
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

// ─── Anti-ban cadence for WhatsApp ───
const WA_SAFE_DELAY_MS = 10_000; // 10s between messages
function waSleep(): Promise<void> {
  return new Promise((r) => setTimeout(r, WA_SAFE_DELAY_MS));
}

// ─── WhatsApp send helper (Meta Cloud API preferred, Evolution fallback) ───
async function sendWA(phone: string, text: string): Promise<boolean> {
  const digits = phone.replace(/\D/g, "");
  const META_PID = Deno.env.get("META_PHONE_NUMBER_ID") ?? "";
  const META_KEY = Deno.env.get("META_API_KEY") ?? "";

  if (META_PID && META_KEY) {
    try {
      const res = await fetch(
        `https://graph.facebook.com/v21.0/${META_PID}/messages`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${META_KEY}`,
          },
          body: JSON.stringify({
            messaging_product: "whatsapp",
            to: digits,
            type: "text",
            text: { body: text },
          }),
        }
      );
      if (res.ok) return true;
      const errBody = await res.text();
      console.error(`Meta WA API error: ${res.status} ${errBody}`);
    } catch (e) {
      console.error("Meta WA API exception:", e);
    }
  }

  // Fallback: Evolution API
  const EVO_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
  const EVO_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
  const EVO_INST = Deno.env.get("EVOLUTION_INSTANCE") ?? "";
  if (EVO_URL && EVO_KEY) {
    try {
      const res = await fetch(`${EVO_URL}/message/sendText/${EVO_INST}`, {
        method: "POST",
        headers: { "Content-Type": "application/json", apikey: EVO_KEY },
        body: JSON.stringify({ number: digits, text }),
      });
      return res.ok;
    } catch { return false; }
  }

  console.error("No WhatsApp provider configured");
  return false;
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
  students: Array<{ id: string; name: string; phone: string; email?: string; is_mentor?: boolean; aliases?: string[] }>
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

      // ALIAS CHECK: treat each alias as an alternate name to match against
      const aliasNames = (s.aliases || []).map(a => normalize(a)).filter(Boolean);

      // LEVEL 0: Exact alias match (score 100)
      if (aliasNames.some(a => a === pName)) {
        bestMatch = { id: s.id, score: 100, name: s.name };
        break;
      }

      // LEVEL 0b: Participant starts with alias (e.g. "João Silva @handle" → alias "João Silva")
      if (aliasNames.some(a => pName.startsWith(a + " ") || a.startsWith(pName + " "))) {
        if (!bestMatch || bestMatch.score < 90) {
          bestMatch = { id: s.id, score: 90, name: s.name };
        }
        continue;
      }

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

    // ── ACTION: health_check (Story 12.6 — EPIC-012) ───────────────────
    // Called by pg_cron at 06:00 AM UTC-3. Checks if daily_pipeline and wa_sync
    // ran today. Sends WhatsApp alert to coordinator if missing or failed.
    if (action === "health_check") {
      const sb = getSupabaseClient();
      const COORDINATOR_PHONE  = Deno.env.get("COORDINATOR_PHONE") ?? "";

      const today = new Date().toISOString().slice(0, 10);
      const alerts: string[] = [];

      // Check each pipeline
      for (const runType of ["daily_pipeline", "wa_sync", "absence_alerts"] as const) {
        const { data: runs } = await sb
          .from("automation_runs")
          .select("status, error_message, step_name")
          .eq("run_type", runType)
          .gte("started_at", today + "T00:00:00Z")
          .order("started_at", { ascending: false })
          .limit(1);

        const labelMap: Record<string, string> = {
          daily_pipeline: "Pipeline Zoom diário",
          wa_sync: "Sync WhatsApp",
          absence_alerts: "Alerta de Ausência",
        };
        const label = labelMap[runType] || runType;

        if (!runs || runs.length === 0) {
          // absence_alerts may not run on weekends — only alert on weekdays
          const dow = new Date().getDay();
          if (runType === "absence_alerts" && (dow === 0 || dow === 6)) continue;
          alerts.push(`⚠️ ${label} NÃO executou hoje.`);
        } else if (runs[0].status === "error") {
          alerts.push(`❌ ${label} falhou: ${runs[0].error_message || runs[0].step_name || "erro desconhecido"}`);
        }
      }

      // Send alert via Slack DM to Igor (no approval needed for health checks — informational only)
      let alertSent = false;
      const SLACK_IGOR = Deno.env.get("SLACK_IGOR_USER_ID") ?? "";
      if (alerts.length > 0 && SLACK_IGOR) {
        const msg = `🩺 *Health Check — ${today}*\n\n${alerts.join("\n")}\n\n<https://painel.igorrover.com.br/admin/?view=automations|Abrir Automações>`;
        try {
          await sendDM(SLACK_IGOR, msg);
          alertSent = true;
        } catch (e) {
          console.error("health_check: Slack alert send failed:", e);
          // Fallback to WhatsApp
          if (COORDINATOR_PHONE) {
            try {
              alertSent = await sendWA(COORDINATOR_PHONE, `🩺 Health Check — ${today}\n\n${alerts.join("\n")}\n\nAcesse: https://painel.igorrover.com.br/admin/?view=automations`);
            } catch { /* ignore */ }
          }
        }
      }

      // Log the health check itself
      const { error: logErr } = await sb.rpc("log_automation_step", {
        p_run_type: "health_check",
        p_step_name: "daily_health_check",
        p_status: alerts.length > 0 ? "error" : "success",
        p_processed: 2,
        p_created: 0,
        p_failed: alerts.length,
        p_error: alerts.length > 0 ? alerts.join("; ") : null,
        p_metadata: { date: today, alerts, alert_sent: alertSent },
      });
      if (logErr) console.error("log_automation_step error:", logErr);

      return new Response(
        JSON.stringify({ ok: true, date: today, issues: alerts.length, alerts, alert_sent: alertSent }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: daily_pipeline (Story 12.2 — EPIC-012) ─────────────────
    // Orchestrates the full daily Zoom pipeline: list → import → rematch → propagate → transfer → chat
    // Called by pg_cron at 03:00 AM UTC-3. Each step logs to automation_runs.
    if (action === "daily_pipeline") {
      const sb = getSupabaseClient();
      const selfUrl = `${SUPABASE_URL}/functions/v1/zoom-attendance`;
      const selfHeaders = { "Content-Type": "application/json", "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}` };
      const pipelineResults: Record<string, { ok: boolean; [k: string]: unknown }> = {};

      async function callSelf(payload: Record<string, unknown>): Promise<Record<string, unknown>> {
        const resp = await fetch(selfUrl, { method: "POST", headers: selfHeaders, body: JSON.stringify(payload) });
        return resp.json() as Promise<Record<string, unknown>>;
      }

      async function logStep(step: string, status: "success" | "error", processed = 0, created = 0, failed = 0, error: string | null = null, meta: Record<string, unknown> = {}) {
        const { error: logErr } = await sb.rpc("log_automation_step", {
          p_run_type: "daily_pipeline", p_step_name: step, p_status: status,
          p_processed: processed, p_created: created, p_failed: failed,
          p_error: error, p_metadata: meta,
        });
        if (logErr) console.error(`log_automation_step(${step}) error:`, logErr);
      }

      // ── Step 1: list_meetings (last 26h for timezone buffer) ──
      const yesterday = new Date(Date.now() - 26 * 60 * 60 * 1000).toISOString().slice(0, 10);
      const today = new Date().toISOString().slice(0, 10);
      let meetingIds: string[] = [];

      try {
        const r = await callSelf({ action: "list_meetings", from: yesterday, to: today });
        const meetings = (r.meetings || []) as Array<{ id: string }>;
        meetingIds = [...new Set(meetings.map(m => m.id))];
        await logStep("list_meetings", "success", (r.total_raw as number) || 0, meetingIds.length, 0, null, { from: yesterday, to: today });
        pipelineResults.list_meetings = { ok: true, found: meetingIds.length };
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        await logStep("list_meetings", "error", 0, 0, 0, msg);
        pipelineResults.list_meetings = { ok: false, error: msg };
      }

      if (meetingIds.length === 0) {
        return new Response(
          JSON.stringify({ ok: true, pipeline: "no_meetings", results: pipelineResults }),
          { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      // ── Step 2: import_participants for each meeting ──
      let totalImported = 0, totalParticipants = 0, importFailed = 0;
      for (const mid of meetingIds) {
        try {
          let offset = 0;
          let hasMore = true;
          while (hasMore) {
            const r = await callSelf({ meeting_id: mid, offset, batch_size: 5 });
            const instances = (r.instances || []) as Array<{ status: string; participants?: number }>;
            for (const inst of instances) {
              if (inst.status === "processed") totalImported++;
              totalParticipants += (inst.participants || 0);
            }
            hasMore = !!(r.has_more);
            offset = (r.next_offset as number) || 0;
          }
        } catch (e) { importFailed++; console.error(`daily_pipeline import ${mid}:`, e); }
      }
      await logStep("import_participants", importFailed > 0 && totalImported === 0 ? "error" : "success",
        meetingIds.length, totalImported, importFailed, importFailed > 0 ? `${importFailed} meetings failed` : null,
        { total_participants: totalParticipants });
      pipelineResults.import_participants = { ok: importFailed === 0, imported: totalImported, failed: importFailed };

      // ── Step 3: rematch_all (paginated until done) ──
      let rematchTotal = 0, rematchMatched = 0;
      try {
        let offset = 0;
        let hasMore = true;
        while (hasMore) {
          const r = await callSelf({ action: "rematch_all", offset, limit: 300 });
          rematchTotal += (r.processed as number) || 0;
          rematchMatched += (r.newly_matched as number) || 0;
          hasMore = !!(r.has_more);
          offset = (r.next_offset as number) || 0;
        }
        await logStep("rematch_all", "success", rematchTotal, rematchMatched);
        pipelineResults.rematch_all = { ok: true, processed: rematchTotal, matched: rematchMatched };
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        await logStep("rematch_all", "error", rematchTotal, rematchMatched, 0, msg);
        pipelineResults.rematch_all = { ok: false, error: msg };
      }

      // ── Step 4: propagate_links ──
      try {
        const r = await callSelf({ action: "propagate_links" });
        const linked = (r.newly_linked as number) || 0;
        await logStep("propagate_links", "success", linked, linked);
        pipelineResults.propagate_links = { ok: true, newly_linked: linked };
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        await logStep("propagate_links", "error", 0, 0, 0, msg);
        pipelineResults.propagate_links = { ok: false, error: msg };
      }

      // ── Step 5: transfer_to_attendance (paginated) ──
      let tfInserted = 0, tfTotal = 0;
      try {
        let offset = 0;
        let hasMore = true;
        while (hasMore) {
          const r = await callSelf({ action: "transfer_to_attendance", tfOffset: offset, tfLimit: 1000 });
          tfInserted += (r.inserted as number) || 0;
          tfTotal += (r.total_source as number) || 0;
          hasMore = !!(r.has_more);
          offset = (r.next_offset as number) || 0;
        }
        await logStep("transfer_to_attendance", "success", tfTotal, tfInserted);
        pipelineResults.transfer_to_attendance = { ok: true, inserted: tfInserted, total: tfTotal };
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        await logStep("transfer_to_attendance", "error", tfTotal, tfInserted, 0, msg);
        pipelineResults.transfer_to_attendance = { ok: false, error: msg };
      }

      // ── Step 6: import_meeting_chat for newly imported meetings ──
      let chatImported = 0, chatFailed = 0;
      for (const mid of meetingIds) {
        try {
          const r = await callSelf({ action: "import_meeting_chat", zoom_meeting_id: mid });
          if (r.ok) chatImported++;
          else chatFailed++;
        } catch { chatFailed++; }
      }
      await logStep("import_meeting_chat", chatFailed > 0 && chatImported === 0 ? "error" : "success",
        meetingIds.length, chatImported, chatFailed, chatFailed > 0 ? `${chatFailed} chats failed` : null);
      pipelineResults.import_meeting_chat = { ok: chatFailed === 0, imported: chatImported, failed: chatFailed };

      // ── Step 7: sync_staff_attendance (Story 14.1 — EPIC-014) ──
      // Matches zoom participants to mentors and inserts into mentor_attendance
      try {
        const { data: staffResult, error: staffErr } = await sb.rpc("sync_staff_attendance_from_zoom", { p_days_back: 2 });
        if (staffErr) throw new Error(staffErr.message);
        const row = Array.isArray(staffResult) ? staffResult[0] : staffResult;
        const staffProcessed = row?.processed ?? 0;
        const staffInserted = row?.inserted ?? 0;
        const staffSkipped = row?.skipped ?? 0;
        await logStep("sync_staff_attendance", "success", staffProcessed, staffInserted, staffSkipped, null,
          { processed: staffProcessed, inserted: staffInserted, skipped: staffSkipped });
        pipelineResults.sync_staff_attendance = { ok: true, processed: staffProcessed, inserted: staffInserted, skipped: staffSkipped };
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        await logStep("sync_staff_attendance", "error", 0, 0, 0, msg);
        pipelineResults.sync_staff_attendance = { ok: false, error: msg };
      }

      // ── Step 8: staff_absence_alert — notify coordinator of staff not found in Zoom ──
      // After syncing staff attendance, check who was scheduled but NOT found.
      // Sends WhatsApp to COORDINATOR_PHONE with the absent staff list.
      try {
        const COORDINATOR_PHONE  = Deno.env.get("COORDINATOR_PHONE") ?? "";

        // Check yesterday (pipeline runs at 03:00 BRT, processes previous day's meetings)
        const checkDate = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

        const { data: absent, error: absentErr } = await sb.rpc("get_staff_not_found_in_zoom", { p_date: checkDate });
        if (absentErr) throw new Error(absentErr.message);

        const absentList = (absent || []) as Array<{ mentor_name: string; mentor_role: string; class_name: string; class_time: string }>;

        if (absentList.length > 0) {
          const SLACK_IGOR = Deno.env.get("SLACK_IGOR_USER_ID") ?? "";
          const lines = absentList.map(a => `  • ${a.mentor_name} (${a.mentor_role}) — ${a.class_name} ${a.class_time}`);

          if (SLACK_IGOR) {
            // Get staff with slack_user_id for the absent members
            const absentNames = absentList.map(a => a.mentor_name);
            const { data: staffRecords } = await sb
              .from("staff")
              .select("id, name, slack_user_id")
              .in("name", absentNames)
              .not("slack_user_id", "is", null);

            const recipients = (staffRecords || []).map(s => ({
              staff_id: s.id,
              slack_user_id: s.slack_user_id,
              name: s.name,
            }));

            // Queue notification for approval
            const msgText = `⚠️ Staff não encontrado no Zoom — ${checkDate}\n\n${lines.join("\n")}\n\nTotal: ${absentList.length} ausência(s)\n<https://painel.igorrover.com.br/relatorio/|Ver Relatório>`;

            const { data: notif } = await sb
              .from("notification_queue")
              .insert({
                type: "attendance_alert",
                title: `Staff ausente — ${checkDate}`,
                payload: {
                  message: `⚠️ Você não foi detectado(a) na aula do Zoom em ${checkDate}.\n\nSe participou, pode ter entrado com nome diferente. Verifique com a coordenação.\n\n<https://painel.igorrover.com.br/relatorio/|Ver Relatório>`,
                  message_builder: "personalized",
                  summary: msgText,
                },
                recipients,
                status: "pending_approval",
              })
              .select("id")
              .single();

            if (notif) {
              await sendApprovalMessage(SLACK_IGOR, {
                title: "⚠️ Alerta de Ausência de Staff",
                summary: `*${absentList.length}* membro(s) do staff não encontrado(s) no Zoom em ${checkDate}`,
                details: lines.map(l => `• ${l.trim()}`),
                notificationId: notif.id,
              });
            }
          } else if (COORDINATOR_PHONE) {
            // Fallback to WhatsApp
            const msg = `⚠️ Staff não encontrado no Zoom — ${checkDate}\n\n${lines.join("\n")}\n\nTotal: ${absentList.length} ausência(s)\n📊 https://painel.igorrover.com.br/relatorio/`;
            await sendWA(COORDINATOR_PHONE, msg);
          }
        }

        await logStep("staff_absence_alert", "success", absentList.length, absentList.length > 0 ? 1 : 0, 0, null,
          { date: checkDate, absent_count: absentList.length, absent: absentList });
        pipelineResults.staff_absence_alert = { ok: true, absent_count: absentList.length, alert_sent: absentList.length > 0 };
      } catch (e) {
        const msg = e instanceof Error ? e.message : String(e);
        await logStep("staff_absence_alert", "error", 0, 0, 0, msg);
        pipelineResults.staff_absence_alert = { ok: false, error: msg };
      }

      return new Response(
        JSON.stringify({ ok: true, pipeline: "completed", meetings: meetingIds.length, results: pipelineResults }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

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

    // ── ACTION: mentor_unmatched_report ──────────────────────────────
    // Returns all mentor names from DB and unmatched zoom participant names
    // to diagnose why certain team members still appear in the unmatched list.
    if (action === "mentor_unmatched_report") {
      const sb = getSupabaseClient();
      const [{ data: mentorList }, { data: unmatchedList }] = await Promise.all([
        sb.from("mentors").select("name, phone, role").eq("active", true).order("name"),
        sb.from("zoom_participants").select("participant_name, participant_email").eq("matched", false).not("participant_name", "is", null).limit(300),
      ]);
      return new Response(
        JSON.stringify({ ok: true, mentors: mentorList, unmatched_sample: unmatchedList }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: fix_phones ───────────────────────────────────────────
    // Normalizes all student phone numbers to 55+DDD+number format.
    // Merges duplicates caused by same phone ± country code.
    // Flags phones that cannot be normalized with phone_issue = '*invalid'.
    // body: { action: "fix_phones" }
    if (action === "fix_phones") {
      const sb = getSupabaseClient();
      const { data, error } = await sb.rpc("fix_student_phones");
      if (error) {
        return new Response(
          JSON.stringify({ ok: false, error: error.message }),
          { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }
      const rows = data || [];
      const summary = {
        normalized: rows.filter((r: { action: string }) => r.action === "normalized").length,
        merged:     rows.filter((r: { action: string }) => r.action === "merged").length,
        flagged:    rows.filter((r: { action: string }) => r.action === "flagged").length,
      };
      return new Response(
        JSON.stringify({ ok: true, summary, details: rows }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: dedup_participants ────────────────────────────────────
    // Removes duplicate zoom_participants within the same meeting.
    // Keeps the row with the longest duration; deletes reconnection entries.
    // body: { action: "dedup_participants" }
    if (action === "dedup_participants") {
      const sb = getSupabaseClient();
      const { data, error } = await sb.rpc("dedup_zoom_participants");
      if (error) {
        return new Response(
          JSON.stringify({ ok: false, error: error.message }),
          { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }
      const result = data?.[0] || { deleted_count: 0, kept_count: 0 };
      return new Response(
        JSON.stringify({ ok: true, deleted: result.deleted_count, remaining: result.kept_count }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: propagate_links ───────────────────────────────────────
    // For every participant_name/email already linked to a student,
    // applies that link to all other meetings where the same name/email appears.
    // Makes manual links persist across all meetings automatically.
    // body: { action: "propagate_links" }
    if (action === "propagate_links") {
      const sb = getSupabaseClient();
      const { data, error } = await sb.rpc("propagate_zoom_links");
      if (error) {
        return new Response(
          JSON.stringify({ ok: false, error: error.message }),
          { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }
      const result = data?.[0] || { updated_count: 0 };
      return new Response(
        JSON.stringify({ ok: true, newly_linked: result.updated_count }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: rematch_all ───────────────────────────────────────────
    // Re-runs matching on unmatched zoom_participants using improved fuzzy algorithm.
    // Paginated — call with { offset: 0, limit: 150 } and repeat until has_more=false.
    // body: { action: "rematch_all", cohort_id?: string, offset?: number, limit?: number }
    if (action === "rematch_all") {
      const sb = getSupabaseClient();
      const { offset: rmOffset = 0, limit: rmLimit = 150 } = body as { offset?: number; limit?: number };

      // Load all active students once
      const { data: students } = await (cohort_id
        ? sb.from("students").select("id, name, phone, email, is_mentor, aliases").eq("active", true).eq("cohort_id", cohort_id)
        : sb.from("students").select("id, name, phone, email, is_mentor, aliases").eq("active", true));

      if (!students?.length) {
        return new Response(
          JSON.stringify({ ok: false, error: "No students found" }),
          { status: 400, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      // Fetch this page of unmatched participants
      const { data: unmatched, error } = await sb
        .from("zoom_participants")
        .select("id, participant_name, participant_email")
        .eq("matched", false)
        .not("participant_name", "is", null)
        .range(rmOffset, rmOffset + rmLimit - 1);

      if (error) {
        return new Response(
          JSON.stringify({ ok: false, error: error.message }),
          { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      const page = unmatched || [];

      // Run matching on this page
      const { matches } = matchStudents(
        page.map(p => ({ name: p.participant_name || "", email: p.participant_email || "" })),
        students
      );

      // Update matched records
      let newlyMatched = 0;
      for (const p of page) {
        const key = p.participant_email || normalize(cleanParticipantName(p.participant_name || ""));
        const studentId = matches[key];
        if (studentId) {
          await sb.from("zoom_participants")
            .update({ student_id: studentId, matched: true })
            .eq("id", p.id);
          newlyMatched++;
        }
      }

      const hasMore = page.length === rmLimit;
      return new Response(
        JSON.stringify({
          ok: true,
          offset: rmOffset,
          processed: page.length,
          newly_matched: newlyMatched,
          has_more: hasMore,
          next_offset: hasMore ? rmOffset + rmLimit : null,
        }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: transfer_to_attendance ────────────────────────────────
    // Copies matched zoom_participants into student_attendance table.
    // Skips duplicates via ON CONFLICT (student_id, class_date, zoom_meeting_id).
    // body: { action: "transfer_to_attendance", cohort_id?: string }
    if (action === "transfer_to_attendance") {
      const sb = getSupabaseClient();

      // Fetch matched participants with their meeting start_time and cohort_id (paginated to avoid 1000-row limit)
      const { tfOffset = 0, tfLimit = 1000 } = body as { tfOffset?: number; tfLimit?: number };
      const { data: participants, error } = await sb
        .from("zoom_participants")
        .select("id, student_id, duration_minutes, meeting_id, zoom_meetings(id, start_time, cohort_id)")
        .eq("matched", true)
        .not("student_id", "is", null)
        .range(tfOffset, tfOffset + tfLimit - 1);

      if (error) {
        return new Response(
          JSON.stringify({ ok: false, error: error.message }),
          { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      let inserted = 0;
      let skipped = 0;

      // Build rows for student_attendance — aggregate SUM of duration per student per meeting
      type MeetingRef = { id: string; start_time: string; cohort_id: string | null };
      const aggMap = new Map<string, { student_id: string; class_date: string; cohort_id: string | null; zoom_meeting_id: string; zoom_participant_id: string; duration_minutes: number }>();
      for (const p of (participants || [])) {
        const meeting = p.zoom_meetings as MeetingRef | null;
        if (!meeting?.start_time) continue;
        const classDate = meeting.start_time.slice(0, 10);
        const key = `${p.student_id}|${classDate}|${meeting.id}`;
        const existing = aggMap.get(key);
        if (existing) {
          existing.duration_minutes += (p.duration_minutes || 0);
        } else {
          aggMap.set(key, {
            student_id: p.student_id,
            class_date: classDate,
            cohort_id: meeting.cohort_id || cohort_id || null,
            zoom_meeting_id: meeting.id,
            zoom_participant_id: p.id,
            duration_minutes: p.duration_minutes || 0,
          });
        }
      }
      // Backfill cohort_id from student's own cohort when meeting has no cohort
      const rowsWithoutCohort = [...aggMap.values()].filter(r => !r.cohort_id);
      if (rowsWithoutCohort.length > 0) {
        const studentIds = [...new Set(rowsWithoutCohort.map(r => r.student_id))];
        const { data: students } = await sb.from("students").select("id, cohort_id").in("id", studentIds);
        const studentCohortMap = new Map((students || []).map(s => [s.id, s.cohort_id]));
        for (const r of rowsWithoutCohort) {
          if (!r.cohort_id) r.cohort_id = studentCohortMap.get(r.student_id) || null;
        }
      }
      const rows = [...aggMap.values()].map(r => ({ ...r, source: "zoom" as const }));

      // Apply optional cohort filter
      const filteredRows = cohort_id
        ? rows.filter(r => r.cohort_id === cohort_id)
        : rows;

      // Upsert in batches of 100 (updates duration on conflict)
      const batchSize = 100;
      for (let i = 0; i < filteredRows.length; i += batchSize) {
        const batch = filteredRows.slice(i, i + batchSize);
        const { data: insertedData, error: insertErr } = await sb
          .from("student_attendance")
          .upsert(batch, { onConflict: "student_id,class_date,zoom_meeting_id" })
          .select("id");

        if (insertErr) {
          skipped += batch.length;
        } else {
          inserted += insertedData?.length || 0;
          skipped += batch.length - (insertedData?.length || 0);
        }
      }

      // Also return current total in student_attendance for reference
      const { count: totalInTable } = await sb
        .from("student_attendance")
        .select("id", { count: "exact", head: true });

      const hasMoreTransfer = (participants?.length || 0) === tfLimit;
      return new Response(
        JSON.stringify({
          ok: true,
          offset: tfOffset,
          total_source: filteredRows.length,
          inserted,
          skipped,
          has_more: hasMoreTransfer,
          next_offset: hasMoreTransfer ? tfOffset + tfLimit : null,
          total_in_table: totalInTable,
        }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: mark_mentor_participants ─────────────────────────────
    // Permanently marks zoom_participants that belong to mentors/staff as matched=true
    // body: { action: "mark_mentor_participants" }
    if (action === "mark_mentor_participants") {
      const sb = getSupabaseClient();
      const { data, error } = await sb.rpc("mark_mentor_participants");
      if (error) {
        return new Response(
          JSON.stringify({ ok: false, error: error.message }),
          { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }
      const updated_count = Array.isArray(data) && data.length > 0 ? data[0].updated_count : 0;
      return new Response(
        JSON.stringify({ ok: true, updated_count }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: zoom_mentor_candidates ───────────────────────────────
    // Returns unmatched participant names that appear in >= 2 distinct meetings
    // and are not already known mentor names/aliases — likely staff not yet linked.
    // body: { action: "zoom_mentor_candidates" }
    if (action === "zoom_mentor_candidates") {
      const sb = getSupabaseClient();

      // Build set of known mentor names + aliases for exclusion
      const { data: mentorList } = await sb
        .from("mentors")
        .select("name, aliases")
        .eq("active", true);

      const knownMentorNames = new Set<string>();
      for (const m of (mentorList || [])) {
        knownMentorNames.add(normalize(m.name));
        for (const alias of (m.aliases || [])) {
          if (alias?.trim()) knownMentorNames.add(normalize(alias));
        }
      }

      // Fetch unmatched participants (limit to avoid timeout)
      const { data: unmatched } = await sb
        .from("zoom_participants")
        .select("participant_name, meeting_id")
        .eq("matched", false)
        .not("participant_name", "is", null)
        .limit(5000);

      // Group by cleaned name, count distinct meeting_ids
      const nameToMeetings = new Map<string, Set<string>>();
      for (const p of (unmatched || [])) {
        const raw = p.participant_name?.trim();
        if (!raw || isBot(raw)) continue;
        const name = cleanParticipantName(raw);
        if (!name || isBot(name)) continue;
        if (!nameToMeetings.has(name)) nameToMeetings.set(name, new Set());
        nameToMeetings.get(name)!.add(String(p.meeting_id));
      }

      // Filter: >= 2 distinct meetings, not already a known mentor
      const candidates: Array<{ name: string; meeting_count: number }> = [];
      for (const [name, meetings] of nameToMeetings) {
        if (meetings.size < 2) continue;
        if (knownMentorNames.has(normalize(name))) continue;
        candidates.push({ name, meeting_count: meetings.size });
      }

      candidates.sort((a, b) => b.meeting_count - a.meeting_count);

      return new Response(
        JSON.stringify({ ok: true, candidates }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: zoom_student_candidates (Story 6.5) ──────────────────────
    // Returns unmatched participant names appearing in 2+ meetings of a cohort
    // body: { action: "zoom_student_candidates", cohort_id?: string }
    if (action === "zoom_student_candidates") {
      const sb = getSupabaseClient();
      const cohortId: string | null = body.cohort_id ?? null;

      // Build set of known student names + aliases for exclusion
      const { data: studentList } = await sb
        .from("students")
        .select("name, aliases")
        .eq("active", true);

      const knownStudentNames = new Set<string>();
      for (const s of (studentList || [])) {
        knownStudentNames.add(normalize(s.name));
        for (const alias of (s.aliases || [])) {
          if (alias?.trim()) knownStudentNames.add(normalize(alias));
        }
      }

      // Build set of known mentor names too (exclude mentors from student candidates)
      const { data: mentorList2 } = await sb
        .from("mentors")
        .select("name, aliases")
        .eq("active", true);

      const knownMentorNames2 = new Set<string>();
      for (const m of (mentorList2 || [])) {
        knownMentorNames2.add(normalize(m.name));
        for (const alias of (m.aliases || [])) {
          if (alias?.trim()) knownMentorNames2.add(normalize(alias));
        }
      }

      // Fetch unmatched participants, optionally scoped to cohort
      let unmatchedQuery = sb
        .from("zoom_participants")
        .select("participant_name, meeting_id")
        .eq("matched", false)
        .not("participant_name", "is", null)
        .limit(5000);

      if (cohortId) {
        // Get meeting IDs for this cohort
        const { data: cohortMeetings } = await sb
          .from("zoom_meetings")
          .select("id")
          .eq("cohort_id", cohortId);
        const meetingIds = (cohortMeetings || []).map((m: { id: string }) => m.id);
        if (meetingIds.length > 0) {
          unmatchedQuery = unmatchedQuery.in("meeting_id", meetingIds);
        }
      }

      const { data: unmatched2 } = await unmatchedQuery;

      const nameToMeetings2 = new Map<string, Set<string>>();
      for (const p of (unmatched2 || [])) {
        const raw = p.participant_name?.trim();
        if (!raw || isBot(raw)) continue;
        const name = cleanParticipantName(raw);
        if (!name || isBot(name)) continue;
        if (!nameToMeetings2.has(name)) nameToMeetings2.set(name, new Set());
        nameToMeetings2.get(name)!.add(String(p.meeting_id));
      }

      const studentCandidates: Array<{ name: string; meeting_count: number }> = [];
      for (const [name, meetings] of nameToMeetings2) {
        if (meetings.size < 2) continue;
        if (knownStudentNames.has(normalize(name))) continue;
        if (knownMentorNames2.has(normalize(name))) continue;
        studentCandidates.push({ name, meeting_count: meetings.size });
      }

      studentCandidates.sort((a, b) => b.meeting_count - a.meeting_count);

      return new Response(
        JSON.stringify({ ok: true, candidates: studentCandidates }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: get_attendance_summary (Story 6.2) ────────────────────────
    // Returns attendance summary for a cohort: rate per student + weekly evolution
    // body: { action: "get_attendance_summary", cohort_id: string }
    if (action === "get_attendance_summary") {
      const sb = getSupabaseClient();
      const cohortId: string = body.cohort_id;
      if (!cohortId) {
        return new Response(
          JSON.stringify({ ok: false, error: "cohort_id required" }),
          { status: 400, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      const { data: summary, error: summaryErr } = await sb.rpc("get_attendance_summary", { p_cohort_id: cohortId });
      const { data: weekly, error: weeklyErr } = await sb.rpc("get_weekly_attendance", { p_cohort_id: cohortId, p_weeks: 8 });

      if (summaryErr) {
        return new Response(
          JSON.stringify({ ok: false, error: summaryErr.message }),
          { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      return new Response(
        JSON.stringify({ ok: true, summary: summary || [], weekly: weekly || [] }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: send_absence_alerts (Story 6.4) ───────────────────────────
    // Sends WhatsApp alerts to students with 2+ consecutive absences
    // body: { action: "send_absence_alerts" }
    if (action === "send_absence_alerts") {
      const sb = getSupabaseClient();
      const { data: alerts, error: alertErr } = await sb.rpc("get_consecutive_absences_needing_alert");
      if (alertErr) {
        return new Response(
          JSON.stringify({ ok: false, error: alertErr.message }),
          { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      let sent = 0;
      let failed = 0;
      for (const a of (alerts || [])) {
        if (!a.phone) continue;
        const phone = a.phone.replace(/\D/g, "");
        if (phone.length < 10) continue;

        const msg = `Oi ${a.student_name}! 👋 Sentimos sua falta nas últimas ${a.consecutive_count} aulas de ${a.cohort_name}. Se precisar de ajuda ou tiver algum problema, fala com a gente. A turma te espera! 💪`;

        try {
          const ok = await sendWA(phone, msg);
          const status = ok ? "sent" : "error";
          const errMsg = ok ? null : "sendWA failed";

          await sb.from("zoom_absence_alerts").insert({
            student_id:        a.student_id,
            cohort_id:         a.cohort_id,
            consecutive_count: a.consecutive_count,
            message_text:      msg,
            whatsapp_status:   status,
            error_message:     errMsg,
          });

          if (ok) sent++; else failed++;
        } catch (e) {
          await sb.from("zoom_absence_alerts").insert({
            student_id:        a.student_id,
            cohort_id:         a.cohort_id,
            consecutive_count: a.consecutive_count,
            message_text:      msg,
            whatsapp_status:   "error",
            error_message:     String(e),
          });
          failed++;
        }
        // Safe cadence between messages
        await waSleep();
      }

      // Log to automation_runs
      const { error: logAbsErr } = await sb.rpc("log_automation_step", {
        p_run_type: "absence_alerts",
        p_step_name: "send_absence_alerts",
        p_status: failed > 0 && sent === 0 ? "error" : "success",
        p_processed: (alerts || []).length,
        p_created: sent,
        p_failed: failed,
        p_error: failed > 0 ? `${failed} alerts failed to send` : null,
        p_metadata: { sent, failed, total: (alerts || []).length },
      });
      if (logAbsErr) console.error("log_automation_step(absence_alerts) error:", logAbsErr);

      return new Response(
        JSON.stringify({ ok: true, sent, failed, total: (alerts || []).length }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── batch_import_transcripts (Story 14.4 — EPIC-014) ──────────────────────
    // Downloads VTT transcripts from Zoom API for recordings missing transcriptions,
    // then generates AI summaries via OpenAI. Processes in batches of 5.
    if (action === "batch_import_transcripts") {
      const sb = getSupabaseClient();
      const batchSize = (body.batch_size as number) || 5;

      // Find recordings without transcript
      const { data: recordings, error: recErr } = await sb
        .from("class_recordings")
        .select("id, zoom_meeting_id, title")
        .is("transcript_text", null)
        .not("zoom_meeting_id", "is", null)
        .order("recording_date", { ascending: false })
        .limit(batchSize);

      if (recErr) {
        return new Response(
          JSON.stringify({ ok: false, error: recErr.message }),
          { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      if (!recordings?.length) {
        return new Response(
          JSON.stringify({ ok: true, message: "no_pending_transcripts", processed: 0 }),
          { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      const token = await getS2SToken();
      let imported = 0, summarized = 0, failed = 0;
      const details: Array<{ id: string; title: string; status: string; error?: string }> = [];

      for (const rec of recordings) {
        try {
          // Get recording files from Zoom API
          const recData = await zoomGet(token, `/meetings/${rec.zoom_meeting_id}/recordings`);
          const files = (recData?.recording_files || []) as Array<{ file_type: string; download_url: string }>;
          const transcriptFile = files.find((f: { file_type: string }) => f.file_type === "TRANSCRIPT");

          if (!transcriptFile?.download_url) {
            details.push({ id: rec.id, title: rec.title, status: "no_transcript_file" });
            continue;
          }

          // Download VTT using S2S token
          const vttResp = await fetch(`${transcriptFile.download_url}?access_token=${token}`);
          if (!vttResp.ok) {
            details.push({ id: rec.id, title: rec.title, status: "download_failed", error: `HTTP ${vttResp.status}` });
            failed++;
            continue;
          }

          const transcriptText = await vttResp.text();
          if (!transcriptText || transcriptText.length < 100) {
            details.push({ id: rec.id, title: rec.title, status: "transcript_too_short" });
            continue;
          }

          // Save transcript
          await sb.from("class_recordings").update({
            transcript_text: transcriptText.slice(0, 50000),
            transcript_vtt: transcriptText.slice(0, 50000),
          }).eq("id", rec.id);
          imported++;

          // Generate AI summary if OPENAI_API_KEY is available
          if (OPENAI_API_KEY) {
            const cleanTranscript = transcriptText
              .split("\n")
              .filter((l: string) => !l.match(/^\d{2}:\d{2}/) && l.trim() !== "" && l !== "WEBVTT")
              .join("\n")
              .slice(0, 8000);

            const aiResp = await fetch("https://api.openai.com/v1/chat/completions", {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                "Authorization": `Bearer ${OPENAI_API_KEY}`,
              },
              body: JSON.stringify({
                model: "gpt-4o-mini",
                max_tokens: 600,
                messages: [{
                  role: "user",
                  content: `Você recebeu a transcrição de uma aula chamada "${rec.title || "Aula"}". Gere um resumo estruturado em português com:\n\n**Temas abordados:**\n• tema 1\n• tema 2\n• (máximo 5 bullets)\n\n**Próximos passos mencionados:**\n• (se houver, senão omitir esta seção)\n\nTranscrição:\n${cleanTranscript}`,
                }],
              }),
            });

            if (aiResp.ok) {
              const aiData = await aiResp.json() as { choices: { message: { content: string } }[] };
              const summary = aiData?.choices?.[0]?.message?.content ?? "";
              if (summary) {
                await sb.from("class_recordings").update({ summary }).eq("id", rec.id);
                summarized++;
              }
            }
          }

          details.push({ id: rec.id, title: rec.title, status: "ok" });
        } catch (e) {
          failed++;
          details.push({ id: rec.id, title: rec.title, status: "error", error: String(e) });
        }
      }

      return new Response(
        JSON.stringify({ ok: true, total: recordings.length, imported, summarized, failed, details }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── send_recording_notification (Story 10.4) ─────────────────────────────
    if (action === "send_recording_notification") {
      const sb = getSupabaseClient();

      const recordingId = body.recording_id as string;
      const cohortId    = body.cohort_id as string;
      const videoUrl    = body.video_url as string;
      const recTitle    = body.title as string;

      if (!recordingId || !cohortId) {
        return new Response(
          JSON.stringify({ ok: false, error: "recording_id and cohort_id required" }),
          { status: 400, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      // Get students in cohort with WhatsApp enabled
      const { data: students } = await sb
        .from("students")
        .select("id, name, phone")
        .eq("cohort_id", cohortId)
        .eq("whatsapp_alerts_enabled", true)
        .not("phone", "is", null);

      let sent = 0, skipped = 0, failed = 0;

      for (const student of (students || [])) {
        const phone = (student.phone || "").replace(/\D/g, "");
        if (phone.length < 10) { skipped++; continue; }

        // Anti-spam: check if notification already sent for this recording
        const { data: existing } = await sb
          .from("class_recording_notifications")
          .select("id")
          .eq("recording_id", recordingId)
          .eq("student_id", student.id)
          .maybeSingle();

        if (existing) { skipped++; continue; }

        const msg = `Oi ${student.name}! 🎬 A gravação da aula "${recTitle}" já está disponível.\n\nAcesse: ${videoUrl || "o painel de aulas"}\n\nBoa revisão! 📚`;

        let status = "sent";
        let errMsg = null;

        try {
          const ok = await sendWA(phone, msg);
          if (!ok) { status = "error"; errMsg = "sendWA failed"; failed++; }
          else sent++;
        } catch (e) {
          status = "error"; errMsg = String(e); failed++;
        }

        await sb.from("class_recording_notifications").insert({
          recording_id: recordingId,
          student_id:   student.id,
          status,
          error_msg:    errMsg,
        }).catch(() => {});

        // Safe cadence between messages
        if (status === "sent") await waSleep();
      }

      // ── Log to automation_runs (Story 12.4) ──
      const total = (students || []).length;
      const runStatus = failed > 0 && sent === 0 ? "error" : "success";
      await sb.rpc("log_automation_step", {
        p_run_type:  "recording_notification",
        p_step_name: `notify_recording_${recordingId.slice(0, 8)}`,
        p_status:    runStatus,
        p_processed: total,
        p_created:   sent,
        p_failed:    failed,
        p_error:     failed > 0 ? `${failed} notifications failed` : null,
        p_metadata:  { recording_id: recordingId, cohort_id: cohortId, skipped },
      }).catch((e: Error) => console.error("log_automation_step error:", e));

      return new Response(
        JSON.stringify({ ok: true, sent, skipped, failed, total }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: import_meeting_chat (Story 11.7 — EPIC-011) ─────────────────
    // body: { action: "import_meeting_chat", zoom_meeting_id: string }
    if (action === "import_meeting_chat") {
      const sb = getSupabaseClient();
      const zmId = (body as { zoom_meeting_id?: string }).zoom_meeting_id;
      if (!zmId) {
        return new Response(
          JSON.stringify({ ok: false, error: "zoom_meeting_id required" }),
          { status: 400, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      // Get cohort_id for this meeting
      const { data: meeting } = await sb
        .from("zoom_meetings")
        .select("cohort_id")
        .eq("zoom_meeting_id", zmId)
        .single();
      const cohortId = meeting?.cohort_id ?? null;

      const token = await getS2SToken();

      // Fetch chat from Zoom Reports API
      let chatMessages: Array<{ message_id: string; sender: string; date_time: string; message: string }> = [];
      try {
        // Need double-encode for URL path
        const encoded = encodeURIComponent(zmId);
        const data = await zoomGet(token, `/report/meetings/${encoded}/chat?page_size=300`);
        chatMessages = (data?.chat_messages ?? data?.messages ?? []) as typeof chatMessages;
      } catch (e) {
        return new Response(
          JSON.stringify({ ok: false, error: `Zoom chat fetch failed: ${e instanceof Error ? e.message : e}` }),
          { status: 502, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
        );
      }

      // Load students for fuzzy name matching
      const { data: students } = cohortId
        ? await sb.from("students").select("id, name").eq("cohort_id", cohortId).eq("active", true)
        : await sb.from("students").select("id, name").eq("active", true);

      function matchStudentByName(senderName: string): string | null {
        if (!students || !senderName) return null;
        const nameLower = senderName.toLowerCase().trim();
        // Exact match first
        let match = students.find((s: { id: string; name: string }) =>
          s.name.toLowerCase() === nameLower
        );
        if (match) return match.id;
        // First name match
        const firstName = nameLower.split(" ")[0];
        match = students.find((s: { id: string; name: string }) =>
          s.name.toLowerCase().startsWith(firstName)
        );
        return match?.id ?? null;
      }

      let inserted = 0, skipped = 0;
      for (const msg of chatMessages) {
        const msgId = msg.message_id;
        if (!msgId) { skipped++; continue; }
        const studentId = matchStudentByName(msg.sender);
        const sentAt = msg.date_time ? new Date(msg.date_time).toISOString() : new Date().toISOString();

        const { error } = await sb.from("zoom_chat_messages").insert({
          zoom_meeting_id: zmId,
          sender_name: msg.sender ?? "",
          student_id: studentId,
          cohort_id: cohortId,
          sent_at: sentAt,
          message: msg.message ?? "",
          message_id: msgId,
        }).onConflict("message_id").ignore();

        if (!error) inserted++;
        else skipped++;
      }

      // Mark meeting as chat_imported
      await sb.from("zoom_meetings")
        .update({ chat_imported: true })
        .eq("zoom_meeting_id", zmId);

      return new Response(
        JSON.stringify({ ok: true, zoom_meeting_id: zmId, inserted, skipped, total: chatMessages.length }),
        { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
      );
    }

    // ── ACTION: nightly_engagement_sync (Story 11.7 — EPIC-011) ─────────────
    // body: { action: "nightly_engagement_sync" }
    // Called by pg_cron at 02:00 AM — imports Zoom chat + recalculates engagement
    if (action === "nightly_engagement_sync") {
      const sb = getSupabaseClient();
      const yesterday = new Date();
      yesterday.setUTCDate(yesterday.getUTCDate() - 1);
      const refDate = yesterday.toISOString().slice(0, 10);

      // 1. Find meetings from yesterday that haven't had chat imported
      const { data: meetings } = await sb
        .from("zoom_meetings")
        .select("zoom_meeting_id, cohort_id")
        .eq("chat_imported", false)
        .gte("start_time", refDate + "T00:00:00Z")
        .lt("start_time", refDate + "T23:59:59Z");

      const meetingsProcessed: string[] = [];
      const affectedCohorts = new Set<string>();

      for (const m of (meetings ?? [])) {
        try {
          const token = await getS2SToken();
          const encoded = encodeURIComponent(m.zoom_meeting_id);
          const data = await zoomGet(token, `/report/meetings/${encoded}/chat?page_size=300`);
          const chatMessages = (data?.chat_messages ?? data?.messages ?? []) as Array<{ message_id: string; sender: string; date_time: string; message: string }>;

          if (m.cohort_id) affectedCohorts.add(m.cohort_id);

          const { data: students } = m.cohort_id
            ? await sb.from("students").select("id, name").eq("cohort_id", m.cohort_id).eq("active", true)
            : await sb.from("students").select("id, name").eq("active", true);

          for (const msg of chatMessages) {
            if (!msg.message_id) continue;
            const firstName = (msg.sender ?? "").toLowerCase().split(" ")[0];
            const studentId = (students ?? []).find((s: { id: string; name: string }) =>
              s.name.toLowerCase().startsWith(firstName)
            )?.id ?? null;
            await sb.from("zoom_chat_messages").insert({
              zoom_meeting_id: m.zoom_meeting_id,
              sender_name: msg.sender ?? "",
              student_id: studentId,
              cohort_id: m.cohort_id ?? null,
              sent_at: msg.date_time ? new Date(msg.date_time).toISOString() : new Date().toISOString(),
              message: msg.message ?? "",
              message_id: msg.message_id,
            }).onConflict("message_id").ignore();
          }

          await sb.from("zoom_meetings").update({ chat_imported: true }).eq("zoom_meeting_id", m.zoom_meeting_id);
          meetingsProcessed.push(m.zoom_meeting_id);
        } catch { /* skip failed meetings — non-critical */ }
      }

      // 2. Recalculate engagement_daily_ranking for affected cohorts
      for (const cohortId of affectedCohorts) {
        const { data: cohortStudents } = await sb
          .from("students")
          .select("id")
          .eq("cohort_id", cohortId)
          .eq("active", true);

        for (const student of (cohortStudents ?? [])) {
          const sId = student.id;

          const [{ count: waCount }, { count: zcCount }, { count: attCount }] = await Promise.all([
            sb.from("whatsapp_group_messages").select("*", { count: "exact", head: true })
              .eq("student_id", sId).eq("cohort_id", cohortId)
              .gte("sent_at", refDate + "T00:00:00Z").lt("sent_at", refDate + "T23:59:59Z"),
            sb.from("zoom_chat_messages").select("*", { count: "exact", head: true })
              .eq("student_id", sId).eq("cohort_id", cohortId)
              .gte("sent_at", refDate + "T00:00:00Z").lt("sent_at", refDate + "T23:59:59Z"),
            sb.from("student_attendance").select("*", { count: "exact", head: true })
              .eq("student_id", sId).eq("class_date", refDate),
          ]);

          const wa = waCount ?? 0;
          const zc = zcCount ?? 0;
          const att = attCount ?? 0;
          const score = att * 3 + wa + zc;

          await sb.from("engagement_daily_ranking").upsert({
            student_id: sId,
            cohort_id: cohortId,
            ref_date: refDate,
            wa_messages: wa,
            zoom_chat_messages: zc,
            attendance_count: att,
            engagement_score: score,
          }, { onConflict: "student_id,cohort_id,ref_date" });
        }
      }

      return new Response(
        JSON.stringify({ ok: true, ref_date: refDate, meetings_processed: meetingsProcessed.length, cohorts_synced: affectedCohorts.size }),
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

    // ── Auto-resolve cohort_id when not provided ──
    // Priority: 1. Existing zoom_meetings  2. classes.zoom_meeting_id → first cohort  3. Topic matching
    let resolvedCohortId = cohort_id || null;
    let resolvedClassId: string | null = null;
    if (!resolvedCohortId) {
      // 1. Try pre-registered zoom_meetings with this meeting_id
      const { data: existingMeeting } = await sb
        .from("zoom_meetings")
        .select("cohort_id")
        .eq("zoom_meeting_id", meeting_id)
        .not("cohort_id", "is", null)
        .limit(1)
        .maybeSingle();

      if (existingMeeting?.cohort_id) {
        resolvedCohortId = existingMeeting.cohort_id;
      }

      // 2. Try classes.zoom_meeting_id → class_cohort_access → first cohort
      if (!resolvedCohortId) {
        const { data: classMatch } = await sb
          .from("classes")
          .select("id, name")
          .eq("zoom_meeting_id", meeting_id)
          .eq("active", true)
          .limit(1)
          .maybeSingle();

        if (classMatch) {
          resolvedClassId = classMatch.id;
          // Get first cohort mapped to this class
          const { data: cohortAccess } = await sb
            .from("class_cohort_access")
            .select("cohort_id")
            .eq("class_id", classMatch.id)
            .limit(1)
            .maybeSingle();
          if (cohortAccess?.cohort_id) {
            resolvedCohortId = cohortAccess.cohort_id;
          }
        }
      }

      // 3. Fallback: match meeting topic against cohort names
      if (!resolvedCohortId) {
        const instData = await zoomGet(token, `/past_meetings/${meeting_id}/instances`).catch(() => null);
        let meetingTopic = "";
        if (instData?.meetings?.length) {
          const latestUuid = instData.meetings[instData.meetings.length - 1].uuid;
          const details = await getPastMeetingDetails(token, latestUuid).catch(() => null);
          meetingTopic = details?.topic || "";
        }
        if (meetingTopic) {
          const normalizedTopic = meetingTopic.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim();
          const { data: cohorts } = await sb.from("cohorts").select("id, name");
          for (const c of (cohorts || [])) {
            const normalizedCohortName = c.name.toLowerCase().normalize("NFD").replace(/[\u0300-\u036f]/g, "").trim();
            if (normalizedTopic.includes(normalizedCohortName) || normalizedCohortName.includes(normalizedTopic)) {
              resolvedCohortId = c.id;
              break;
            }
          }
        }
      }
    }

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
    const { data: students } = await (resolvedCohortId
      ? sb.from("students").select("id, name, phone, email, is_mentor, aliases").eq("active", true).eq("cohort_id", resolvedCohortId)
      : sb.from("students").select("id, name, phone, email, is_mentor, aliases").eq("active", true));

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
        cohort_id: resolvedCohortId || null,
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

      // ── Auto-transfer matched participants to student_attendance ──
      // Aggregate: SUM duration_minutes per student (they may join/leave multiple times)
      let attendanceInserted = 0;
      const classDate = (details?.start_time || instance.start_time || "").slice(0, 10);
      if (classDate) {
        const durationMap = new Map<string, number>();
        for (const p of participantRows) {
          if (!p.student_id) continue;
          durationMap.set(p.student_id, (durationMap.get(p.student_id) || 0) + (p.duration_minutes || 0));
        }
        const attendanceRows = [...durationMap.entries()].map(([sid, totalMin]) => ({
            student_id: sid,
            class_date: classDate,
            cohort_id: resolvedCohortId || null,
            zoom_meeting_id: meeting.id,
            source: "zoom" as const,
            duration_minutes: totalMin,
          }));

        // Need participant IDs — fetch them after insert
        if (attendanceRows.length > 0) {
          const { data: insertedParticipants } = await sb
            .from("zoom_participants")
            .select("id, student_id")
            .eq("meeting_id", meeting.id)
            .eq("matched", true);

          const participantIdMap: Record<string, string> = {};
          for (const ip of (insertedParticipants || [])) {
            if (ip.student_id) participantIdMap[ip.student_id] = ip.id;
          }

          const finalRows = attendanceRows.map(r => ({
            student_id: r.student_id,
            class_date: r.class_date,
            cohort_id: r.cohort_id,
            zoom_meeting_id: r.zoom_meeting_id,
            zoom_participant_id: participantIdMap[r.student_id!] || null,
            source: r.source,
            duration_minutes: r.duration_minutes,
          }));

          const batchSize = 100;
          for (let i = 0; i < finalRows.length; i += batchSize) {
            const batch = finalRows.slice(i, i + batchSize);
            const { data: inserted } = await sb
              .from("student_attendance")
              .upsert(batch, { onConflict: "student_id,class_date,zoom_meeting_id" })
              .select("id");
            attendanceInserted += inserted?.length || 0;
          }
        }
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
        attendance_inserted: attendanceInserted,
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

    // Auto-run mentor matching after each import batch and collect feedback
    let mentors_matched = 0;
    let unmatched_remaining = 0;
    try {
      const { data: mentorMatchData } = await sb.rpc("mark_mentor_participants");
      mentors_matched = Array.isArray(mentorMatchData) && mentorMatchData.length > 0
        ? Number(mentorMatchData[0].updated_count)
        : 0;

      // Count unmatched participants in the meetings just processed
      const processedMeetingIds = results
        .filter((r: { status: string; meeting_id?: string }) => r.status === "processed" && r.meeting_id)
        .map((r: { meeting_id: string }) => r.meeting_id);

      if (processedMeetingIds.length > 0) {
        const { count } = await sb
          .from("zoom_participants")
          .select("id", { count: "exact", head: true })
          .in("meeting_id", processedMeetingIds)
          .eq("matched", false);
        unmatched_remaining = count ?? 0;
      }
    } catch {
      // Non-critical — import already succeeded, just skip the feedback metrics
    }

    // Update import queue status (Story 6.1 — auto-import callback)
    try {
      const allDone = results.every((r: { status: string }) => r.status === "processed" || r.status === "skipped");
      await sb.rpc("update_zoom_import_queue", {
        p_meeting_id: meeting_id,
        p_status: allDone ? "done" : "error",
        p_error_msg: allDone ? null : "One or more instances failed",
      });
    } catch {
      // Non-critical — queue update failure does not affect the import result
    }

    return new Response(
      JSON.stringify({
        ok: true,
        meeting_id,
        total_instances: totalInstances,
        offset,
        batch_size,
        has_more: hasMore,
        next_offset: hasMore ? nextOffset : null,
        mentors_matched,
        unmatched_remaining,
        instances: results,
      }),
      { headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
    );

  } catch (err) {
    // Update queue to error on import failure
    try {
      const sb2 = getSupabaseClient();
      const body2 = await req.clone().json().catch(() => ({}));
      if (body2?.meeting_id) {
        await sb2.rpc("update_zoom_import_queue", {
          p_meeting_id: body2.meeting_id,
          p_status: "error",
          p_error_msg: err instanceof Error ? err.message : "Unknown error",
        });
      }
    } catch { /* ignore */ }

    return new Response(
      JSON.stringify({ ok: false, error: err instanceof Error ? err.message : "Unknown error" }),
      { status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" } }
    );
  }
});
