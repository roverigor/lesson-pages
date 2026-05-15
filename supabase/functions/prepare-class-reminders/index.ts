// ═══════════════════════════════════════════════════════════════════════════
// prepare-class-reminders — Gera batch de PREVIEW pra avisos de aula
//
// POST body:
//   { "target_date": "2026-05-18" }   // ISO date BRT — default: hoje
//   { "force": true }                  // overwrite existing preview pra mesma data
//
// Output: batch_id + sends array (preview, sem envio).
// Aprovação manual via UI muda status pra 'approved' → cron picks up.
//
// Templates rotacionados: tabela class_reminder_templates
//   - Selector preferindo least-recently-used (last_used_at)
//   - applies_to: ps|regular|any
//   - reminder_type: 1h_before|start|holiday
// ═══════════════════════════════════════════════════════════════════════════

import { createClient, SupabaseClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

interface ClassRow {
  id: string;
  name: string;
  weekday: number;
  time_start: string;
  time_end: string | null;
  zoom_link: string | null;
  start_date: string;
  end_date: string;
  active: boolean;
  kind: string | null;
}

interface CohortRow {
  id: string;
  name: string;
  whatsapp_group_jid: string | null;
  whatsapp_group_name: string | null;
}

interface TemplateRow {
  id: string;
  name: string;
  body: string;
  variant_label: string | null;
  applies_to: string;
  last_used_at: string | null;
  use_count: number;
}

function brtDate(iso?: string): { isoDate: string; weekday: number } {
  const base = iso ? new Date(iso + "T12:00:00-03:00") : new Date();
  const brt = new Date(base.toLocaleString("en-US", { timeZone: "America/Sao_Paulo" }));
  return {
    isoDate: brt.toISOString().split("T")[0],
    weekday: brt.getDay(),
  };
}

function saudacaoFromTime(timeStr: string): string {
  const [h] = timeStr.split(":").map(Number);
  if (h < 12) return "Bom dia";
  if (h < 18) return "Boa tarde";
  return "Boa noite";
}

function buildScheduledAt(targetDate: string, timeStart: string, offsetMin = 0): string {
  const [h, m] = timeStart.split(":").map(Number);
  const totalMin = h * 60 + m - offsetMin;
  const hh = String(Math.floor(totalMin / 60)).padStart(2, "0");
  const mm = String(totalMin % 60).padStart(2, "0");
  return `${targetDate}T${hh}:${mm}:00-03:00`;
}

function renderTemplate(body: string, vars: Record<string, string>): string {
  return body.replace(/\{(\w+)\}/g, (_, key) => vars[key] ?? `{${key}}`);
}

async function pickTemplate(
  sb: SupabaseClient,
  reminderType: string,
  appliesTo: string,
): Promise<TemplateRow | null> {
  // Fetch active templates matching reminder_type AND (applies_to=target OR any)
  const { data } = await sb
    .from("class_reminder_templates")
    .select("id, name, body, variant_label, applies_to, last_used_at, use_count")
    .eq("reminder_type", reminderType)
    .in("applies_to", [appliesTo, "any"])
    .eq("active", true);

  if (!data || data.length === 0) return null;

  // Sort by least-recently-used (null first), then by use_count asc
  const sorted = (data as TemplateRow[]).sort((a, b) => {
    const aT = a.last_used_at ? new Date(a.last_used_at).getTime() : 0;
    const bT = b.last_used_at ? new Date(b.last_used_at).getTime() : 0;
    if (aT !== bT) return aT - bT;
    return (a.use_count ?? 0) - (b.use_count ?? 0);
  });

  // Pick from top-3 (LRU) com random tie-breaker pra variedade
  const pool = sorted.slice(0, Math.min(3, sorted.length));
  return pool[Math.floor(Math.random() * pool.length)];
}

async function markTemplateUsed(sb: SupabaseClient, templateId: string): Promise<void> {
  const { data: current } = await sb
    .from("class_reminder_templates")
    .select("use_count")
    .eq("id", templateId)
    .single();
  const newCount = (current?.use_count ?? 0) + 1;
  await sb
    .from("class_reminder_templates")
    .update({
      last_used_at: new Date().toISOString(),
      use_count: newCount,
      updated_at: new Date().toISOString(),
    })
    .eq("id", templateId);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const body = await req.json().catch(() => ({}));
    const target = brtDate(body.target_date);
    const force = body.force === true;

    const sb: SupabaseClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Holiday check
    const { data: holidayRow } = await sb
      .from("holidays")
      .select("name")
      .eq("date", target.isoDate)
      .maybeSingle();
    const isHoliday = !!holidayRow;
    const holidayName: string | null = holidayRow?.name ?? null;

    // Active classes for target weekday + within date range + reminder_enabled
    const { data: classes, error: clsErr } = await sb
      .from("classes")
      .select("id, name, weekday, time_start, time_end, zoom_link, start_date, end_date, active, kind, reminder_enabled")
      .eq("active", true)
      .eq("reminder_enabled", true)
      .eq("weekday", target.weekday)
      .lte("start_date", target.isoDate)
      .gte("end_date", target.isoDate);
    if (clsErr) throw clsErr;

    const classRows: ClassRow[] = (classes ?? []) as ClassRow[];
    if (classRows.length === 0) {
      return new Response(
        JSON.stringify({
          success: true,
          target_date: target.isoDate,
          is_holiday: isHoliday,
          message: "no_active_classes_on_this_weekday",
          batch_id: null,
          sends: [],
        }),
        { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }

    // Existing batch handling
    const { data: existing } = await sb
      .from("class_reminder_batches")
      .select("id, status")
      .eq("target_date", target.isoDate)
      .in("status", ["preview", "approved"])
      .maybeSingle();

    if (existing) {
      if (!force) {
        return new Response(
          JSON.stringify({
            success: false,
            error: "batch_already_exists",
            batch_id: existing.id,
            status: existing.status,
            hint: "Use force:true to recreate",
          }),
          { status: 409, headers: { ...CORS, "Content-Type": "application/json" } },
        );
      }
      await sb
        .from("class_reminder_batches")
        .update({ status: "cancelled", updated_at: new Date().toISOString() })
        .eq("id", existing.id);
    }

    const { data: batch, error: batchErr } = await sb
      .from("class_reminder_batches")
      .insert({
        target_date: target.isoDate,
        status: "preview",
        notes: isHoliday ? `Feriado: ${holidayName}` : null,
      })
      .select("id")
      .single();
    if (batchErr) throw batchErr;

    const sends: Record<string, unknown>[] = [];
    const templatesUsed = new Set<string>();
    // Dedup: evitar 2 sends pro mesmo grupo+aula+tipo quando 2 cohorts apontam mesmo JID
    const dedupKey = new Set<string>();

    for (const cls of classRows) {
      const { data: bridge } = await sb
        .from("class_cohorts")
        .select("cohort_id")
        .eq("class_id", cls.id);
      const cohortIds = (bridge ?? []).map((r: { cohort_id: string }) => r.cohort_id);
      if (cohortIds.length === 0) continue;

      const { data: cohorts } = await sb
        .from("cohorts")
        .select("id, name, whatsapp_group_jid, whatsapp_group_name")
        .in("id", cohortIds)
        .eq("active", true);

      const zoomLink = cls.zoom_link || "";
      const classKind = cls.kind || "regular";

      // Pick template ONCE per class+reminder_type — same variant pra todos grupos da mesma aula
      const tpl1h = isHoliday ? null : await pickTemplate(sb, "1h_before", classKind);
      const tplStart = isHoliday ? null : await pickTemplate(sb, "start", classKind);
      const tplHoliday = isHoliday ? await pickTemplate(sb, "holiday", classKind) : null;
      if (tpl1h) templatesUsed.add(tpl1h.id);
      if (tplStart) templatesUsed.add(tplStart.id);
      if (tplHoliday) templatesUsed.add(tplHoliday.id);

      // Saudação por hora do envio:
      // 1h antes → time_start - 1h ; start → time_start ; feriado → time_start (msg no horário normal)
      const [csH, csM] = cls.time_start.split(":").map(Number);
      const dispatchHour1h = String(Math.max(0, csH - 1)).padStart(2, "0");
      const saudacao1h = saudacaoFromTime(`${dispatchHour1h}:${String(csM).padStart(2, "0")}`);
      const saudacaoStart = saudacaoFromTime(cls.time_start);

      for (const co of (cohorts ?? []) as CohortRow[]) {
        if (!co.whatsapp_group_jid) continue;

        // Dedup por aula+grupo (caso 2 cohorts apontem mesmo JID)
        const groupKey = `${cls.id}::${co.whatsapp_group_jid}`;
        if (dedupKey.has(groupKey)) continue;
        dedupKey.add(groupKey);

        const baseVars1h: Record<string, string> = {
          saudacao: saudacao1h,
          class_name: cls.name,
          time_start: cls.time_start,
          time_end: cls.time_end ?? cls.time_start,
          zoom_link: zoomLink,
          holiday_name: holidayName ?? "",
        };
        const baseVarsStart: Record<string, string> = {
          ...baseVars1h,
          saudacao: saudacaoStart,
        };

        if (isHoliday) {
          const body = tplHoliday ? renderTemplate(tplHoliday.body, baseVarsStart) : `Hoje é ${holidayName}. Sem aula.`;
          sends.push({
            batch_id: batch.id,
            class_id: cls.id,
            cohort_id: co.id,
            group_jid: co.whatsapp_group_jid,
            group_name: co.whatsapp_group_name,
            reminder_type: "holiday",
            scheduled_at: buildScheduledAt(target.isoDate, cls.time_start, 0),
            message_preview: body,
            zoom_link_snapshot: null,
            send_status: "pending",
          });
          continue;
        }

        if (!zoomLink) {
          sends.push({
            batch_id: batch.id,
            class_id: cls.id,
            cohort_id: co.id,
            group_jid: co.whatsapp_group_jid,
            group_name: co.whatsapp_group_name,
            reminder_type: "1h_before",
            scheduled_at: buildScheduledAt(target.isoDate, cls.time_start, 60),
            message_preview: `[SKIP] Aula ${cls.name} sem zoom_link configurado`,
            zoom_link_snapshot: null,
            send_status: "cancelled",
            error_detail: "missing_zoom_link",
          });
          continue;
        }

        const body1h = tpl1h ? renderTemplate(tpl1h.body, baseVars1h) : `Lembrete: ${cls.name} em 1h.`;
        const bodyStart = tplStart ? renderTemplate(tplStart.body, baseVarsStart) : `${cls.name} começou.`;

        sends.push({
          batch_id: batch.id,
          class_id: cls.id,
          cohort_id: co.id,
          group_jid: co.whatsapp_group_jid,
          group_name: co.whatsapp_group_name,
          reminder_type: "1h_before",
          scheduled_at: buildScheduledAt(target.isoDate, cls.time_start, 60),
          message_preview: body1h,
          zoom_link_snapshot: zoomLink,
          send_status: "pending",
        });
        sends.push({
          batch_id: batch.id,
          class_id: cls.id,
          cohort_id: co.id,
          group_jid: co.whatsapp_group_jid,
          group_name: co.whatsapp_group_name,
          reminder_type: "start",
          scheduled_at: buildScheduledAt(target.isoDate, cls.time_start, 0),
          message_preview: bodyStart,
          zoom_link_snapshot: zoomLink,
          send_status: "pending",
        });
      }
    }

    if (sends.length > 0) {
      const { error: insErr } = await sb.from("class_reminder_sends").insert(sends);
      if (insErr) throw insErr;
    }

    // Mark templates used (last_used_at + use_count++)
    for (const tplId of templatesUsed) {
      await markTemplateUsed(sb, tplId);
    }

    const realTotal = sends.filter((s) => s.send_status === "pending").length;
    await sb
      .from("class_reminder_batches")
      .update({ total_sends: realTotal, updated_at: new Date().toISOString() })
      .eq("id", batch.id);

    const { data: sendRows } = await sb
      .from("class_reminder_sends")
      .select("id, class_id, cohort_id, group_jid, group_name, reminder_type, scheduled_at, message_preview, send_status, error_detail")
      .eq("batch_id", batch.id)
      .order("scheduled_at");

    return new Response(
      JSON.stringify({
        success: true,
        batch_id: batch.id,
        target_date: target.isoDate,
        weekday: target.weekday,
        is_holiday: isHoliday,
        holiday_name: holidayName,
        total_pending: realTotal,
        total_sends: sendRows?.length ?? 0,
        sends: sendRows ?? [],
      }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    console.error("[prepare-class-reminders]", e);
    return new Response(
      JSON.stringify({ success: false, error: e instanceof Error ? e.message : String(e) }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }
});
