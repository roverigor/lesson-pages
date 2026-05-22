-- ═══════════════════════════════════════════════════════════════════════════
-- Story 22.0 / ADR-019: nps_class_links.session_number_snapshot
--
-- Adiciona coluna pra imortalizar session_number no momento do dispatch.
-- Dispatcher dispatch-class-nps preenche esse valor; label histórica não muda
-- se cohort remarcar aulas depois.
--
-- DOWN: 20260522010100_nps_links_session_snapshot.down.sql
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.nps_class_links
  ADD COLUMN IF NOT EXISTS session_number_snapshot INT;

COMMENT ON COLUMN public.nps_class_links.session_number_snapshot IS
  'Session number capturado no momento do dispatch — imutável. NULL pra links históricos (pre-2026-05-22). Story 22.0 / ADR-019.';

CREATE INDEX IF NOT EXISTS idx_nps_links_session_snap
  ON public.nps_class_links(session_number_snapshot)
  WHERE session_number_snapshot IS NOT NULL;

COMMIT;
