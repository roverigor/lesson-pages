-- ═══════════════════════════════════════
-- LESSON PAGES — Zoom data cleanup functions
-- 1. dedup_zoom_participants() — remove duplicate entries per meeting
-- 2. propagate_zoom_links()   — spread manual/fuzzy links across all meetings
-- ═══════════════════════════════════════

-- ─── 1. dedup_zoom_participants ────────────────────────────────────────────
-- Within each meeting, multiple rows can exist for the same person
-- (reconnections, dropped connection, re-join). Keep the row with the
-- longest duration_minutes; delete the rest.
-- Dedup key: meeting_id + COALESCE(email, normalized_name)
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.dedup_zoom_participants()
RETURNS TABLE (deleted_count BIGINT, kept_count BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_deleted BIGINT;
  v_kept    BIGINT;
BEGIN
  -- Identify and delete duplicate rows within the same meeting
  -- Keep the row with the highest duration; on tie, keep the earliest join_time
  WITH ranked AS (
    SELECT
      id,
      ROW_NUMBER() OVER (
        PARTITION BY
          meeting_id,
          COALESCE(
            NULLIF(TRIM(participant_email), ''),
            LOWER(TRIM(participant_name))
          )
        ORDER BY
          duration_minutes DESC NULLS LAST,
          join_time ASC NULLS LAST
      ) AS rn
    FROM public.zoom_participants
  ),
  to_delete AS (
    SELECT id FROM ranked WHERE rn > 1
  )
  DELETE FROM public.zoom_participants
  WHERE id IN (SELECT id FROM to_delete);

  GET DIAGNOSTICS v_deleted = ROW_COUNT;

  SELECT COUNT(*) INTO v_kept FROM public.zoom_participants;

  RETURN QUERY SELECT v_deleted, v_kept;
END;
$$;

-- ─── 2. propagate_zoom_links ───────────────────────────────────────────────
-- For every distinct participant_name (or email) that has been linked to a
-- student (matched=true, student_id IS NOT NULL), find all OTHER zoom_participants
-- rows with the SAME name or email that are still unlinked and set their
-- student_id + matched = true.
--
-- This makes manual links in one meeting automatically apply to all meetings.
-- ───────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.propagate_zoom_links()
RETURNS TABLE (updated_count BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_updated BIGINT;
BEGIN
  -- Build name→student_id mapping from confirmed matches
  -- If same name was linked to different students, take the most frequent one
  WITH name_mapping AS (
    SELECT
      LOWER(TRIM(participant_name)) AS norm_name,
      -- Most frequent student_id for this name wins
      (
        SELECT inner_sid
        FROM (
          SELECT student_id AS inner_sid, COUNT(*) AS cnt
          FROM public.zoom_participants z2
          WHERE z2.matched = true
            AND z2.student_id IS NOT NULL
            AND LOWER(TRIM(z2.participant_name)) = LOWER(TRIM(zp.participant_name))
          GROUP BY student_id
          ORDER BY cnt DESC, student_id
          LIMIT 1
        ) freq
      ) AS student_id
    FROM public.zoom_participants zp
    WHERE zp.matched = true
      AND zp.student_id IS NOT NULL
      AND zp.participant_name IS NOT NULL
      AND TRIM(zp.participant_name) != ''
    GROUP BY LOWER(TRIM(participant_name))
  ),
  -- Also build email→student_id mapping
  email_mapping AS (
    SELECT
      LOWER(TRIM(participant_email)) AS norm_email,
      (
        SELECT inner_sid
        FROM (
          SELECT student_id AS inner_sid, COUNT(*) AS cnt
          FROM public.zoom_participants z2
          WHERE z2.matched = true
            AND z2.student_id IS NOT NULL
            AND LOWER(TRIM(z2.participant_email)) = LOWER(TRIM(zp.participant_email))
          GROUP BY student_id
          ORDER BY cnt DESC, student_id
          LIMIT 1
        ) freq
      ) AS student_id
    FROM public.zoom_participants zp
    WHERE zp.matched = true
      AND zp.student_id IS NOT NULL
      AND zp.participant_email IS NOT NULL
      AND TRIM(zp.participant_email) != ''
    GROUP BY LOWER(TRIM(participant_email))
  )
  UPDATE public.zoom_participants AS zp
  SET
    student_id = COALESCE(nm.student_id, em.student_id),
    matched    = true
  FROM name_mapping nm
  FULL OUTER JOIN email_mapping em
    ON nm.student_id = em.student_id
  WHERE
    zp.matched = false
    AND zp.student_id IS NULL
    AND (
      (zp.participant_name IS NOT NULL
        AND LOWER(TRIM(zp.participant_name)) = nm.norm_name)
      OR
      (zp.participant_email IS NOT NULL
        AND TRIM(zp.participant_email) != ''
        AND LOWER(TRIM(zp.participant_email)) = em.norm_email)
    );

  GET DIAGNOSTICS v_updated = ROW_COUNT;

  RETURN QUERY SELECT v_updated;
END;
$$;

-- Grant execute to service role (used by edge functions)
GRANT EXECUTE ON FUNCTION public.dedup_zoom_participants() TO service_role;
GRANT EXECUTE ON FUNCTION public.propagate_zoom_links() TO service_role;
