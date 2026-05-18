-- ═══════════════════════════════════════════════════════════════════════════
-- NPS.P.6 — Guard: never allow deactivating the LAST active variant per channel.
-- Adds protection at RPC layer (frontend mirrors UX message).
-- ═══════════════════════════════════════════════════════════════════════════

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
  v_currently_active BOOLEAN;
  v_other_active INT;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT channel, active INTO v_channel, v_currently_active
  FROM public.nps_message_variants
  WHERE id = p_variant_id;

  IF v_channel IS NULL THEN
    RAISE EXCEPTION 'variant_not_found: %', p_variant_id USING ERRCODE = 'P0002';
  END IF;

  -- Group variants must have non-empty body; dm variants must keep template name
  IF v_channel = 'group' AND (p_body_template IS NULL OR LENGTH(TRIM(p_body_template)) < 10) THEN
    RAISE EXCEPTION 'body_too_short' USING ERRCODE = '22023';
  END IF;

  -- NPS.P.6 guard: block deactivating last active variant of channel
  IF v_currently_active AND NOT p_active THEN
    SELECT COUNT(*) INTO v_other_active
    FROM public.nps_message_variants
    WHERE channel = v_channel
      AND active = true
      AND id <> p_variant_id;

    IF v_other_active = 0 THEN
      RAISE EXCEPTION 'min_one_active_variant_required: cannot deactivate last % variant', v_channel
        USING ERRCODE = '23514';
    END IF;
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

COMMENT ON FUNCTION public.nps_admin_update_variant IS
  'NPS.P.6: blocks deactivating the last active variant per channel to prevent silent dispatch failures.';
