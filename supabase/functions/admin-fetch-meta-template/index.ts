// Quick read-only: fetch Meta template body for given names.
import { sendEvolutionGroupText as _ignore } from "../_shared/evolution-group.ts";

const META_API_KEY = Deno.env.get("META_API_KEY") ?? "";
const META_WABA_ID = Deno.env.get("META_WABA_ID") ?? "";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("POST only", { status: 405 });
  const adminToken = Deno.env.get("ADMIN_ONE_SHOT_TOKEN") ?? "";
  if ((req.headers.get("x-admin-token") ?? "") !== adminToken) {
    return new Response("unauthorized", { status: 401 });
  }

  const { names } = await req.json();
  if (!Array.isArray(names) || names.length === 0) {
    return new Response("missing names[]", { status: 400 });
  }

  const url = `https://graph.facebook.com/v21.0/${META_WABA_ID}/message_templates?limit=200&fields=name,language,status,category,components`;
  const res = await fetch(url, { headers: { Authorization: `Bearer ${META_API_KEY}` } });
  if (!res.ok) return new Response(`meta_${res.status}: ${await res.text()}`, { status: 502 });
  const data = await res.json();
  const filtered = (data.data ?? []).filter((t: any) => names.includes(t.name));
  return new Response(JSON.stringify(filtered, null, 2), {
    headers: { "Content-Type": "application/json" },
  });
});
