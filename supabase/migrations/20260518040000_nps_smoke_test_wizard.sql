-- ═══════════════════════════════════════════════════════════════════════════
-- NPS Smoke Test Wizard RPC — collaborator-runnable end-to-end test setup
-- via UI clicks only. Creates test cohort + student + class + binding,
-- verifies the group, returns IDs ready for force-dispatch.
--
-- Idempotent: re-running with same test_name updates rather than duplicates.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.nps_admin_setup_smoke_test(
  p_test_name      TEXT,
  p_phone          TEXT,
  p_group_jid      TEXT,
  p_zoom_meeting_id TEXT,
  p_class_name     TEXT DEFAULT 'TESTE NPS — Aula validação'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cohort_id  UUID;
  v_student_id UUID;
  v_class_id   UUID;
  v_cohort_name TEXT;
  v_user_id    UUID;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  IF p_phone !~ '^[0-9]{10,15}$' THEN
    RAISE EXCEPTION 'invalid_phone_format: digits only, country code (10-15 chars). Got: %', p_phone USING ERRCODE = '22023';
  END IF;

  IF NOT public.nps_is_valid_group_jid(p_group_jid) THEN
    RAISE EXCEPTION 'invalid_group_jid: must match *@g.us' USING ERRCODE = '22023';
  END IF;

  IF p_zoom_meeting_id IS NULL OR length(trim(p_zoom_meeting_id)) < 9 THEN
    RAISE EXCEPTION 'invalid_zoom_meeting_id: at least 9 digits' USING ERRCODE = '22023';
  END IF;

  v_user_id := auth.uid();
  v_cohort_name := 'TESTE-NPS-' || regexp_replace(p_test_name, '[^A-Za-z0-9-]', '', 'g');

  -- 1. Cohort (idempotent by name)
  SELECT id INTO v_cohort_id FROM public.cohorts WHERE name = v_cohort_name LIMIT 1;
  IF v_cohort_id IS NULL THEN
    INSERT INTO public.cohorts (
      name, active, whatsapp_group_jid, whatsapp_group_verified,
      whatsapp_group_verified_at, whatsapp_group_verified_by, whatsapp_group_label
    ) VALUES (
      v_cohort_name, true, p_group_jid, true,
      NOW(), v_user_id, 'SMOKE TEST — gerado via wizard'
    )
    RETURNING id INTO v_cohort_id;
  ELSE
    UPDATE public.cohorts
       SET whatsapp_group_jid = p_group_jid,
           whatsapp_group_verified = true,
           whatsapp_group_verified_at = NOW(),
           whatsapp_group_verified_by = v_user_id,
           whatsapp_group_label = 'SMOKE TEST — gerado via wizard'
     WHERE id = v_cohort_id;
  END IF;

  -- 2. Student (idempotent by name+cohort)
  SELECT id INTO v_student_id
  FROM public.students
  WHERE cohort_id = v_cohort_id AND name = p_test_name
  LIMIT 1;

  IF v_student_id IS NULL THEN
    INSERT INTO public.students (name, phone, cohort_id, active, is_mentor)
    VALUES (p_test_name, p_phone, v_cohort_id, true, false)
    RETURNING id INTO v_student_id;
  ELSE
    UPDATE public.students
       SET phone = p_phone, active = true, is_mentor = false
     WHERE id = v_student_id;
  END IF;

  -- 3. Class (idempotent by zoom_meeting_id, otherwise by name)
  SELECT id INTO v_class_id FROM public.classes WHERE zoom_meeting_id = p_zoom_meeting_id LIMIT 1;
  IF v_class_id IS NULL THEN
    INSERT INTO public.classes (name, zoom_meeting_id, active)
    VALUES (p_class_name, p_zoom_meeting_id, true)
    RETURNING id INTO v_class_id;
  ELSE
    UPDATE public.classes
       SET name = p_class_name, active = true
     WHERE id = v_class_id;
  END IF;

  -- 4. Bind class × cohort (idempotent)
  INSERT INTO public.class_cohort_access (class_id, cohort_id)
  VALUES (v_class_id, v_cohort_id)
  ON CONFLICT DO NOTHING;

  RETURN jsonb_build_object(
    'ok', true,
    'cohort_id', v_cohort_id,
    'cohort_name', v_cohort_name,
    'student_id', v_student_id,
    'class_id', v_class_id,
    'class_name', p_class_name,
    'zoom_meeting_id', p_zoom_meeting_id,
    'group_jid', p_group_jid,
    'phone', p_phone,
    'group_verified', true,
    'message', 'Setup completo. Próximo passo: ativar dispatcher + iniciar Zoom.'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_setup_smoke_test(TEXT, TEXT, TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_setup_smoke_test(TEXT, TEXT, TEXT, TEXT, TEXT) TO authenticated;

-- Cleanup helper — soft delete the test cohort + students (preserves audit)
CREATE OR REPLACE FUNCTION public.nps_admin_cleanup_smoke_test(
  p_cohort_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cohort_name TEXT;
  v_students_affected INT;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT name INTO v_cohort_name FROM public.cohorts WHERE id = p_cohort_id;
  IF v_cohort_name IS NULL THEN
    RAISE EXCEPTION 'cohort_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_cohort_name NOT LIKE 'TESTE-NPS-%' THEN
    RAISE EXCEPTION 'safety_check: only TESTE-NPS-* cohorts can be cleaned via this RPC' USING ERRCODE = '42501';
  END IF;

  UPDATE public.cohorts SET active = false, whatsapp_group_verified = false WHERE id = p_cohort_id;
  WITH affected AS (
    UPDATE public.students SET active = false WHERE cohort_id = p_cohort_id RETURNING 1
  )
  SELECT COUNT(*) INTO v_students_affected FROM affected;

  RETURN jsonb_build_object(
    'ok', true,
    'cohort_id', p_cohort_id,
    'students_deactivated', v_students_affected
  );
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_cleanup_smoke_test(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_cleanup_smoke_test(UUID) TO authenticated;

COMMIT;
