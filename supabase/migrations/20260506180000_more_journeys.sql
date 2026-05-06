-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-018 Story 18.4 — Adicionar 5 jornadas pré-built
-- Cobre cenários comuns: pré-graduação, win-back, mensal premium, B2B, mentoria
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO public.journeys (name, description, service_tier, duration_days, is_template, active, steps) VALUES
(
  'Acompanhamento Mensal Premium 12m',
  'Touchpoint leve mensal pra alunos premium ao longo de 12 meses (manter relacionamento longo).',
  'premium', 365, true, false,
  '[
    {"step_num": 1, "day_offset": 30,  "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "csat", "scope": "monthly_pulse"}},
    {"step_num": 2, "day_offset": 60,  "trigger": "time", "action": "send_template", "config": {"template": "checkin_aluno"}},
    {"step_num": 3, "day_offset": 90,  "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "nps"}},
    {"step_num": 4, "day_offset": 180, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "csat", "scope": "semester"}},
    {"step_num": 5, "day_offset": 270, "trigger": "time", "action": "send_template", "config": {"template": "marco_9_meses"}},
    {"step_num": 6, "day_offset": 365, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "feedback", "scope": "anniversary"}}
  ]'::jsonb
),
(
  'Pré-Graduação 30d',
  'Sequência pra alunos próximos de concluir o curso — colher feedback final + indicações.',
  'standard', 30, true, false,
  '[
    {"step_num": 1, "day_offset": 0,  "trigger": "graduation_imminent", "action": "send_template", "config": {"template": "pre_graduacao_30d"}},
    {"step_num": 2, "day_offset": 7,  "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "feedback", "scope": "exit_interview"}},
    {"step_num": 3, "day_offset": 15, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "nps", "scope": "final"}},
    {"step_num": 4, "day_offset": 25, "trigger": "time", "action": "send_template", "config": {"template": "indique_amigo"}}
  ]'::jsonb
),
(
  'Win-Back 60d (alunos churned)',
  'Sequência pra ex-alunos que cancelaram — tentativa de recuperação com oferta.',
  'standard', 60, true, false,
  '[
    {"step_num": 1, "day_offset": 7,  "trigger": "time", "action": "send_template", "config": {"template": "winback_dia_7"}},
    {"step_num": 2, "day_offset": 14, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "feedback", "scope": "porque_saiu"}},
    {"step_num": 3, "day_offset": 30, "trigger": "no_response", "action": "send_template", "config": {"template": "winback_oferta"}},
    {"step_num": 4, "day_offset": 60, "trigger": "no_response", "action": "create_pending", "config": {"reason": "Win-back manual CS — última tentativa"}}
  ]'::jsonb
),
(
  'Onboarding Empresarial B2B',
  'Onboarding pra contas corporativas — múltiplos colaboradores + relatórios pro decisor.',
  'premium', 60, true, false,
  '[
    {"step_num": 1, "day_offset": 0,  "trigger": "purchase", "action": "send_template", "config": {"template": "boas_vindas_empresa"}},
    {"step_num": 2, "day_offset": 1,  "trigger": "time", "action": "create_pending", "config": {"reason": "Agendar kickoff call CS"}},
    {"step_num": 3, "day_offset": 14, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "csat", "scope": "kickoff"}},
    {"step_num": 4, "day_offset": 30, "trigger": "time", "action": "send_template", "config": {"template": "relatorio_uso_mensal"}},
    {"step_num": 5, "day_offset": 60, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "nps", "scope": "renewal_check"}}
  ]'::jsonb
),
(
  'Mentoria Individual 90d',
  'Programa de mentoria 1:1 — touchpoints semanais com mentor designado.',
  'premium', 90, true, false,
  '[
    {"step_num": 1, "day_offset": 0,  "trigger": "purchase", "action": "create_pending", "config": {"reason": "Atribuir mentor + agendar 1ª sessão"}},
    {"step_num": 2, "day_offset": 7,  "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "csat", "scope": "first_session"}},
    {"step_num": 3, "day_offset": 14, "trigger": "time", "action": "send_template", "config": {"template": "checkin_mentoria"}},
    {"step_num": 4, "day_offset": 30, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "nps"}},
    {"step_num": 5, "day_offset": 60, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "csat", "scope": "midpoint"}},
    {"step_num": 6, "day_offset": 90, "trigger": "time", "action": "dispatch_survey", "config": {"survey_category": "feedback", "scope": "graduation"}}
  ]'::jsonb
)
ON CONFLICT DO NOTHING;
