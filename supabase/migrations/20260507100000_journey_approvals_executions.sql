-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-018 Story 18.2a — Journey Approvals + Executions tables
-- Per ADR-018 decisão #10: comm externa via approval queue (NON-NEGOTIABLE).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.journey_pending_approvals (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journey_state_id uuid REFERENCES public.student_journey_states(id) ON DELETE CASCADE,
  step_num integer NOT NULL,
  action_type text NOT NULL,
  action_config jsonb NOT NULL,
  preview_data jsonb,
  status text DEFAULT 'awaiting_approval' CHECK (status IN ('awaiting_approval', 'approved', 'rejected', 'expired')),
  approved_by uuid REFERENCES auth.users(id),
  approved_at timestamptz,
  created_at timestamptz DEFAULT now(),
  expires_at timestamptz DEFAULT (now() + interval '7 days')
);

CREATE INDEX IF NOT EXISTS idx_journey_approvals_pending
  ON public.journey_pending_approvals (created_at)
  WHERE status = 'awaiting_approval';

CREATE INDEX IF NOT EXISTS idx_journey_approvals_expiring
  ON public.journey_pending_approvals (expires_at)
  WHERE status = 'awaiting_approval';

ALTER TABLE public.journey_pending_approvals ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cs_admin_read_approvals" ON public.journey_pending_approvals FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));
CREATE POLICY "cs_admin_update_approvals" ON public.journey_pending_approvals FOR UPDATE
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));
GRANT SELECT, UPDATE ON public.journey_pending_approvals TO authenticated;
GRANT INSERT ON public.journey_pending_approvals TO service_role;

-- ─── journey_executions log ─────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.journey_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  journey_state_id uuid REFERENCES public.student_journey_states(id) ON DELETE CASCADE,
  step_num integer NOT NULL,
  trigger_evaluated text,
  action_attempted text,
  action_result text CHECK (action_result IN ('executed', 'queued_approval', 'skipped_capping', 'skipped_paused', 'failed')),
  result_meta jsonb,
  executed_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_journey_executions_state
  ON public.journey_executions (journey_state_id, executed_at DESC);

ALTER TABLE public.journey_executions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cs_admin_read_executions" ON public.journey_executions FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));
GRANT SELECT ON public.journey_executions TO authenticated;
GRANT INSERT ON public.journey_executions TO service_role;

-- ─── ALTER student_journey_states observability ─────────────────────────
ALTER TABLE public.student_journey_states
  ADD COLUMN IF NOT EXISTS auto_pause_count integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS escalation_count integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS last_action_at timestamptz;

-- ─── Auto-expire approvals após 7 dias ──────────────────────────────────
CREATE OR REPLACE FUNCTION public.expire_old_approvals()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE v_count integer;
BEGIN
  UPDATE public.journey_pending_approvals
  SET status = 'expired'
  WHERE status = 'awaiting_approval' AND expires_at <= now();
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('expired', v_count, 'at', now());
END $$;

GRANT EXECUTE ON FUNCTION public.expire_old_approvals() TO service_role;

SELECT cron.schedule('epic018-expire-approvals', '0 * * * *',
  $$ SELECT public.expire_old_approvals(); $$
) WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'epic018-expire-approvals');

COMMENT ON TABLE public.journey_pending_approvals IS
  'EPIC-018 Story 18.2a — Approval queue ADR-018 decisão #10. Worker journey enfileira aqui antes de actions externas; CS rep aprova via /cs/approvals.';
