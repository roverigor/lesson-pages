// ═══════════════════════════════════════════════════════════════════════════
// Evolution API helper — group message dispatch
// Reuse pra class reminders + outras integrações grupo
// ═══════════════════════════════════════════════════════════════════════════

const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";

export interface EvolutionGroupResult {
  success: boolean;
  messageId: string | null;
  error?: string;
}

/**
 * Envia texto pra grupo WhatsApp via Evolution API.
 *
 * @param groupJid — JID do grupo (com ou sem sufixo @g.us)
 * @param text — corpo da mensagem
 */
export async function sendEvolutionGroupText(
  groupJid: string,
  text: string,
): Promise<EvolutionGroupResult> {
  if (!EVOLUTION_API_URL || !EVOLUTION_API_KEY || !EVOLUTION_INSTANCE) {
    return { success: false, messageId: null, error: "evolution_env_missing" };
  }

  const jid = groupJid.includes("@g.us") ? groupJid : `${groupJid}@g.us`;

  try {
    const res = await fetch(
      `${EVOLUTION_API_URL}/message/sendText/${EVOLUTION_INSTANCE}`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          apikey: EVOLUTION_API_KEY,
        },
        body: JSON.stringify({ number: jid, text }),
      },
    );

    if (!res.ok) {
      const body = await res.text();
      return {
        success: false,
        messageId: null,
        error: `evolution_http_${res.status}: ${body.slice(0, 200)}`,
      };
    }

    const data = await res.json().catch(() => ({}));
    const messageId =
      data?.key?.id ?? data?.messageId ?? data?.message?.id ?? null;
    return { success: true, messageId };
  } catch (e) {
    return {
      success: false,
      messageId: null,
      error: `evolution_exception: ${e instanceof Error ? e.message : String(e)}`,
    };
  }
}
