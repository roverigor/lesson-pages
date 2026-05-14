-- ═══════════════════════════════════════════════════════════════════════════
-- Migration — Survey instance "Encerramento Fundamentals T4"
-- Spec: docs/superpowers/specs/2026-05-14-encerramento-fundamentals-t4-design.md
--
-- Cria survey + 9 perguntas vinculadas cohort Fundamentals T4.
-- Status: draft (dispatch manual via admin /surveys após aprovação template Meta).
-- ═══════════════════════════════════════════════════════════════════════════

DO $$
DECLARE
  v_cohort_id uuid;
  v_survey_id uuid := gen_random_uuid();
BEGIN
  -- 1. Resolver cohort Fundamentals T4
  SELECT id INTO v_cohort_id
    FROM public.cohorts
   WHERE name ILIKE '%fundamentals%t4%'
     AND active = true
   ORDER BY created_at DESC
   LIMIT 1;

  IF v_cohort_id IS NULL THEN
    RAISE EXCEPTION 'Cohort Fundamentals T4 não encontrado (active=true). Verifique tabela cohorts antes de aplicar.';
  END IF;

  -- 2. Inserir survey (idempotente por nome+cohort)
  IF NOT EXISTS (
    SELECT 1 FROM public.surveys
     WHERE name = 'Encerramento Fundamentals T4' AND cohort_id = v_cohort_id
  ) THEN
    INSERT INTO public.surveys (id, name, type, cohort_id, question, intro_text, follow_up, status, accent_color)
    VALUES (
      v_survey_id,
      'Encerramento Fundamentals T4',
      'mixed',
      v_cohort_id,
      'Survey multi-question (ver survey_questions)',
      'A turma acabou ontem 🎓. Sua opinião vai ajudar a tornar o próximo Fundamentals ainda melhor. Leva uns 4 min.',
      'Valeu pelo feedback! Sua resposta foi registrada.',
      'draft',
      '#6366f1'
    );

    -- 3. Inserir 9 perguntas
    INSERT INTO public.survey_questions (survey_id, position, type, label, required, options, scale_max, placeholder) VALUES
      (v_survey_id, 1, 'nps',    'De 0 a 10, quanto você recomendaria o Fundamentals pra um colega?', true,  NULL, NULL, NULL),
      (v_survey_id, 2, 'text',   'O que motivou sua nota?',                                           false, NULL, NULL, 'Conte um pouco mais...'),
      (v_survey_id, 3, 'csat',   'Como avalia o curso de forma geral?',                               true,  NULL, NULL, NULL),
      (v_survey_id, 4, 'scale',  'O curso atendeu suas expectativas iniciais?',                       true,  NULL, 5,    NULL),
      (v_survey_id, 5, 'text',   'Quais foram os pontos mais fortes do curso pra você?',              true,  NULL, NULL, 'O que mais te marcou...'),
      (v_survey_id, 6, 'text',   'O que poderíamos melhorar?',                                        false, NULL, NULL, 'Sugestões honestas são bem-vindas...'),
      (v_survey_id, 7, 'scale',  'Como avalia o ritmo das aulas? (1=muito lento, 5=muito rápido)',    false, NULL, 5,    NULL),
      (v_survey_id, 8, 'choice', 'Pretende continuar com a gente no próximo nível?',                  true,  '["Sim","Talvez","Não","Já estou inscrito"]'::jsonb, NULL, NULL),
      (v_survey_id, 9, 'text',   'Deixe um depoimento que possamos usar pra divulgar a próxima turma (opcional)', false, NULL, NULL, 'Depoimentos ajudam outros alunos a decidir...');

    RAISE NOTICE 'Survey % criado pra cohort %.', v_survey_id, v_cohort_id;
  ELSE
    RAISE NOTICE 'Survey Encerramento Fundamentals T4 já existe pra cohort %. Skip.', v_cohort_id;
  END IF;
END $$;
