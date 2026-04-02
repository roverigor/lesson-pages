// ═══════════════════════════════════════
// Edge Function: delivery-webhook
// Receives Evolution API webhook on MESSAGES_UPDATE events.
// Maps DELIVERY_ACK → 'delivered', READ/PLAYED → 'read'.
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

  // Only process messages.update events
  if (payload.event !== "messages.update") {
    return new Response(JSON.stringify({ ok: true, skipped: true }), {
      status: 200,
      headers: { "Content-Type": "application/json" },
    });
  }

  // data is an array of message updates
  const updates = Array.isArray(payload.data) ? payload.data : [payload.data];

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

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
