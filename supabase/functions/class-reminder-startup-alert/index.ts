// class-reminder-startup-alert — Diário 09:00 BRT
// Encontra classes acontecendo HOJE com reminder_enabled=false
// Envia Slack DM ao Igor com botões interativos:
//   - [Ativar dispatch] → activate_class:UUID
//   - [Pular hoje] → dismiss_class_today:UUID
//
// Se hoje é feriado, mostra também botão pra confirmar/pular envio.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { openDM } from "../_shared/slack.ts";

const SLACK_API = "https://slack.com/api";
const SLACK_BOT_TOKEN = Deno.env.get("SLACK_BOT_TOKEN") ?? "";
const SLACK_IGOR = Deno.env.get("SLACK_IGOR_USER_ID") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function brtToday(): { isoDate: string; weekday: number; weekdayName: string } {
  const now = new Date();
  const brt = new Date(now.toLocaleString("en-US", { timeZone: "America/Sao_Paulo" }));
  const names = ["Domingo", "Segunda", "Terça", "Quarta", "Quinta", "Sexta", "Sábado"];
  return {
    isoDate: brt.toISOString().split("T")[0],
    weekday: brt.getDay(),
    weekdayName: names[brt.getDay()],
  };
}

async function postBlocks(channel: string, text: string, blocks: unknown[]) {
  const r = await fetch(`${SLACK_API}/chat.postMessage`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${SLACK_BOT_TOKEN}`,
      "Content-Type": "application/json; charset=utf-8",
    },
    body: JSON.stringify({ channel, text, blocks }),
  });
  return await r.json();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const today = brtToday();
  const body = await req.json().catch(() => ({}));
  const dryRun = body.dry_run === true;
  const targetDate: string = body.target_date ?? today.isoDate;
  const targetWeekday = body.target_date ? new Date(targetDate + "T12:00:00-03:00").getDay() : today.weekday;

  // Check holiday
  const { data: holidayRow } = await sb
    .from("holidays")
    .select("name")
    .eq("date", targetDate)
    .maybeSingle();
  const isHoliday = !!holidayRow;
  const holidayName = holidayRow?.name ?? null;

  // Find classes happening today (any reminder_enabled state)
  const { data: classes } = await sb
    .from("classes")
    .select("id, name, time_start, time_end, weekday, reminder_enabled, zoom_link, start_date, end_date")
    .eq("active", true)
    .eq("weekday", targetWeekday)
    .lte("start_date", targetDate)
    .gte("end_date", targetDate)
    .order("time_start");

  if (!classes || classes.length === 0) {
    return new Response(
      JSON.stringify({ success: true, today: targetDate, message: "no_classes_today" }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }

  const pendingActivation = classes.filter((c) => !c.reminder_enabled);
  const alreadyActive = classes.filter((c) => c.reminder_enabled);

  // Build blocks
  const blocks: Record<string, unknown>[] = [
    {
      type: "header",
      text: { type: "plain_text", text: `Aulas de hoje — ${today.weekdayName} ${targetDate.split("-").reverse().join("/")}`, emoji: true },
    },
  ];

  if (isHoliday) {
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: `:warning: *Hoje é feriado: ${holidayName}*\n\nPor padrão, mensagens de "sem aula hoje" serão enviadas. Pra pular completamente, clique abaixo.` },
    });
    blocks.push({
      type: "actions",
      block_id: `holiday_${targetDate}`,
      elements: [
        {
          type: "button",
          text: { type: "plain_text", text: "Confirmar envio msg feriado", emoji: true },
          style: "primary",
          action_id: "confirm_holiday_send",
          value: targetDate,
        },
        {
          type: "button",
          text: { type: "plain_text", text: "Pular hoje (nada envia)", emoji: true },
          style: "danger",
          action_id: "skip_holiday",
          value: targetDate,
        },
      ],
    });
    blocks.push({ type: "divider" });
  }

  // Pending activation section
  if (pendingActivation.length > 0) {
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: `*Aulas precisam ativação (${pendingActivation.length}):*` },
    });
    for (const c of pendingActivation) {
      // Get group count
      const { data: bridge } = await sb.from("class_cohorts").select("cohort_id").eq("class_id", c.id);
      const cohortIds = (bridge ?? []).map((r: { cohort_id: string }) => r.cohort_id);
      let groupCount = 0;
      if (cohortIds.length > 0) {
        const { data: cohorts } = await sb
          .from("cohorts")
          .select("whatsapp_group_jid")
          .in("id", cohortIds)
          .eq("active", true)
          .not("whatsapp_group_jid", "is", null);
        groupCount = cohorts?.length ?? 0;
      }
      const zoomFlag = c.zoom_link ? "✓ Zoom" : "✗ sem Zoom";
      blocks.push({
        type: "section",
        text: { type: "mrkdwn", text: `• *${c.name}* — ${c.time_start} às ${c.time_end} — ${groupCount} grupo(s) WA — ${zoomFlag}` },
        accessory: {
          type: "button",
          text: { type: "plain_text", text: "Ativar", emoji: true },
          style: "primary",
          action_id: "activate_class",
          value: c.id,
        },
      });
    }
  }

  if (alreadyActive.length > 0) {
    blocks.push({ type: "divider" });
    const activeText = alreadyActive.map((c) => `:white_check_mark: *${c.name}* — ${c.time_start}`).join("\n");
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: `*Já ativadas (${alreadyActive.length}):*\n${activeText}` },
    });
  }

  blocks.push({
    type: "context",
    elements: [
      { type: "mrkdwn", text: `<https://painel.igorrover.com.br/admin/lembretes-aulas/|Painel completo>` },
    ],
  });

  const summaryText = `Aulas hoje: ${pendingActivation.length} precisam ativação, ${alreadyActive.length} já ativas${isHoliday ? ` — feriado ${holidayName}` : ""}`;

  if (dryRun) {
    return new Response(
      JSON.stringify({ success: true, today: targetDate, pending: pendingActivation.length, active: alreadyActive.length, is_holiday: isHoliday, preview: blocks }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }

  if (!SLACK_IGOR) {
    return new Response(
      JSON.stringify({ success: false, error: "SLACK_IGOR_USER_ID not set" }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }

  const channel = await openDM(SLACK_IGOR);
  const result = await postBlocks(channel, summaryText, blocks);

  return new Response(
    JSON.stringify({ success: result.ok === true, today: targetDate, pending: pendingActivation.length, active: alreadyActive.length, is_holiday: isHoliday, slack_response: result }),
    { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
  );
});
