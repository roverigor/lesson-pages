// fetch-group-invite-links — Busca invite code via Evolution pra cada cohort com JID
// Salva em cohorts.whatsapp_group_link

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

async function fetchInvite(jid: string): Promise<{ link: string | null; raw: string }> {
  const cleanJid = jid.replace("@g.us", "");
  // Common Evolution v2 path
  const url = `${EVOLUTION_API_URL}/group/inviteCode/${EVOLUTION_INSTANCE}?groupJid=${cleanJid}@g.us`;
  const res = await fetch(url, { headers: { apikey: EVOLUTION_API_KEY } });
  const text = await res.text();
  if (!res.ok) return { link: null, raw: text.slice(0, 200) };
  try {
    const data = JSON.parse(text);
    const code = data.inviteCode ?? data.code ?? data.invite ?? null;
    const link = data.inviteUrl ?? data.url ?? (code ? `https://chat.whatsapp.com/${code}` : null);
    return { link, raw: text.slice(0, 100) };
  } catch {
    return { link: null, raw: text.slice(0, 200) };
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  const body = await req.json().catch(() => ({}));
  const onlyCohortId: string | undefined = body.cohort_id;
  const overwrite = body.overwrite === true;

  let q = sb.from("cohorts").select("id, name, whatsapp_group_jid, whatsapp_group_link").not("whatsapp_group_jid", "is", null);
  if (onlyCohortId) q = q.eq("id", onlyCohortId);
  const { data: cohorts, error } = await q;
  if (error) {
    return new Response(JSON.stringify({ success: false, error: error.message }), {
      status: 500, headers: { ...CORS, "Content-Type": "application/json" },
    });
  }

  const results: Record<string, unknown>[] = [];
  for (const co of cohorts ?? []) {
    if (co.whatsapp_group_link && !overwrite) {
      results.push({ cohort: co.name, skipped: true, link: co.whatsapp_group_link });
      continue;
    }
    const { link, raw } = await fetchInvite(co.whatsapp_group_jid);
    if (link) {
      await sb.from("cohorts").update({ whatsapp_group_link: link }).eq("id", co.id);
      results.push({ cohort: co.name, link });
    } else {
      results.push({ cohort: co.name, link: null, error: raw });
    }
    await new Promise((r) => setTimeout(r, 500));
  }

  return new Response(JSON.stringify({ success: true, results }), {
    status: 200, headers: { ...CORS, "Content-Type": "application/json" },
  });
});
