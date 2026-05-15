-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-018 Story 18.1 — Journey Orchestration Foundation
-- Schema journeys + per-student state machine.
-- Worker (18.2) virá depois. V1 só schema + data.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.journeys (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  service_tier text CHECK (service_tier IN ('premium', 'standard', 'basic')),
  duration_days integer,  -- ex: 90 dias
  is_template boolean DEFAULT false,  -- pre-built journeys
  active boolean DEFAULT true,
  steps jsonb NOT NULL,  -- array de {step_num, day_offset, trigger, action_type, action_config, branch_conditions}
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_journeys_active ON public.journeys (active) WHERE active = true;

ALTER TABLE public.journeys ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cs_admin_read_journeys" ON public.journeys FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));
CREATE POLICY "admin_write_journeys" ON public.journeys FOR INSERT
  WITH CHECK ((auth.jwt()->'user_metadata'->>'role') = 'admin');
CREATE POLICY "admin_update_journeys" ON public.journeys FOR UPDATE
  USING ((auth.jwt()->'user_metadata'->>'role') = 'admin');
GRANT SELECT, INSERT, UPDATE ON public.journeys TO authenticated;

-- ─── Per-student journey state ──────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.student_journey_states (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  journey_id uuid NOT NULL REFERENCES public.journeys(id) ON DELETE CASCADE,
  current_step integer DEFAULT 0,
  total_steps integer NOT NULL,
  status text NOT NULL DEFAULT 'active' CHECK (status IN (
    'active', 'paused', 'completed', 'escalated', 'abandoned'
  )),
  started_at timestamptz DEFAULT now(),
  completed_at timestamptz,
  next_eval_at timestamptz,
  branch_data jsonb DEFAULT '{}'::jsonb,
  paused_reason text,
  UNIQUE (student_id, journey_id)
);

CREATE INDEX IF NOT EXISTS idx_journey_states_eval
  ON public.student_journey_states (next_eval_at) WHERE status = 'active';
CREATE INDEX IF NOT EXISTS idx_journey_states_student
  ON public.student_journey_states (student_id);

ALTER TABLE public.student_journey_states ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cs_admin_read_journey_states" ON public.student_journey_states FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));
GRANT SELECT, INSERT, UPDATE ON public.student_journey_states TO authenticated, service_role;

-- ─── Pre-built journey: Premium 90 dias ─────────────────────────────────
INSERT INTO public.journeys (name, description, service_tier, duration_days, is_template, active, steps) VALUES
(
  'Premium Onboarding 90d',
  'Touchpoints 10x ao longo de 90 dias pra alunos premium — boas-vindas, pulse, NPS, deep CSAT, graduation.',
  'premium',
  90,
  true,
  false,  -- INATIVO por padrão (admin ativa via UI quando ready)
  '[
    {"step_num": 1, "day_offset": 0,  "trigger": "purchase", "action": "send_template", "config": {"template": "boas_vindas_premium"}},
    {"step_num": 2, "day_offset": 1,  "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "onboarding"}},
    {"step_num": 3, "day_offset": 7,  "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "csat", "scope": "pulse"}},
    {"step_num": 4, "day_offset": 14, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "nps"}},
    {"step_num": 5, "day_offset": 21, "trigger": "inactivity_5d", "action": "send_template", "config": {"template": "re_engagement"}},
    {"step_num": 6, "day_offset": 30, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "csat", "scope": "deep"}},
    {"step_num": 7, "day_offset": 60, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "nps", "scope": "comparativo"}},
    {"step_num": 8, "day_offset": 90, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "feedback", "scope": "exit_interview"}}
  ]'::jsonb
),
(
  'Standard 30 dias',
  'Touchpoints essenciais pra alunos standard — boas-vindas, NPS, exit.',
  'standard',
  30,
  true,
  false,
  '[
    {"step_num": 1, "day_offset": 0,  "trigger": "purchase", "action": "send_template", "config": {"template": "boas_vindas"}},
    {"step_num": 2, "day_offset": 7,  "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "csat"}},
    {"step_num": 3, "day_offset": 30, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "nps"}}
  ]'::jsonb
),
(
  'Re-Engagement (alunos at-risk)',
  'Disparado pra alunos identificados como at-risk pelo engagement engine.',
  'premium',
  14,
  true,
  false,
  '[
    {"step_num": 1, "day_offset": 0, "trigger": "at_risk_detected", "action": "create_pending", "config": {"reason": "Aluno at-risk — contato CS"}},
    {"step_num": 2, "day_offset": 3, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "feedback", "scope": "win_back"}},
    {"step_num": 3, "day_offset": 14, "trigger": "no_response", "action": "slack_alert", "config": {"channel": "#cs-escalation"}}
  ]'::jsonb
)
ON CONFLICT DO NOTHING;

COMMENT ON TABLE public.journeys IS
  'EPIC-018 Story 18.1: definição de jornadas. Worker (18.2) ainda não implementado — ativação manual via UI por enquanto.';
