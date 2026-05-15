// class-reminders-healthcheck — Daily 08:00 BRT
// Resumo diário no Slack:
//   - Aulas hoje (status enabled + grupos + zoom)
//   - Batches preview/approved pendentes
//   - Sends agendados próximos 7 dias
//   - Botão pra aprovar batch de hoje (se preview)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { openDM } from "../_shared/slack.ts";

const SLACK_API = "https://slack.com/api";
const SLACK_BOT_TOKEN = Deno.env.get("SLACK_BOT_TOKEN") ?? "";
const SLACK_IGOR = Deno.env.get("SLACK_IGOR_USER_ID") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function brtToday() {
  const now = new Date();
  const brt = new Date(now.toLocaleString("en-US", { timeZone: "America/Sao_Paulo" }));
  const names = ["Dom","Seg","Ter","Qua","Qui","Sex","Sab"];
  return {
    iso: brt.toISOString().split("T")[0],
    weekday: brt.getDay(),
    name: names[brt.getDay()],
  };
}

async function postBlocks(channel: string, text: string, blocks: unknown[]) {
  const r = await fetch(`${SLACK_API}/chat.postMessage`, {
    method: "POST",
    headers: { Authorization: `Bearer ${SLACK_BOT_TOKEN}`, "Content-Type": "application/json; charset=utf-8" },
    body: JSON.stringify({ channel, text, blocks }),
  });
  return await r.json();
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const body = await req.json().catch(() => ({}));
  const dryRun = body.dry_run === true;
  const today = brtToday();

  // ─── 1. Aulas hoje ──────────────────────────────────────────────────────
  const { data: todayClasses } = await sb
    .from("classes")
    .select("id, name, time_start, time_end, reminder_enabled, zoom_link")
    .eq("active", true)
    .eq("weekday", today.weekday)
    .lte("start_date", today.iso)
    .gte("end_date", today.iso)
    .order("time_start");

  // ─── 2. Batch hoje ──────────────────────────────────────────────────────
  const { data: batchToday } = await sb
    .from("class_reminder_batches")
    .select("id, status, total_sends")
    .eq("target_date", today.iso)
    .maybeSingle();

  // ─── 3. Sends próximos 7 dias ──────────────────────────────────────────
  const next7End = new Date(today.iso + "T23:59:59-03:00");
  next7End.setDate(next7End.getDate() + 7);
  const { data: upcomingSends } = await sb
    .from("class_reminder_sends")
    .select("scheduled_at, group_name, reminder_type, send_status, class_id")
    .gte("scheduled_at", today.iso)
    .lt("scheduled_at", next7End.toISOString())
    .order("scheduled_at");

  // Group upcoming by day
  const byDay = new Map<string, { total: number; sent: number; pending: number }>();
  for (const s of upcomingSends ?? []) {
    const day = s.scheduled_at.split("T")[0];
    if (!byDay.has(day)) byDay.set(day, { total: 0, sent: 0, pending: 0 });
    const c = byDay.get(day)!;
    c.total++;
    if (s.send_status === "sent") c.sent++;
    if (s.send_status === "pending") c.pending++;
  }

  // ─── 4. Holiday check ──────────────────────────────────────────────────
  const { data: holidayRow } = await sb.from("holidays").select("name").eq("date", today.iso).maybeSingle();
  const isHoliday = !!holidayRow;

  // ─── Build blocks ──────────────────────────────────────────────────────
  const blocks: Record<string, unknown>[] = [
    {
      type: "header",
      text: { type: "plain_text", text: `Health check — ${today.name} ${today.iso.split("-").reverse().join("/")}`, emoji: true },
    },
  ];

  // Hoje
  if (!todayClasses || todayClasses.length === 0) {
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: ":zzz: *Sem aulas hoje.* Tudo tranquilo." },
    });
  } else {
    let txt = "*Aulas hoje:*\n";
    for (const c of todayClasses) {
      const status = c.reminder_enabled ? ":white_check_mark: ATIVA" : ":no_entry_sign: desativada";
      const zoom = c.zoom_link ? ":link:" : ":x:";
      txt += `• ${c.time_start}-${c.time_end} *${c.name}* — ${status} ${zoom}\n`;
    }
    if (isHoliday) txt += `\n:warning: *Hoje é feriado: ${holidayRow.name}*`;
    blocks.push({ type: "section", text: { type: "mrkdwn", text: txt } });
  }

  // Batch hoje
  if (batchToday) {
    const statusEmoji = {
      preview: ":hourglass_flowing_sand:",
      approved: ":white_check_mark:",
      sent: ":mailbox_with_mail:",
      cancelled: ":x:",
    }[batchToday.status] ?? ":grey_question:";
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: `*Batch hoje:* ${statusEmoji} ${batchToday.status} — ${batchToday.total_sends} envios` },
    });
    if (batchToday.status === "preview" && batchToday.total_sends > 0) {
      blocks.push({
        type: "actions",
        block_id: `batch_${batchToday.id}`,
        elements: [{
          type: "button",
          text: { type: "plain_text", text: "Aprovar batch agora", emoji: true },
          style: "primary",
          action_id: "approve_batch_today",
          value: batchToday.id,
        }],
      });
    }
  } else if (todayClasses && todayClasses.some((c) => c.reminder_enabled)) {
    blocks.push({
      type: "section",
      text: { type: "mrkdwn", text: ":warning: *Sem batch gerado pra hoje* mas tem aulas ativas. Gere preview no painel." },
    });
  }

  // Forecast 7 dias
  if (byDay.size > 0) {
    blocks.push({ type: "divider" });
    let forecastTxt = "*Próximos 7 dias:*\n";
    const sortedDays = Array.from(byDay.keys()).sort();
    for (const day of sortedDays) {
      const c = byDay.get(day)!;
      const dt = new Date(day + "T12:00:00-03:00");
      const wdName = ["Dom","Seg","Ter","Qua","Qui","Sex","Sab"][dt.getDay()];
      forecastTxt += `• ${wdName} ${day.split("-").reverse().slice(0,2).join("/")} — ${c.total} envios (✓ ${c.sent} sent | ⏳ ${c.pending} pending)\n`;
    }
    blocks.push({ type: "section", text: { type: "mrkdwn", text: forecastTxt } });
  } else {
    blocks.push({ type: "section", text: { type: "mrkdwn", text: ":information_source: Nenhum envio agendado próximos 7 dias." } });
  }

  blocks.push({
    type: "context",
    elements: [{ type: "mrkdwn", text: "<https://painel.igorrover.com.br/admin/lembretes-aulas/|Painel>" }],
  });

  const summary = `Health: ${todayClasses?.length ?? 0} aulas hoje, ${batchToday?.status ?? 'sem batch'}, ${upcomingSends?.length ?? 0} envios próximos 7d`;

  if (dryRun) {
    return new Response(JSON.stringify({ success: true, summary, blocks }), {
      status: 200, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  if (!SLACK_IGOR) {
    return new Response(JSON.stringify({ success: false, error: "SLACK_IGOR_USER_ID not set" }), {
      status: 500, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  const channel = await openDM(SLACK_IGOR);
  const result = await postBlocks(channel, summary, blocks);
  return new Response(JSON.stringify({ success: result.ok === true, summary, slack: result }), {
    status: 200, headers: { ...CORS, "Content-Type": "application/json" },
  });
});
