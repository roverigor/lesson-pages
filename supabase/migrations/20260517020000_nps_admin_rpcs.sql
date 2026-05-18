-- ═══════════════════════════════════════════════════════════════════════════
-- P3-UI — Admin RPCs for nps-monitor dashboard
-- Wraps config + variants + jobs with admin-only auth.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Master dashboard payload ───
CREATE OR REPLACE FUNCTION public.nps_admin_dashboard()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_config JSONB;
  v_variants JSONB;
  v_rotation JSONB;
  v_pending_jobs JSONB;
  v_recent_jobs JSONB;
  v_stats JSONB;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  -- Config map
  SELECT jsonb_object_agg(key, value) INTO v_config
  FROM public.nps_dispatch_config;

  -- Variants grouped by channel
  SELECT jsonb_build_object(
    'group', COALESCE((SELECT jsonb_agg(
      jsonb_build_object(
        'id', id, 'channel', channel, 'body_template', body_template,
        'meta_template_name', meta_template_name, 'active', active,
        'weight', weight, 'created_at', created_at
      ) ORDER BY id
    ) FROM public.nps_message_variants WHERE channel = 'group'), '[]'::jsonb),
    'dm', COALESCE((SELECT jsonb_agg(
      jsonb_build_object(
        'id', id, 'channel', channel, 'body_template', body_template,
        'meta_template_name', meta_template_name, 'active', active,
        'weight', weight, 'created_at', created_at
      ) ORDER BY id
    ) FROM public.nps_message_variants WHERE channel = 'dm'), '[]'::jsonb)
  ) INTO v_variants;

  -- Rotation state
  SELECT jsonb_object_agg(channel, jsonb_build_object(
    'last_variant_id', last_variant_id,
    'rotation_count', rotation_count,
    'updated_at', updated_at
  )) INTO v_rotation
  FROM public.nps_variant_rotation_state;

  -- Pending + in_progress jobs (next 20)
  SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) INTO v_pending_jobs
  FROM (
    SELECT jsonb_build_object(
      'id', j.id,
      'class_id', j.class_id,
      'cohort_id', j.cohort_id,
      'cohort_name', c.name,
      'class_name', cl.name,
      'session_date', j.session_date,
      'status', j.status,
      'scheduled_at', j.scheduled_at,
      'started_at', j.started_at,
      'total_eligible_students', j.total_eligible_students,
      'dm_sent_count', j.dm_sent_count,
      'dm_failed_count', j.dm_failed_count,
      'group_send_status', j.group_send_status
    ) AS row
    FROM public.nps_class_dispatch_jobs j
    LEFT JOIN public.cohorts c ON c.id = j.cohort_id
    LEFT JOIN public.classes cl ON cl.id = j.class_id
    WHERE j.status IN ('pending','in_progress')
    ORDER BY j.scheduled_at ASC
    LIMIT 20
  ) sub;

  -- Recent finished jobs (last 20)
  SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) INTO v_recent_jobs
  FROM (
    SELECT jsonb_build_object(
      'id', j.id,
      'cohort_name', c.name,
      'class_name', cl.name,
      'session_date', j.session_date,
      'status', j.status,
      'finished_at', j.finished_at,
      'dm_sent_count', j.dm_sent_count,
      'dm_failed_count', j.dm_failed_count,
      'group_send_status', j.group_send_status,
      'error_detail', j.error_detail
    ) AS row
    FROM public.nps_class_dispatch_jobs j
    LEFT JOIN public.cohorts c ON c.id = j.cohort_id
    LEFT JOIN public.classes cl ON cl.id = j.class_id
    WHERE j.status IN ('sent','partial','failed','skipped')
    ORDER BY j.finished_at DESC NULLS LAST
    LIMIT 20
  ) sub;

  -- 24h stats
  SELECT jsonb_build_object(
    'jobs_24h', COUNT(*),
    'jobs_sent_24h', COUNT(*) FILTER (WHERE status = 'sent'),
    'jobs_partial_24h', COUNT(*) FILTER (WHERE status = 'partial'),
    'jobs_failed_24h', COUNT(*) FILTER (WHERE status = 'failed'),
    'dm_sent_24h', COALESCE(SUM(dm_sent_count), 0),
    'dm_failed_24h', COALESCE(SUM(dm_failed_count), 0),
    'opens_24h', (
      SELECT COUNT(*) FROM public.dispatch_link_opens
       WHERE source = 'nps_class_link' AND opened_at > NOW() - interval '24 hours'
    ),
    'responses_24h', (
      SELECT COUNT(*) FROM public.class_nps_responses
       WHERE created_at > NOW() - interval '24 hours'
    )
  ) INTO v_stats
  FROM public.nps_class_dispatch_jobs
  WHERE created_at > NOW() - interval '24 hours';

  RETURN jsonb_build_object(
    'config', v_config,
    'variants', v_variants,
    'rotation', v_rotation,
    'pending_jobs', v_pending_jobs,
    'recent_jobs', v_recent_jobs,
    'stats', v_stats,
    'fetched_at', NOW()
  );
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_dashboard() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_dashboard() TO authenticated;

-- ─── Set config value ───
CREATE OR REPLACE FUNCTION public.nps_admin_set_config(
  p_key   TEXT,
  p_value TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  -- Whitelist allowed keys
  IF p_key NOT IN (
    'nps_dispatch_enabled',
    'nps_cohort_cooldown_hours',
    'nps_dispatch_delay_minutes',
    'nps_dispatch_max_dm_per_run',
    'nps_dispatch_dm_throttle_ms'
  ) THEN
    RAISE EXCEPTION 'invalid_key: %', p_key USING ERRCODE = '22023';
  END IF;

  -- Validation by key
  IF p_key = 'nps_dispatch_enabled' AND p_value NOT IN ('true','false') THEN
    RAISE EXCEPTION 'invalid_value for boolean: %', p_value USING ERRCODE = '22023';
  END IF;

  IF p_key IN ('nps_cohort_cooldown_hours','nps_dispatch_delay_minutes','nps_dispatch_max_dm_per_run') THEN
    BEGIN
      PERFORM p_value::int;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'invalid_int_value: %', p_value USING ERRCODE = '22023';
    END;
  END IF;

  IF p_key = 'nps_dispatch_dm_throttle_ms' THEN
    BEGIN
      IF p_value::int < 1000 THEN
        RAISE EXCEPTION 'throttle_too_low: min 1000ms' USING ERRCODE = '22023';
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE EXCEPTION 'invalid_throttle: %', p_value USING ERRCODE = '22023';
    END;
  END IF;

  UPDATE public.nps_dispatch_config
     SET value = p_value, updated_at = NOW()
   WHERE key = p_key;

  RETURN jsonb_build_object('ok', true, 'key', p_key, 'value', p_value);
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_set_config(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_set_config(TEXT, TEXT) TO authenticated;

-- ─── Update variant (body + active toggle) ───
CREATE OR REPLACE FUNCTION public.nps_admin_update_variant(
  p_variant_id     TEXT,
  p_body_template  TEXT,
  p_active         BOOLEAN
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_channel TEXT;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT channel INTO v_channel
  FROM public.nps_message_variants
  WHERE id = p_variant_id;

  IF v_channel IS NULL THEN
    RAISE EXCEPTION 'variant_not_found: %', p_variant_id USING ERRCODE = 'P0002';
  END IF;

  -- Group variants must have non-empty body; dm variants must keep template name
  IF v_channel = 'group' AND (p_body_template IS NULL OR LENGTH(TRIM(p_body_template)) < 10) THEN
    RAISE EXCEPTION 'body_too_short' USING ERRCODE = '22023';
  END IF;

  UPDATE public.nps_message_variants
     SET body_template = p_body_template,
         active = p_active
   WHERE id = p_variant_id;

  RETURN jsonb_build_object('ok', true, 'variant_id', p_variant_id);
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_update_variant(TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_update_variant(TEXT, TEXT, BOOLEAN) TO authenticated;

-- ─── Skip job (mark as skipped manually) ───
CREATE OR REPLACE FUNCTION public.nps_admin_skip_job(
  p_job_id UUID,
  p_reason TEXT DEFAULT 'manual_skip'
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_status TEXT;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_current_status
  FROM public.nps_class_dispatch_jobs
  WHERE id = p_job_id;

  IF v_current_status IS NULL THEN
    RAISE EXCEPTION 'job_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_current_status NOT IN ('pending','in_progress') THEN
    RAISE EXCEPTION 'job_not_skippable: status=%', v_current_status USING ERRCODE = '22023';
  END IF;

  UPDATE public.nps_class_dispatch_jobs
     SET status = 'skipped',
         finished_at = NOW(),
         error_detail = p_reason
   WHERE id = p_job_id;

  RETURN jsonb_build_object('ok', true, 'job_id', p_job_id, 'reason', p_reason);
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_skip_job(UUID, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_skip_job(UUID, TEXT) TO authenticated;

-- ─── Force job now (move scheduled_at to NOW) ───
CREATE OR REPLACE FUNCTION public.nps_admin_force_job_now(
  p_job_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT status INTO v_status
  FROM public.nps_class_dispatch_jobs
  WHERE id = p_job_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'job_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_status <> 'pending' THEN
    RAISE EXCEPTION 'job_not_pending: status=%', v_status USING ERRCODE = '22023';
  END IF;

  UPDATE public.nps_class_dispatch_jobs
     SET scheduled_at = NOW()
   WHERE id = p_job_id;

  RETURN jsonb_build_object('ok', true, 'job_id', p_job_id);
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_force_job_now(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_force_job_now(UUID) TO authenticated;

-- ─── Reset stuck job (in_progress → pending) ───
CREATE OR REPLACE FUNCTION public.nps_admin_reset_stuck_job(
  p_job_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_status TEXT;
  v_started TIMESTAMPTZ;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT status, started_at INTO v_status, v_started
  FROM public.nps_class_dispatch_jobs
  WHERE id = p_job_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'job_not_found' USING ERRCODE = 'P0002';
  END IF;

  IF v_status <> 'in_progress' THEN
    RAISE EXCEPTION 'job_not_stuck: status=%', v_status USING ERRCODE = '22023';
  END IF;

  -- Safety: only allow reset if started_at older than 15min (avoid racing live runs)
  IF v_started > NOW() - interval '15 minutes' THEN
    RAISE EXCEPTION 'job_too_recent: wait 15min before reset' USING ERRCODE = '22023';
  END IF;

  UPDATE public.nps_class_dispatch_jobs
     SET status = 'pending',
         started_at = NULL,
         scheduled_at = NOW()
   WHERE id = p_job_id;

  RETURN jsonb_build_object('ok', true, 'job_id', p_job_id);
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_reset_stuck_job(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_reset_stuck_job(UUID) TO authenticated;

COMMENT ON FUNCTION public.nps_admin_dashboard IS
  'P3-UI: returns config + variants + rotation + jobs (pending + recent) + 24h stats. Admin only.';

COMMENT ON FUNCTION public.nps_admin_set_config IS
  'P3-UI: whitelisted config key/value setter with type validation. Admin only.';

COMMENT ON FUNCTION public.nps_admin_update_variant IS
  'P3-UI: edit body_template + active flag of a variant. Admin only.';

COMMENT ON FUNCTION public.nps_admin_skip_job IS
  'P3-UI: cancel pending/in_progress job. Marks status=skipped.';

COMMENT ON FUNCTION public.nps_admin_force_job_now IS
  'P3-UI: bring forward scheduled_at to NOW for pending job.';

COMMENT ON FUNCTION public.nps_admin_reset_stuck_job IS
  'P3-UI: reset in_progress job to pending if started_at > 15min ago.';
