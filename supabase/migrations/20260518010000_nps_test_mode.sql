-- ═══════════════════════════════════════════════════════════════════════════
-- NPS Test Mode — Redirect ALL dispatches to a single phone/group for
-- end-to-end testing without spamming real students.
--
-- When enabled:
--   - Every DM goes to nps_test_mode_phone (regardless of student.phone)
--   - Group send goes to nps_test_mode_group_jid (if set) OR is skipped
--   - dm_skipped/dm_sent counters still reflect ACTUAL students processed
--   - Tokens are still created per-student (response attribution works)
--
-- Default: OFF. Designed to be toggled in seconds without redeploys.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

INSERT INTO public.nps_dispatch_config (key, value, description) VALUES
  ('nps_test_mode_enabled', 'false',
   'When true: redirects every DM to nps_test_mode_phone and group sends to nps_test_mode_group_jid (or skips). Tokens still created per real student.'),
  ('nps_test_mode_phone', '',
   'Phone override for DMs when test mode is on. Format: digits only, with country code. Ex: 5543999250490'),
  ('nps_test_mode_group_jid', '',
   'Group JID override for group sends when test mode is on. Leave empty to skip group sends entirely during test mode.')
ON CONFLICT (key) DO NOTHING;

-- Extend whitelist in nps_admin_set_config (replace fn)
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
    'nps_test_mode_group_jid'
  ) THEN
    RAISE EXCEPTION 'invalid_key: %', p_key USING ERRCODE = '22023';
  END IF;

  IF p_key IN ('nps_dispatch_enabled','nps_test_mode_enabled') AND p_value NOT IN ('true','false') THEN
    RAISE EXCEPTION 'invalid_boolean_value: %', p_value USING ERRCODE = '22023';
  END IF;

  IF p_key IN ('nps_cohort_cooldown_hours','nps_dispatch_delay_minutes','nps_dispatch_max_dm_per_run') THEN
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

  -- Phone format: digits only, 10-15 chars (E.164-ish)
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

  -- Safety gate: cannot enable test mode without phone configured
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

COMMIT;
