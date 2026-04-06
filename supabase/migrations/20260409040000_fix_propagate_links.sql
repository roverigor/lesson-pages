-- ═══════════════════════════════════════
-- Fix propagate_zoom_links — rewrite with cleaner CTE (no correlated subqueries)
-- ═══════════════════════════════════════

CREATE OR REPLACE FUNCTION public.propagate_zoom_links()
RETURNS TABLE (updated_count BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_by_name  BIGINT := 0;
  v_by_email BIGINT := 0;
BEGIN
  -- ── Step 1: Propagate links by participant_name ──
  -- For each normalized name, pick the most frequently linked student_id
  WITH name_counts AS (
    SELECT
      LOWER(TRIM(participant_name)) AS norm_name,
      student_id,
      COUNT(*)                      AS cnt
    FROM public.zoom_participants
    WHERE matched = true
      AND student_id IS NOT NULL
      AND participant_name IS NOT NULL
      AND TRIM(participant_name) != ''
    GROUP BY LOWER(TRIM(participant_name)), student_id
  ),
  name_mapping AS (
    SELECT DISTINCT ON (norm_name) norm_name, student_id
    FROM name_counts
    ORDER BY norm_name, cnt DESC, student_id
  )
  UPDATE public.zoom_participants zp
  SET student_id = nm.student_id,
      matched    = true
  FROM name_mapping nm
  WHERE zp.matched    = false
    AND zp.student_id IS NULL
    AND zp.participant_name IS NOT NULL
    AND LOWER(TRIM(zp.participant_name)) = nm.norm_name;

  GET DIAGNOSTICS v_by_name = ROW_COUNT;

  -- ── Step 2: Propagate links by participant_email (for remaining unmatched) ──
  WITH email_counts AS (
    SELECT
      LOWER(TRIM(participant_email)) AS norm_email,
      student_id,
      COUNT(*)                       AS cnt
    FROM public.zoom_participants
    WHERE matched = true
      AND student_id IS NOT NULL
      AND participant_email IS NOT NULL
      AND TRIM(participant_email) != ''
    GROUP BY LOWER(TRIM(participant_email)), student_id
  ),
  email_mapping AS (
    SELECT DISTINCT ON (norm_email) norm_email, student_id
    FROM email_counts
    ORDER BY norm_email, cnt DESC, student_id
  )
  UPDATE public.zoom_participants zp
  SET student_id = em.student_id,
      matched    = true
  FROM email_mapping em
  WHERE zp.matched    = false
    AND zp.student_id IS NULL
    AND zp.participant_email IS NOT NULL
    AND TRIM(zp.participant_email) != ''
    AND LOWER(TRIM(zp.participant_email)) = em.norm_email;

  GET DIAGNOSTICS v_by_email = ROW_COUNT;

  RETURN QUERY SELECT v_by_name + v_by_email;
END;
$$;

GRANT EXECUTE ON FUNCTION public.propagate_zoom_links() TO service_role;
