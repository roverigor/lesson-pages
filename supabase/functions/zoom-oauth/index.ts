// ═══════════════════════════════════════
// Edge Function: zoom-oauth
// Handles OAuth callback from Zoom
// Exchanges code for tokens and saves to zoom_tokens
// ═══════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const ZOOM_CLIENT_ID = Deno.env.get("ZOOM_CLIENT_ID") ?? "";
const ZOOM_CLIENT_SECRET = Deno.env.get("ZOOM_CLIENT_SECRET") ?? "";
const REDIRECT_URI = "https://lesson-pages.vercel.app/api/zoom/callback";

const ALLOWED_ORIGINS = [
  "https://lesson-pages.vercel.app",
  "https://calendario.igorrover.com.br",
];

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("origin") ?? "";
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGINS.includes(origin)
      ? origin
      : ALLOWED_ORIGINS[0],
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
}

function getSupabaseClient() {
  return createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: getCorsHeaders(req) });
  }

  try {
    const url = new URL(req.url);
    const action = url.searchParams.get("action");

    const sb = getSupabaseClient();

    // Action 1: Generate authorization URL — store state in DB with TTL (P-004)
    if (action === "authorize") {
      const mentorId = url.searchParams.get("mentor_id") || "";
      const state = crypto.randomUUID();

      // Persist state server-side; cleanup expired states
      await sb.rpc("cleanup_oauth_states");
      await sb.from("oauth_states").insert({ state, mentor_id: mentorId });

      const authUrl = `https://zoom.us/oauth/authorize?response_type=code&client_id=${ZOOM_CLIENT_ID}&redirect_uri=${encodeURIComponent(REDIRECT_URI)}&state=${state}`;
      return new Response(JSON.stringify({ url: authUrl }), {
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Action 2: Exchange code for tokens (called from callback page)
    if (action === "callback") {
      const body = await req.json();
      const { code, state } = body;

      if (!code) {
        return new Response(JSON.stringify({ ok: false, error: "No code provided" }), {
          status: 400, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // Validate state: must exist in DB and be < 10 minutes old (P-004)
      const { data: stateRow } = await sb.from("oauth_states")
        .select("mentor_id, created_at").eq("state", state).single();

      if (!stateRow) {
        return new Response(JSON.stringify({ ok: false, error: "Invalid or expired OAuth state. Please restart the authorization." }), {
          status: 400, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
        });
      }

      const ageMs = Date.now() - new Date(stateRow.created_at).getTime();
      if (ageMs > 10 * 60 * 1000) {
        await sb.from("oauth_states").delete().eq("state", state);
        return new Response(JSON.stringify({ ok: false, error: "OAuth state expired (> 10 min). Please restart." }), {
          status: 400, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
        });
      }

      // Consume state (one-time use)
      await sb.from("oauth_states").delete().eq("state", state);
      const mentorId = stateRow.mentor_id || null;

      // Exchange code for tokens
      const basicAuth = btoa(`${ZOOM_CLIENT_ID}:${ZOOM_CLIENT_SECRET}`);
      const tokenRes = await fetch("https://zoom.us/oauth/token", {
        method: "POST",
        headers: { "Authorization": `Basic ${basicAuth}`, "Content-Type": "application/x-www-form-urlencoded" },
        body: new URLSearchParams({ grant_type: "authorization_code", code, redirect_uri: REDIRECT_URI }),
      });

      if (!tokenRes.ok) {
        const err = await tokenRes.text();
        return new Response(JSON.stringify({ ok: false, error: `Zoom token error: ${err}` }), {
          status: 400, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
        });
      }

      const tokens = await tokenRes.json();

      // Get user info — fail loudly if unavailable (P-033)
      const userRes = await fetch("https://api.zoom.us/v2/users/me", {
        headers: { "Authorization": `Bearer ${tokens.access_token}` },
      });
      if (!userRes.ok) {
        return new Response(JSON.stringify({ ok: false, error: "Failed to fetch Zoom user info after token exchange." }), {
          status: 502, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
        });
      }
      const user = await userRes.json();

      // Calculate expiry
      const expiresAt = new Date(Date.now() + tokens.expires_in * 1000).toISOString();

      // Upsert token
      const { data, error } = await sb.from("zoom_tokens").upsert({
        zoom_email: user.email,
        zoom_account_id: user.account_id || null,
        mentor_id: mentorId || null,
        access_token: tokens.access_token,
        refresh_token: tokens.refresh_token,
        token_type: tokens.token_type || "Bearer",
        expires_at: expiresAt,
        scope: tokens.scope || "",
        active: true,
      }, { onConflict: "zoom_email" }).select().single();

      if (error) {
        return new Response(JSON.stringify({ ok: false, error: error.message }), {
          status: 500,
          headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
        });
      }

      return new Response(JSON.stringify({
        ok: true,
        email: user?.email,
        name: user?.first_name + " " + user?.last_name,
        mentor_id: mentorId,
      }), {
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    // Action 3: Refresh token
    if (action === "refresh") {
      const body = await req.json();
      const { zoom_email } = body;

      const sb = getSupabaseClient();
      const { data: token } = await sb.from("zoom_tokens")
        .select("*")
        .eq("zoom_email", zoom_email)
        .single();

      if (!token) {
        return new Response(JSON.stringify({ ok: false, error: "Token not found" }), {
          status: 404, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
        });
      }

      const basicAuth = btoa(`${ZOOM_CLIENT_ID}:${ZOOM_CLIENT_SECRET}`);
      const refreshRes = await fetch("https://zoom.us/oauth/token", {
        method: "POST",
        headers: {
          "Authorization": `Basic ${basicAuth}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({
          grant_type: "refresh_token",
          refresh_token: token.refresh_token,
        }),
      });

      if (!refreshRes.ok) {
        await sb.from("zoom_tokens").update({ active: false }).eq("id", token.id);
        return new Response(JSON.stringify({ ok: false, error: "Refresh failed, token deactivated" }), {
          status: 401, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
        });
      }

      const newTokens = await refreshRes.json();
      const expiresAt = new Date(Date.now() + newTokens.expires_in * 1000).toISOString();

      await sb.from("zoom_tokens").update({
        access_token: newTokens.access_token,
        refresh_token: newTokens.refresh_token,
        expires_at: expiresAt,
        scope: newTokens.scope || token.scope,
      }).eq("id", token.id);

      return new Response(JSON.stringify({ ok: true, access_token: newTokens.access_token }), {
        headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
      });
    }

    return new Response(JSON.stringify({ ok: false, error: "Unknown action" }), {
      status: 400, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
    });

  } catch (err) {
    return new Response(JSON.stringify({ ok: false, error: err instanceof Error ? err.message : "Unknown error" }), {
      status: 500, headers: { ...getCorsHeaders(req), "Content-Type": "application/json" },
    });
  }
});
