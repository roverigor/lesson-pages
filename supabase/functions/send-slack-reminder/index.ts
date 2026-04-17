/**
 * send-slack-reminder — Send class reminders via Slack DM with interactive buttons
 * Queries today's class assignments and sends personalized DMs with confirm/decline buttons.
 * When mentor clicks, Igor receives the response via slack-interact.
 *
 * POST body (optional):
 *   { "dry_run": true }  — preview messages without sending
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { openDM } from "../_shared/slack.ts";

const SLACK_API = "https://slack.com/api";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function getToken(): string {
  const token = Deno.env.get("SLACK_BOT_TOKEN");
  if (!token) throw new Error("SLACK_BOT_TOKEN not set");
  return token;
}

/** Send Block Kit message with interactive buttons */
async function sendBlockMessage(
  userId: string,
  textFallback: string,
  blocks: unknown[],
) {
  const channel = await openDM(userId);
  const resp = await fetch(`${SLACK_API}/chat.postMessage`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${getToken()}`,
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify({ channel, text: textFallback, blocks }),
  });
  const data = await resp.json();
  if (!data.ok) throw new Error(`Slack chat.postMessage failed: ${data.error}`);
  return data;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    const body = await req.json().catch(() => ({}));
    const dryRun = body.dry_run === true;

    const sb = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Get today's weekday in BRT
    const now = new Date();
    const brt = new Date(now.toLocaleString("en-US", { timeZone: "America/Sao_Paulo" }));
    const todayDow = brt.getDay();
    const todayISO = brt.toISOString().split("T")[0];

    // Query today's class assignments
    const { data: classRows, error: cErr } = await sb
      .from("classes")
      .select(`
        id, name, time_start, time_end, zoom_link, active,
        class_mentors!inner(weekday, role, valid_from, valid_until,
          mentors!inner(id, name, slack_user_id, notification_channel)
        )
      `)
      .eq("active", true)
      .lte("start_date", todayISO)
      .gte("end_date", todayISO);

    if (cErr) throw cErr;

    // Flatten nested join
    const flatRows: Array<Record<string, any>> = [];
    for (const c of classRows || []) {
      for (const cm of (c as any).class_mentors || []) {
        if (cm.weekday !== todayDow) continue;
        if (cm.valid_from && todayISO < cm.valid_from) continue;
        if (cm.valid_until && todayISO > cm.valid_until) continue;
        const m = cm.mentors;
        if (!m || !m.slack_user_id) continue;
        flatRows.push({
          class_id: c.id,
          class_name: c.name,
          time_start: c.time_start,
          time_end: c.time_end,
          zoom_link: c.zoom_link,
          mentor_id: m.id,
          mentor_name: m.name,
          slack_user_id: m.slack_user_id,
          mentor_role: cm.role,
        });
      }
    }

    if (flatRows.length === 0) {
      return new Response(
        JSON.stringify({ message: "Nenhuma aula encontrada para hoje", sent: 0 }),
        { headers: { ...corsHeaders, "Content-Type": "application/json" } },
      );
    }

    // Group by mentor
    const mentorMap = new Map<string, {
      mentor_name: string;
      slack_user_id: string;
      classes: Array<{ class_id: string; class_name: string; role: string; time_start: string; time_end: string; zoom_link: string; mentor_id: string }>;
    }>();

    for (const r of flatRows) {
      const key = r.slack_user_id;
      if (!mentorMap.has(key)) {
        mentorMap.set(key, {
          mentor_name: r.mentor_name,
          slack_user_id: r.slack_user_id,
          classes: [],
        });
      }
      mentorMap.get(key)!.classes.push({
        class_id: r.class_id,
        class_name: r.class_name,
        role: r.mentor_role,
        time_start: r.time_start?.substring(0, 5) || "",
        time_end: r.time_end?.substring(0, 5) || "",
        zoom_link: r.zoom_link || "",
        mentor_id: r.mentor_id,
      });
    }

    const roleEmoji: Record<string, string> = {
      Professor: "\u{1F468}\u200D\u{1F3EB}",
      Host: "\u{1F399}\uFE0F",
      Mentor: "\u{1F9D1}\u200D\u{1F91D}\u200D\u{1F9D1}",
    };

    const results: Array<{ name: string; status: string; message?: string }> = [];

    for (const [, mentor] of mentorMap) {
      // Build text body
      let textBody = "";
      if (mentor.classes.length === 1) {
        const c = mentor.classes[0];
        const emoji = roleEmoji[c.role] || "\u{1F4CC}";
        textBody += `Voc\u00EA est\u00E1 escalado(a) hoje como ${emoji} *${c.role}* na aula:\n\n`;
        textBody += `\u{1F4DA} *${c.class_name}* \u2014 ${c.time_start} \u00E0s ${c.time_end}\n`;
        if (c.zoom_link) textBody += `\u{1F517} ${c.zoom_link}`;
      } else {
        textBody += `Voc\u00EA est\u00E1 escalado(a) hoje nas seguintes aulas:\n\n`;
        for (const c of mentor.classes) {
          const emoji = roleEmoji[c.role] || "\u{1F4CC}";
          textBody += `${emoji} *${c.role}* \u2014 \u{1F4DA} *${c.class_name}* (${c.time_start}\u2013${c.time_end})\n`;
          if (c.zoom_link) textBody += `\u{1F517} ${c.zoom_link}\n`;
        }
      }

      // Value encodes mentor info for slack-interact callback (absence tracking)
      const classNames = mentor.classes.map((c) => c.class_name).join(", ");
      const buttonValue = JSON.stringify({
        mentor_name: mentor.mentor_name,
        mentor_id: mentor.classes[0].mentor_id,
        classes: classNames,
        class_details: mentor.classes.map((c) => ({
          class_id: c.class_id,
          class_name: c.class_name,
          role: c.role,
        })),
        date: todayISO,
      });

      // Build Block Kit blocks
      const blocks = [
        {
          type: "header",
          text: { type: "plain_text", text: `Bom dia, ${mentor.mentor_name}! \u{1F44B}`, emoji: true },
        },
        {
          type: "section",
          text: { type: "mrkdwn", text: textBody },
        },
        { type: "divider" },
        {
          type: "section",
          text: { type: "mrkdwn", text: "Posso confirmar sua presen\u00E7a?" },
        },
        {
          type: "actions",
          block_id: `presence_${todayISO}_${mentor.slack_user_id}`,
          elements: [
            {
              type: "button",
              text: { type: "plain_text", text: "\u2705 Confirmado", emoji: true },
              style: "primary",
              action_id: "confirm_presence",
              value: buttonValue,
            },
            {
              type: "button",
              text: { type: "plain_text", text: "\u274C N\u00E3o vou conseguir", emoji: true },
              style: "danger",
              action_id: "decline_presence",
              value: buttonValue,
            },
          ],
        },
      ];

      const fallbackText = `Bom dia, ${mentor.mentor_name}! Confirma presen\u00E7a hoje em ${classNames}?`;

      if (dryRun) {
        results.push({ name: mentor.mentor_name, status: "dry_run", message: fallbackText });
      } else {
        try {
          await sendBlockMessage(mentor.slack_user_id, fallbackText, blocks);
          results.push({ name: mentor.mentor_name, status: "sent" });
          await new Promise((r) => setTimeout(r, 1000));
        } catch (e) {
          results.push({ name: mentor.mentor_name, status: "failed", message: (e as Error).message });
        }
      }
    }

    const sent = results.filter((r) => r.status === "sent").length;
    const failed = results.filter((r) => r.status === "failed").length;

    return new Response(
      JSON.stringify({ dry_run: dryRun, sent, failed, total: results.length, results }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("send-slack-reminder error:", e);
    return new Response(
      JSON.stringify({ error: (e as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
