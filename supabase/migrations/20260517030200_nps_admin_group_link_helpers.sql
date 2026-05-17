-- ═══════════════════════════════════════════════════════════════════════════
-- NPS admin UI — expose whatsapp_group_link in list + zoom binding info
-- for pending jobs. Plus RPC to enqueue invite-link refresh request.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- Replace list to include invite link, zoom meeting binding via classes
CREATE OR REPLACE FUNCTION public.nps_admin_list_cohort_groups()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows JSONB;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT jsonb_build_object(
      'cohort_id', c.id,
      'cohort_name', c.name,
      'whatsapp_group_jid', c.whatsapp_group_jid,
      'whatsapp_group_link', c.whatsapp_group_link,
      'jid_valid_format', public.nps_is_valid_group_jid(c.whatsapp_group_jid),
      'verified', c.whatsapp_group_verified,
      'verified_at', c.whatsapp_group_verified_at,
      'verified_by', c.whatsapp_group_verified_by,
      'label', c.whatsapp_group_label,
      'active_students_count', (
        SELECT COUNT(*) FROM public.students s
        WHERE s.cohort_id = c.id AND s.active = true AND COALESCE(s.is_mentor, false) = false
      ),
      'classes_bound', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'class_id', cl.id,
          'class_name', cl.name,
          'zoom_meeting_id', cl.zoom_meeting_id
        )), '[]'::jsonb)
        FROM public.classes cl
        JOIN public.class_cohort_access cca ON cca.class_id = cl.id
        WHERE cca.cohort_id = c.id
      )
    ) AS row
    FROM public.cohorts c
    WHERE c.whatsapp_group_jid IS NOT NULL
    ORDER BY c.whatsapp_group_verified ASC, c.name
  ) sub;

  RETURN v_rows;
END;
$$;

-- RPC to trigger invite-link fetch via existing edge function
-- (pg_net call; admin clicks "atualizar invite" in UI)
CREATE OR REPLACE FUNCTION public.nps_admin_refresh_group_invite(
  p_cohort_id UUID
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_fn_url  TEXT;
  v_svc_key TEXT;
  v_request_id BIGINT;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT value INTO v_fn_url FROM public.app_config WHERE key = 'fetch_group_invite_links_url';
  IF v_fn_url IS NULL THEN
    -- Fallback to convention
    v_fn_url := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/fetch-group-invite-links';
  END IF;

  SELECT value INTO v_svc_key FROM public.app_config WHERE key = 'supabase_service_key';

  IF v_svc_key IS NULL THEN
    RAISE EXCEPTION 'service_key_missing in app_config' USING ERRCODE = '42501';
  END IF;

  SELECT net.http_post(
    url     := v_fn_url,
    body    := jsonb_build_object('cohort_id', p_cohort_id),
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_svc_key,
      'Content-Type',  'application/json'
    )
  ) INTO v_request_id;

  RETURN jsonb_build_object(
    'ok', true,
    'queued', true,
    'http_request_id', v_request_id,
    'message', 'Invite refresh requested. Reload em ~10s pra ver link atualizado.'
  );
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_refresh_group_invite(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_refresh_group_invite(UUID) TO authenticated;

-- Update dashboard to include zoom binding on pending jobs (helpful for trigger debug)
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

  SELECT jsonb_object_agg(key, value) INTO v_config FROM public.nps_dispatch_config;

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
  )) INTO v_rotation FROM public.nps_variant_rotation_state;

  -- Pending jobs now include zoom_meeting_id for class binding visibility
  SELECT COALESCE(jsonb_agg(row), '[]'::jsonb) INTO v_pending_jobs
  FROM (
    SELECT jsonb_build_object(
      'id', j.id,
      'class_id', j.class_id,
      'cohort_id', j.cohort_id,
      'cohort_name', c.name,
      'class_name', cl.name,
      'class_zoom_meeting_id', cl.zoom_meeting_id,
      'job_zoom_meeting_id', j.zoom_meeting_id,
      'session_date', j.session_date,
      'status', j.status,
      'scheduled_at', j.scheduled_at,
      'started_at', j.started_at,
      'total_eligible_students', j.total_eligible_students,
      'dm_sent_count', j.dm_sent_count,
      'dm_failed_count', j.dm_failed_count,
      'group_send_status', j.group_send_status,
      'cohort_group_verified', c.whatsapp_group_verified
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
      'error_detail', j.error_detail,
      'variant_group_id', j.variant_group_id,
      'variant_dm_id', j.variant_dm_id
    ) AS row
    FROM public.nps_class_dispatch_jobs j
    LEFT JOIN public.cohorts c ON c.id = j.cohort_id
    LEFT JOIN public.classes cl ON cl.id = j.class_id
    WHERE j.status IN ('sent','partial','failed','skipped')
    ORDER BY j.finished_at DESC NULLS LAST
    LIMIT 20
  ) sub;

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

COMMIT;
