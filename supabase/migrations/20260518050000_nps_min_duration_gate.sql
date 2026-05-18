-- ═══════════════════════════════════════════════════════════════════════════
-- NPS anti-test-meeting gate — duration check before enqueue
--
-- Problem: Zoom meetings <1h likely are TESTS (mentor checking audio, etc),
-- not real classes. Dispatching NPS to all students for tests = bad UX.
--
-- Solution: config flag nps_dispatch_min_duration_minutes (default 60).
-- Trigger reads zoom_meetings.duration_minutes (or computes from end-start)
-- and skips enqueue if below threshold.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- 1. Seed config flag
INSERT INTO public.nps_dispatch_config (key, value, description) VALUES
  ('nps_dispatch_min_duration_minutes', '60',
   'Skip NPS dispatch for Zoom meetings shorter than this (treats short meetings as tests/check-ins). Set 0 to disable.')
ON CONFLICT (key) DO NOTHING;

-- 2. Extend nps_admin_set_config whitelist
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

  IF p_key NOT IN (
    'nps_dispatch_enabled',
    'nps_cohort_cooldown_hours',
    'nps_dispatch_delay_minutes',
    'nps_dispatch_max_dm_per_run',
    'nps_dispatch_dm_throttle_ms',
    'nps_test_mode_enabled',
    'nps_test_mode_phone',
    'nps_test_mode_group_jid',
    'nps_dispatch_min_duration_minutes'
  ) THEN
    RAISE EXCEPTION 'invalid_key: %', p_key USING ERRCODE = '22023';
  END IF;

  IF p_key IN ('nps_dispatch_enabled','nps_test_mode_enabled') AND p_value NOT IN ('true','false') THEN
    RAISE EXCEPTION 'invalid_boolean_value: %', p_value USING ERRCODE = '22023';
  END IF;

  IF p_key IN ('nps_cohort_cooldown_hours','nps_dispatch_delay_minutes','nps_dispatch_max_dm_per_run','nps_dispatch_min_duration_minutes') THEN
    BEGIN PERFORM p_value::int;
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

  IF p_key = 'nps_test_mode_phone' AND p_value <> '' THEN
    IF p_value !~ '^[0-9]{10,15}$' THEN
      RAISE EXCEPTION 'invalid_phone_format: digits only, country code required (10-15 chars). Got: %', p_value USING ERRCODE = '22023';
    END IF;
  END IF;

  IF p_key = 'nps_test_mode_group_jid' AND p_value <> '' THEN
    IF NOT public.nps_is_valid_group_jid(p_value) THEN
      RAISE EXCEPTION 'invalid_group_jid_format' USING ERRCODE = '22023';
    END IF;
  END IF;

  IF p_key = 'nps_test_mode_enabled' AND p_value = 'true' THEN
    IF (SELECT value FROM public.nps_dispatch_config WHERE key = 'nps_test_mode_phone') = '' THEN
      RAISE EXCEPTION 'test_phone_not_configured: set nps_test_mode_phone first' USING ERRCODE = '22023';
    END IF;
  END IF;

  UPDATE public.nps_dispatch_config
     SET value = p_value, updated_at = NOW()
   WHERE key = p_key;

  RETURN jsonb_build_object('ok', true, 'key', p_key, 'value', p_value);
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_set_config(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_set_config(TEXT, TEXT) TO authenticated;

-- 3. Update trigger to check duration before enqueue (anti test-meeting gate)
CREATE OR REPLACE FUNCTION public.trg_enqueue_nps_after_zoom_processed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_class_id      UUID;
  v_session_date  DATE;
  v_cohort_rec    RECORD;
  v_enqueue_result JSONB;
  v_jobs_enqueued INT := 0;
  v_min_duration  INT;
  v_duration      INT;
BEGIN
  -- Only fire when processed flips false → true
  IF NOT (NEW.processed = true AND COALESCE(OLD.processed, false) = false) THEN
    RETURN NEW;
  END IF;

  -- ─── Anti test-meeting gate ─────────────────────────────────────────
  v_min_duration := public.nps_config_int('nps_dispatch_min_duration_minutes', 60);

  -- Use stored duration_minutes if present, else compute from start/end
  v_duration := NEW.duration_minutes;
  IF v_duration IS NULL AND NEW.start_time IS NOT NULL AND NEW.end_time IS NOT NULL THEN
    v_duration := EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time))::int / 60;
  END IF;

  IF v_min_duration > 0 AND v_duration IS NOT NULL AND v_duration < v_min_duration THEN
    RAISE NOTICE 'nps-hook: SKIPPED meeting % — duration % min < threshold % min (likely test)',
      NEW.id, v_duration, v_min_duration;
    RETURN NEW;
  END IF;

  v_session_date := (NEW.start_time AT TIME ZONE 'America/Sao_Paulo')::date;

  -- Resolve class_id via classes.zoom_meeting_id direct match
  SELECT c.id INTO v_class_id
  FROM public.classes c
  WHERE c.zoom_meeting_id = NEW.zoom_meeting_id
  LIMIT 1;

  -- Multi-cohort loop (NPS.E.2)
  IF v_class_id IS NOT NULL THEN
    FOR v_cohort_rec IN
      SELECT cca.cohort_id
        FROM public.class_cohort_access cca
       WHERE cca.class_id = v_class_id
    LOOP
      BEGIN
        SELECT public.enqueue_nps_class_dispatch(
          v_class_id, v_cohort_rec.cohort_id, v_session_date, NEW.zoom_meeting_id
        ) INTO v_enqueue_result;

        IF (v_enqueue_result->>'enqueued')::boolean THEN
          v_jobs_enqueued := v_jobs_enqueued + 1;
        END IF;
      EXCEPTION WHEN OTHERS THEN
        RAISE WARNING 'nps-hook: enqueue failed meeting=% cohort=% err=%',
          NEW.id, v_cohort_rec.cohort_id, SQLERRM;
      END;
    END LOOP;
  END IF;

  -- Legacy fallback (single cohort)
  IF v_class_id IS NULL AND NEW.cohort_id IS NOT NULL THEN
    BEGIN
      SELECT public.enqueue_nps_class_dispatch(
        NULL, NEW.cohort_id, v_session_date, NEW.zoom_meeting_id
      ) INTO v_enqueue_result;
      IF (v_enqueue_result->>'enqueued')::boolean THEN
        v_jobs_enqueued := v_jobs_enqueued + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'nps-hook: legacy enqueue failed meeting=% err=%', NEW.id, SQLERRM;
    END;
  END IF;

  RAISE NOTICE 'nps-hook: meeting % duration % min, jobs enqueued %', NEW.id, v_duration, v_jobs_enqueued;
  RETURN NEW;
END;
$$;

COMMIT;
