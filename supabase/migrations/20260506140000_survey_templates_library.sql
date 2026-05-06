-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-017 Story 17.8 — Survey Templates Library
-- Pré-built templates de surveys que CS pode clonar pra uso rápido.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.survey_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  description text,
  category text NOT NULL CHECK (category IN ('nps', 'csat', 'onboarding', 'feedback', 'churn', 'custom')),
  intro_text text,
  follow_up text,
  questions jsonb NOT NULL,  -- array de {position, type, label, required, options, scale_max, placeholder}
  is_winner boolean DEFAULT false,  -- destaque pra templates de alto desempenho
  use_count integer DEFAULT 0,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_survey_templates_category ON public.survey_templates (category);
CREATE INDEX IF NOT EXISTS idx_survey_templates_winner ON public.survey_templates (is_winner) WHERE is_winner = true;

ALTER TABLE public.survey_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cs_admin_read_templates"
  ON public.survey_templates FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));

GRANT SELECT ON public.survey_templates TO authenticated;

-- ─── Pré-built templates ─────────────────────────────────────────────────
INSERT INTO public.survey_templates (name, description, category, intro_text, follow_up, questions, is_winner) VALUES
(
  'NPS Padrão',
  'Net Promoter Score clássico — 1 pergunta NPS + razão livre.',
  'nps',
  'Como está sua experiência conosco até aqui?',
  'Obrigado pelo feedback! Sua opinião nos ajuda a melhorar.',
  '[
    {"position": 1, "type": "nps", "label": "De 0 a 10, quanto você recomendaria nosso curso para um amigo?", "required": true},
    {"position": 2, "type": "text", "label": "O que motivou sua nota?", "required": false, "placeholder": "Conte-nos mais..."}
  ]'::jsonb,
  true
),
(
  'CSAT Modular',
  'Customer Satisfaction com escala emoji 1-5.',
  'csat',
  'Avalie sua satisfação com o módulo recém-concluído:',
  null,
  '[
    {"position": 1, "type": "csat", "label": "Como você se sente sobre o módulo?", "required": true},
    {"position": 2, "type": "scale", "label": "Quanto o conteúdo atendeu suas expectativas?", "required": true, "scale_max": 5},
    {"position": 3, "type": "text", "label": "O que melhoraríamos?", "required": false}
  ]'::jsonb,
  false
),
(
  'Onboarding Premium 3-Step',
  'Pulse de onboarding pra novos alunos premium — expectativas + ritmo + suporte.',
  'onboarding',
  'Bem-vindo! Conta pra gente como podemos te ajudar a começar bem.',
  'Recebemos suas respostas. Em breve um membro do time entrará em contato!',
  '[
    {"position": 1, "type": "choice", "label": "Qual seu objetivo principal com o curso?", "required": true, "options": ["Aprender do zero", "Aprofundar skills existentes", "Mudança de carreira", "Outro"]},
    {"position": 2, "type": "scale", "label": "Quão familiar você já é com o tema?", "required": true, "scale_max": 5},
    {"position": 3, "type": "text", "label": "Tem alguma pergunta ou preocupação inicial?", "required": false}
  ]'::jsonb,
  true
),
(
  'Detractor Follow-up',
  'Pra alunos que deram NPS <= 6 — investigação detalhada do problema.',
  'feedback',
  'Notamos que sua experiência não atendeu expectativas. Queremos entender melhor.',
  'Obrigado pela honestidade. Nosso time entrará em contato pra resolver.',
  '[
    {"position": 1, "type": "multi", "label": "Quais áreas precisam melhorar?", "required": true, "options": ["Conteúdo", "Instrutor", "Ritmo das aulas", "Suporte CS", "Plataforma técnica", "Preço", "Outro"]},
    {"position": 2, "type": "text", "label": "Descreva o principal problema que enfrentou:", "required": true, "placeholder": "Seja específico — exemplos ajudam."},
    {"position": 3, "type": "choice", "label": "O que faria você reconsiderar a opinião?", "required": false, "options": ["Acompanhamento individual", "Material extra", "Reembolso parcial", "Mudar de turma", "Outra coisa"]}
  ]'::jsonb,
  false
),
(
  'Churn Risk Pulse',
  'Mini-pulse pra alunos identificados como em risco — 1 pergunta scale.',
  'churn',
  'Como tá indo seus estudos esta semana?',
  null,
  '[
    {"position": 1, "type": "scale", "label": "De 1 (péssimo) a 5 (excelente), como tá fluindo?", "required": true, "scale_max": 5},
    {"position": 2, "type": "text", "label": "Algo está te atrapalhando?", "required": false}
  ]'::jsonb,
  false
)
ON CONFLICT DO NOTHING;

COMMENT ON TABLE public.survey_templates IS
  'EPIC-017 Story 17.8: biblioteca de templates pré-built. CS clica "Criar de template" no /cs/forms pra duplicar.';
