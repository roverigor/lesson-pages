-- ═══════════════════════════════════════════════════════════════════════════
-- Migration — Survey Template "Encerramento de Curso"
-- Spec: docs/superpowers/specs/2026-05-14-encerramento-fundamentals-t4-design.md
--
-- Adiciona template reusável na biblioteca survey_templates pra uso em
-- futuras turmas (Advanced, próximos Fundamentals). Template é clonado
-- via UI admin "Criar de template".
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO public.survey_templates (name, description, category, intro_text, follow_up, questions, is_winner)
VALUES (
  'Encerramento de Curso',
  'Survey final de curso — NPS + CSAT + pontos fortes/fracos + intenção continuar + depoimento. 9 perguntas, ~4min responder.',
  'feedback',
  'A turma acabou ontem 🎓. Sua opinião vai ajudar a tornar o próximo curso ainda melhor. Leva uns 4 min.',
  'Valeu pelo feedback! Sua resposta foi registrada.',
  '[
    {"position": 1, "type": "nps",    "label": "De 0 a 10, quanto você recomendaria o curso pra um colega?", "required": true},
    {"position": 2, "type": "text",   "label": "O que motivou sua nota?", "required": false, "placeholder": "Conte um pouco mais..."},
    {"position": 3, "type": "csat",   "label": "Como avalia o curso de forma geral?", "required": true},
    {"position": 4, "type": "scale",  "label": "O curso atendeu suas expectativas iniciais?", "required": true, "scale_max": 5},
    {"position": 5, "type": "text",   "label": "Quais foram os pontos mais fortes do curso pra você?", "required": true, "placeholder": "O que mais te marcou..."},
    {"position": 6, "type": "text",   "label": "O que poderíamos melhorar?", "required": false, "placeholder": "Sugestões honestas são bem-vindas..."},
    {"position": 7, "type": "scale",  "label": "Como avalia o ritmo das aulas? (1=muito lento, 5=muito rápido)", "required": false, "scale_max": 5},
    {"position": 8, "type": "choice", "label": "Pretende continuar com a gente no próximo nível?", "required": true, "options": ["Sim", "Talvez", "Não", "Já estou inscrito"]},
    {"position": 9, "type": "text",   "label": "Deixe um depoimento que possamos usar pra divulgar a próxima turma (opcional)", "required": false, "placeholder": "Depoimentos ajudam outros alunos a decidir..."}
  ]'::jsonb,
  true
)
ON CONFLICT DO NOTHING;

COMMENT ON TABLE public.survey_templates IS
  'Biblioteca de templates pré-built. Story 17.8 + 2026-05-14 (template Encerramento de Curso).';
