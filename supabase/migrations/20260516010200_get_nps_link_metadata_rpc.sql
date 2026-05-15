-- ═══════════════════════════════════════════════════════════════════════════
-- P2 — Public RPC for landing page to fetch link metadata without exposing
--      nps_class_links to anon clients.
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.get_nps_link_metadata(p_token text)
RETURNS TABLE (
  valid        boolean,
  expired      boolean,
  mode         text,
  class_name   text,
  cohort_name  text,
  student_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link nps_class_links%ROWTYPE;
BEGIN
  SELECT * INTO v_link FROM nps_class_links WHERE token = p_token;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, false, NULL::text, NULL::text, NULL::text, NULL::text;
    RETURN;
  END IF;

  IF v_link.expires_at < now() THEN
    RETURN QUERY SELECT false, true, v_link.mode, NULL::text, NULL::text, NULL::text;
    RETURN;
  END IF;

  RETURN QUERY
    SELECT
      true,
      false,
      v_link.mode,
      c.title,
      coh.name,
      CASE WHEN v_link.mode = 'dm' THEN s.name ELSE NULL END
    FROM classes c
    JOIN cohorts coh ON coh.id = v_link.cohort_id
    LEFT JOIN students s ON s.id = v_link.student_id
    WHERE c.id = v_link.class_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_nps_link_metadata(text) FROM public;
GRANT EXECUTE ON FUNCTION public.get_nps_link_metadata(text) TO anon, authenticated;

COMMIT;
