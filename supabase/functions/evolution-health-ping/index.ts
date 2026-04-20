import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { sendDM } from "../_shared/slack.ts";

/**
 * Evolution API Health Ping
 * Called by pg_cron once daily at 09:00 BRT to verify Evolution API (WhatsApp) is reachable.
 * If unreachable or disconnected, sends Slack DM alert to Igor.
 * If Slack fails, logs the error (no WA fallback since WA is what's being checked).
 */

const EVO_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVO_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVO_INST = Deno.env.get("EVOLUTION_INSTANCE") ?? "";
const SLACK_IGOR = Deno.env.get("SLACK_IGOR_USER_ID") ?? "";

serve(async (req) => {
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  };
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  const now = new Date().toISOString();
  let status = "unknown";
  let error: string | null = null;
  let alertSent = false;

  // ── 1. Ping Evolution API ──
  if (!EVO_URL || !EVO_KEY || !EVO_INST) {
    status = "not_configured";
    error = "Evolution API env vars missing";
  } else {
    try {
      const res = await fetch(
        `${EVO_URL}/instance/connectionState/${EVO_INST}`,
        {
          headers: { apikey: EVO_KEY },
          signal: AbortSignal.timeout(15000),
        }
      );

      if (!res.ok) {
        status = `http_${res.status}`;
        error = `Evolution API returned HTTP ${res.status}`;
      } else {
        const data = await res.json();
        const connState = data?.instance?.state ?? data?.state ?? "unknown";
        status = connState;

        if (connState !== "open" && connState !== "connected") {
          error = `Instance "${EVO_INST}" state: ${connState}`;
        }
      }
    } catch (e) {
      status = "unreachable";
      error = e instanceof Error ? e.message : "network/timeout error";
    }
  }

  // ── 2. Alert if problems detected ──
  if (error && SLACK_IGOR) {
    const msg = [
      `🚨 *Evolution API — WhatsApp Offline*`,
      ``,
      `📱 Status: \`${status}\``,
      `❌ ${error}`,
      `🕐 ${now}`,
      ``,
      `_Lembretes de WhatsApp NÃO serão entregues até resolver._`,
      ``,
      `*Ações sugeridas:*`,
      `• Verificar VPS: \`ssh -i ~/.ssh/contabo root@194.163.179.68\``,
      `• Checar container: \`docker ps | grep evolution\``,
      `• Logs: \`docker logs evolution-api --tail 50\``,
      `• Reconectar QR: acessar painel Evolution API`,
    ].join("\n");

    try {
      await sendDM(SLACK_IGOR, msg);
      alertSent = true;
    } catch (e) {
      console.error("Failed to send Slack alert:", e);
    }
  }

  // ── 3. Log result ──
  const result = {
    ok: !error,
    status,
    error,
    alert_sent: alertSent,
    timestamp: now,
    instance: EVO_INST,
  };
  console.log("evolution-health-ping:", JSON.stringify(result));

  return new Response(JSON.stringify(result), {
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
});
