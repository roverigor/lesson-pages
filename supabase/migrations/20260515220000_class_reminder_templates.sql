-- ============================================================================
-- Class Reminder Templates — Variações de mensagem com rotação
-- Date: 2026-05-15
-- ============================================================================
-- Tom: premium, direto, sem excesso de emoji. Mantemos 🔗 funcional pro link.
-- Placeholders renderizados pela edge function:
--   {saudacao} → Bom dia / Boa tarde / Boa noite (BRT hora)
--   {class_name}, {time_start}, {time_end}, {zoom_link}, {holiday_name}
-- ============================================================================

BEGIN;

-- 1. Add kind column to classes
ALTER TABLE public.classes ADD COLUMN IF NOT EXISTS kind text DEFAULT 'regular' CHECK (kind IN ('ps','regular'));

UPDATE public.classes
   SET kind = 'ps'
 WHERE name ILIKE 'PS %' AND kind = 'regular';

-- 2. Templates table
CREATE TABLE IF NOT EXISTS public.class_reminder_templates (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name            text NOT NULL UNIQUE,
  reminder_type   text NOT NULL CHECK (reminder_type IN ('1h_before','start','holiday')),
  applies_to      text NOT NULL DEFAULT 'any' CHECK (applies_to IN ('ps','regular','any')),
  variant_label   text,
  body            text NOT NULL,
  weight          smallint NOT NULL DEFAULT 1,
  active          boolean NOT NULL DEFAULT true,
  last_used_at    timestamptz,
  use_count       integer NOT NULL DEFAULT 0,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_class_templates_lookup ON public.class_reminder_templates (reminder_type, applies_to, active);

ALTER TABLE public.class_reminder_templates ENABLE ROW LEVEL SECURITY;
CREATE POLICY "templates: read auth" ON public.class_reminder_templates FOR SELECT TO authenticated USING (true);
CREATE POLICY "templates: full service" ON public.class_reminder_templates FOR ALL TO service_role USING (true) WITH CHECK (true);

-- 3. Seed templates

-- ─── PS plantão — 1h antes ─────────────────────────────────────────────────
INSERT INTO public.class_reminder_templates (name, reminder_type, applies_to, variant_label, body) VALUES
('ps_1h_completo', '1h_before', 'ps', 'completo',
E'{saudacao}, pessoal.\n\nAs aulas do Cohort acabaram, mas ainda temos o Plantão de Dúvidas (PS).\n\nEsse é o momento que vocês têm para:\n• Tirar dúvida sobre o que está construindo agora\n• Pedir feedback sobre o que já colocou em prática\n• Destravar qualquer ponto que ficou confuso durante as aulas\n\nVamos começar daqui a uns minutos.\n\n*{class_name}* — {time_start} às {time_end} (horário de Brasília)\n🔗 {zoom_link}'),

('ps_1h_direto', '1h_before', 'ps', 'direto',
E'{saudacao}, pessoal.\n\nDaqui 1 hora começa o *Plantão de Dúvidas — {class_name}*, às {time_start}.\n\nLevem suas dúvidas, dificuldades e projetos travados. Resolvemos junto.\n\n🔗 {zoom_link}'),

('ps_1h_convite', '1h_before', 'ps', 'convite',
E'{saudacao}, pessoal.\n\nDaqui pouco temos *{class_name}* — plantão para tirar dúvidas, trocar experiências e destravar pontos.\n\nHorário: {time_start} às {time_end} (Brasília)\n🔗 {zoom_link}\n\nNos vemos lá.'),

('ps_1h_prep', '1h_before', 'ps', 'preparar',
E'{saudacao}, pessoal.\n\nEm uma hora abre o *Plantão de Dúvidas {class_name}*. Separa tua pergunta, projeto ou ponto que precisa de feedback.\n\n{time_start} às {time_end} (Brasília)\n🔗 {zoom_link}');

-- ─── PS plantão — no horário (start) ───────────────────────────────────────
INSERT INTO public.class_reminder_templates (name, reminder_type, applies_to, variant_label, body) VALUES
('ps_start_direto', 'start', 'ps', 'direto',
E'Pessoal, *{class_name}* começando agora.\n\nQuem tem dúvida ou quer feedback, é o momento.\n\n🔗 {zoom_link}'),

('ps_start_aberto', 'start', 'ps', 'aberto',
E'{saudacao}, pessoal.\n\nO Plantão *{class_name}* começou agora. Sala aberta pra dúvidas, feedback e debate técnico.\n\n🔗 {zoom_link}'),

('ps_start_chamada', 'start', 'ps', 'chamada',
E'Plantão *{class_name}* iniciado.\n\nSe tem alguma dúvida em construção, projeto travado ou quer feedback, entra agora.\n\n🔗 {zoom_link}'),

('ps_start_sucinto', 'start', 'ps', 'sucinto',
E'*{class_name}* começou.\n\n🔗 {zoom_link}\n\nTraz tuas dúvidas.');

-- ─── Regular aula — 1h antes ───────────────────────────────────────────────
INSERT INTO public.class_reminder_templates (name, reminder_type, applies_to, variant_label, body) VALUES
('reg_1h_lembrete', '1h_before', 'regular', 'lembrete',
E'{saudacao}, pessoal.\n\nLembrete: a aula *{class_name}* começa em 1 hora, às {time_start} (Brasília).\n\n🔗 {zoom_link}\n\nNos vemos lá.'),

('reg_1h_prep', '1h_before', 'regular', 'preparar',
E'{saudacao}, pessoal.\n\nDaqui 1 hora começamos a aula *{class_name}*. Separa o material e prepara tuas dúvidas.\n\n{time_start} às {time_end} (Brasília)\n🔗 {zoom_link}'),

('reg_1h_direto', '1h_before', 'regular', 'direto',
E'{saudacao}, pessoal.\n\nFalta 1 hora pra aula *{class_name}*.\n\n{time_start} às {time_end} (Brasília)\n🔗 {zoom_link}'),

('reg_1h_simples', '1h_before', 'regular', 'simples',
E'{saudacao}.\n\nAula *{class_name}* daqui 1 hora — {time_start} (Brasília).\n\n🔗 {zoom_link}');

-- ─── Regular aula — no horário (start) ─────────────────────────────────────
INSERT INTO public.class_reminder_templates (name, reminder_type, applies_to, variant_label, body) VALUES
('reg_start_agora', 'start', 'regular', 'agora',
E'Pessoal, *{class_name}* começando agora.\n\n🔗 {zoom_link}'),

('reg_start_chamada', 'start', 'regular', 'chamada',
E'{saudacao}, pessoal.\n\nA aula *{class_name}* começou agora. Sala aberta.\n\n🔗 {zoom_link}'),

('reg_start_warm', 'start', 'regular', 'caloroso',
E'{saudacao}, pessoal.\n\n*{class_name}* iniciado. Vamos transformar conhecimento em prática.\n\n🔗 {zoom_link}'),

('reg_start_sucinto', 'start', 'regular', 'sucinto',
E'*{class_name}* começou.\n\n🔗 {zoom_link}');

-- ─── Feriado ───────────────────────────────────────────────────────────────
INSERT INTO public.class_reminder_templates (name, reminder_type, applies_to, variant_label, body) VALUES
('holiday_breve', 'holiday', 'any', 'breve',
E'Pessoal, hoje é feriado — *{holiday_name}*.\n\nNão teremos {class_name} hoje. Nos vemos na próxima semana.'),

('holiday_calorosa', 'holiday', 'any', 'calorosa',
E'{saudacao}, pessoal.\n\nHoje é *{holiday_name}* — não teremos {class_name} hoje.\n\nAproveitem o dia. Voltamos na próxima semana.'),

('holiday_descontraida', 'holiday', 'any', 'curta',
E'Pessoal, feriado de *{holiday_name}* hoje. Sem aula. Nos vemos na próxima semana.');

COMMIT;
