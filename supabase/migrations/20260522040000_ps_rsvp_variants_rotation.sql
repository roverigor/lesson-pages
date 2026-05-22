-- ═══════════════════════════════════════════════════════════════════════════
-- Rotação por DISPATCH (não por aluno) em ps_rsvp_variants.
-- Sequência: dispatch pega variant active mais antiga (last_used_at NULLS FIRST),
-- todos alunos da run recebem mesma variant. Final do dispatch atualiza
-- last_used_at = now(). Próximo dispatch pega outra automaticamente.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

ALTER TABLE public.ps_rsvp_variants
  ADD COLUMN IF NOT EXISTS last_used_at timestamptz;

COMMIT;
