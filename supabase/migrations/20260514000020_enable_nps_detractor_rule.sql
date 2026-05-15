-- ═══════════════════════════════════════════════════════════════════════════
-- Migration — Ativar automation_rule "NPS Detractor → Pendência CS"
-- Spec: docs/superpowers/specs/2026-05-14-encerramento-fundamentals-t4-design.md
--
-- Rule pré-built da Story 16.11 (migration 20260506120000) iniciou com
-- active=false. Encerramento T4 vai gerar respostas NPS — ativamos rule
-- pra worker pg_cron criar pendências internas em pending_student_assignments
-- quando aluno responde NPS <= 6.
--
-- Comportamento: ZERO envio externo automático. Só cria registro interno
-- pra CS rep contatar humanamente (alinha NON-NEGOTIABLE rule).
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_count int;
BEGIN
  -- Verifica rule existe
  SELECT count(*) INTO v_count
    FROM public.automation_rules
   WHERE name = 'NPS Detractor → Pendência CS';

  IF v_count = 0 THEN
    RAISE EXCEPTION 'Rule "NPS Detractor → Pendência CS" não encontrada. Migration 20260506120000_automation_rules deve ter sido aplicada antes.';
  END IF;

  -- Ativa
  UPDATE public.automation_rules
     SET active = true,
         updated_at = now()
   WHERE name = 'NPS Detractor → Pendência CS'
     AND active = false;

  RAISE NOTICE 'Rule NPS Detractor → Pendência CS ativada.';
END $$;
