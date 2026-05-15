// ═══════════════════════════════════════════════════════════════════════════
// EPIC-015 Story 15.B — ActiveCampaign utils (HMAC validation + payload helpers)
// ═══════════════════════════════════════════════════════════════════════════

/**
 * Validate HMAC SHA-256 signature.
 * Compatible com formato `sha256=<hex>` (GitHub-style) ou hex puro.
 *
 * Usage:
 *   const ok = await validateHmac(body, sig, AC_WEBHOOK_SECRET);
 */
export async function validateHmac(
  body: string,
  signature: string | null,
  secret: string,
): Promise<boolean> {
  if (!signature || !secret) return false;

  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const sigBuf = await crypto.subtle.sign("HMAC", key, encoder.encode(body));
  const expected = Array.from(new Uint8Array(sigBuf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  // Aceita ambos formatos
  const sigClean = signature.replace(/^sha256=/, "").trim();

  // Timing-safe compare
  if (sigClean.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < sigClean.length; i++) {
    diff |= sigClean.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

/**
 * Deriva idempotency key a partir do payload AC.
 * OQ-5: AC pode enviar event_id direto OU derivamos via order_id+contact_id+product_id.
 */
export function deriveAcEventId(payload: Record<string, unknown>): string {
  if (typeof payload.event_id === "string" && payload.event_id) {
    return payload.event_id;
  }

  const order = payload.order_id ?? payload.order ?? "no-order";
  const contact = payload.contact_id ?? payload.contact ?? "no-contact";
  const product = payload.product_id ?? payload.product ?? "no-product";
  const ts = payload.purchased_at ?? payload.created_at ?? "";

  return `${order}_${contact}_${product}_${ts}`.replace(/\s/g, "");
}

/**
 * Extrai campos canônicos do payload AC (defensivo — tolera variações).
 */
export interface AcPurchasePayload {
  email: string | null;
  phone: string | null;
  fullName: string | null;
  contactId: string | null;
  productId: string | null;
  orderId: string | null;
  purchasedAt: string | null;
}

export function parseAcPayload(payload: Record<string, unknown>): AcPurchasePayload {
  return {
    email: (payload.email as string) ?? null,
    phone: (payload.phone as string) ?? (payload.telephone as string) ?? null,
    fullName: ((payload.full_name as string) ?? (payload.name as string) ?? null) || null,
    contactId: (payload.contact_id as string) ?? (payload.contact as string) ?? null,
    productId: (payload.product_id as string) ?? (payload.product as string) ?? null,
    orderId: (payload.order_id as string) ?? (payload.order as string) ?? null,
    purchasedAt: (payload.purchased_at as string) ?? (payload.created_at as string) ?? null,
  };
}
