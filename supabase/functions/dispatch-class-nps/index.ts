// ═══════════════════════════════════════════════════════════════════════════
// dispatch-class-nps — Post-class NPS dispatcher (P3).
//
// Trigger:
//   - Cron (*/5 min) — empty body, processes all due jobs
//   - Manual: { job_id, dry_run }
//
// Logic per job:
//   1. Lock (UPDATE status='in_progress' WHERE status='pending' RETURNING ...).
//   2. Pick group + dm variants via round-robin RPC.
//   3. Resolve eligible students via nps_resolve_eligible_students RPC.
//   4. Insert nps_class_links rows (1 group + N dm, all idempotent).
//   5. Send group via Evolution.
//   6. Send DM loop via Meta template, throttled.
//   7. Update job counters + final status.
//   8. Post Slack summary (#dev-alerts).
//
// Safety:
//   - nps_dispatch_enabled flag (DB) — function bails if false.
//   - Per-run cap: nps_dispatch_max_dm_per_run (default 50).
//   - Throttle: nps_dispatch_dm_throttle_ms (default 10s).
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { sendEvolutionGroupText } from "../_shared/evolution-group.ts";
import { sendWhatsAppTemplate } from "../_shared/meta-whatsapp.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const SLACK_WEBHOOK_URL = Deno.env.get("SLACK_DEV_ALERTS_WEBHOOK") ?? "";

const BASE_URL = "https://painel.academialendaria.ai";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

const sleep = (ms: number) => new Promise((r) => setTimeout(r, ms));

function sb() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

interface JobRow {
  id: string;
  class_id: string | null;
  cohort_id: string;
  session_date: string;
  zoom_meeting_id: string | null;
}

interface StudentRow {
  student_id: string;
  name: string;
  phone: string;
}

interface VariantRow {
  variant_id: string;
  body_template: string;
  meta_template_name: string | null;
}

interface JobResult {
  job_id: string;
  status: string;
  group: { sent: boolean; error?: string };
  dm: { sent: number; failed: number; skipped: number; total: number };
  cohort_id: string;
  class_id: string | null;
}

async function postSlack(text: string): Promise<void> {
  if (!SLACK_WEBHOOK_URL) return;
  try {
    await fetch(SLACK_WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ text }),
    });
  } catch (_e) {
    // best effort
  }
}

function renderTemplate(template: string, vars: Record<string, string>): string {
  let out = template;
  for (const [k, v] of Object.entries(vars)) {
    out = out.replace(new RegExp(`{{\\s*${k}\\s*}}`, "g"), v);
  }
  return out;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const client = sb();

  // ─── Feature flag gate ───
  const { data: cfgEnabled } = await client
    .from("nps_dispatch_config")
    .select("value")
    .eq("key", "nps_dispatch_enabled")
    .maybeSingle();

  if (cfgEnabled?.value !== "true") {
    return new Response(
      JSON.stringify({ success: true, message: "feature_disabled", processed: 0 }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }

  // ─── Read tunables ───
  const { data: cfgRows } = await client
    .from("nps_dispatch_config")
    .select("key, value")
    .in("key", ["nps_dispatch_max_dm_per_run", "nps_dispatch_dm_throttle_ms"]);

  const cfg = Object.fromEntries((cfgRows ?? []).map((r) => [r.key, r.value]));
  const maxDmPerRun = parseInt(cfg["nps_dispatch_max_dm_per_run"] ?? "50", 10);
  const throttleMs = parseInt(cfg["nps_dispatch_dm_throttle_ms"] ?? "10000", 10);

  // ─── Parse body ───
  const body = await req.json().catch(() => ({}));
  const dryRun = body.dry_run === true;
  const specificJobId: string | undefined = body.job_id;

  // ─── Acquire jobs ───
  let jobsQ = client
    .from("nps_class_dispatch_jobs")
    .update({ status: "in_progress", started_at: new Date().toISOString() })
    .eq("status", "pending")
    .lte("scheduled_at", new Date().toISOString())
    .select("id, class_id, cohort_id, session_date, zoom_meeting_id");

  if (specificJobId) jobsQ = jobsQ.eq("id", specificJobId);

  const { data: jobs, error: jobsErr } = await jobsQ.limit(10);
  if (jobsErr) {
    return new Response(
      JSON.stringify({ success: false, error: jobsErr.message }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }

  if (!jobs || jobs.length === 0) {
    return new Response(
      JSON.stringify({ success: true, processed: 0, message: "no_due_jobs" }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }

  const results: JobResult[] = [];

  for (const job of jobs as JobRow[]) {
    const result = await processJob(client, job, { dryRun, maxDmPerRun, throttleMs });
    results.push(result);
  }

  return new Response(
    JSON.stringify({ success: true, processed: results.length, results }),
    { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
  );
});

// ─── Core: process one job ───
async function processJob(
  client: ReturnType<typeof sb>,
  job: JobRow,
  opts: { dryRun: boolean; maxDmPerRun: number; throttleMs: number },
): Promise<JobResult> {
  const baseResult: JobResult = {
    job_id: job.id,
    status: "in_progress",
    group: { sent: false },
    dm: { sent: 0, failed: 0, skipped: 0, total: 0 },
    cohort_id: job.cohort_id,
    class_id: job.class_id,
  };

  try {
    // 1. Cohort + class metadata
    const [{ data: cohort }, { data: klass }] = await Promise.all([
      client.from("cohorts").select("name, whatsapp_group_jid").eq("id", job.cohort_id).maybeSingle(),
      job.class_id
        ? client.from("classes").select("name").eq("id", job.class_id).maybeSingle()
        : Promise.resolve({ data: { name: null } }),
    ]);

    if (!cohort) {
      await finishJob(client, job.id, "failed", { error_detail: "cohort_not_found" });
      baseResult.status = "failed";
      return baseResult;
    }

    const cohortName = cohort.name ?? "Turma";
    const className = (klass as { name?: string } | null)?.name ?? cohortName;

    // 2. Eligible students
    const { data: studentsData } = await client.rpc("nps_resolve_eligible_students", {
      p_class_id: job.class_id,
      p_cohort_id: job.cohort_id,
      p_session_date: job.session_date,
    });
    const students: StudentRow[] = (studentsData ?? []) as StudentRow[];

    // 3. Variants
    const { data: groupVarRaw } = await client.rpc("nps_next_variant", { p_channel: "group" });
    const { data: dmVarRaw } = await client.rpc("nps_next_variant", { p_channel: "dm" });
    const groupVar = (Array.isArray(groupVarRaw) ? groupVarRaw[0] : groupVarRaw) as VariantRow | null;
    const dmVar = (Array.isArray(dmVarRaw) ? dmVarRaw[0] : dmVarRaw) as VariantRow | null;

    // 4. Insert nps_class_links (1 group + N dm)
    const expiresAt = new Date(Date.now() + 14 * 24 * 60 * 60 * 1000).toISOString();
    let groupLinkId: string | null = null;
    let groupToken: string | null = null;

    if (cohort.whatsapp_group_jid && groupVar) {
      const { data: groupLink } = await client
        .from("nps_class_links")
        .insert({
          mode: "group",
          cohort_id: job.cohort_id,
          class_id: job.class_id,
          trigger_date: job.session_date,
          session_date: job.session_date,
          expires_at: expiresAt,
          dispatch_job_id: job.id,
          created_by: "dispatch-class-nps",
        })
        .select("id, token")
        .maybeSingle();
      if (groupLink) {
        groupLinkId = groupLink.id;
        groupToken = groupLink.token;
      }
    }

    const dmLinks: { id: string; token: string; student_id: string; phone: string; name: string }[] = [];
    if (dmVar && students.length > 0) {
      const dmInserts = students.map((s) => ({
        mode: "dm",
        cohort_id: job.cohort_id,
        class_id: job.class_id,
        trigger_date: job.session_date,
        session_date: job.session_date,
        student_id: s.student_id,
        expires_at: expiresAt,
        dispatch_job_id: job.id,
        created_by: "dispatch-class-nps",
      }));
      const { data: dmInserted } = await client
        .from("nps_class_links")
        .insert(dmInserts)
        .select("id, token, student_id");
      for (const dl of dmInserted ?? []) {
        const stu = students.find((s) => s.student_id === dl.student_id);
        if (stu) dmLinks.push({ ...dl, phone: stu.phone, name: stu.name });
      }
    }

    baseResult.dm.total = dmLinks.length;

    // 5. Dry-run preview
    if (opts.dryRun) {
      await finishJob(client, job.id, "skipped", {
        error_detail: "dry_run",
        total_eligible_students: students.length,
        variant_group_id: groupVar?.variant_id ?? null,
        variant_dm_id: dmVar?.variant_id ?? null,
      });
      baseResult.status = "dry_run";
      return baseResult;
    }

    // 6. Send group via Evolution
    if (cohort.whatsapp_group_jid && groupVar && groupToken) {
      const groupLink = `${BASE_URL}/survey/grupo/${groupToken}`;
      const groupMsg = renderTemplate(groupVar.body_template, {
        class_name: className,
        cohort_name: cohortName,
        link: groupLink,
      });
      const r = await sendEvolutionGroupText(cohort.whatsapp_group_jid, groupMsg);
      if (r.success) {
        baseResult.group.sent = true;
        await client.from("nps_class_links").update({
          send_status: "sent",
          sent_at: new Date().toISOString(),
          evolution_message_id: r.messageId,
        }).eq("id", groupLinkId!);
      } else {
        baseResult.group.error = r.error;
        await client.from("nps_class_links").update({
          send_status: "failed",
          error_detail: r.error,
        }).eq("id", groupLinkId!);
      }
    } else {
      baseResult.group.error = cohort.whatsapp_group_jid ? "no_variant" : "no_group_jid";
    }

    // 7. DM loop (capped at maxDmPerRun per tick)
    if (dmVar?.meta_template_name) {
      const batch = dmLinks.slice(0, opts.maxDmPerRun);
      for (let i = 0; i < batch.length; i++) {
        const link = batch[i];
        const dmLink = `${BASE_URL}/survey/aluno/${link.token}`;
        const bodyParams = [link.name.split(" ")[0], className]; // template: {{1}}=first_name, {{2}}=class
        const buttonParam = link.token;

        const r = await sendWhatsAppTemplate(
          link.phone,
          dmVar.meta_template_name,
          bodyParams,
          [buttonParam],
        );

        if (r.success) {
          baseResult.dm.sent++;
          await client.from("nps_class_links").update({
            send_status: "sent",
            sent_at: new Date().toISOString(),
            meta_message_id: r.messageId,
          }).eq("id", link.id);
        } else {
          baseResult.dm.failed++;
          await client.from("nps_class_links").update({
            send_status: "failed",
            error_detail: r.error,
          }).eq("id", link.id);
        }

        if (i < batch.length - 1) await sleep(opts.throttleMs);
      }
      baseResult.dm.skipped = dmLinks.length - batch.length;
    } else {
      baseResult.dm.skipped = dmLinks.length;
    }

    // 8. Final status
    const isGroupOk = baseResult.group.sent || !cohort.whatsapp_group_jid;
    const isDmOk = baseResult.dm.failed === 0 && baseResult.dm.skipped === 0;
    const isPartial = (baseResult.dm.sent > 0 || baseResult.group.sent) && (!isGroupOk || !isDmOk);
    const finalStatus = isGroupOk && isDmOk ? "sent" : (isPartial ? "partial" : "failed");

    await finishJob(client, job.id, finalStatus, {
      total_eligible_students: students.length,
      variant_group_id: groupVar?.variant_id ?? null,
      variant_dm_id: dmVar?.variant_id ?? null,
      group_send_status: baseResult.group.sent ? "sent" : (cohort.whatsapp_group_jid ? "failed" : "not_applicable"),
      group_send_error: baseResult.group.error ?? null,
      dm_sent_count: baseResult.dm.sent,
      dm_failed_count: baseResult.dm.failed,
      dm_skipped_count: baseResult.dm.skipped,
    });

    baseResult.status = finalStatus;

    // 9. Slack summary
    await postSlack(
      `📊 *NPS post-class* [${finalStatus}] cohort=*${cohortName}* class=*${className}* date=${job.session_date}\n` +
      `   group: ${baseResult.group.sent ? "✅" : "❌"} ${baseResult.group.error ?? ""}\n` +
      `   dm: sent=${baseResult.dm.sent} failed=${baseResult.dm.failed} skipped=${baseResult.dm.skipped}/${baseResult.dm.total}`,
    );

    return baseResult;
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    await finishJob(client, job.id, "failed", { error_detail: msg });
    baseResult.status = "failed";
    baseResult.group.error = msg;
    return baseResult;
  }
}

async function finishJob(
  client: ReturnType<typeof sb>,
  jobId: string,
  status: string,
  extra: Record<string, unknown>,
): Promise<void> {
  await client
    .from("nps_class_dispatch_jobs")
    .update({
      status,
      finished_at: new Date().toISOString(),
      ...extra,
    })
    .eq("id", jobId);
}
