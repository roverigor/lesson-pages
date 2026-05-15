// ═══════════════════════════════════════════════════════════════════════════
// dispatch-retry — Re-trigger a single dispatch identified by (source, id).
//
// Invoked by retry_dispatch RPC (PostgreSQL) via pg_net.http_post with body:
//   { source, dispatch_id, audit_id, retried_by }
//
// V1: supports notification + class_reminder. Other sources return not_supported.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const CORS: Record<string, string> = {
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

  let body: { source?: string; dispatch_id?: string; audit_id?: string; retried_by?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  const source = body.source;
  const dispatch_id = body.dispatch_id;
  const audit_id = body.audit_id;

  if (!source || !dispatch_id || !audit_id) {
    return json({ error: "missing_fields" }, 400);
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  const updateAudit = async (result: Record<string, unknown>) => {
    await sb.from("dispatch_retry_audit").update({ result }).eq("id", audit_id);
  };

  try {
    if (source === "class_reminder") {
      const { data: row } = await sb
        .from("class_reminder_sends")
        .select("id, batch_id, send_status")
        .eq("id", dispatch_id)
        .maybeSingle();

      if (!row) {
        await updateAudit({ ok: false, reason: "row_not_found" });
        return json({ ok: false });
      }
      if (row.send_status !== "failed") {
        await updateAudit({ ok: false, reason: "not_failed_anymore", current_status: row.send_status });
        return json({ ok: false });
      }

      await sb
        .from("class_reminder_sends")
        .update({ send_status: "pending", error_detail: null })
        .eq("id", dispatch_id);

      const r = await fetch(`${SUPABASE_URL}/functions/v1/dispatch-class-reminders`, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ batch_id: row.batch_id }),
      });

      await updateAudit({ ok: r.ok, status: r.status });
      return json({ ok: r.ok });
    }

    if (source === "notification") {
      const { data: row } = await sb
        .from("notifications")
        .select("id, status")
        .eq("id", dispatch_id)
        .maybeSingle();

      if (!row) {
        await updateAudit({ ok: false, reason: "row_not_found" });
        return json({ ok: false });
      }
      if (row.status !== "failed") {
        await updateAudit({ ok: false, reason: "not_failed_anymore" });
        return json({ ok: false });
      }

      await sb.from("notifications").update({ status: "pending" }).eq("id", dispatch_id);
      await updateAudit({ ok: true, action: "marked_pending_for_worker" });
      return json({ ok: true });
    }

    if (source === "survey_link") {
      await updateAudit({ ok: false, reason: "retry_not_supported_for_survey_link_v1" });
      return json({ ok: false, error: "not_supported" }, 501);
    }

    if (source === "nps_class_link") {
      await updateAudit({ ok: false, reason: "retry_not_applicable_for_nps_class_link" });
      return json({ ok: false, error: "not_applicable" }, 501);
    }

    await updateAudit({ ok: false, reason: "unknown_source" });
    return json({ error: "unknown_source" }, 400);
  } catch (e) {
    await updateAudit({ ok: false, reason: "exception", error: String(e) });
    return json({ error: "internal_error" }, 500);
  }
});
