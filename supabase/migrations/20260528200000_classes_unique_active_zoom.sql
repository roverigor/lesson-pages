-- ═══════════════════════════════════════════════════════════════════════════
-- Fix 1 (Story 22.10) — UNIQUE parcial: 1 turma ativa por zoom_meeting_id
--
-- Incidente 27/05: 2 classes com mesmo zoom_meeting_id (uma DUP-DESATIVADA
-- com active=false sem cohorts, uma ativa). Trigger pegou DUP → 0 enqueues.
--
-- Paliativo aplicado em 20260528120000: trigger filtra c.active=true.
-- Esta migration é a GARANTIA ESTRUTURAL: banco bloqueia criar 2 turmas
-- ativas com mesmo zoom_meeting_id. Defesa em profundidade.
--
-- Pré-requisito (verificado 28/05): SELECT zoom_meeting_id, count(*)
--   FROM classes WHERE active=true AND zoom_meeting_id IS NOT NULL
--   GROUP BY 1 HAVING count(*) > 1 → [] (zero conflitos atuais).
--
-- CONCURRENTLY pra não lockar tabela durante create.
-- Rollback: DROP INDEX uq_classes_active_zoom_meeting;
-- ═══════════════════════════════════════════════════════════════════════════

CREATE UNIQUE INDEX CONCURRENTLY IF NOT EXISTS uq_classes_active_zoom_meeting
  ON public.classes (zoom_meeting_id)
  WHERE active = true AND zoom_meeting_id IS NOT NULL;

COMMENT ON INDEX public.uq_classes_active_zoom_meeting IS
  'Story 22.10 Fix 1: garante 1 turma ativa por zoom_meeting_id. Banco bloqueia INSERT/UPDATE que cria duplicata. Defesa estrutural complementa trigger filter c.active=true (migration 20260528120000).';
