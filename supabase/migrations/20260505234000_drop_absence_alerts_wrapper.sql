-- ═══════════════════════════════════════════════════════════════════════════
-- DROP send_absence_alerts_now() wrapper function
--
-- Decisão: dispatch automático de WhatsApp pra alunos REQUER autorização humana
-- explícita no momento da execução. Wrapper removido pra evitar dispatch acidental.
--
-- Cron job zoom-absence-alert já foi desagendado via cron.unschedule().
--
-- Function get_consecutive_absences_needing_alert() MANTIDA (read-only utility,
-- útil pra dashboards de visibilidade).
--
-- Re-implementação no futuro DEVE incluir aprovação humana inline (ex: UI button
-- "Disparar alertas agora" com preview da lista + confirmação antes do envio).
-- ═══════════════════════════════════════════════════════════════════════════

DROP FUNCTION IF EXISTS public.send_absence_alerts_now();
