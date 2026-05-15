// ═══════════════════════════════════════════════════════════════════════════
// EPIC-015 Story 15.8 — sync-meta-templates
// Fetch templates aprovados via Meta Graph API + UPSERT em meta_templates.
//
// Auth: admin OR cs.
// Refs: FR-15, OQ-8, AC-3 spec story 15.8
// ═══════════════════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";
import { verifyAdminOrCs } from "../_shared/auth.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const META_WABA_ID = Deno.env.get("META_WABA_ID") ?? "";
const META_API_KEY = Deno.env.get("META_API_KEY") ?? "";
const META_GRAPH_VERSION = "v21.0";

const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { autoRefreshToken: false, persistSession: false },
});

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

interface MetaTemplate {
  id: string;
  name: string;
  language: string;
  status: string;
  category: string;
  components?: Array<{
    type: string;
    text?: string;
    example?: { body_text?: string[][] };
    buttons?: Array<{ type: string }>;
  }>;
  created_time?: string;
}

function countBodyParams(template: MetaTemplate): number {
  const body = template.components?.find((c) => c.type === "BODY");
  if (!body?.text) return 0;
  // Count {{N}} placeholders
  const matches = body.text.match(/\{\{\d+\}\}/g);
  return matches?.length ?? 0;
}

function countButtons(template: MetaTemplate): number {
  const buttons = template.components?.find((c) => c.type === "BUTTONS");
  return buttons?.buttons?.length ?? 0;
}

function mapStatus(metaStatus: string): string {
  const s = metaStatus.toUpperCase();
  if (s === "APPROVED") return "active";
  if (s === "REJECTED") return "rejected";
  if (s === "PAUSED") return "paused";
  if (s === "PENDING" || s === "IN_APPEAL" || s === "PENDING_DELETION") return "pending";
  return "pending";
}

function mapCategory(metaCategory: string): string {
  const c = metaCategory.toUpperCase();
  if (c === "MARKETING") return "MARKETING";
  if (c === "UTILITY") return "UTILITY";
  if (c === "AUTHENTICATION") return "AUTHENTICATION";
  return "MARKETING";
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { status: 204, headers: CORS_HEADERS });
  }

  if (req.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405);
  }

  // Auth: admin OR cs
  const auth = await verifyAdminOrCs(req.headers.get("Authorization"));
  if (!auth) return jsonResponse({ error: "unauthorized" }, 401);

  if (!META_WABA_ID || !META_API_KEY) {
    return jsonResponse({ error: "meta_config_missing", detail: "META_WABA_ID + META_API_KEY required" }, 500);
  }

  try {
    // Graph API: GET /{WABA_ID}/message_templates
    const url = `https://graph.facebook.com/${META_GRAPH_VERSION}/${META_WABA_ID}/message_templates?limit=200&fields=id,name,language,status,category,components,created_time`;
    const res = await fetch(url, {
      headers: { Authorization: `Bearer ${META_API_KEY}` },
    });

    if (!res.ok) {
      const errText = await res.text().catch(() => "");
      return jsonResponse({
        error: "meta_api_error",
        status: res.status,
        detail: errText.slice(0, 500),
      }, 502);
    }

    const json = await res.json();
    const templates = (json.data ?? []) as MetaTemplate[];

    if (templates.length === 0) {
      return jsonResponse({ synced: 0, message: "no_templates_found" });
    }

    // UPSERT por name (UNIQUE)
    const upserts = templates.map((t) => ({
      name: t.name,
      language: t.language || "pt_BR",
      category: mapCategory(t.category ?? "MARKETING"),
      body_params_count: countBodyParams(t),
      button_count: countButtons(t),
      status: mapStatus(t.status),
      approved_at: t.status?.toUpperCase() === "APPROVED" ? (t.created_time ?? null) : null,
      updated_at: new Date().toISOString(),
    }));

    const { error } = await sb.from("meta_templates").upsert(upserts, { onConflict: "name" });
    if (error) {
      console.error("[sync-meta-templates] upsert error:", error);
      return jsonResponse({ error: "db_error", detail: error.message }, 500);
    }

    console.log(`[sync-meta-templates] synced ${upserts.length} templates`);

    return jsonResponse({
      synced: upserts.length,
      breakdown: {
        active: upserts.filter((t) => t.status === "active").length,
        paused: upserts.filter((t) => t.status === "paused").length,
        rejected: upserts.filter((t) => t.status === "rejected").length,
        pending: upserts.filter((t) => t.status === "pending").length,
      },
    });
  } catch (e) {
    console.error("[sync-meta-templates] exception:", e);
    return jsonResponse({
      error: "exception",
      detail: e instanceof Error ? e.message : String(e),
    }, 500);
  }
});
