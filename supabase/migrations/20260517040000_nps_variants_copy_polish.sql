-- ═══════════════════════════════════════════════════════════════════════════
-- NPS.P.5 — Copy polish per PM review (premium-brand consistency)
-- - Drop "Galera" register (v2, v4)
-- - Simplify v1 (remove awkward "opção de colocar nome" explainer)
-- - v5 prepend "Time " for cohort-aware opener (matches v3/v8 cadence)
-- - v7 add {{greeting}} for relationship signal in opener
-- - v4 polish (best variant — light touch)
-- Final registers: "Pessoal" (warm-formal) + "Time {{cohort_name}}" (cohort).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

UPDATE public.nps_message_variants SET body_template = E'Pessoal, obrigado pela presença em *{{class_name}}* hoje! 💜\n\nComo foi pra vocês? (30s, anônimo se preferir)\n{{link}}'
 WHERE id = 'group_v1';

UPDATE public.nps_message_variants SET body_template = E'Pessoal, fechamos *{{class_name}}* agora! 🚀\n\nUma pergunta rápida pra continuar evoluindo o conteúdo:\n{{link}}\n\nLeva 30s — pode responder anônimo, se preferir.'
 WHERE id = 'group_v2';

UPDATE public.nps_message_variants SET body_template = E'Time {{cohort_name}}! 👋\n\nFeedback express da aula de hoje (*{{class_name}}*) — sua opinião direciona os próximos encontros:\n{{link}}'
 WHERE id = 'group_v3';

UPDATE public.nps_message_variants SET body_template = E'Pessoal, valeu pela energia em *{{class_name}}*! ✨\n\nPra fechar com chave de ouro, dá uma nota rapidinho — ajuda demais:\n{{link}}\n\n_(anônimo, 30s)_'
 WHERE id = 'group_v4';

UPDATE public.nps_message_variants SET body_template = E'Time {{cohort_name}} 🎯\n\nFeedback rápido sobre *{{class_name}}*?\n{{link}}\n\nSua nota orienta o próximo encontro.'
 WHERE id = 'group_v5';

UPDATE public.nps_message_variants SET body_template = E'Pessoal, encerramos *{{class_name}}* agora há pouco. 👇\n\nSe tiver 30 segundos, agradeceríamos muito a nota:\n{{link}}\n\nObrigado pela presença e dedicação. 🙏'
 WHERE id = 'group_v6';

UPDATE public.nps_message_variants SET body_template = E'{{greeting}}, pessoal! Como foi a aula *{{class_name}}*?\n\nAvaliação rápida aqui (anônimo se preferir):\n{{link}}\n\nSua opinião direciona evolução do conteúdo. 💜'
 WHERE id = 'group_v7';

UPDATE public.nps_message_variants SET body_template = E'Time {{cohort_name}}!\n\nObrigado pela presença em *{{class_name}}* hoje. Pra continuarmos refinando cada encontro, nota rápida aqui:\n\n{{link}}'
 WHERE id = 'group_v8';

COMMIT;
