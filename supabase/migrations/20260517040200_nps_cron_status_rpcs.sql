-- ═══════════════════════════════════════════════════════════════════════════
-- NPS.P.7 — Cron status + register/unregister RPCs (admin only)
-- Surfaces cron.job + cron.job_run_details to the monitor UI.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Status: returns whether dispatch-class-nps-tick is registered + last run ───
CREATE OR REPLACE FUNCTION public.nps_admin_cron_status()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, cron
AS $$
DECLARE
  v_job RECORD;
  v_last RECORD;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT jobid, jobname, schedule, active
    INTO v_job
    FROM cron.job
   WHERE jobname = 'dispatch-class-nps-tick'
   LIMIT 1;

  IF v_job IS NULL THEN
    RETURN jsonb_build_object(
      'registered', false,
      'jobname', 'dispatch-class-nps-tick'
    );
  END IF;

  -- Last run details (may not exist on fresh registration)
  BEGIN
    SELECT start_time, end_time, status, return_message
      INTO v_last
      FROM cron.job_run_details
     WHERE jobid = v_job.jobid
     ORDER BY start_time DESC
     LIMIT 1;
  EXCEPTION WHEN OTHERS THEN
    v_last := NULL;
  END;

  RETURN jsonb_build_object(
    'registered', true,
    'jobname', v_job.jobname,
    'schedule', v_job.schedule,
    'active', v_job.active,
    'last_run', CASE WHEN v_last.start_time IS NULL THEN NULL ELSE jsonb_build_object(
      'start_time', v_last.start_time,
      'end_time', v_last.end_time,
      'status', v_last.status,
      'return_message', v_last.return_message
    ) END
  );
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_cron_status() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_cron_status() TO authenticated;

-- ─── Register cron (idempotent — only if missing) ───
CREATE OR REPLACE FUNCTION public.nps_admin_register_cron()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_already_exists BOOLEAN;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dispatch-class-nps-tick')
    INTO v_already_exists;

  IF v_already_exists THEN
    RETURN jsonb_build_object('ok', true, 'already_registered', true);
  END IF;

  PERFORM cron.schedule(
    'dispatch-class-nps-tick',
    '*/5 * * * *',
    $cron$
    DO $inner$
    DECLARE
      fn_url  TEXT;
      svc_key TEXT;
    BEGIN
      SELECT value INTO fn_url  FROM public.app_config WHERE key = 'dispatch_class_nps_url';
      SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';
      IF fn_url IS NOT NULL AND svc_key IS NOT NULL THEN
        PERFORM net.http_post(
          url     := fn_url,
          body    := '{}'::jsonb,
          headers := json_build_object(
            'Authorization', 'Bearer ' || svc_key,
            'Content-Type',  'application/json'
          )::jsonb
        );
      END IF;
    END;
    $inner$;
    $cron$
  );

  RETURN jsonb_build_object('ok', true, 'registered', true);
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_register_cron() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_register_cron() TO authenticated;

-- ─── Unregister cron ───
CREATE OR REPLACE FUNCTION public.nps_admin_unregister_cron()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dispatch-class-nps-tick') THEN
    RETURN jsonb_build_object('ok', true, 'already_unregistered', true);
  END IF;

  PERFORM cron.unschedule('dispatch-class-nps-tick');
  RETURN jsonb_build_object('ok', true, 'unregistered', true);
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_unregister_cron() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_unregister_cron() TO authenticated;
