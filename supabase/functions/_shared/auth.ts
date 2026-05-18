// ═══════════════════════════════════════════════════════════════════════════
// EPIC-015 Story 15.1 — Shared auth helper for Edge Functions
// Reusable verifyAdminOrCs() — aceita role IN ('admin','cs') OR service_role.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY") ?? "";

export interface AuthResult {
  role: "admin" | "cs" | "service_role";
  userId: string;
  email?: string;
}

function decodeJwtRole(token: string): string | null {
  try {
    const parts = token.split(".");
    if (parts.length !== 3) return null;
    const payload = JSON.parse(
      atob(parts[1].replace(/-/g, "+").replace(/_/g, "/"))
    );
    return payload?.role ?? null;
  } catch {
    return null;
  }
}

/**
 * Verify JWT and return AuthResult if role is admin OR cs OR service_role.
 * Returns null if unauthorized.
 *
 * Usage:
 *   const auth = await verifyAdminOrCs(req.headers.get("Authorization"));
 *   if (!auth) return jsonResponse({ error: "unauthorized" }, 401);
 */
export async function verifyAdminOrCs(
  authHeader: string | null
): Promise<AuthResult | null> {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const token = authHeader.slice(7);

  // Service-role bypass (worker pg_cron, internal calls)
  if (decodeJwtRole(token) === "service_role") {
    return { role: "service_role", userId: "system" };
  }

  // Validate user JWT via Supabase Auth
  const client = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const {
    data: { user },
  } = await client.auth.getUser(token);

  const role = user?.user_metadata?.role;

  if (role === "admin" || role === "cs") {
    return {
      role: role as "admin" | "cs",
      userId: user!.id,
      email: user?.email,
    };
  }

  return null;
}

/**
 * Strict admin-only verification (legacy compat).
 * Use this when you specifically need to deny CS access.
 */
export async function verifyAdminStrict(
  authHeader: string | null
): Promise<AuthResult | null> {
  const auth = await verifyAdminOrCs(authHeader);
  if (!auth) return null;
  if (auth.role === "admin" || auth.role === "service_role") return auth;
  return null;
}

const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

/**
 * Timing-safe constant-time string compare.
 * Returns false immediately if lengths differ — sacrifices full timing safety
 * for that case but avoids cycling on huge inputs.
 */
function timingSafeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let result = 0;
  for (let i = 0; i < a.length; i++) {
    result |= a.charCodeAt(i) ^ b.charCodeAt(i);
  }
  return result === 0;
}

/**
 * Verify request carries service-role bearer token. Use this on internal
 * edge-function endpoints that should NEVER accept user JWTs (workers, cron,
 * retry helpers). Returns true only if `Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>`.
 *
 * NPS.D.3 — added per architect review 2026-05-17.
 *
 * Usage:
 *   if (!verifyServiceRole(req)) {
 *     return new Response(
 *       JSON.stringify({ error: "unauthorized" }),
 *       { status: 401, headers: { ...CORS, "Content-Type": "application/json" } },
 *     );
 *   }
 */
export function verifyServiceRole(req: Request): boolean {
  if (!SUPABASE_SERVICE_ROLE_KEY) {
    // Fail closed if env var missing — would otherwise allow empty bearer through
    console.error("[auth] SUPABASE_SERVICE_ROLE_KEY env var missing — denying all requests");
    return false;
  }
  const header = req.headers.get("authorization") ?? req.headers.get("Authorization") ?? "";
  const m = header.match(/^Bearer\s+(.+)$/i);
  if (!m) return false;
  const presented = m[1].trim();
  return timingSafeEqual(presented, SUPABASE_SERVICE_ROLE_KEY);
}
