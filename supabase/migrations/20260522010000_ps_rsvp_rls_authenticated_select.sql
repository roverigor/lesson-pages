-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: ps_rsvp_{links,responses} faltam policies SELECT pra authenticated.
-- RLS está ENABLE com policy só pra service_role → admin logado no painel
-- recebe [] vazio. Sem isso, /admin/nps-results/ não mostra respostas.
-- Padrão segue class_nps_responses (20260516010100).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE POLICY "ps_rsvp_links: read for auth"
  ON public.ps_rsvp_links FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "ps_rsvp_responses: read for auth"
  ON public.ps_rsvp_responses FOR SELECT
  TO authenticated USING (true);

COMMIT;
