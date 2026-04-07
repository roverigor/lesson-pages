// ═══════════════════════════════════════
// Edge Function: zoom-webhook
// Receives Zoom webhook events and updates host session pool
// Events handled: meeting.started, meeting.ended, meeting.alert, recording.completed
// Signature verification: HMAC-SHA256 (Zoom webhook secret)
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL              = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ZOOM_WEBHOOK_SECRET       = Deno.env.get("ZOOM_WEBHOOK_SECRET") ?? "";
const ANTHROPIC_API_KEY         = Deno.env.get("ANTHROPIC_API_KEY") ?? "";

function getSupabaseClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

// ─── HMAC-SHA256 signature verification ───
async function verifyZoomSignature(req: Request, body: string): Promise<boolean> {
  if (!ZOOM_WEBHOOK_SECRET) return true; // skip in dev if secret not configured

  const timestamp = req.headers.get("x-zm-request-timestamp") ?? "";
  const signature = req.headers.get("x-zm-signature") ?? "";

  if (!timestamp || !signature) return false;

  // Zoom signature format: v0=HMAC(secret, "v0:{timestamp}:{body}")
  const message = `v0:${timestamp}:${body}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(ZOOM_WEBHOOK_SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  const hex = Array.from(new Uint8Array(mac)).map(b => b.toString(16).padStart(2, "0")).join("");
  const expected = `v0=${hex}`;

  return expected === signature;
}

// ─── Handler ───

serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  const body = await req.text();

  // Zoom URL validation challenge (one-time during webhook registration)
  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(body);
  } catch {
    return new Response("Bad Request", { status: 400 });
  }

  // Handle Zoom's endpoint validation challenge
  // Must respond BEFORE signature check — Zoom sends this to verify the URL is reachable
  if (payload.event === "endpoint.url_validation") {
    const plainToken = (payload.payload as Record<string, string>)?.plainToken ?? "";

    if (!ZOOM_WEBHOOK_SECRET) {
      // Secret not yet configured — return error so user knows to add it
      return new Response(
        JSON.stringify({ error: "ZOOM_WEBHOOK_SECRET not configured in Supabase secrets" }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }

    try {
      const key = await crypto.subtle.importKey(
        "raw",
        new TextEncoder().encode(ZOOM_WEBHOOK_SECRET),
        { name: "HMAC", hash: "SHA-256" },
        false,
        ["sign"]
      );
      const mac = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(plainToken));
      const encryptedToken = Array.from(new Uint8Array(mac)).map(b => b.toString(16).padStart(2, "0")).join("");
      return new Response(
        JSON.stringify({ plainToken, encryptedToken }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    } catch (e) {
      return new Response(
        JSON.stringify({ error: "HMAC computation failed: " + String(e) }),
        { status: 500, headers: { "Content-Type": "application/json" } }
      );
    }
  }

  // Verify signature for all other events
  const valid = await verifyZoomSignature(req, body);
  if (!valid) {
    return new Response("Unauthorized", { status: 401 });
  }

  const event     = payload.event as string;
  const eventPayload = (payload.payload as Record<string, unknown>) ?? {};
  const object    = (eventPayload.object as Record<string, unknown>) ?? {};
  const meetingId = String(object.id ?? "");
  const uuid      = String(object.uuid ?? "");
  const hostEmail = String(object.host_email ?? "");
  const topic     = String(object.topic ?? "");
  const startTime = String(object.start_time ?? "");

  const sb = getSupabaseClient();

  // ── meeting.started ──────────────────────────────────────────────────
  if (event === "meeting.started") {
    // Upsert: if already exists (e.g., from manual creation), update; else insert
    const { error } = await sb.from("zoom_host_sessions").upsert(
      {
        host_email:  hostEmail,
        meeting_id:  meetingId,
        zoom_uuid:   uuid,
        topic,
        started_at:  startTime || new Date().toISOString(),
        released_at: null,
        released_by: null,
      },
      { onConflict: "meeting_id" }
    );

    if (error) console.error("zoom-webhook: meeting.started upsert error", error.message);

    return new Response(JSON.stringify({ ok: true, event, meeting_id: meetingId }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }

  // ── meeting.ended ────────────────────────────────────────────────────
  if (event === "meeting.ended") {
    // Release the host — match by meeting_id OR zoom_uuid
    const { error } = await sb.from("zoom_host_sessions")
      .update({ released_at: new Date().toISOString(), released_by: "webhook" })
      .or(`meeting_id.eq.${meetingId},zoom_uuid.eq.${uuid}`)
      .is("released_at", null);

    if (error) console.error("zoom-webhook: meeting.ended update error", error.message);

    // Also mark the zoom_meetings record as ready for processing
    await sb.from("zoom_meetings")
      .update({ processed: false })
      .eq("zoom_meeting_id", meetingId)
      .eq("processed", false)
      .is("end_time", null);

    // Enqueue for automatic import (process_after = 5 min to let Zoom generate the report)
    const { error: queueError } = await sb.from("zoom_import_queue").insert({
      meeting_id:    meetingId,
      zoom_uuid:     uuid || null,
      host_email:    hostEmail || null,
      topic:         topic || null,
      status:        "pending",
      process_after: new Date(Date.now() + 5 * 60 * 1000).toISOString(),
    });

    if (queueError) console.error("zoom-webhook: queue insert error", queueError.message);

    return new Response(JSON.stringify({ ok: true, event, meeting_id: meetingId, queued: !queueError }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }

  // ── meeting.alert ────────────────────────────────────────────────────
  if (event === "meeting.alert") {
    const alertType = String((object.alert_type as number) ?? 0);
    console.warn(`zoom-webhook: meeting.alert type=${alertType} meeting=${meetingId}`);
    // Log only — no state change needed for alerts
    return new Response(JSON.stringify({ ok: true, event, alert_type: alertType }), {
      status: 200, headers: { "Content-Type": "application/json" },
    });
  }

  // ── recording.completed ─────────────────────────────────────────────────
  if (event === "recording.completed") {
    const duration     = Number(object.duration ?? 0); // seconds
    const shareUrl     = String(object.share_url ?? "");
    const recordingFiles = (object.recording_files as Record<string, unknown>[] | undefined) ?? [];
    const transcriptFile = recordingFiles.find((f) => (f.file_type as string) === "TRANSCRIPT");
    const transcriptUrl  = transcriptFile ? String(transcriptFile.download_url ?? "") : "";

    // Find cohort_id from host_email via zoom_host_sessions
    let cohortId: string | null = null;
    if (hostEmail) {
      const { data: session } = await sb
        .from("zoom_host_sessions")
        .select("cohort_id")
        .eq("host_email", hostEmail)
        .not("cohort_id", "is", null)
        .order("started_at", { ascending: false })
        .limit(1)
        .maybeSingle();
      cohortId = session?.cohort_id ?? null;
    }

    // UPSERT in class_recordings (dedup by meeting_id)
    const { data: rec, error: recErr } = await sb
      .from("class_recordings")
      .upsert(
        {
          meeting_id:       meetingId,
          cohort_id:        cohortId,
          recording_date:   startTime ? startTime.split("T")[0] : new Date().toISOString().split("T")[0],
          title:            topic || `Aula — ${startTime?.split("T")[0] ?? ""}`,
          duration_minutes: duration > 0 ? Math.round(duration / 60) : null,
          video_url:        shareUrl || null,
        },
        { onConflict: "meeting_id", ignoreDuplicates: false }
      )
      .select("id")
      .maybeSingle();

    if (recErr) console.error("zoom-webhook: recording upsert error", recErr.message);

    const recordingId = rec?.id ?? null;

    // Download transcript and generate AI summary (fire-and-forget)
    if (recordingId && transcriptUrl && ANTHROPIC_API_KEY) {
      generateAndSaveSummary(sb, recordingId, transcriptUrl, topic).catch((e) =>
        console.error("zoom-webhook: AI summary error", String(e))
      );
    }

    // Send WhatsApp notifications (fire-and-forget)
    if (recordingId && cohortId && SUPABASE_URL && SUPABASE_SERVICE_ROLE_KEY) {
      sendRecordingNotifications(recordingId, cohortId, shareUrl, topic).catch((e) =>
        console.error("zoom-webhook: notification error", String(e))
      );
    }

    return new Response(
      JSON.stringify({ ok: true, event, meeting_id: meetingId, recording_id: recordingId }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }

  // All other events: acknowledge and ignore
  return new Response(JSON.stringify({ ok: true, event, ignored: true }), {
    status: 200, headers: { "Content-Type": "application/json" },
  });
});

// ─── AI Summary Generation ───────────────────────────────────────────────────
async function generateAndSaveSummary(
  sb: ReturnType<typeof getSupabaseClient>,
  recordingId: string,
  transcriptUrl: string,
  topic: string
): Promise<void> {
  // Download transcript (requires Zoom OAuth token — use download_token if present)
  let transcriptText = "";
  try {
    const resp = await fetch(transcriptUrl);
    if (resp.ok) transcriptText = await resp.text();
  } catch {
    console.warn("zoom-webhook: transcript download failed for", recordingId);
    return;
  }

  if (!transcriptText || transcriptText.length < 100) return;

  // Strip VTT timing lines for cleaner input
  const cleanTranscript = transcriptText
    .split("\n")
    .filter((l) => !l.match(/^\d{2}:\d{2}/) && l.trim() !== "" && l !== "WEBVTT")
    .join("\n")
    .slice(0, 8000);

  // Call Anthropic API
  const aiResp = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": ANTHROPIC_API_KEY,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model: "claude-haiku-4-5-20251001",
      max_tokens: 600,
      messages: [
        {
          role: "user",
          content: `Você recebeu a transcrição de uma aula chamada "${topic}". Gere um resumo estruturado em português com:

**Temas abordados:**
• tema 1
• tema 2
• (máximo 5 bullets)

**Próximos passos mencionados:**
• (se houver, senão omitir esta seção)

Transcrição:
${cleanTranscript}`,
        },
      ],
    }),
  });

  if (!aiResp.ok) {
    console.error("zoom-webhook: Anthropic error", aiResp.status);
    return;
  }

  const aiData = await aiResp.json() as { content: { text: string }[] };
  const summary = aiData?.content?.[0]?.text ?? "";

  if (summary) {
    await sb.from("class_recordings").update({
      summary,
      transcript_text: transcriptText.slice(0, 50000),
      transcript_vtt:  transcriptText.slice(0, 50000),
    }).eq("id", recordingId);
  }
}

// ─── WhatsApp Notifications ───────────────────────────────────────────────────
async function sendRecordingNotifications(
  recordingId: string,
  cohortId: string,
  videoUrl: string,
  title: string
): Promise<void> {
  const resp = await fetch(`${SUPABASE_URL}/functions/v1/zoom-attendance`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
    },
    body: JSON.stringify({
      action: "send_recording_notification",
      recording_id: recordingId,
      cohort_id: cohortId,
      video_url: videoUrl,
      title,
    }),
  });
  if (!resp.ok) console.error("zoom-webhook: notification dispatch error", resp.status);
}
