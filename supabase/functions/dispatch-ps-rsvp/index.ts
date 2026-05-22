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
import { sendWhatsAppTemplate } from "../_shared/meta-whatsapp.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SLACK_CHANNEL = Deno.env.get("SLACK_CHANNEL_DEV_ALERTS") ?? Deno.env.get("SLACK_CHANNEL_DETRACTORS") ?? "";
// Meta Cloud API — 500ms throttle (2 msg/s, comfortable under tier limits).
const DELAY_MS = 100;

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

// ── Variant rotation ──
function pickRandom<T>(arr: T[]): T { return arr[Math.floor(Math.random() * arr.length)]; }

interface PsVariant {
  id: string;
  meta_template_name: string;
  weight: number;
}

function pickWeighted(variants: PsVariant[]): PsVariant {
  const total = variants.reduce((s, v) => s + v.weight, 0);
  let r = Math.random() * total;
  for (const v of variants) {
    r -= v.weight;
    if (r <= 0) return v;
  }
  return variants[variants.length - 1];
}

function buildGroupText(className: string, timeStart: string): string {
  // ATENÇÃO: URL aqui é sem token (group msg compartilhada). Form requer token único
  // por aluno. Esta função ficou DESATIVADA em prod 2026-05-22 — usar DM-only.
  // Se re-habilitar, trocar texto pra "confira sua DM" sem URL.
  const url = `https://painel.academialendaria.ai/ps-rsvp`;
  const variants = [
    `Bom dia, time.\n\nHoje rola *${className}*, ${timeStart} (Brasília).\n\nQuanto mais a sessão for sobre o que vocês estão construindo, mais valor ela gera. Reserva 30s pra contar o que precisa destravar:\n${url}`,
    `Time, bom dia!\n\n*${className}* abre hoje às ${timeStart}. O foco do PS se ajusta às dúvidas que vocês trouxerem — vale separar 30s antes:\n${url}`,
    `Bom dia.\n\nPS *${className}* — ${timeStart} (Brasília). Pra mentor chegar com pauta calibrada pro seu caso, conta o que está precisando trabalhar:\n${url}`,
    `Time, hoje tem *${className}* às ${timeStart}.\n\nA sessão fica mais cirúrgica quando os pontos chegam antes. 30s pra preencher:\n${url}`,
    `Bom dia, Lendários.\n\n*${className}* — ${timeStart} (Brasília). Compartilha o que está te travando hoje pra gente trazer resposta direcionada:\n${url}`,
  ];
  return pickRandom(variants);
}

async function sendDmTemplate(
  phone: string,
  templateName: string,
  firstName: string,
  className: string,
  timeStart: string,
  token: string,
): Promise<{ ok: boolean; messageId: string | null; error?: string }> {
  const r = await sendWhatsAppTemplate(
    phone,
    templateName,
    [firstName, className, timeStart],
    [token],
  );
  return { ok: r.success, messageId: r.messageId, error: r.error };
}

async function slackNotify(_text: string, _blocks?: Array<Record<string, unknown>>) {
  // DESATIVADO 2026-05-22 — user pediu remover avisos PS RSVP do canal Slack.
  // Pra re-habilitar: descomentar bloco abaixo + restaurar params nomes.
  return;
  // eslint-disable-next-line no-unreachable
  if (!SLACK_CHANNEL) return;
  try {
    await sendBlockMessage(SLACK_CHANNEL, text, blocks ?? [{ type: "section", text: { type: "mrkdwn", text } }]);
  } catch (e) {
    console.error("[slack-notify]", e instanceof Error ? e.message : e);
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

  // STARTUP notify (always, regardless of outcome)
  await slackNotify(`🚀 dispatch-ps-rsvp fired — ${today.isoDate} (weekday ${today.weekday})${dryRun ? " [DRY RUN]" : ""}`);

  try {

  // Find PS classes for today's weekday via class_mentors (multi-day support).
  // Schema: classes.weekday is single int, mas mentors são cadastrados por dia
  // em class_mentors.weekday → fonte real do calendário ativo.
  const { data: mentorRows } = await sb
    .from("class_mentors")
    .select("class_id")
    .eq("weekday", today.weekday)
    .lte("valid_from", today.isoDate)
    .or(`valid_until.is.null,valid_until.gte.${today.isoDate}`);
  const classIds = [...new Set((mentorRows ?? []).map((r: { class_id: string }) => r.class_id))];

  const { data: classes } = classIds.length === 0
    ? { data: [] as Array<{ id: string; name: string; weekday: number; time_start: string; kind: string }> }
    : await sb
        .from("classes")
        .select("id, name, weekday, time_start, kind")
        .eq("active", true)
        .eq("kind", "ps")
        .in("id", classIds);

  if (!classes || classes.length === 0) {
    await slackNotify(`✅ dispatch-ps-rsvp finished — no PS class today (${today.isoDate}, weekday ${today.weekday})`);
    return json({ success: true, message: "no PS class today", today });
  }

  // Rotação por DISPATCH (não por aluno): pega variant active com last_used_at
  // mais antigo (NULLS FIRST). Mesma variant pra TODOS alunos da run. Final
  // do dispatch atualiza last_used_at → próximo dispatch pega outra automaticamente.
  // Re-triggers da mesma session_date continuam mesma variant (idempotente).
  const { data: variantRows } = await sb
    .from("ps_rsvp_variants")
    .select("id, meta_template_name, weight, last_used_at")
    .eq("active", true)
    .order("last_used_at", { ascending: true, nullsFirst: true })
    .limit(1);

  const variants: PsVariant[] = (variantRows ?? []) as PsVariant[];
  if (variants.length === 0) {
    await slackNotify(`❌ dispatch-ps-rsvp aborted — no active ps_rsvp_variants. Approve Meta templates and flip active=true.`);
    return json({ success: false, error: "no_active_variants" }, 412);
  }
  const dispatchVariant = variants[0];

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

      const r = await sendDmTemplate(stu.phone, dispatchVariant.meta_template_name, firstName, cls.name, cls.time_start, lnk.token);
      if (r.ok) {
        await sb.from("ps_rsvp_links").update({ send_status: "sent", sent_at: new Date().toISOString(), meta_message_id: r.messageId }).eq("id", lnk.id);
        sent++;
      } else {
        await sb.from("ps_rsvp_links").update({ send_status: "failed", error_detail: r.error }).eq("id", lnk.id);
        failed++;
      }
      if (i < pending.length - 1) await sleep(DELAY_MS);
    }

    // Group msgs DESATIVADAS (2026-05-22) — re-triggers spamavam grupos.
    // Dispatch DM-only. Group precisa idempotência via gravar dispatch_group_sent
    // antes de re-habilitar.
    const groupSent = 0; const groupFailed = 0;

    results.push({ class_id: cls.id, class_name: cls.name, eligible: eligible.length, sent, failed, group_sent: groupSent, group_failed: groupFailed, group_disabled: true });
  }

  // Marca variant como usada (rotação por dispatch). Idempotente: re-trigger no
  // mesmo dia pega mesma variant pq last_used_at já está no dia atual.
  const totalSentInRun = results.reduce((s, r) => s + ((r.sent as number) ?? 0), 0);
  if (totalSentInRun > 0) {
    await sb.from("ps_rsvp_variants")
      .update({ last_used_at: new Date().toISOString() })
      .eq("id", dispatchVariant.id);
  }

  // Final summary Slack (always)
  const totals = results.reduce((acc, r) => {
    acc.sent += (r.sent as number) ?? 0;
    acc.failed += (r.failed as number) ?? 0;
    acc.groupSent += (r.group_sent as number) ?? 0;
    acc.groupFailed += (r.group_failed as number) ?? 0;
    return acc;
  }, { sent: 0, failed: 0, groupSent: 0, groupFailed: 0 });

  const detailLines = results.map((r) =>
    `• *${r.class_name}* — DM: ${r.sent ?? 0}/${(r.sent ?? 0) + (r.failed ?? 0)} · Grupo: ${r.group_sent ?? 0}/${(r.group_sent ?? 0) + (r.group_failed ?? 0)}`
  ).join("\n");

  await slackNotify(
    `✅ dispatch-ps-rsvp finished — ${today.isoDate}`,
    [
      { type: "section", text: { type: "mrkdwn", text: `*✅ dispatch-ps-rsvp finished* — ${today.isoDate}\n\n*DMs:* ${totals.sent} sent · ${totals.failed} failed\n*Groups:* ${totals.groupSent} sent · ${totals.groupFailed} failed\n\n${detailLines}\n\n_Respostas → https://painel.academialendaria.ai/admin/ps-rsvp/_` } },
    ],
  );

  return json({ success: true, today, results });

  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    await slackNotify(`❌ dispatch-ps-rsvp FAILED — ${today.isoDate}\n\`\`\`${msg}\`\`\``);
    return json({ success: false, error: msg }, 500);
  }
});
