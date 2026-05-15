-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-016 Story 16.9 — LGPD Compliance V1
-- - Opt-out flag (já existe whatsapp_alerts_enabled — adiciona consent timestamp)
-- - Function export_student_pii() pra Art. 18 LGPD
-- - Function anonymize_student() pra direito ao esquecimento
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS consent_given_at timestamptz,
  ADD COLUMN IF NOT EXISTS consent_revoked_at timestamptz,
  ADD COLUMN IF NOT EXISTS anonymized_at timestamptz;

CREATE INDEX IF NOT EXISTS idx_students_consent
  ON public.students (consent_given_at)
  WHERE consent_given_at IS NOT NULL;

-- ─── Function: export_student_pii(student_id) ──────────────────────────
-- Retorna JSON com TODOS dados pessoais do aluno (LGPD Art. 18 — direito de acesso)
CREATE OR REPLACE FUNCTION public.export_student_pii(p_student_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_result jsonb;
BEGIN
  -- Apenas admin pode exportar
  IF (auth.jwt()->'user_metadata'->>'role') NOT IN ('admin', 'cs') THEN
    RAISE EXCEPTION 'Permission denied — admin/cs only';
  END IF;

  SELECT jsonb_build_object(
    'student_data', (SELECT to_jsonb(s.*) FROM public.students s WHERE s.id = p_student_id),
    'cohorts', (SELECT jsonb_agg(c) FROM public.cohorts c
                JOIN public.student_cohorts sc ON sc.cohort_id = c.id
                WHERE sc.student_id = p_student_id),
    'survey_responses', (SELECT jsonb_agg(sr) FROM public.survey_responses sr
                         WHERE sr.student_id = p_student_id),
    'survey_answers', (SELECT jsonb_agg(sa) FROM public.survey_answers sa
                       JOIN public.survey_responses sr ON sr.id = sa.response_id
                       WHERE sr.student_id = p_student_id),
    'attendance', (SELECT jsonb_agg(att) FROM public.student_attendance att
                   WHERE att.student_id = p_student_id),
    'dispatches', (SELECT jsonb_agg(sl) FROM public.survey_links sl
                   WHERE sl.student_id = p_student_id),
    'audit_log', (SELECT jsonb_agg(al) FROM public.audit_log al
                  WHERE al.entity_id = p_student_id AND al.entity_type = 'students'),
    'exported_at', now(),
    'exported_by', auth.uid()
  ) INTO v_result;

  -- Log da exportação no audit_log
  INSERT INTO public.audit_log (actor_user_id, actor_email, action, entity_type, entity_id, after_data)
  VALUES (auth.uid(),
          (auth.jwt()->>'email'),
          'update',
          'students',
          p_student_id,
          jsonb_build_object('lgpd_export', true, 'exported_at', now()));

  RETURN v_result;
END $$;

GRANT EXECUTE ON FUNCTION public.export_student_pii(uuid) TO authenticated;

-- ─── Function: anonymize_student(student_id) ───────────────────────────
-- LGPD Art. 18 — direito de eliminação. Mantém ID + estatísticas, remove PII.
CREATE OR REPLACE FUNCTION public.anonymize_student(p_student_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_anon_id text;
BEGIN
  IF (auth.jwt()->'user_metadata'->>'role') != 'admin' THEN
    RAISE EXCEPTION 'Permission denied — admin only';
  END IF;

  v_anon_id := 'ANONIMIZADO_' || substring(p_student_id::text, 1, 8);

  UPDATE public.students SET
    name = v_anon_id,
    email = v_anon_id || '@anonimizado.local',
    phone = NULL,
    ac_contact_id = NULL,
    consent_revoked_at = COALESCE(consent_revoked_at, now()),
    anonymized_at = now(),
    active = false
  WHERE id = p_student_id;

  -- Anonimiza respostas free-text pra remover possíveis PII no conteúdo
  UPDATE public.survey_answers
  SET value = '[ANONIMIZADO]'
  WHERE response_id IN (SELECT id FROM public.survey_responses WHERE student_id = p_student_id)
    AND question_id IN (SELECT id FROM public.survey_questions WHERE type = 'text');

  INSERT INTO public.audit_log (actor_user_id, actor_email, action, entity_type, entity_id, after_data)
  VALUES (auth.uid(),
          (auth.jwt()->>'email'),
          'update',
          'students',
          p_student_id,
          jsonb_build_object('lgpd_anonymized', true, 'at', now()));

  RETURN jsonb_build_object('ok', true, 'anonymized_id', v_anon_id, 'at', now());
END $$;

GRANT EXECUTE ON FUNCTION public.anonymize_student(uuid) TO authenticated;

COMMENT ON COLUMN public.students.consent_given_at IS
  'EPIC-016 Story 16.9: timestamp do consent LGPD (preenchido em onboarding).';

COMMENT ON COLUMN public.students.consent_revoked_at IS
  'EPIC-016 Story 16.9: opt-out marketing — worker dispatch DEVE pular se preenchido.';

COMMENT ON FUNCTION public.export_student_pii(uuid) IS
  'EPIC-016 Story 16.9 — LGPD Art. 18: retorna TODOS dados pessoais do aluno em JSON.';

COMMENT ON FUNCTION public.anonymize_student(uuid) IS
  'EPIC-016 Story 16.9 — LGPD Art. 18: remove PII mantendo estatísticas. IRREVERSÍVEL.';
