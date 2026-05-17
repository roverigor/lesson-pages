-- ═══════════════════════════════════════════════════════════════════════════
-- P3 — RPCs: enqueue dispatch, round-robin variant, resolve eligible students
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Helper: read config value ───
CREATE OR REPLACE FUNCTION public.nps_config_value(p_key TEXT)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT value FROM public.nps_dispatch_config WHERE key = p_key;
$$;

CREATE OR REPLACE FUNCTION public.nps_config_bool(p_key TEXT, p_default BOOLEAN DEFAULT false)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT value::boolean FROM public.nps_dispatch_config WHERE key = p_key),
    p_default
  );
$$;

CREATE OR REPLACE FUNCTION public.nps_config_int(p_key TEXT, p_default INT DEFAULT 0)
RETURNS INT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT value::int FROM public.nps_dispatch_config WHERE key = p_key),
    p_default
  );
$$;

-- ─── Enqueue: insert job idempotently with feature-flag + cooldown + holiday checks ───
CREATE OR REPLACE FUNCTION public.enqueue_nps_class_dispatch(
  p_class_id     UUID,
  p_cohort_id    UUID,
  p_session_date DATE,
  p_zoom_meeting_id TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_enabled BOOLEAN;
  v_cooldown_hours INT;
  v_delay_minutes INT;
  v_holiday BOOLEAN;
  v_recent_job_count INT;
  v_job_id UUID;
  v_existing_id UUID;
BEGIN
  -- 1. Master flag
  v_enabled := public.nps_config_bool('nps_dispatch_enabled', false);
  IF NOT v_enabled THEN
    RETURN jsonb_build_object('enqueued', false, 'reason', 'feature_disabled');
  END IF;

  -- 2. Holiday check
  v_holiday := public.is_holiday(p_session_date);
  IF v_holiday THEN
    RETURN jsonb_build_object('enqueued', false, 'reason', 'holiday');
  END IF;

  -- 3. Cohort existence
  IF NOT EXISTS (SELECT 1 FROM public.cohorts WHERE id = p_cohort_id) THEN
    RETURN jsonb_build_object('enqueued', false, 'reason', 'cohort_not_found');
  END IF;

  -- 4. Idempotency check (active job exists)
  SELECT id INTO v_existing_id
  FROM public.nps_class_dispatch_jobs
  WHERE cohort_id = p_cohort_id
    AND COALESCE(class_id, '00000000-0000-0000-0000-000000000000'::uuid)
        = COALESCE(p_class_id, '00000000-0000-0000-0000-000000000000'::uuid)
    AND session_date = p_session_date
    AND status NOT IN ('skipped','failed')
  LIMIT 1;

  IF v_existing_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'enqueued', false,
      'reason', 'already_exists',
      'job_id', v_existing_id
    );
  END IF;

  -- 5. Cooldown check (recent successful or pending job for cohort)
  v_cooldown_hours := public.nps_config_int('nps_cohort_cooldown_hours', 12);
  SELECT COUNT(*) INTO v_recent_job_count
  FROM public.nps_class_dispatch_jobs
  WHERE cohort_id = p_cohort_id
    AND created_at > NOW() - (v_cooldown_hours || ' hours')::interval
    AND status IN ('pending','in_progress','sent','partial');

  IF v_recent_job_count > 0 THEN
    RETURN jsonb_build_object(
      'enqueued', false,
      'reason', 'cooldown_active',
      'cooldown_hours', v_cooldown_hours
    );
  END IF;

  -- 6. Insert job
  v_delay_minutes := public.nps_config_int('nps_dispatch_delay_minutes', 5);

  INSERT INTO public.nps_class_dispatch_jobs (
    class_id, cohort_id, session_date, zoom_meeting_id, scheduled_at
  ) VALUES (
    p_class_id, p_cohort_id, p_session_date, p_zoom_meeting_id,
    NOW() + (v_delay_minutes || ' minutes')::interval
  )
  RETURNING id INTO v_job_id;

  RETURN jsonb_build_object(
    'enqueued', true,
    'job_id', v_job_id,
    'scheduled_at', NOW() + (v_delay_minutes || ' minutes')::interval
  );
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_nps_class_dispatch(UUID, UUID, DATE, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.enqueue_nps_class_dispatch(UUID, UUID, DATE, TEXT) TO service_role, authenticated;

-- ─── Round-robin variant picker (atomic) ───
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
  v_chosen TEXT;
BEGIN
  IF p_channel NOT IN ('group','dm') THEN
    RAISE EXCEPTION 'invalid channel: %', p_channel;
  END IF;

  -- Pick next variant: order by (id > last_id) then wrap to smallest id
  WITH last_state AS (
    SELECT last_variant_id FROM public.nps_variant_rotation_state WHERE channel = p_channel
  ),
  ordered AS (
    SELECT v.id
    FROM public.nps_message_variants v, last_state ls
    WHERE v.channel = p_channel AND v.active = true
      AND (ls.last_variant_id IS NULL OR v.id > ls.last_variant_id)
    ORDER BY v.id ASC
    LIMIT 1
  ),
  wrap AS (
    SELECT v.id
    FROM public.nps_message_variants v
    WHERE v.channel = p_channel AND v.active = true
    ORDER BY v.id ASC
    LIMIT 1
  )
  SELECT COALESCE((SELECT id FROM ordered), (SELECT id FROM wrap))
    INTO v_chosen;

  IF v_chosen IS NULL THEN
    RETURN; -- empty set, caller handles
  END IF;

  -- Atomic state update
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

-- ─── Resolve eligible students (PS attendance-gated vs cohort all-enrolled) ───
-- PS cohorts identified by name pattern; safer: cohort flag.
-- For V1, use attendance for ALL classes if attendance rows exist for session_date.
-- If none, fall back to all enrolled.
CREATE OR REPLACE FUNCTION public.nps_resolve_eligible_students(
  p_class_id     UUID,
  p_cohort_id    UUID,
  p_session_date DATE
)
RETURNS TABLE (
  student_id     UUID,
  name           TEXT,
  phone          TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_has_attendance BOOLEAN := false;
BEGIN
  -- Check if student_attendance rows exist for this cohort + date
  SELECT EXISTS (
    SELECT 1 FROM public.student_attendance
    WHERE cohort_id = p_cohort_id
      AND class_date = p_session_date
    LIMIT 1
  ) INTO v_has_attendance;

  IF v_has_attendance THEN
    -- Attendance-gated: only present students
    RETURN QUERY
    SELECT DISTINCT s.id, s.name, s.phone
    FROM public.students s
    JOIN public.student_attendance sa ON sa.student_id = s.id
    WHERE sa.cohort_id = p_cohort_id
      AND sa.class_date = p_session_date
      AND s.cohort_id = p_cohort_id
      AND s.active = true
      AND COALESCE(s.is_mentor, false) = false
      AND s.phone IS NOT NULL
      AND TRIM(s.phone) <> '';
  ELSE
    -- All-enrolled fallback (cohort fechado sem registro de presença)
    RETURN QUERY
    SELECT s.id, s.name, s.phone
    FROM public.students s
    WHERE s.cohort_id = p_cohort_id
      AND s.active = true
      AND COALESCE(s.is_mentor, false) = false
      AND s.phone IS NOT NULL
      AND TRIM(s.phone) <> '';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.nps_resolve_eligible_students(UUID, UUID, DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_resolve_eligible_students(UUID, UUID, DATE) TO service_role;

COMMENT ON FUNCTION public.enqueue_nps_class_dispatch IS
  'P3: idempotent enqueue. Checks feature flag, holiday, cooldown, dedup.';

COMMENT ON FUNCTION public.nps_next_variant IS
  'P3: atomic round-robin variant chooser per channel.';

COMMENT ON FUNCTION public.nps_resolve_eligible_students IS
  'P3: eligible students for DM. Uses attendance gate when available, else all enrolled.';
