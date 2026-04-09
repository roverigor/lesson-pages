// ═══════════════════════════════════════
// Edge Function: delivery-webhook
// Handles Evolution API webhooks:
//   messages.update → delivery status tracking
//   messages.upsert → WhatsApp group message capture (EPIC-011)
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const DELIVERY_WEBHOOK_TOKEN = Deno.env.get("DELIVERY_WEBHOOK_TOKEN") ?? "";

// Evolution API delivery status → our notification status
const STATUS_MAP: Record<string, string> = {
  DELIVERY_ACK: "delivered",
  READ: "read",
  PLAYED: "read",
};

// ─── WhatsApp group message handler (messages.upsert) ─────────────────────
async function handleGroupMessage(
  payload: Record<string, unknown>,
  sb: ReturnType<typeof createClient>
): Promise<Response> {
  const data = payload.data as Record<string, unknown> | null;
  if (!data) return new Response(JSON.stringify({ ok: true, skipped: true }), { status: 200, headers: { "Content-Type": "application/json" } });

  // Only process group messages (remoteJid ends with @g.us)
  const key = data.key as Record<string, unknown> | null;
  const remoteJid = (key?.remoteJid as string) ?? "";
  if (!remoteJid.endsWith("@g.us")) {
    return new Response(JSON.stringify({ ok: true, skipped: true }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  // Ignore own messages (fromMe)
  if (key?.fromMe === true) {
    return new Response(JSON.stringify({ ok: true, skipped: true }), { status: 200, headers: { "Content-Type": "application/json" } });
  }

  const messageId = (key?.id as string) ?? "";
  if (!messageId) return new Response(JSON.stringify({ ok: true, skipped: true }), { status: 200, headers: { "Content-Type": "application/json" } });

  // Extract sender phone from participant JID (e.g., 5543999...@s.whatsapp.net)
  const participantJid = (data.participant as string) ?? (data.pushName as string) ?? "";
  const senderPhone = participantJid.replace(/@s\.whatsapp\.net$/, "").replace(/\D/g, "");

  // Detect message type
  const msgContent = data.message as Record<string, unknown> | null;
  let messageType = "other";
  if (msgContent) {
    if (msgContent.conversation || msgContent.extendedTextMessage) messageType = "text";
    else if (msgContent.imageMessage) messageType = "image";
    else if (msgContent.audioMessage) messageType = "audio";
    else if (msgContent.videoMessage) messageType = "video";
  }

  // Sent timestamp
  const messageTimestamp = data.messageTimestamp as number | null;
  const sentAt = messageTimestamp ? new Date(messageTimestamp * 1000).toISOString() : new Date().toISOString();

  // Lookup student_id by phone (try exact, then normalized variants)
  let studentId: string | null = null;
  if (senderPhone) {
    // Try exact match first
    const { data: student } = await sb
      .from("students")
      .select("id")
      .eq("phone", senderPhone)
      .eq("active", true)
      .limit(1)
      .maybeSingle();
    studentId = student?.id ?? null;

    // If not found, try common normalizations
    if (!studentId && senderPhone.length >= 10) {
      const variants: string[] = [];
      // Brazilian: add/remove 55 prefix, add/remove 9th digit
      if (senderPhone.startsWith("55")) {
        variants.push(senderPhone.slice(2)); // without country code
        // Toggle 9th digit (55+DD+9XXXX vs 55+DD+XXXX)
        const ddd = senderPhone.slice(2, 4);
        const num = senderPhone.slice(4);
        if (num.length === 9 && num.startsWith("9")) {
          variants.push("55" + ddd + num.slice(1)); // remove 9th digit
        } else if (num.length === 8) {
          variants.push("55" + ddd + "9" + num); // add 9th digit
        }
      } else if (senderPhone.length >= 10 && senderPhone.length <= 11) {
        variants.push("55" + senderPhone); // add country code
      }

      for (const v of variants) {
        const { data: vs } = await sb
          .from("students")
          .select("id")
          .eq("phone", v)
          .eq("active", true)
          .limit(1)
          .maybeSingle();
        if (vs?.id) { studentId = vs.id; break; }
      }
    }
  }

  // Lookup cohort_id by group JID
  let cohortId: string | null = null;
  const { data: cohort } = await sb
    .from("cohorts")
    .select("id")
    .eq("whatsapp_group_jid", remoteJid)
    .single();
  cohortId = cohort?.id ?? null;

  // Insert (deduplication via UNIQUE on evolution_message_id)
  await sb.from("whatsapp_group_messages").insert({
    group_jid: remoteJid,
    sender_phone: senderPhone || participantJid,
    student_id: studentId,
    cohort_id: cohortId,
    sent_at: sentAt,
    message_type: messageType,
    evolution_message_id: messageId,
  }).onConflict("evolution_message_id").ignore();

  return new Response(JSON.stringify({ ok: true, captured: true }), { status: 200, headers: { "Content-Type": "application/json" } });
}
// ─────────────────────────────────────────────────────────────────────────────

serve(async (req: Request) => {
  // Only accept POST
  if (req.method !== "POST") {
    return new Response("Method Not Allowed", { status: 405 });
  }

  // Token auth via query param: ?token=<DELIVERY_WEBHOOK_TOKEN>
  const url = new URL(req.url);
  const token = url.searchParams.get("token");
  if (!token || token !== DELIVERY_WEBHOOK_TOKEN) {
    return new Response("Unauthorized", { status: 401 });
  }

  let payload: Record<string, unknown>;
  try {
    payload = await req.json();
  } catch {
    return new Response("Bad Request", { status: 400 });
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Route by event type
  if (payload.event === "messages.upsert") {
    return await handleGroupMessage(payload, sb);
  }

  if (payload.event !== "messages.update") {
    return new Response(JSON.stringify({ ok: true, skipped: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  // data is an array of message updates
  const updates = Array.isArray(payload.data) ? payload.data : [payload.data];

  let processed = 0;

  for (const update of updates) {
    const msgId = (update as { key?: { id?: string } }).key?.id;
    const evoStatus = (update as { update?: { status?: string } }).update?.status;

    if (!msgId || !evoStatus) continue;

    const newStatus = STATUS_MAP[evoStatus];
    if (!newStatus) continue; // ignore PENDING, SERVER_ACK, ERROR

    // Find notification that contains this message ID
    const { data: notification } = await sb
      .from("notifications")
      .select("id, status")
      .contains("evolution_message_ids", [msgId])
      .in("status", ["sent", "partial", "delivered"]) // only advance, never downgrade
      .single();

    if (!notification) continue;

    // Only advance: sent → delivered → read (never go backwards)
    const STATUS_ORDER = ["sent", "partial", "delivered", "read"];
    const currentRank = STATUS_ORDER.indexOf(notification.status);
    const newRank = STATUS_ORDER.indexOf(newStatus);
    if (newRank <= currentRank) continue;

    await sb
      .from("notifications")
      .update({
        status: newStatus,
        delivered_at: newStatus === "delivered" || newStatus === "read"
          ? new Date().toISOString()
          : null,
      })
      .eq("id", notification.id);

    processed++;
  }

  return new Response(
    JSON.stringify({ ok: true, processed }),
    { status: 200, headers: { "Content-Type": "application/json" } }
  );
});
