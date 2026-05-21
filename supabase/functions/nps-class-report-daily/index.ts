// ═══════════════════════════════════════════════════════════════════════════
// nps-class-report-daily — Daily MD report pós-aula
//
// Dispara via pg_cron 09:00 BRT (12:00 UTC). Lê jobs sent/partial das
// últimas 36h cujo report ainda não foi enviado. Pra cada job:
//   1. Query class_nps_responses
//   2. Compute aggregates (NPS, distribution, comments)
//   3. Render MD
//   4. POST Evolution Group
//   5. UPDATE job.report_sent_at
//
// Idempotency: column report_sent_at IS NULL → elegível
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendEvolutionGroupText } from "../_shared/evolution-group.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

interface JobRow {
  id: string;
  class_id: string | null;
  cohort_id: string;
  session_date: string;
  status: string;
  dm_sent_count: number;
  total_eligible_students: number | null;
}

interface ResponseRow {
  nps_score: number;
  comment: string | null;
  detractor_followup_text: string | null;
  improvement_text: string | null;
  name_provided: string | null;
  mode: string;
  student_id: string | null;
}

function npsBucket(score: number): "promoter" | "passive" | "detractor" {
  if (score >= 9) return "promoter";
  if (score >= 7) return "passive";
  return "detractor";
}

function fmtDate(iso: string): string {
  const d = new Date(iso + "T00:00:00-03:00");
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
}

function renderMd(opts: {
  className: string;
  cohortName: string;
  sessionDate: string;
  responses: ResponseRow[];
  totalEligible: number;
  dmSent: number;
}): string {
  const { className, cohortName, sessionDate, responses, totalEligible, dmSent } = opts;
  const total = responses.length;
  if (total === 0) return "";

  const promoters = responses.filter((r) => npsBucket(r.nps_score) === "promoter").length;
  const passives = responses.filter((r) => npsBucket(r.nps_score) === "passive").length;
  const detractors = responses.filter((r) => npsBucket(r.nps_score) === "detractor").length;
  const nps = Math.round(((promoters - detractors) / total) * 100);
  const avg = (responses.reduce((a, r) => a + r.nps_score, 0) / total).toFixed(1);
  const rate = totalEligible > 0 ? Math.round((total / totalEligible) * 100) : 0;

  // Comments por bucket
  const collectComments = (rows: ResponseRow[]) => rows
    .map((r) => {
      const txt = (r.detractor_followup_text || r.comment || r.improvement_text || "").trim();
      const who = r.mode === "dm" ? "" : (r.name_provided ? ` — ${r.name_provided}` : "");
      return txt ? `• "${txt.slice(0, 200)}"${who}` : "";
    })
    .filter(Boolean);

  const promComments = collectComments(responses.filter((r) => npsBucket(r.nps_score) === "promoter")).slice(0, 5);
  const passComments = collectComments(responses.filter((r) => npsBucket(r.nps_score) === "passive")).slice(0, 5);
  const detComments = collectComments(responses.filter((r) => npsBucket(r.nps_score) === "detractor")).slice(0, 10);

  let md = `📊 *NPS Pós-Aula* — ${className} (${fmtDate(sessionDate)})\n\n`;
  md += `*NPS:* ${nps}  ·  Média: ${avg}/10\n`;
  md += `*Respostas:* ${total}/${totalEligible || dmSent || "?"} (${rate}%)\n\n`;
  md += `💚 Promoters: ${promoters} (${Math.round((promoters / total) * 100)}%)\n`;
  md += `💛 Passives: ${passives} (${Math.round((passives / total) * 100)}%)\n`;
  md += `❤️ Detractors: ${detractors} (${Math.round((detractors / total) * 100)}%)\n`;

  if (promComments.length) md += `\n*💚 Comentários positivos:*\n${promComments.join("\n")}\n`;
  if (passComments.length) md += `\n*💛 Pra melhorar (passive):*\n${passComments.join("\n")}\n`;
  if (detComments.length) md += `\n*❤️ Atenção (detractor):*\n${detComments.join("\n")}\n`;

  md += `\n_Relatório consolidado 24h pós-aula. Detalhe completo em /admin/nps-results/_`;
  return md;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // Body opcional pra dry_run / specific job
  const body = await req.json().catch(() => ({}));
  const dryRun = body.dry_run === true;
  const specificJob: string | undefined = body.job_id;

  // Jobs elegíveis: status sent/partial, finished 12-48h atrás, report_sent_at NULL
  const since = new Date(Date.now() - 48 * 3600000).toISOString();
  const until = new Date(Date.now() - 12 * 3600000).toISOString();

  let q = sb.from("nps_class_dispatch_jobs")
    .select("id, class_id, cohort_id, session_date, status, dm_sent_count, total_eligible_students")
    .in("status", ["sent", "partial"])
    .gte("finished_at", since)
    .lte("finished_at", until)
    .is("report_sent_at", null);
  if (specificJob) q = q.eq("id", specificJob);

  const { data: jobs, error: jobsErr } = await q;
  if (jobsErr) return new Response(JSON.stringify({ error: jobsErr.message }), { status: 500, headers: { ...CORS, "Content-Type": "application/json" } });
  if (!jobs?.length) return new Response(JSON.stringify({ success: true, processed: 0, message: "no_eligible_jobs" }), { status: 200, headers: { ...CORS, "Content-Type": "application/json" } });

  const results: Array<{ job_id: string; cohort: string; status: string; detail?: string }> = [];

  for (const j of jobs as JobRow[]) {
    const [{ data: cohort }, { data: klass }, { data: responses }] = await Promise.all([
      sb.from("cohorts").select("name, whatsapp_group_jid, whatsapp_group_verified").eq("id", j.cohort_id).maybeSingle(),
      j.class_id ? sb.from("classes").select("name").eq("id", j.class_id).maybeSingle() : Promise.resolve({ data: { name: null as string | null } }),
      sb.from("class_nps_responses")
        .select("nps_score, comment, detractor_followup_text, improvement_text, name_provided, mode, student_id")
        .eq("cohort_id", j.cohort_id)
        .eq("session_date", j.session_date),
    ]);

    if (!cohort?.whatsapp_group_jid || cohort?.whatsapp_group_verified !== true) {
      results.push({ job_id: j.id, cohort: cohort?.name ?? "?", status: "skipped_no_verified_group" });
      continue;
    }
    if (!responses?.length) {
      results.push({ job_id: j.id, cohort: cohort.name ?? "?", status: "skipped_no_responses" });
      // Mark report_sent_at anyway pra não polling repetir
      if (!dryRun) await sb.from("nps_class_dispatch_jobs").update({ report_sent_at: new Date().toISOString() }).eq("id", j.id);
      continue;
    }

    const md = renderMd({
      className: (klass as { name?: string | null })?.name ?? cohort.name ?? "Aula",
      cohortName: cohort.name ?? "Turma",
      sessionDate: j.session_date,
      responses: responses as ResponseRow[],
      totalEligible: j.total_eligible_students ?? j.dm_sent_count ?? 0,
      dmSent: j.dm_sent_count ?? 0,
    });
    if (!md) {
      results.push({ job_id: j.id, cohort: cohort.name ?? "?", status: "skipped_empty_md" });
      continue;
    }

    if (dryRun) {
      results.push({ job_id: j.id, cohort: cohort.name ?? "?", status: "dry_run_preview", detail: md.slice(0, 500) });
      continue;
    }

    const sendResult = await sendEvolutionGroupText(cohort.whatsapp_group_jid, md);
    if (sendResult.success) {
      await sb.from("nps_class_dispatch_jobs").update({
        report_sent_at: new Date().toISOString(),
        report_evolution_message_id: sendResult.messageId,
      }).eq("id", j.id);
      results.push({ job_id: j.id, cohort: cohort.name ?? "?", status: "sent" });
    } else {
      results.push({ job_id: j.id, cohort: cohort.name ?? "?", status: "send_failed", detail: sendResult.error });
    }
  }

  return new Response(JSON.stringify({ success: true, processed: results.length, results }, null, 2), {
    status: 200,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
});
