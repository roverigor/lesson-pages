// ═══════════════════════════════════════════════════════════════════════════
// dispatch-class-reminders — Envia sends pending de batches approved.
//
// Chamado por:
//   - Cron tick (*/5 min) — sem body, processa todos approved sends devidos
//   - UI manual — body: { "batch_id": "..." } pra forçar processamento batch
//   - dry_run=true pra preview sem enviar
//
// Logic:
//   1. Find sends WHERE send_status='pending' AND batch.status='approved' AND scheduled_at<=NOW
//   2. Send each via Evolution group endpoint
//   3. Update send_status + evolution_message_id
//   4. Throttle 3s entre msgs
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendEvolutionGroupText } from "../_shared/evolution-group.ts";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const THROTTLE_MS = 3000;
const MAX_SENDS_PER_RUN = 50;

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const body = await req.json().catch(() => ({}));
    const dryRun = body.dry_run === true;
    const batchIdFilter: string | undefined = body.batch_id;

    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const nowIso = new Date().toISOString();

    // Find approved batches
    let batchQuery = sb
      .from("class_reminder_batches")
      .select("id")
      .eq("status", "approved");
    if (batchIdFilter) batchQuery = batchQuery.eq("id", batchIdFilter);
    const { data: batches } = await batchQuery;

    const batchIds = (batches ?? []).map((b: { id: string }) => b.id);
    if (batchIds.length === 0) {
      return new Response(
        JSON.stringify({ success: true, dispatched: 0, skipped: 0, message: "no_approved_batches" }),
        { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    // Find due pending sends
    const { data: sends, error: sendsErr } = await sb
      .from("class_reminder_sends")
      .select("id, batch_id, group_jid, group_name, reminder_type, message_preview, scheduled_at, class_id, cohort_id")
      .in("batch_id", batchIds)
      .eq("send_status", "pending")
      .lte("scheduled_at", nowIso)
      .order("scheduled_at")
      .limit(MAX_SENDS_PER_RUN);
    if (sendsErr) throw sendsErr;

    if (!sends || sends.length === 0) {
      return new Response(
        JSON.stringify({ success: true, dispatched: 0, skipped: 0, message: "no_due_sends" }),
        { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    let dispatched = 0;
    let skipped = 0;
    const results: Record<string, unknown>[] = [];

    for (let i = 0; i < sends.length; i++) {
      const s = sends[i];

      if (!s.group_jid) {
        await sb
          .from("class_reminder_sends")
          .update({ send_status: "skipped", error_detail: "missing_group_jid", sent_at: new Date().toISOString() })
          .eq("id", s.id);
        skipped++;
        results.push({ id: s.id, status: "skipped", reason: "missing_group_jid" });
        continue;
      }

      if (dryRun) {
        results.push({ id: s.id, status: "dry_run", group: s.group_name, msg_preview: s.message_preview.slice(0, 80) });
        continue;
      }

      const result = await sendEvolutionGroupText(s.group_jid, s.message_preview);

      if (result.success) {
        await sb
          .from("class_reminder_sends")
          .update({
            send_status: "sent",
            evolution_message_id: result.messageId,
            sent_at: new Date().toISOString(),
          })
          .eq("id", s.id);
        dispatched++;
        results.push({ id: s.id, status: "sent", message_id: result.messageId, group: s.group_name });
      } else {
        await sb
          .from("class_reminder_sends")
          .update({
            send_status: "failed",
            error_detail: result.error ?? "unknown_error",
            sent_at: new Date().toISOString(),
          })
          .eq("id", s.id);
        skipped++;
        results.push({ id: s.id, status: "failed", error: result.error });
      }

      if (i < sends.length - 1) await sleep(THROTTLE_MS);
    }

    // Mark batches as 'sent' if all their sends are terminal
    for (const batchId of batchIds) {
      const { data: pendingLeft } = await sb
        .from("class_reminder_sends")
        .select("id", { count: "exact", head: true })
        .eq("batch_id", batchId)
        .eq("send_status", "pending");
      const remaining = (pendingLeft as unknown as { count?: number })?.count ?? 0;
      if (remaining === 0) {
        await sb
          .from("class_reminder_batches")
          .update({ status: "sent", updated_at: new Date().toISOString() })
          .eq("id", batchId);
      }
    }

    return new Response(
      JSON.stringify({
        success: true,
        dispatched,
        skipped,
        total: sends.length,
        dry_run: dryRun,
        results,
      }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("[dispatch-class-reminders]", e);
    return new Response(
      JSON.stringify({ success: false, error: e instanceof Error ? e.message : String(e) }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }
});
