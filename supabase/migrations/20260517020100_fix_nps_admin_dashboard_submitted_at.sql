-- ═══════════════════════════════════════════════════════════════════════════
-- NPS.U.1 — Fix nps_admin_dashboard: class_nps_responses uses submitted_at
-- not created_at (column doesn't exist).
-- Architect review 2026-05-17, finding #5.
-- ═══════════════════════════════════════════════════════════════════════════

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

  SELECT jsonb_object_agg(key, value) INTO v_config
  FROM public.nps_dispatch_config;

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

  SELECT jsonb_object_agg(channel, jsonb_build_object(
    'last_variant_id', last_variant_id,
    'rotation_count', rotation_count,
    'updated_at', updated_at
  )) INTO v_rotation
  FROM public.nps_variant_rotation_state;

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

  -- 24h stats — NPS.U.1 fix: class_nps_responses has submitted_at, not created_at
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
       WHERE submitted_at > NOW() - interval '24 hours'
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

COMMENT ON FUNCTION public.nps_admin_dashboard IS
  'NPS.U.1 fix: uses class_nps_responses.submitted_at (not nonexistent created_at).';
