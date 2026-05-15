-- ============================================================================
-- Class Reminder Templates — Refinamento premium (sem "Plantão de Dúvidas")
-- Date: 2026-05-15
-- ============================================================================
-- Substitui textos dos templates PS. Mantém estrutura/variant_label.
-- Foco: tom sóbrio, direto, sem jargão "plantão", emojis mínimos.
-- ============================================================================

BEGIN;

-- ─── PS 1h antes — refinamento ─────────────────────────────────────────────
UPDATE public.class_reminder_templates SET body = E'{saudacao}, pessoal.\n\nHoje temos *{class_name}* — espaço pra revisar o que vocês estão construindo, pedir feedback sobre o que já colocaram em prática e destravar pontos que ficaram confusos durante as aulas.\n\nComeçamos em 1 hora.\n\n*{class_name}* — {time_start} às {time_end} (horário de Brasília)\n🔗 {zoom_link}'
 WHERE name = 'ps_1h_completo';

UPDATE public.class_reminder_templates SET body = E'{saudacao}, pessoal.\n\nDaqui 1 hora começa *{class_name}*, às {time_start}.\n\nLevem perguntas, projetos em construção e qualquer ponto que precise destravar. Resolvemos juntos.\n\n🔗 {zoom_link}'
 WHERE name = 'ps_1h_direto';

UPDATE public.class_reminder_templates SET body = E'{saudacao}, pessoal.\n\nEm uma hora abrimos *{class_name}* — espaço pra dúvidas, troca de experiências e debate técnico sobre o que cada um está construindo.\n\nHorário: {time_start} às {time_end} (Brasília)\n🔗 {zoom_link}'
 WHERE name = 'ps_1h_convite';

UPDATE public.class_reminder_templates SET body = E'{saudacao}, pessoal.\n\nFalta 1 hora pro nosso *{class_name}*. Aproveitem para preparar perguntas, projetos em andamento ou pontos de feedback que querem trabalhar.\n\n{time_start} às {time_end} (Brasília)\n🔗 {zoom_link}'
 WHERE name = 'ps_1h_prep';

-- ─── PS na hora (start) — refinamento ──────────────────────────────────────
UPDATE public.class_reminder_templates SET body = E'Pessoal, *{class_name}* começando agora.\n\nQuem está com dúvida em construção, projeto travado ou quer feedback — esse é o momento.\n\n🔗 {zoom_link}'
 WHERE name = 'ps_start_direto';

UPDATE public.class_reminder_templates SET body = E'{saudacao}, pessoal.\n\n*{class_name}* iniciado. Sala aberta pra dúvidas, feedback e debate técnico.\n\n🔗 {zoom_link}'
 WHERE name = 'ps_start_aberto';

UPDATE public.class_reminder_templates SET body = E'*{class_name}* começou.\n\nQuem tem ponto pra discutir, projeto pra mostrar ou dúvida em aberto — entra agora.\n\n🔗 {zoom_link}'
 WHERE name = 'ps_start_chamada';

UPDATE public.class_reminder_templates SET body = E'*{class_name}* iniciado.\n\n🔗 {zoom_link}\n\nLevem suas perguntas.'
 WHERE name = 'ps_start_sucinto';

-- ─── Reset rotação pra evitar templates "queimados" pelo teste ─────────────
UPDATE public.class_reminder_templates SET last_used_at = NULL, use_count = 0
 WHERE name LIKE 'ps_%';

COMMIT;
