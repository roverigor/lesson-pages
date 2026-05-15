// class-reminder-startup-alert — Diário 09:00 BRT
// Encontra classes acontecendo HOJE com reminder_enabled=false
// Envia Slack DM ao Igor pedindo confirmação pra ativar dispatch
//
// Após ativação manual via UI, prepare-class-reminders + cron tick disparam normalmente.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendDM } from "../_shared/slack.ts";

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

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const sb = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const today = brtToday();
  const body = await req.json().catch(() => ({}));
  const dryRun = body.dry_run === true;

  // Find classes happening today + reminder_enabled=false
  const { data: classes } = await sb
    .from("classes")
    .select("id, name, time_start, time_end, weekday, reminder_enabled, zoom_link, start_date, end_date")
    .eq("active", true)
    .eq("weekday", today.weekday)
    .eq("reminder_enabled", false)
    .lte("start_date", today.isoDate)
    .gte("end_date", today.isoDate);

  if (!classes || classes.length === 0) {
    return new Response(
      JSON.stringify({ success: true, today: today.isoDate, alerts: 0, message: "no_pending_classes" }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }

  // Build Slack message
  const lines = [
    `*Lembretes de aula pendentes pra hoje (${today.weekdayName} ${today.isoDate.split("-").reverse().join("/")})*`,
    "",
    "As aulas abaixo ainda *não estão ativas* pra disparo automático:",
    "",
  ];
  for (const c of classes) {
    // Get cohorts/grupos
    const { data: bridge } = await sb
      .from("class_cohorts")
      .select("cohort_id")
      .eq("class_id", c.id);
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
    lines.push(`• *${c.name}* — ${c.time_start} às ${c.time_end} — ${groupCount} grupo(s) WA`);
  }
  lines.push("");
  lines.push("Pra ativar, acesse https://painel.igorrover.com.br/admin/lembretes-aulas/");
  lines.push("Ou responda *ATIVAR <nome da aula>* aqui (em breve).");

  const text = lines.join("\n");

  if (dryRun) {
    return new Response(
      JSON.stringify({ success: true, today: today.isoDate, alerts: classes.length, preview_text: text }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }

  if (!SLACK_IGOR) {
    return new Response(
      JSON.stringify({ success: false, error: "SLACK_IGOR_USER_ID not set" }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }

  try {
    await sendDM(SLACK_IGOR, text);
    return new Response(
      JSON.stringify({ success: true, today: today.isoDate, alerts: classes.length, slack_sent: true }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ success: false, error: e instanceof Error ? e.message : String(e) }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }
});
