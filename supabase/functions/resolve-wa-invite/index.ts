// resolve-wa-invite — Resolve WhatsApp invite code to group JID via Evolution API.
// GET ?code=<inviteCode> OR POST { code }
// Returns { jid, subject, owner }

// NOTE: this is a helper fn for one-time setup (invite code → JID).
// Read-only via Evolution API. JWT verification handled by deploy flag.
const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  let code: string | null = null;
  if (req.method === "GET") {
    const url = new URL(req.url);
    code = url.searchParams.get("code");
  } else if (req.method === "POST") {
    const body = await req.json().catch(() => ({}));
    code = body.code ?? null;
  }

  if (!code) return json({ error: "missing_code" }, 400);

  // Try multiple Evolution endpoints
  const candidates = [
    `${EVOLUTION_API_URL}/group/inviteInfo/${EVOLUTION_INSTANCE}?inviteCode=${code}`,
    `${EVOLUTION_API_URL}/group/findByInvite/${EVOLUTION_INSTANCE}?inviteCode=${code}`,
    `${EVOLUTION_API_URL}/group/inviteCode/${EVOLUTION_INSTANCE}?inviteCode=${code}`,
  ];

  for (const url of candidates) {
    try {
      const res = await fetch(url, { headers: { apikey: EVOLUTION_API_KEY } });
      const text = await res.text();
      if (!res.ok) continue;
      try {
        const data = JSON.parse(text);
        const jid = data.id ?? data.jid ?? data.groupJid ?? data.gid ?? null;
        if (jid) {
          return json({ ok: true, jid, subject: data.subject ?? data.name ?? null, owner: data.owner ?? null, raw_endpoint: url });
        }
        // Some Evolution variants nest result
        if (data.group?.id) {
          return json({ ok: true, jid: data.group.id, subject: data.group.subject ?? null, raw_endpoint: url });
        }
      } catch {
        // not JSON, continue
      }
    } catch (_e) {
      // continue
    }
  }

  return json({ error: "invite_resolution_failed", code }, 502);
});
