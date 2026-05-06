-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-016 Story 16.11 — Automation Rules Engine V1
-- Schema + worker pra triggered actions baseado em survey responses.
--
-- V1: 1 trigger type (nps_response_received), 2 action types (create_pending, slack_alert)
-- V2 futuro: mais triggers (zoom_attendance, journey_step), mais actions (send_template Meta)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.automation_rules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  trigger_type text NOT NULL CHECK (trigger_type IN (
    'nps_response_received',     -- nova resposta NPS
    'survey_response_received',  -- qualquer resposta
    'student_silent_30d'         -- aluno sem atividade 30+ dias
  )),
  conditions jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- exemplo NPS: {"nps_max": 6, "cohort_id": null}
  action_type text NOT NULL CHECK (action_type IN (
    'create_pending',  -- cria pending_student_assignment pra CS
    'slack_alert',     -- dispara Slack alert (canal configurável)
    'tag_student'      -- adiciona tag em response_metadata.manual_tags
  )),
  action_config jsonb NOT NULL DEFAULT '{}'::jsonb,
  -- exemplo create_pending: {"reason": "NPS detractor follow-up"}
  -- exemplo slack_alert: {"channel": "#cs-alerts", "message_template": "..."}
  active boolean DEFAULT true,
  last_fired_at timestamptz,
  fire_count integer DEFAULT 0,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_automation_rules_active
  ON public.automation_rules (trigger_type, active) WHERE active = true;

ALTER TABLE public.automation_rules ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cs_admin_read_automation_rules"
  ON public.automation_rules FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));

CREATE POLICY "admin_write_automation_rules"
  ON public.automation_rules FOR INSERT
  WITH CHECK ((auth.jwt()->'user_metadata'->>'role') = 'admin');

CREATE POLICY "admin_update_automation_rules"
  ON public.automation_rules FOR UPDATE
  USING ((auth.jwt()->'user_metadata'->>'role') = 'admin');

CREATE POLICY "admin_delete_automation_rules"
  ON public.automation_rules FOR DELETE
  USING ((auth.jwt()->'user_metadata'->>'role') = 'admin');

GRANT SELECT, INSERT, UPDATE, DELETE ON public.automation_rules TO authenticated;

-- ─── automation_executions: log de cada execução ─────────────────────────
CREATE TABLE IF NOT EXISTS public.automation_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  rule_id uuid NOT NULL REFERENCES public.automation_rules(id) ON DELETE CASCADE,
  triggered_by_response_id uuid REFERENCES public.survey_responses(id),
  triggered_by_student_id uuid REFERENCES public.students(id),
  status text NOT NULL CHECK (status IN ('success', 'error', 'skipped')),
  result jsonb,
  error_message text,
  executed_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_automation_executions_rule
  ON public.automation_executions (rule_id, executed_at DESC);

ALTER TABLE public.automation_executions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cs_admin_read_automation_executions"
  ON public.automation_executions FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));

GRANT SELECT ON public.automation_executions TO authenticated;
GRANT INSERT ON public.automation_executions TO service_role;

-- ─── Worker function: process_automation_rules() ────────────────────────
CREATE OR REPLACE FUNCTION public.process_automation_rules()
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_rule RECORD;
  v_response RECORD;
  v_nps_score integer;
  v_processed integer := 0;
  v_actions_fired integer := 0;
BEGIN
  -- Process rule: nps_response_received com nps_max
  FOR v_rule IN
    SELECT * FROM public.automation_rules
    WHERE active = true AND trigger_type = 'nps_response_received'
  LOOP
    -- Pega responses NPS últimos 10min que ainda não dispararam essa rule
    FOR v_response IN
      SELECT DISTINCT sr.id, sr.student_id, sr.survey_id, sr.submitted_at,
             (SELECT sa.value::int FROM survey_answers sa
              JOIN survey_questions sq ON sq.id = sa.question_id
              WHERE sa.response_id = sr.id AND sq.type = 'nps' LIMIT 1) AS nps_value
      FROM public.survey_responses sr
      WHERE sr.submitted_at > now() - interval '10 minutes'
        AND NOT EXISTS (
          SELECT 1 FROM public.automation_executions ae
          WHERE ae.rule_id = v_rule.id AND ae.triggered_by_response_id = sr.id
        )
    LOOP
      v_processed := v_processed + 1;
      v_nps_score := v_response.nps_value;
      IF v_nps_score IS NULL THEN CONTINUE; END IF;

      -- Avalia condition nps_max
      IF (v_rule.conditions->>'nps_max')::int IS NOT NULL
         AND v_nps_score > (v_rule.conditions->>'nps_max')::int THEN
        CONTINUE;
      END IF;

      -- Executa action
      BEGIN
        IF v_rule.action_type = 'create_pending' THEN
          INSERT INTO public.pending_student_assignments (student_id, status, notes)
          VALUES (v_response.student_id, 'pending',
                  COALESCE(v_rule.action_config->>'reason', v_rule.name) || ' (NPS=' || v_nps_score || ')');

          INSERT INTO public.automation_executions (rule_id, triggered_by_response_id, triggered_by_student_id, status, result)
          VALUES (v_rule.id, v_response.id, v_response.student_id, 'success',
                  jsonb_build_object('action', 'pending_created', 'nps', v_nps_score));

          v_actions_fired := v_actions_fired + 1;

        ELSIF v_rule.action_type = 'slack_alert' THEN
          PERFORM public.send_slack_alert(
            'auto_rule_' || v_rule.id::text || '_' || v_response.id::text,
            COALESCE(v_rule.action_config->>'message_template',
                     '🚨 Aluno detractor: NPS=' || v_nps_score)
          );

          INSERT INTO public.automation_executions (rule_id, triggered_by_response_id, triggered_by_student_id, status, result)
          VALUES (v_rule.id, v_response.id, v_response.student_id, 'success',
                  jsonb_build_object('action', 'slack_sent', 'nps', v_nps_score));

          v_actions_fired := v_actions_fired + 1;
        END IF;

      EXCEPTION WHEN OTHERS THEN
        INSERT INTO public.automation_executions (rule_id, triggered_by_response_id, triggered_by_student_id, status, error_message)
        VALUES (v_rule.id, v_response.id, v_response.student_id, 'error', SQLERRM);
      END;
    END LOOP;

    -- Atualiza last_fired_at + fire_count
    IF v_actions_fired > 0 THEN
      UPDATE public.automation_rules SET last_fired_at = now(), fire_count = fire_count + v_actions_fired
      WHERE id = v_rule.id;
    END IF;
  END LOOP;

  RETURN jsonb_build_object('processed', v_processed, 'actions_fired', v_actions_fired, 'at', now());
END $$;

GRANT EXECUTE ON FUNCTION public.process_automation_rules() TO service_role;

-- ─── pg_cron: roda automation worker a cada 5min ────────────────────────
SELECT cron.schedule(
  'epic016-automation-worker',
  '*/5 * * * *',
  $$ SELECT public.process_automation_rules(); $$
) WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'epic016-automation-worker');

-- ─── Pre-built default rule: NPS detractor follow-up ───────────────────
INSERT INTO public.automation_rules (name, description, trigger_type, conditions, action_type, action_config, active)
VALUES (
  'NPS Detractor → Pendência CS',
  'Quando aluno responde NPS <= 6, cria pendência pro CS rep contatar.',
  'nps_response_received',
  '{"nps_max": 6}'::jsonb,
  'create_pending',
  '{"reason": "Detractor NPS follow-up"}'::jsonb,
  false  -- INICIA INATIVO — admin ativa via UI quando quiser
)
ON CONFLICT DO NOTHING;

COMMENT ON TABLE public.automation_rules IS
  'EPIC-016 Story 16.11: rules engine V1. Worker pg_cron 5min processa survey_responses recentes contra rules ativas.';
