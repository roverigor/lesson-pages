// ═══════════════════════════════════════════════════════════════════════════
// safeSendGroup — wrapper idempotente sobre sendEvolutionGroupText
// Guardrail: grava em group_dispatch_log ANTES do envio.
// Unique idx (group_jid, content_hash, sent_date) — 2ª tentativa do mesmo
// conteúdo pro mesmo grupo no mesmo dia retorna {success:true, skipped:true}.
// ═══════════════════════════════════════════════════════════════════════════

import { sendEvolutionGroupText, type EvolutionGroupResult } from "./evolution-group.ts";

async function sha256Hex(text: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return Array.from(new Uint8Array(buf)).map((b) => b.toString(16).padStart(2, "0")).join("");
}

export interface SafeGroupResult extends EvolutionGroupResult {
  skipped?: boolean;
  skipped_reason?: string;
}

/**
 * Envia mensagem pra grupo APENAS se ainda não enviou no mesmo dia.
 *
 * @param sb — Supabase client (service role)
 * @param groupJid — JID do grupo
 * @param text — conteúdo
 * @param source — identificador do dispatcher (ex: 'dispatch-class-nps')
 * @param referenceId — opcional, link/job ID pra audit
 */
export async function safeSendGroup(
  // deno-lint-ignore no-explicit-any
  sb: any,
  groupJid: string,
  text: string,
  source: string,
  referenceId?: string | null,
): Promise<SafeGroupResult> {
  const hash = await sha256Hex(`${groupJid}|${text}`);

  // Tenta gravar log ANTES do envio. Unique idx bloqueia duplicates.
  const { data: logRow, error: logErr } = await sb
    .from("group_dispatch_log")
    .insert({
      group_jid: groupJid,
      content_hash: hash,
      source,
      reference_id: referenceId ?? null,
    })
    .select("id")
    .maybeSingle();

  // PostgreSQL 23505 = unique_violation → mesmo conteúdo já enviado hoje pra esse grupo
  if (logErr && (logErr as { code?: string }).code === "23505") {
    return {
      success: true,
      messageId: null,
      skipped: true,
      skipped_reason: "duplicate_same_day",
    };
  }
  if (logErr) {
    return { success: false, messageId: null, error: `log_insert_failed: ${logErr.message}` };
  }

  // Log OK → envia pra Evolution
  const result = await sendEvolutionGroupText(groupJid, text);

  // Update log com message_id pra audit
  if (logRow?.id) {
    await sb.from("group_dispatch_log")
      .update({
        evolution_message_id: result.messageId,
        metadata: { success: result.success, error: result.error ?? null },
      })
      .eq("id", logRow.id);
  }

  return result;
}
