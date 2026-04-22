/**
 * send-whatsapp-reminder — Send class reminders via WhatsApp (Evolution API)
 * Mirror of send-slack-reminder: queries today's class assignments and sends
 * personalized WhatsApp messages to mentors with the Zoom link.
 *
 * POST body (optional):
 *   { "dry_run": true }  — preview messages without sending
 */
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function sendEvolutionText(phone: string, text: string): Promise<void> {
  if (!EVOLUTION_API_URL || !EVOLUTION_API_KEY || !EVOLUTION_INSTANCE) {
    throw new Error("Evolution API env vars not set (EVOLUTION_API_URL/KEY/INSTANCE)");
  }
  const digits = phone.replace(/\D/g, "");
  const url = `${EVOLUTION_API_URL}/message/sendText/${EVOLUTION_INSTANCE}`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: EVOLUTION_API_KEY,
    },
    body: JSON.stringify({ number: digits, text }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Evolution API HTTP ${res.status}: ${body}`);
  }
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

    const now = new Date();
    const brt = new Date(now.toLocaleString("en-US", { timeZone: "America/Sao_Paulo" }));
    const todayDow = brt.getDay();
    const todayISO = brt.toISOString().split("T")[0];

    const { data: classRows, error: cErr } = await sb
      .from("classes")
      .select(`
        id, name, time_start, time_end, zoom_link, active,
        class_mentors!inner(weekday, role, valid_from, valid_until,
          mentors!inner(id, name, phone)
        )
      `)
      .eq("active", true)
      .lte("start_date", todayISO)
      .gte("end_date", todayISO);

    if (cErr) throw cErr;

    const flatRows: Array<Record<string, any>> = [];
    for (const c of classRows || []) {
      for (const cm of (c as any).class_mentors || []) {
        if (cm.weekday !== todayDow) continue;
        if (cm.valid_from && todayISO < cm.valid_from) continue;
        if (cm.valid_until && todayISO > cm.valid_until) continue;
        const m = cm.mentors;
        if (!m || !m.phone) continue;
        flatRows.push({
          class_id: c.id,
          class_name: c.name,
          time_start: c.time_start,
          time_end: c.time_end,
          zoom_link: c.zoom_link,
          mentor_id: m.id,
          mentor_name: m.name,
          mentor_phone: m.phone,
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

    const mentorMap = new Map<string, {
      mentor_name: string;
      mentor_phone: string;
      classes: Array<{ class_name: string; role: string; time_start: string; time_end: string; zoom_link: string }>;
    }>();

    for (const r of flatRows) {
      const key = r.mentor_phone;
      if (!mentorMap.has(key)) {
        mentorMap.set(key, {
          mentor_name: r.mentor_name,
          mentor_phone: r.mentor_phone,
          classes: [],
        });
      }
      mentorMap.get(key)!.classes.push({
        class_name: r.class_name,
        role: r.mentor_role,
        time_start: r.time_start?.substring(0, 5) || "",
        time_end: r.time_end?.substring(0, 5) || "",
        zoom_link: r.zoom_link || "",
      });
    }

    const roleEmoji: Record<string, string> = {
      Professor: "\u{1F468}‍\u{1F3EB}",
      Host: "\u{1F399}️",
      Mentor: "\u{1F9D1}‍\u{1F91D}‍\u{1F9D1}",
    };

    const results: Array<{ name: string; phone: string; status: string; message?: string }> = [];

    for (const [, mentor] of mentorMap) {
      let text = `Olá, ${mentor.mentor_name}! \u{1F44B}\n\n`;
      if (mentor.classes.length === 1) {
        const c = mentor.classes[0];
        const emoji = roleEmoji[c.role] || "\u{1F4CC}";
        text += `Você está escalado(a) hoje como ${emoji} *${c.role}* na aula:\n\n`;
        text += `\u{1F4DA} *${c.class_name}* — ${c.time_start} às ${c.time_end}\n`;
        if (c.zoom_link) text += `\u{1F517} ${c.zoom_link}`;
      } else {
        text += `Você está escalado(a) hoje nas seguintes aulas:\n\n`;
        for (const c of mentor.classes) {
          const emoji = roleEmoji[c.role] || "\u{1F4CC}";
          text += `${emoji} *${c.role}* — \u{1F4DA} *${c.class_name}* (${c.time_start}–${c.time_end})\n`;
          if (c.zoom_link) text += `\u{1F517} ${c.zoom_link}\n`;
          text += `\n`;
        }
      }

      if (dryRun) {
        results.push({ name: mentor.mentor_name, phone: mentor.mentor_phone, status: "dry_run", message: text });
      } else {
        try {
          await sendEvolutionText(mentor.mentor_phone, text);
          results.push({ name: mentor.mentor_name, phone: mentor.mentor_phone, status: "sent" });
          await new Promise((r) => setTimeout(r, 1200));
        } catch (e) {
          results.push({ name: mentor.mentor_name, phone: mentor.mentor_phone, status: "failed", message: (e as Error).message });
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
    console.error("send-whatsapp-reminder error:", e);
    return new Response(
      JSON.stringify({ error: (e as Error).message }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  }
});
