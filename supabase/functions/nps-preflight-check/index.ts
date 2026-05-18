// nps-preflight-check — Pre-dispatch validator. Audits everything that could
// break a real send. Returns structured OK/FAIL list. Does NOT trigger anything.
//
// POST { survey_id?, cohort_id?, meta_template_name?, frontend_urls? }
// Returns { ok: bool, checks: [{name, status, detail}], total_recipients: int }

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const META_API_KEY = Deno.env.get("META_API_KEY") ?? "";
const META_PHONE_NUMBER_ID = Deno.env.get("META_PHONE_NUMBER_ID") ?? "";
const META_WABA_ID = Deno.env.get("META_WABA_ID") ?? "";
const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface Check {
  name: string;
  status: "ok" | "fail" | "warn";
  detail: string;
}

function json(body: unknown): Response {
  return new Response(JSON.stringify(body, null, 2), {
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function isValidPhoneBR(p: string): boolean {
  const d = (p || "").replace(/\D/g, "");
  return /^55\d{2}9\d{8}$/.test(d);
}

function isValidGroupJid(jid: string | null | undefined): boolean {
  if (!jid) return false;
  return /^[0-9A-Za-z._-]+@g\.us$/.test(jid) && jid.length >= 12 && jid.length <= 64;
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const body = await req.json().catch(() => ({}));
  const surveyId = body.survey_id;
  const cohortId = body.cohort_id;
  const metaTemplate = body.meta_template_name;
  const frontendUrls: string[] = body.frontend_urls ?? [];
  const checkGroupJid = body.check_group_jid;

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const checks: Check[] = [];

  // ─── 1. Survey ───
  if (surveyId) {
    const { data: s, error } = await sb.from("surveys").select("id, name, status").eq("id", surveyId).maybeSingle();
    if (error) checks.push({ name: "survey.exists", status: "fail", detail: `query error: ${error.message}` });
    else if (!s) checks.push({ name: "survey.exists", status: "fail", detail: `survey_id ${surveyId} not found` });
    else if (s.status !== "active") checks.push({ name: "survey.active", status: "fail", detail: `status=${s.status}, expected active` });
    else {
      checks.push({ name: "survey.active", status: "ok", detail: `'${s.name}' active` });
      const { data: qs } = await sb.from("survey_questions").select("id, position, type, required, label").eq("survey_id", surveyId).order("position");
      if (!qs || qs.length === 0) checks.push({ name: "survey.questions", status: "fail", detail: "no questions configured" });
      else {
        checks.push({ name: "survey.questions", status: "ok", detail: `${qs.length} questions configured` });
        const invalidTypes = qs.filter((q) => !["choice", "text", "nps", "csat", "scale", "multi"].includes(q.type));
        if (invalidTypes.length > 0) checks.push({ name: "survey.question_types", status: "fail", detail: `invalid types: ${invalidTypes.map((q) => q.type).join(", ")}` });
        else checks.push({ name: "survey.question_types", status: "ok", detail: "all types supported" });
      }
    }
  }

  // ─── 2. Cohort + students ───
  let totalRecipients = 0;
  if (cohortId) {
    const { data: c, error } = await sb.from("cohorts").select("id, name, active, whatsapp_group_jid, whatsapp_group_verified").eq("id", cohortId).maybeSingle();
    if (error) checks.push({ name: "cohort.exists", status: "fail", detail: error.message });
    else if (!c) checks.push({ name: "cohort.exists", status: "fail", detail: `cohort_id ${cohortId} not found` });
    else if (!c.active) checks.push({ name: "cohort.active", status: "fail", detail: `cohort ${c.name} is inactive` });
    else {
      checks.push({ name: "cohort.active", status: "ok", detail: `'${c.name}' active` });
      if (c.whatsapp_group_jid) {
        if (!isValidGroupJid(c.whatsapp_group_jid)) checks.push({ name: "cohort.group_jid_format", status: "fail", detail: `JID '${c.whatsapp_group_jid}' invalid format` });
        else checks.push({ name: "cohort.group_jid_format", status: "ok", detail: c.whatsapp_group_jid });
        if (!c.whatsapp_group_verified) checks.push({ name: "cohort.group_verified", status: "warn", detail: "group NOT verified — group send will be skipped" });
        else checks.push({ name: "cohort.group_verified", status: "ok", detail: "verified" });
      } else {
        checks.push({ name: "cohort.group_jid", status: "warn", detail: "no JID — group send not applicable" });
      }

      const { data: studentsAll } = await sb.from("students").select("id, name, phone, email, active, is_mentor").eq("cohort_id", cohortId);
      const active = (studentsAll ?? []).filter((s) => s.active && !s.is_mentor);
      const validPhone = active.filter((s) => isValidPhoneBR(s.phone));
      const placeholderName = active.filter((s) => s.name && s.name.startsWith("WA "));
      const withEmail = active.filter((s) => s.email);
      totalRecipients = validPhone.length;

      checks.push({ name: "students.total_active", status: active.length > 0 ? "ok" : "fail", detail: `${active.length} active non-mentor students` });
      checks.push({ name: "students.valid_phone", status: validPhone.length === active.length ? "ok" : "warn", detail: `${validPhone.length}/${active.length} with canonical BR phone (55XX9XXXXXXXX)` });
      checks.push({ name: "students.placeholder_names", status: placeholderName.length === 0 ? "ok" : "warn", detail: `${placeholderName.length} students with placeholder name (WA XXXX) — DM would send with bad name` });
      checks.push({ name: "students.with_email", status: "ok", detail: `${withEmail.length}/${active.length} with email (email channel optional)` });
    }
  }

  // ─── 3. Meta template ───
  if (metaTemplate) {
    const { data: tmpl, error } = await sb.from("meta_templates").select("name, status, category").eq("name", metaTemplate).maybeSingle();
    if (error) checks.push({ name: "meta.template_exists", status: "fail", detail: error.message });
    else if (!tmpl) checks.push({ name: "meta.template_exists", status: "fail", detail: `template '${metaTemplate}' not found in DB` });
    else if (tmpl.status !== "active" && tmpl.status !== "approved" && tmpl.status !== "APPROVED") {
      checks.push({ name: "meta.template_approved", status: "fail", detail: `template status=${tmpl.status}` });
    } else {
      checks.push({ name: "meta.template_approved", status: "ok", detail: `${tmpl.name} (${tmpl.category}) active` });
    }
  }

  // ─── 4. Meta API config ───
  if (META_API_KEY && META_PHONE_NUMBER_ID) {
    checks.push({ name: "meta.api_config", status: "ok", detail: "META_API_KEY + PHONE_NUMBER_ID set" });
  } else {
    checks.push({ name: "meta.api_config", status: "fail", detail: "META_API_KEY or META_PHONE_NUMBER_ID missing" });
  }

  // ─── 5. Evolution API ───
  if (EVOLUTION_API_URL && EVOLUTION_API_KEY && EVOLUTION_INSTANCE) {
    try {
      const res = await fetch(`${EVOLUTION_API_URL}/instance/connectionState/${EVOLUTION_INSTANCE}`, {
        headers: { apikey: EVOLUTION_API_KEY },
      });
      if (res.ok) {
        const data = await res.json();
        const state = data?.instance?.state ?? data?.state ?? "unknown";
        if (state === "open" || state === "connected") {
          checks.push({ name: "evolution.connection", status: "ok", detail: `state=${state}` });
        } else {
          checks.push({ name: "evolution.connection", status: "warn", detail: `state=${state} (group sends may fail)` });
        }
      } else {
        checks.push({ name: "evolution.connection", status: "warn", detail: `HTTP ${res.status}` });
      }
    } catch (e) {
      checks.push({ name: "evolution.connection", status: "warn", detail: `unreachable: ${e instanceof Error ? e.message : String(e)}` });
    }
  } else {
    checks.push({ name: "evolution.config", status: "warn", detail: "Evolution env vars missing" });
  }

  // ─── 6. Optional group JID check ───
  if (checkGroupJid) {
    if (!isValidGroupJid(checkGroupJid)) {
      checks.push({ name: "group.jid_format", status: "fail", detail: `'${checkGroupJid}' invalid` });
    } else {
      checks.push({ name: "group.jid_format", status: "ok", detail: checkGroupJid });
    }
  }

  // ─── 7. App config ───
  const { data: appCfg } = await sb.from("app_config").select("key").in("key", ["supabase_service_key", "dispatch_class_nps_url"]);
  const cfgKeys = new Set((appCfg ?? []).map((r) => r.key));
  if (cfgKeys.has("supabase_service_key")) checks.push({ name: "app_config.service_key", status: "ok", detail: "set" });
  else checks.push({ name: "app_config.service_key", status: "fail", detail: "supabase_service_key missing (cron/retry will 401)" });

  // ─── 8. Frontend URLs reachable ───
  for (const url of frontendUrls) {
    try {
      const res = await fetch(url, { method: "HEAD" });
      if (res.ok) checks.push({ name: `frontend.${url}`, status: "ok", detail: `HTTP ${res.status}` });
      else checks.push({ name: `frontend.${url}`, status: "fail", detail: `HTTP ${res.status}` });
    } catch (e) {
      checks.push({ name: `frontend.${url}`, status: "fail", detail: `unreachable: ${e instanceof Error ? e.message : String(e)}` });
    }
  }

  // ─── Tally ───
  const fails = checks.filter((c) => c.status === "fail").length;
  const warns = checks.filter((c) => c.status === "warn").length;
  const oks = checks.filter((c) => c.status === "ok").length;

  return json({
    ok: fails === 0,
    summary: { ok: oks, warn: warns, fail: fails, total: checks.length },
    total_recipients: totalRecipients,
    checks,
    recommendation: fails === 0
      ? warns === 0
        ? "✅ GO — all green, dispatch safe"
        : `🟡 GO WITH CAUTION — ${warns} warnings (review before dispatch)`
      : `❌ NO-GO — ${fails} critical failures must be fixed`,
  });
});
