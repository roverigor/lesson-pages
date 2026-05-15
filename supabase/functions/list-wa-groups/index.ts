// list-wa-groups — Lista todos os grupos WhatsApp da instância Evolution
// GET / POST → retorna [{ id, subject, owner, size, ... }]
// Usado pra descobrir JIDs e mapear pra cohorts.

const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  if (!EVOLUTION_API_URL || !EVOLUTION_API_KEY || !EVOLUTION_INSTANCE) {
    return new Response(
      JSON.stringify({ success: false, error: "evolution_env_missing" }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }

  try {
    const url = `${EVOLUTION_API_URL}/group/fetchAllGroups/${EVOLUTION_INSTANCE}?getParticipants=false`;
    const res = await fetch(url, {
      headers: { apikey: EVOLUTION_API_KEY },
    });
    const text = await res.text();
    if (!res.ok) {
      return new Response(
        JSON.stringify({ success: false, status: res.status, error: text.slice(0, 500) }),
        { status: 502, headers: { ...CORS, "Content-Type": "application/json" } },
      );
    }
    const data = JSON.parse(text);
    const groups = Array.isArray(data) ? data : data.groups ?? [];
    const simplified = groups.map((g: Record<string, unknown>) => ({
      jid: g.id ?? g.remoteJid ?? g.groupJid,
      subject: g.subject ?? g.name ?? g.subjectOwner,
      size: g.size ?? g.participantsCount ?? (Array.isArray(g.participants) ? g.participants.length : null),
      owner: g.owner ?? g.subjectOwner,
      creation: g.creation ?? g.createdAt,
    }));
    return new Response(
      JSON.stringify({ success: true, total: simplified.length, groups: simplified }),
      { status: 200, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(
      JSON.stringify({ success: false, error: e instanceof Error ? e.message : String(e) }),
      { status: 500, headers: { ...CORS, "Content-Type": "application/json" } },
    );
  }
});
