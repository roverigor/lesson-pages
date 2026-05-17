-- ═══════════════════════════════════════════════════════════════════════════
-- NPS Humanize V1+V2 — expand group variant pool (3→8) + weighted random
-- in place of strict round-robin (still tracks last for telemetry).
--
-- Rationale: premium positioning — same 3 msgs cycling = robotic. 8 variants
-- with weighted random + per-cohort offset = effectively unique per cohort
-- for first few sends.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- 1. Seed 5 additional group variants (idempotent)
INSERT INTO public.nps_message_variants (id, channel, body_template, meta_template_name, active, weight) VALUES
  ('group_v4', 'group',
   E'Galera, valeu pela energia em *{{class_name}}*! ✨\n\nPra fechar com chave de ouro, dá uma nota rapidinho — ajuda demais:\n{{link}}\n\n_(anônimo, 30s)_',
   NULL, true, 1),
  ('group_v5', 'group',
   E'{{cohort_name}} 🎯\n\nFeedback express sobre *{{class_name}}* hoje?\n\nLink rápido aqui: {{link}}\n\nSua nota orienta o próximo módulo.',
   NULL, true, 1),
  ('group_v6', 'group',
   E'Pessoal, encerramos *{{class_name}}* agora há pouco. 👇\n\nSe tiver 30 segundos, agradeceríamos muito a nota:\n{{link}}\n\nObrigado pela presença e dedicação. 🙏',
   NULL, true, 1),
  ('group_v7', 'group',
   E'Avaliação rápida da aula *{{class_name}}*?\n\n{{link}}\n\nPode responder anônimo se preferir — sua opinião direciona evolução do conteúdo. 💜',
   NULL, true, 1),
  ('group_v8', 'group',
   E'Time {{cohort_name}}!\n\nObrigado pela presença em *{{class_name}}* hoje. Pra continuarmos refinando cada encontro, nota rápida aqui:\n\n{{link}}',
   NULL, true, 1)
ON CONFLICT (id) DO NOTHING;

-- 2. Replace nps_next_variant with weighted-random version (still atomic via row lock)
CREATE OR REPLACE FUNCTION public.nps_next_variant(p_channel TEXT)
RETURNS TABLE (
  variant_id     TEXT,
  body_template  TEXT,
  meta_template_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_chosen   TEXT;
  v_total    INT;
  v_rand     INT;
  v_running  INT := 0;
  v_rec      RECORD;
BEGIN
  IF p_channel NOT IN ('group','dm') THEN
    RAISE EXCEPTION 'invalid channel: %', p_channel;
  END IF;

  -- Lock rotation state row (prevents concurrent runs colliding — NPS.E.1 fix)
  PERFORM 1 FROM public.nps_variant_rotation_state
   WHERE channel = p_channel FOR UPDATE;

  -- Compute total weight of active variants
  SELECT COALESCE(SUM(weight), 0) INTO v_total
  FROM public.nps_message_variants
  WHERE channel = p_channel AND active = true;

  IF v_total = 0 THEN
    RETURN; -- no active variant
  END IF;

  -- Pick random point in [1, v_total]
  v_rand := 1 + (floor(random() * v_total))::INT;
  IF v_rand > v_total THEN v_rand := v_total; END IF;

  -- Walk weighted buckets
  FOR v_rec IN
    SELECT id, weight, body_template, meta_template_name
    FROM public.nps_message_variants
    WHERE channel = p_channel AND active = true
    ORDER BY id
  LOOP
    v_running := v_running + v_rec.weight;
    IF v_running >= v_rand THEN
      v_chosen := v_rec.id;
      EXIT;
    END IF;
  END LOOP;

  IF v_chosen IS NULL THEN
    -- Defensive fallback (shouldn't reach here)
    SELECT id INTO v_chosen
    FROM public.nps_message_variants
    WHERE channel = p_channel AND active = true
    ORDER BY id LIMIT 1;
  END IF;

  -- Update telemetry state
  UPDATE public.nps_variant_rotation_state
     SET last_variant_id = v_chosen,
         rotation_count = rotation_count + 1,
         updated_at = NOW()
   WHERE channel = p_channel;

  RETURN QUERY
    SELECT v.id, v.body_template, v.meta_template_name
    FROM public.nps_message_variants v
    WHERE v.id = v_chosen;
END;
$$;

REVOKE ALL ON FUNCTION public.nps_next_variant(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_next_variant(TEXT) TO service_role;

COMMENT ON FUNCTION public.nps_next_variant IS
  'V1+V2: weighted-random variant pick with row lock for concurrency. Replaces round-robin to avoid cycle detection. Telemetry preserved in nps_variant_rotation_state.';

COMMIT;
