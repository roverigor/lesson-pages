// dispatch-ps-rsvp — Runs morning of PS day. Sends DM to ALL bound students
// (cross-cohort, ignores cohort.active) inviting them to fill RSVP + share doubts.
//
// Trigger: cron 11:00 UTC = 08:00 BRT on Tue + Fri (matches PS weekdays 2+5).
// Body: { dry_run?: boolean }
//
// Healthcheck: posts Slack message before + after each PS class dispatch.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendBlockMessage } from "../_shared/slack.ts";
import { sendEvolutionGroupText } from "../_shared/evolution-group.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";
const SLACK_CHANNEL = Deno.env.get("SLACK_CHANNEL_DEV_ALERTS") ?? Deno.env.get("SLACK_CHANNEL_DETRACTORS") ?? "";
const BASE_URL = "https://painel.academialendaria.ai";
const DELAY_MS = 5000;

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(b: unknown, s = 200) { return new Response(JSON.stringify(b), { status: s, headers: { ...CORS, "Content-Type": "application/json" } }); }
function sleep(ms: number) { return new Promise<void>((r) => setTimeout(r, ms)); }

function brtToday(): { isoDate: string; weekday: number } {
  // BRT (UTC-3). Get current BRT date.
  const now = new Date();
  const brt = new Date(now.getTime() - 3 * 60 * 60 * 1000);
  return { isoDate: brt.toISOString().slice(0, 10), weekday: brt.getUTCDay() };
}

// ── Variant pools — rotated per send, premium tone, no clichês ──
function pickRandom<T>(arr: T[]): T { return arr[Math.floor(Math.random() * arr.length)]; }

function buildDMText(firstName: string, className: string, timeStart: string, token: string): string {
  const url = `https://painel.academialendaria.ai/ps-rsvp/${token}`;
  const variants = [
    `Bom dia, ${firstName}.\n\nHoje rola *${className}* — ${timeStart} (Brasília).\n\nPra eu chegar preparado pro seu caso específico, me conta em 30s:\n${url}`,
    `${firstName}, bom dia.\n\nPS de hoje é *${className}*, ${timeStart}.\n\nQual ponto travado você quer destravar hoje? Conta aqui pro mentor já chegar com material relevante:\n${url}`,
    `Bom dia, ${firstName}!\n\n*${className}* abre ${timeStart}. Pra valer cada minuto seu, o mentor adapta o foco baseado no que vocês trouxerem.\n\nLeva 30s:\n${url}`,
    `${firstName}, ${className} hoje ${timeStart} (Brasília).\n\nMe diz o que você quer trabalhar — o PS rende muito mais com pauta pré-definida:\n${url}`,
    `Bom dia, ${firstName}.\n\nHoje tem *${className}* — ${timeStart}. Conta rapidamente onde você está e o que precisa destravar; chega tudo pro mentor antes da sessão:\n${url}`,
  ];
  return pickRandom(variants);
}

function buildGroupText(className: string, timeStart: string): string {
  const url = `https://painel.academialendaria.ai/ps-rsvp`;
  const variants = [
    `Bom dia, time.\n\nHoje rola *${className}*, ${timeStart} (Brasília). Cada um recebeu DM individual pra confirmar presença + listar dúvidas que está trazendo — o mentor já se prepara com base nisso.\n\nSe não viu o DM, passa aqui: ${url}`,
    `Time, bom dia!\n\n*${className}* aberta hoje às ${timeStart}. Foco da sessão se ajusta às dúvidas que vocês trouxerem — verifica o DM individual e conta o que tá precisando destravar.`,
    `Bom dia.\n\nPS *${className}* — ${timeStart} (Brasília). Vocês receberam DM individual: 30s pra dizer se vem + dúvidas. Mentor chega com pauta calibrada pelas respostas.\n\nNão viu? ${url}`,
    `Time, hoje tem *${className}* às ${timeStart}.\n\nO mentor vai usar os pontos que vocês compartilharam no DM individual pra calibrar a sessão. Vale a pena reservar 30s pra responder.`,
    `Bom dia, Lendários.\n\n*${className}* — ${timeStart} (Brasília). DM individual chegou: confirma presença + manda dúvidas. Quanto mais sincero, mais o mentor consegue te ajudar de fato.`,
  ];
  return pickRandom(variants);
}

async function sendDM(phone: string, text: string): Promise<{ ok: boolean; messageId: string | null; error?: string }> {
  if (!EVOLUTION_API_URL || !EVOLUTION_API_KEY) return { ok: false, messageId: null, error: "evolution_env_missing" };
  const digits = phone.replace(/\D/g, "");
  try {
    const res = await fetch(`${EVOLUTION_API_URL}/message/sendText/${EVOLUTION_INSTANCE}`, {
      method: "POST",
      headers: { "Content-Type": "application/json", apikey: EVOLUTION_API_KEY },
      body: JSON.stringify({ number: `${digits}@s.whatsapp.net`, text }),
    });
    if (!res.ok) return { ok: false, messageId: null, error: `http_${res.status}: ${(await res.text()).slice(0, 200)}` };
    const data = await res.json().catch(() => ({}));
    const id = data?.key?.id ?? data?.messageId ?? data?.message?.id ?? null;
    return { ok: true, messageId: id };
  } catch (e) {
    return { ok: false, messageId: null, error: e instanceof Error ? e.message : String(e) };
  }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  let body: { dry_run?: boolean; force_date?: string } = {};
  try { body = await req.json(); } catch { /* empty body OK */ }
  const dryRun = body.dry_run === true;

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const today = body.force_date ? { isoDate: body.force_date, weekday: new Date(body.force_date).getUTCDay() } : brtToday();

  // Find PS classes for today's weekday + active + reminder_enabled
  // Cross-cohort: get class_cohorts → students (active=true, is_mentor=false)
  // Ignores cohort.active per design B.
  const { data: classes } = await sb
    .from("classes")
    .select("id, name, weekday, time_start, kind")
    .eq("active", true)
    .eq("kind", "ps")
    .eq("weekday", today.weekday);

  if (!classes || classes.length === 0) {
    return json({ success: true, message: "no PS class today", today });
  }

  const results: Record<string, unknown>[] = [];

  for (const cls of classes) {
    // Find all student_ids bound via class_cohorts (cross-cohort, ignore cohort.active)
    const { data: bridges } = await sb
      .from("class_cohorts")
      .select("cohort_id")
      .eq("class_id", cls.id);
    const cohortIds = (bridges ?? []).map((b: { cohort_id: string }) => b.cohort_id);
    if (cohortIds.length === 0) {
      results.push({ class_id: cls.id, class_name: cls.name, eligible: 0, reason: "no_cohorts" });
      continue;
    }

    const { data: students } = await sb
      .from("students")
      .select("id, name, phone")
      .in("cohort_id", cohortIds)
      .eq("active", true)
      .eq("is_mentor", false)
      .not("phone", "is", null)
      .order("name");

    const eligible = students ?? [];
    if (eligible.length === 0) {
      results.push({ class_id: cls.id, class_name: cls.name, eligible: 0, reason: "no_students" });
      continue;
    }

    // Upsert links (idempotent per class+student+date)
    const linkInserts = eligible.map((s) => ({
      class_id: cls.id,
      student_id: s.id,
      session_date: today.isoDate,
    }));
    const { data: upserted } = await sb
      .from("ps_rsvp_links")
      .upsert(linkInserts, { onConflict: "class_id,student_id,session_date", ignoreDuplicates: false })
      .select("id, token, student_id, send_status");

    if (dryRun) {
      results.push({ class_id: cls.id, class_name: cls.name, eligible: eligible.length, links_prepared: upserted?.length ?? 0, dry_run: true });
      continue;
    }

    // Send DMs to pending only
    const pending = (upserted ?? []).filter((l) => l.send_status === "pending");

    // Slack healthcheck — pre-send announce
    if (SLACK_CHANNEL && pending.length > 0) {
      await sendBlockMessage(
        SLACK_CHANNEL,
        `🔔 PS RSVP dispatch starting — ${cls.name}`,
        [
          { type: "section", text: { type: "mrkdwn", text: `*🔔 PS RSVP dispatch starting*\n*Class:* ${cls.name}\n*Date:* ${today.isoDate}\n*Eligible students:* ${eligible.length}\n*DMs to send:* ${pending.length}\n*Throttle:* ${DELAY_MS}ms` } },
        ],
      ).catch((e) => console.error("[slack-pre]", e));
    }

    const studentMap = new Map<string, { name: string; phone: string }>();
    eligible.forEach((s) => studentMap.set(s.id, { name: s.name, phone: s.phone }));

    let sent = 0; let failed = 0;
    for (let i = 0; i < pending.length; i++) {
      const lnk = pending[i];
      const stu = studentMap.get(lnk.student_id);
      if (!stu?.phone) {
        await sb.from("ps_rsvp_links").update({ send_status: "skipped", error_detail: "no_phone" }).eq("id", lnk.id);
        failed++;
        continue;
      }
      const firstName = (stu.name || "").trim().split(/\s+/)[0] || "Lendário";
      const text = buildDMText(firstName, cls.name, cls.time_start, lnk.token);

      const r = await sendDM(stu.phone, text);
      if (r.ok) {
        await sb.from("ps_rsvp_links").update({ send_status: "sent", sent_at: new Date().toISOString(), evolution_message_id: r.messageId }).eq("id", lnk.id);
        sent++;
      } else {
        await sb.from("ps_rsvp_links").update({ send_status: "failed", error_detail: r.error }).eq("id", lnk.id);
        failed++;
      }
      if (i < pending.length - 1) await sleep(DELAY_MS);
    }

    // Group msg to each cohort WA group (single msg per group)
    const { data: cohortGroups } = await sb
      .from("cohorts")
      .select("id, name, whatsapp_group_jid, whatsapp_group_name")
      .in("id", cohortIds)
      .not("whatsapp_group_jid", "is", null);

    let groupSent = 0; let groupFailed = 0;
    for (const cg of (cohortGroups ?? [])) {
      const groupText = buildGroupText(cls.name, cls.time_start);
      const r = await sendEvolutionGroupText(cg.whatsapp_group_jid as string, groupText);
      if (r.success) groupSent++;
      else groupFailed++;
      await sleep(2000);
    }

    results.push({ class_id: cls.id, class_name: cls.name, eligible: eligible.length, sent, failed, group_sent: groupSent, group_failed: groupFailed });

    // Slack healthcheck — post-send summary
    if (SLACK_CHANNEL) {
      await sendBlockMessage(
        SLACK_CHANNEL,
        `✅ PS RSVP dispatch finished — ${cls.name}`,
        [
          { type: "section", text: { type: "mrkdwn", text: `*✅ PS RSVP dispatch finished*\n*Class:* ${cls.name}\n*DMs sent:* ${sent}\n*DMs failed:* ${failed}\n*Groups sent:* ${groupSent}\n*Groups failed:* ${groupFailed}\n*Date:* ${today.isoDate}\n_Responses → ps_rsvp_today view._` } },
        ],
      ).catch((e) => console.error("[slack-post]", e));
    }
  }

  return json({ success: true, today, results });
});
