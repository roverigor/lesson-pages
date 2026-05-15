-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-018 Stories 18.2b/c/d/e — Journey Engine Worker + Triggers
-- Per ADR-018 spec completo. Auto-enroll + process state machine + approval execution.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 1. Adicionar journey_id em ac_product_mappings (Story 18.2c dep) ───
ALTER TABLE public.ac_product_mappings
  ADD COLUMN IF NOT EXISTS journey_id uuid REFERENCES public.journeys(id);

CREATE INDEX IF NOT EXISTS idx_mappings_journey ON public.ac_product_mappings (journey_id) WHERE journey_id IS NOT NULL;

-- ─── 2. Trigger enroll_student_in_journeys() ────────────────────────────
-- AFTER UPDATE ac_purchase_events status='processed' → cria student_journey_states
CREATE OR REPLACE FUNCTION public.enroll_student_in_journeys()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_student_id uuid;
  v_product_id text;
BEGIN
  IF NEW.status != 'processed' OR (OLD.status = 'processed') THEN
    RETURN NEW;
  END IF;

  v_student_id := (NEW.payload->>'student_id')::uuid;
  v_product_id := COALESCE(NEW.payload->>'product_external_id', NEW.payload->>'product_id');

  IF v_student_id IS NULL THEN RETURN NEW; END IF;

  -- Auto-enroll em journeys ativas linked ao product via mapping
  INSERT INTO public.student_journey_states (
    student_id, journey_id, total_steps, next_eval_at, status
  )
  SELECT
    v_student_id,
    j.id,
    jsonb_array_length(j.steps),
    now() + interval '1 minute',  -- worker pega imediato
    'active'
  FROM public.journeys j
  WHERE j.active = true
    AND j.id IN (
      SELECT journey_id FROM public.ac_product_mappings
      WHERE ac_product_id = v_product_id AND journey_id IS NOT NULL AND active = true
    )
  ON CONFLICT (student_id, journey_id) DO NOTHING;

  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_enroll_journeys ON public.ac_purchase_events;
CREATE TRIGGER trg_enroll_journeys
  AFTER UPDATE ON public.ac_purchase_events
  FOR EACH ROW EXECUTE FUNCTION public.enroll_student_in_journeys();

-- ─── 3. Worker process_journey_states() (Story 18.2b) ──────────────────
CREATE OR REPLACE FUNCTION public.process_journey_states()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_state RECORD;
  v_journey RECORD;
  v_step jsonb;
  v_action text;
  v_can_dispatch jsonb;
  v_capping_check boolean;
  v_processed integer := 0;
  v_executed integer := 0;
  v_queued integer := 0;
  v_skipped integer := 0;
BEGIN
  SET LOCAL statement_timeout = '120s';
  SET LOCAL lock_timeout = '5s';

  FOR v_state IN
    SELECT * FROM public.student_journey_states
    WHERE status = 'active'
      AND (next_eval_at IS NULL OR next_eval_at <= now())
    ORDER BY next_eval_at NULLS FIRST
    LIMIT 200
    FOR UPDATE SKIP LOCKED
  LOOP
    v_processed := v_processed + 1;

    SELECT * INTO v_journey FROM public.journeys WHERE id = v_state.journey_id;
    IF NOT FOUND OR NOT v_journey.active THEN
      UPDATE public.student_journey_states SET status = 'paused', paused_reason = 'journey_inactive_or_missing'
      WHERE id = v_state.id;
      CONTINUE;
    END IF;

    -- Pega step current (current_step é index)
    v_step := v_journey.steps->(v_state.current_step);

    IF v_step IS NULL THEN
      UPDATE public.student_journey_states SET status = 'completed', completed_at = now()
      WHERE id = v_state.id;
      CONTINUE;
    END IF;

    v_action := v_step->>'action';

    -- Anti-fatigue check pra actions externas (Story 18.2d)
    IF v_action IN ('send_template', 'dispatch_survey', 'send_email') THEN
      SELECT public.can_dispatch_to_student(v_state.student_id) INTO v_can_dispatch;
      v_capping_check := (v_can_dispatch->>'allowed')::boolean;

      IF NOT v_capping_check THEN
        -- Skip step desta rodada — adia 1h e tenta novamente
        UPDATE public.student_journey_states SET next_eval_at = now() + interval '1 hour'
        WHERE id = v_state.id;
        INSERT INTO public.journey_executions (journey_state_id, step_num, action_attempted, action_result, result_meta)
        VALUES (v_state.id, v_state.current_step, v_action, 'skipped_capping', v_can_dispatch);
        v_skipped := v_skipped + 1;
        CONTINUE;
      END IF;
    END IF;

    -- Auto-fire actions (não comm externa)
    IF v_action IN ('create_pending', 'slack_alert', 'tag_student') THEN
      BEGIN
        IF v_action = 'create_pending' THEN
          INSERT INTO public.pending_student_assignments (student_id, status, notes)
          VALUES (v_state.student_id, 'pending',
                  COALESCE(v_step->'config'->>'reason', v_journey.name) || ' — journey step ' || v_state.current_step);

        ELSIF v_action = 'slack_alert' THEN
          PERFORM public.send_slack_alert(
            'journey_' || v_state.id::text || '_step_' || v_state.current_step,
            COALESCE(v_step->'config'->>'message_template',
                     '🗺️ Journey "' || v_journey.name || '" step ' || v_state.current_step || ' pra aluno ' || v_state.student_id::text)
          );

        ELSIF v_action = 'tag_student' THEN
          -- Tag student via response_metadata.manual_tags se aplicável
          -- V1: apenas log
          NULL;
        END IF;

        INSERT INTO public.journey_executions (journey_state_id, step_num, action_attempted, action_result, result_meta)
        VALUES (v_state.id, v_state.current_step, v_action, 'executed', v_step->'config');
        v_executed := v_executed + 1;
      EXCEPTION WHEN OTHERS THEN
        INSERT INTO public.journey_executions (journey_state_id, step_num, action_attempted, action_result, result_meta)
        VALUES (v_state.id, v_state.current_step, v_action, 'failed', jsonb_build_object('error', SQLERRM));
      END;
    ELSE
      -- Comm externa → enfileira approval (NON-NEGOTIABLE)
      INSERT INTO public.journey_pending_approvals (
        journey_state_id, step_num, action_type, action_config, preview_data
      ) VALUES (
        v_state.id,
        v_state.current_step,
        v_action,
        v_step->'config',
        jsonb_build_object(
          'student_id', v_state.student_id,
          'journey_name', v_journey.name,
          'step', v_step
        )
      );
      INSERT INTO public.journey_executions (journey_state_id, step_num, action_attempted, action_result, result_meta)
      VALUES (v_state.id, v_state.current_step, v_action, 'queued_approval', v_step->'config');
      v_queued := v_queued + 1;
    END IF;

    -- Avança step + recalcula next_eval_at
    UPDATE public.student_journey_states SET
      current_step = current_step + 1,
      last_action_at = now(),
      next_eval_at = CASE
        WHEN v_journey.steps->(v_state.current_step + 1) IS NOT NULL
          THEN started_at + ((v_journey.steps->(v_state.current_step + 1)->>'day_offset')::int || ' days')::interval
        ELSE NULL
      END
    WHERE id = v_state.id;
  END LOOP;

  RETURN jsonb_build_object(
    'processed', v_processed,
    'auto_executed', v_executed,
    'queued_for_approval', v_queued,
    'skipped_capping', v_skipped,
    'at', now()
  );
END $$;

GRANT EXECUTE ON FUNCTION public.process_journey_states() TO service_role, authenticated;

-- ─── 4. pg_cron schedule worker (Story 18.2b) ───────────────────────────
SELECT cron.schedule('epic018-journey-worker', '*/5 * * * *',
  $$ SELECT public.process_journey_states(); $$
) WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'epic018-journey-worker');

-- ─── 5. Trigger execute_approved_journey_action (Story 18.2e) ──────────
-- Quando approval status='approved', dispatch_survey/send_template execute
-- via NOTIFY → handler edge function (V1 marca como ready, edge function picks up)
CREATE OR REPLACE FUNCTION public.handle_approval_status_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  IF NEW.status = 'approved' AND OLD.status = 'awaiting_approval' THEN
    INSERT INTO public.journey_executions (journey_state_id, step_num, action_attempted, action_result, result_meta)
    VALUES (NEW.journey_state_id, NEW.step_num, NEW.action_type, 'executed',
            jsonb_build_object('approved_by', NEW.approved_by, 'approved_at', NEW.approved_at));

    -- Notify edge function pra disparo real (via Supabase realtime channel)
    PERFORM pg_notify('journey_approval_executed', NEW.id::text);
  ELSIF NEW.status = 'rejected' AND OLD.status = 'awaiting_approval' THEN
    INSERT INTO public.journey_executions (journey_state_id, step_num, action_attempted, action_result, result_meta)
    VALUES (NEW.journey_state_id, NEW.step_num, NEW.action_type, 'failed',
            jsonb_build_object('rejected_by', NEW.approved_by, 'rejected_at', NEW.approved_at, 'reason', 'manual_rejection'));
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_approval_status ON public.journey_pending_approvals;
CREATE TRIGGER trg_approval_status
  AFTER UPDATE ON public.journey_pending_approvals
  FOR EACH ROW EXECUTE FUNCTION public.handle_approval_status_change();

-- ─── 6. Anti-loop guardrail (ADR-018 #7) ────────────────────────────────
CREATE OR REPLACE FUNCTION public.enforce_journey_limit()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  IF NEW.status = 'active' AND (
    SELECT COUNT(*) FROM public.student_journey_states
    WHERE student_id = NEW.student_id AND status = 'active'
  ) >= 3 THEN
    RAISE EXCEPTION 'Aluno % já está em 3 journeys ativas (limite anti-loop ADR-018)', NEW.student_id;
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_journey_limit ON public.student_journey_states;
CREATE TRIGGER trg_journey_limit
  BEFORE INSERT ON public.student_journey_states
  FOR EACH ROW EXECUTE FUNCTION public.enforce_journey_limit();

COMMENT ON FUNCTION public.process_journey_states() IS
  'EPIC-018 Story 18.2b — Worker journey state machine. Roda 5min via pg_cron. Approval queue pra comm externa (NON-NEGOTIABLE).';
