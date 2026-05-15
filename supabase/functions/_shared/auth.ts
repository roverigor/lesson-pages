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
