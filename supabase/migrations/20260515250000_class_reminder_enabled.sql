-- ============================================================================
-- Class reminder activation gate
-- Date: 2026-05-15
-- ============================================================================
-- Purpose:
--   - Add classes.reminder_enabled (default false)
--   - Set true só pras aulas que JÁ rodam dispatch hoje
--   - prepare-class-reminders filtra reminder_enabled=true
--   - Cron diário pinga Slack quando start_date=hoje E reminder_enabled=false
-- ============================================================================

BEGIN;

ALTER TABLE public.classes ADD COLUMN IF NOT EXISTS reminder_enabled boolean NOT NULL DEFAULT false;
COMMENT ON COLUMN public.classes.reminder_enabled IS 'Quando true, prepare-class-reminders gera batch pra essa aula. Default false — exige ativação manual ou via Slack alert no dia da próxima aula.';

-- Todas aulas começam reminder_enabled=false. User vai ativar via Slack ping
-- no dia da próxima ocorrência (PS Adv/Fund Ter, MS5 Qui, T5 Seg, T6 Sab, Adv T3 Qua).
-- Sem dispatch automático até confirmação humana.

COMMIT;
