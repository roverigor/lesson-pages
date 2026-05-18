-- ═══════════════════════════════════════════════════════════════════════════
-- NPS Safety L1+L2 — cohort.whatsapp_group_verified flag + JID format CHECK
--
-- Goal: prevent dispatch-class-nps from sending to wrong group.
-- Adds verified flag — dispatcher MUST require true before group send.
-- Adds soft format validation (warns, doesn't drop bad rows on apply).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- 1. Add verified flag (default false — opt-in safety)
ALTER TABLE public.cohorts
  ADD COLUMN IF NOT EXISTS whatsapp_group_verified BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS whatsapp_group_verified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS whatsapp_group_verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS whatsapp_group_label TEXT;  -- human-friendly label (fetched once or set manually)

CREATE INDEX IF NOT EXISTS idx_cohorts_wa_group_verified
  ON public.cohorts (whatsapp_group_verified)
  WHERE whatsapp_group_jid IS NOT NULL;

COMMENT ON COLUMN public.cohorts.whatsapp_group_verified IS
  'Safety gate: dispatch-class-nps SKIPS group send unless TRUE. Set via admin UI after visual confirmation.';

-- 2. Validation helper — checks JID format without raising
CREATE OR REPLACE FUNCTION public.nps_is_valid_group_jid(p_jid TEXT)
RETURNS BOOLEAN
LANGUAGE sql
IMMUTABLE
AS $$
  -- Evolution groups end in @g.us; the prefix is the group ID
  SELECT p_jid IS NOT NULL
     AND p_jid ~ '^[0-9A-Za-z._-]+@g\.us$'
     AND length(p_jid) BETWEEN 12 AND 64;
$$;

GRANT EXECUTE ON FUNCTION public.nps_is_valid_group_jid(TEXT) TO authenticated, service_role;

-- 3. Admin RPC: set verified flag (idempotent + audit)
CREATE OR REPLACE FUNCTION public.nps_admin_set_cohort_group_verified(
  p_cohort_id UUID,
  p_verified  BOOLEAN,
  p_label     TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_jid TEXT;
  v_user UUID;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT whatsapp_group_jid INTO v_jid FROM public.cohorts WHERE id = p_cohort_id;
  IF v_jid IS NULL THEN
    RAISE EXCEPTION 'cohort_has_no_group_jid' USING ERRCODE = '22023';
  END IF;

  -- When verifying, JID must be valid format
  IF p_verified AND NOT public.nps_is_valid_group_jid(v_jid) THEN
    RAISE EXCEPTION 'invalid_jid_format: % (must match *@g.us)', v_jid USING ERRCODE = '22023';
  END IF;

  v_user := auth.uid();

  UPDATE public.cohorts
     SET whatsapp_group_verified = p_verified,
         whatsapp_group_verified_at = CASE WHEN p_verified THEN NOW() ELSE NULL END,
         whatsapp_group_verified_by = CASE WHEN p_verified THEN v_user ELSE NULL END,
         whatsapp_group_label = COALESCE(p_label, whatsapp_group_label)
   WHERE id = p_cohort_id;

  RETURN jsonb_build_object(
    'ok', true,
    'cohort_id', p_cohort_id,
    'verified', p_verified
  );
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_set_cohort_group_verified(UUID, BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_set_cohort_group_verified(UUID, BOOLEAN, TEXT) TO authenticated;

-- 4. Admin RPC: list cohorts with group jids (for verification UI)
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
      'jid_valid_format', public.nps_is_valid_group_jid(c.whatsapp_group_jid),
      'verified', c.whatsapp_group_verified,
      'verified_at', c.whatsapp_group_verified_at,
      'verified_by', c.whatsapp_group_verified_by,
      'label', c.whatsapp_group_label,
      'active_students_count', (
        SELECT COUNT(*) FROM public.students s
        WHERE s.cohort_id = c.id AND s.active = true AND COALESCE(s.is_mentor, false) = false
      )
    ) AS row
    FROM public.cohorts c
    WHERE c.whatsapp_group_jid IS NOT NULL
    ORDER BY c.whatsapp_group_verified ASC, c.name
  ) sub;

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_list_cohort_groups() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_list_cohort_groups() TO authenticated;

COMMIT;
