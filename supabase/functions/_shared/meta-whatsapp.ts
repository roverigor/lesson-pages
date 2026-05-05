// ═══════════════════════════════════════════════════════════════════════════
// EPIC-015 Story 15.4 — Meta WhatsApp Cloud API helper (CON-10 extraction)
//
// Extraído de dispatch-survey/index.ts para reuso em:
//   - dispatch-survey (refactored)
//   - send-whatsapp
//   - send-whatsapp-reminder
//   - ac-purchase-webhook worker (futuro)
//
// Returns meta_message_id na response (necessário para correlação 15.I delivery webhook).
// ═══════════════════════════════════════════════════════════════════════════

const META_PHONE_NUMBER_ID = Deno.env.get("META_PHONE_NUMBER_ID") ?? "";
const META_API_KEY = Deno.env.get("META_API_KEY") ?? "";

// Fallback: Evolution API (legacy)
const EVOLUTION_API_URL = Deno.env.get("EVOLUTION_API_URL") ?? "";
const EVOLUTION_API_KEY = Deno.env.get("EVOLUTION_API_KEY") ?? "";
const EVOLUTION_INSTANCE = Deno.env.get("EVOLUTION_INSTANCE") ?? "";

const META_GRAPH_VERSION = "v21.0";

export interface MetaSendResult {
  success: boolean;
  messageId: string | null;
  error?: string;
}

/**
 * Envia mensagem WhatsApp via Meta Cloud API (texto plain).
 * Use dentro da janela 24h. Para fora janela, use sendWhatsAppTemplate.
 */
export async function sendWhatsApp(
  phone: string,
  message: string,
): Promise<MetaSendResult> {
  const digits = phone.replace(/\D/g, "");

  // Prefer Meta Cloud API
  if (META_PHONE_NUMBER_ID && META_API_KEY) {
    try {
      const res = await fetch(
        `https://graph.facebook.com/${META_GRAPH_VERSION}/${META_PHONE_NUMBER_ID}/messages`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${META_API_KEY}`,
          },
          body: JSON.stringify({
            messaging_product: "whatsapp",
            to: digits,
            type: "text",
            text: { body: message },
          }),
        },
      );

      if (res.ok) {
        const data = await res.json().catch(() => ({}));
        return {
          success: true,
          messageId: data?.messages?.[0]?.id ?? null,
        };
      }

      const errBody = await res.text();
      console.error(`[meta-whatsapp] API error: ${res.status} ${errBody}`);
      return { success: false, messageId: null, error: `${res.status}` };
    } catch (e) {
      console.error("[meta-whatsapp] exception:", e);
      return {
        success: false,
        messageId: null,
        error: e instanceof Error ? e.message : String(e),
      };
    }
  }

  // Fallback: Evolution API (legacy)
  if (EVOLUTION_API_URL && EVOLUTION_API_KEY) {
    try {
      const res = await fetch(
        `${EVOLUTION_API_URL}/message/sendText/${EVOLUTION_INSTANCE}`,
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            apikey: EVOLUTION_API_KEY,
          },
          body: JSON.stringify({
            number: digits + "@s.whatsapp.net",
            text: message,
          }),
        },
      );
      return { success: res.ok, messageId: null };
    } catch {
      return { success: false, messageId: null, error: "evolution_failed" };
    }
  }

  console.error("[meta-whatsapp] No WhatsApp provider configured");
  return { success: false, messageId: null, error: "no_provider" };
}

/**
 * Envia mensagem via Meta Template aprovado (bypass janela 24h).
 *
 * @param phone - número destino com ou sem formatação
 * @param templateName - nome do template aprovado em meta_templates
 * @param bodyParams - array de strings para placeholders {{1}}, {{2}}, ...
 * @param buttonUrlParams - array de strings para button URL params
 *
 * Retorna meta_message_id quando disponível (para 15.I delivery webhook).
 */
export async function sendWhatsAppTemplate(
  phone: string,
  templateName: string,
  bodyParams: string[] = [],
  buttonUrlParams: string[] = [],
  language = "pt_BR",
): Promise<MetaSendResult> {
  const digits = phone.replace(/\D/g, "");

  if (!META_PHONE_NUMBER_ID || !META_API_KEY) {
    console.error("[meta-whatsapp] Meta API not configured for template send");
    return {
      success: false,
      messageId: null,
      error: "meta_not_configured",
    };
  }

  const components: Record<string, unknown>[] = [];

  if (bodyParams.length > 0) {
    components.push({
      type: "body",
      parameters: bodyParams.map((p) => ({ type: "text", text: p })),
    });
  }

  if (buttonUrlParams.length > 0) {
    buttonUrlParams.forEach((param, idx) => {
      components.push({
        type: "button",
        sub_type: "url",
        index: idx.toString(),
        parameters: [{ type: "text", text: param }],
      });
    });
  }

  try {
    const res = await fetch(
      `https://graph.facebook.com/${META_GRAPH_VERSION}/${META_PHONE_NUMBER_ID}/messages`,
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${META_API_KEY}`,
        },
        body: JSON.stringify({
          messaging_product: "whatsapp",
          to: digits,
          type: "template",
          template: {
            name: templateName,
            language: { code: language },
            components,
          },
        }),
      },
    );

    if (res.ok) {
      const data = await res.json().catch(() => ({}));
      return {
        success: true,
        messageId: data?.messages?.[0]?.id ?? null,
      };
    }

    const errBody = await res.text();
    console.error(`[meta-whatsapp] Template API error: ${res.status} ${errBody}`);
    return { success: false, messageId: null, error: `${res.status}` };
  } catch (e) {
    console.error("[meta-whatsapp] Template exception:", e);
    return {
      success: false,
      messageId: null,
      error: e instanceof Error ? e.message : String(e),
    };
  }
}
