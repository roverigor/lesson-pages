-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-017 Story 17.7 — Frequency Capping (anti-fatigue)
-- Limita disparos por aluno em janela de tempo. Worker dispatch deve checar antes.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.frequency_cap_config (
  id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),  -- singleton row
  max_per_student_per_week integer DEFAULT 2,
  max_per_student_per_day integer DEFAULT 1,
  quiet_hours_start integer DEFAULT 22,  -- 22h
  quiet_hours_end integer DEFAULT 8,     -- 8h next day
  cooldown_after_response_hours integer DEFAULT 48,
  enabled boolean DEFAULT true,
  updated_at timestamptz DEFAULT now()
);

INSERT INTO public.frequency_cap_config (id) VALUES (1) ON CONFLICT DO NOTHING;

-- ─── Function: pode disparar pra esse aluno agora? ─────────────────────
CREATE OR REPLACE FUNCTION public.can_dispatch_to_student(p_student_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE AS $$
DECLARE
  v_config RECORD;
  v_dispatches_24h integer;
  v_dispatches_7d integer;
  v_last_response_hours integer;
  v_current_hour integer;
  v_in_quiet boolean;
BEGIN
  SELECT * INTO v_config FROM public.frequency_cap_config WHERE id = 1;

  IF NOT v_config.enabled THEN
    RETURN jsonb_build_object('allowed', true, 'reason', 'capping_disabled');
  END IF;

  -- Quiet hours check
  v_current_hour := EXTRACT(HOUR FROM now() AT TIME ZONE 'America/Sao_Paulo');
  v_in_quiet := (v_config.quiet_hours_start > v_config.quiet_hours_end
                 AND (v_current_hour >= v_config.quiet_hours_start OR v_current_hour < v_config.quiet_hours_end))
                OR (v_config.quiet_hours_start <= v_config.quiet_hours_end
                 AND v_current_hour >= v_config.quiet_hours_start AND v_current_hour < v_config.quiet_hours_end);
  IF v_in_quiet THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'quiet_hours', 'current_hour', v_current_hour);
  END IF;

  -- 24h cap
  SELECT COUNT(*) INTO v_dispatches_24h
  FROM public.survey_links
  WHERE student_id = p_student_id AND created_at > now() - interval '24 hours';

  IF v_dispatches_24h >= v_config.max_per_student_per_day THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'daily_cap', 'count', v_dispatches_24h);
  END IF;

  -- 7d cap
  SELECT COUNT(*) INTO v_dispatches_7d
  FROM public.survey_links
  WHERE student_id = p_student_id AND created_at > now() - interval '7 days';

  IF v_dispatches_7d >= v_config.max_per_student_per_week THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'weekly_cap', 'count', v_dispatches_7d);
  END IF;

  -- Cooldown após response
  SELECT EXTRACT(EPOCH FROM (now() - MAX(submitted_at)))/3600 INTO v_last_response_hours
  FROM public.survey_responses
  WHERE student_id = p_student_id;

  IF v_last_response_hours IS NOT NULL AND v_last_response_hours < v_config.cooldown_after_response_hours THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'response_cooldown', 'hours_since_response', v_last_response_hours);
  END IF;

  RETURN jsonb_build_object('allowed', true);
END $$;

GRANT EXECUTE ON FUNCTION public.can_dispatch_to_student(uuid) TO authenticated, service_role;

ALTER TABLE public.frequency_cap_config ENABLE ROW LEVEL SECURITY;
CREATE POLICY "cs_admin_read_freq_config" ON public.frequency_cap_config FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));
CREATE POLICY "admin_update_freq_config" ON public.frequency_cap_config FOR UPDATE
  USING ((auth.jwt()->'user_metadata'->>'role') = 'admin');

GRANT SELECT, UPDATE ON public.frequency_cap_config TO authenticated;

COMMENT ON FUNCTION public.can_dispatch_to_student(uuid) IS
  'EPIC-017 Story 17.7: retorna {allowed, reason} indicando se aluno pode receber novo dispatch agora.';
