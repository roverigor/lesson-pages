import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import {
  verifySignatureAsync,
  updateApprovalMessage,
  sendDM,
  sendMessage,
} from "../_shared/slack.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const SIGNING_SECRET = Deno.env.get("SLACK_SIGNING_SECRET")!;

serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const body = await req.text();
  const timestamp = req.headers.get("x-slack-request-timestamp") || "";
  const signature = req.headers.get("x-slack-signature") || "";

  // Verify Slack signature
  if (SIGNING_SECRET && signature && timestamp) {
    const valid = await verifySignatureAsync(SIGNING_SECRET, signature, timestamp, body);
    if (!valid) {
      console.error("Invalid Slack signature");
      return new Response("Invalid signature", { status: 401 });
    }
  }

  // Slack sends URL-encoded payload
  const params = new URLSearchParams(body);
  const payloadStr = params.get("payload");
  if (!payloadStr) {
    return new Response("No payload", { status: 400 });
  }

  const payload = JSON.parse(payloadStr);
  const action = payload.actions?.[0];
  if (!action) {
    return new Response("No action", { status: 400 });
  }

  const actionId = action.action_id;
  const actionValue = action.value;
  const channel = payload.channel?.id;
  const messageTs = payload.message?.ts;
  const userName = payload.user?.real_name || payload.user?.name || "?";

  console.log(`Action: ${actionId}, value: ${actionValue}, by: ${userName}`);

  const supabase = createClient(SUPABASE_URL, SUPABASE_KEY);

  // ─── Handle presence confirmation from staff reminders ───
  if (actionId === "confirm_presence" || actionId === "decline_presence") {
    const confirmed = actionId === "confirm_presence";
    let info: {
      mentor_name: string;
      mentor_id?: string;
      classes: string;
      class_details?: Array<{ class_id: string; class_name: string; role: string }>;
      date: string;
    };
    try {
      info = JSON.parse(actionValue);
    } catch {
      info = { mentor_name: userName, classes: "?", date: "?" };
    }

    const statusEmoji = confirmed ? "\u2705" : "\u274C";
    const statusText = confirmed ? "Confirmado" : "N\u00E3o vai conseguir";

    // Update the original message to show the response (remove buttons)
    try {
      const token = Deno.env.get("SLACK_BOT_TOKEN")!;
      await fetch("https://slack.com/api/chat.update", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json; charset=utf-8",
        },
        body: JSON.stringify({
          channel,
          ts: messageTs,
          text: `${statusEmoji} ${statusText}`,
          blocks: [
            {
              type: "section",
              text: {
                type: "mrkdwn",
                text: `${statusEmoji} *${statusText}* \u2014 ${info.classes} (${info.date})`,
              },
            },
          ],
        }),
      });
    } catch (e) {
      console.error("Failed to update message:", e);
    }

    // ─── Register in attendance table (single source of truth) ───
    if (info.class_details && info.date) {
      const status = confirmed ? "present" : "absent";
      const notes = confirmed ? "Confirmou via Slack" : "Recusou via Slack";

      for (const cls of info.class_details) {
        // Upsert into attendance (unique on lesson_date + course + teacher_name)
        try {
          const { data: existing } = await supabase
            .from("attendance")
            .select("id")
            .eq("lesson_date", info.date)
            .eq("course", cls.class_name)
            .eq("teacher_name", info.mentor_name)
            .maybeSingle();

          if (existing) {
            await supabase
              .from("attendance")
              .update({ status, notes })
              .eq("id", existing.id);
          } else {
            await supabase.from("attendance").insert({
              lesson_date: info.date,
              course: cls.class_name,
              teacher_name: info.mentor_name,
              role: cls.role,
              status,
              notes,
            });
          }
        } catch (e) {
          console.error("Failed to upsert attendance:", e);
        }

        // Note: no schedule_override insert — the mentor stays visible in the grid
        // but shows as "absent" via attendance.status. Schedule overrides are only
        // for manual admin operations (adding substitutes).
      }
    }

    // Notify Igor about the response
    const igorUserId = Deno.env.get("SLACK_IGOR_USER_ID");
    if (igorUserId) {
      const absenceTag = !confirmed ? " \u{1F6A8} *FALTA REGISTRADA*" : "";
      const notifyMsg = `${statusEmoji} *${info.mentor_name}* respondeu: *${statusText}*\n\u{1F4DA} ${info.classes} \u2014 ${info.date}${absenceTag}`;
      try {
        await sendDM(igorUserId, notifyMsg);
      } catch (e) {
        console.error("Failed to notify Igor:", e);
      }
    }

    return new Response(JSON.stringify({ ok: true }));
  }

  // ─── Handle notification queue approvals ───
  const notificationId = actionValue;

  // Get notification from queue
  const { data: notification, error: fetchErr } = await supabase
    .from("notification_queue")
    .select("*")
    .eq("id", notificationId)
    .single();

  if (fetchErr || !notification) {
    console.error("Notification not found:", fetchErr);
    await updateApprovalMessage(channel, messageTs, false, "Notificação não encontrada.");
    return new Response(JSON.stringify({ ok: true }));
  }

  if (notification.status !== "pending_approval") {
    await updateApprovalMessage(
      channel,
      messageTs,
      notification.status === "approved" || notification.status === "sent",
      `Já processado: ${notification.status}`
    );
    return new Response(JSON.stringify({ ok: true }));
  }

  if (actionId === "reject_notification") {
    // Reject
    await supabase
      .from("notification_queue")
      .update({ status: "rejected", approved_at: new Date().toISOString() })
      .eq("id", notificationId);

    await updateApprovalMessage(channel, messageTs, false, `Rejeitado por ${userName}`);
    return new Response(JSON.stringify({ ok: true }));
  }

  if (actionId === "approve_notification") {
    // Approve and send
    await supabase
      .from("notification_queue")
      .update({ status: "approved", approved_at: new Date().toISOString() })
      .eq("id", notificationId);

    await updateApprovalMessage(channel, messageTs, true, `Aprovado por ${userName} — enviando...`);

    // Send DMs to all recipients
    const recipients = notification.recipients as Array<{
      staff_id: string;
      slack_user_id: string;
      name: string;
    }>;
    const messageTemplate = notification.payload?.message || "";
    const messageBuilder = notification.payload?.message_builder;

    let sent = 0;
    let failed = 0;

    await supabase
      .from("notification_queue")
      .update({ status: "sending" })
      .eq("id", notificationId);

    for (const r of recipients) {
      try {
        let msg = messageTemplate;
        if (messageBuilder === "personalized") {
          // Replace {{name}} placeholder
          msg = messageTemplate.replace(/\{\{name\}\}/g, r.name.split(" ")[0]);
        }
        await sendDM(r.slack_user_id, msg);
        sent++;
        // Rate limit: 1 msg/sec
        await new Promise((resolve) => setTimeout(resolve, 1000));
      } catch (e) {
        failed++;
        console.error(`Failed DM to ${r.name}:`, e);
      }
    }

    // Update final status
    await supabase
      .from("notification_queue")
      .update({
        status: failed === recipients.length ? "failed" : "sent",
        sent_at: new Date().toISOString(),
        payload: {
          ...notification.payload,
          result: { sent, failed, total: recipients.length },
        },
      })
      .eq("id", notificationId);

    // Update approval message with results
    await updateApprovalMessage(
      channel,
      messageTs,
      true,
      `Aprovado por ${userName}\n📊 Enviado: ${sent}/${recipients.length} | Falhas: ${failed}`
    );

    return new Response(JSON.stringify({ ok: true }));
  }

  return new Response(JSON.stringify({ ok: true }));
});
