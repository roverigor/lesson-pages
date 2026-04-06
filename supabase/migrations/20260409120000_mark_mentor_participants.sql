-- ═══════════════════════════════════════
-- Mark zoom_participants that belong to mentors/staff as matched
-- so they stop appearing in the unmatched/vincular list.
-- Uses full-name and first-name prefix matching against the mentors table.
-- Sets matched=true with student_id=NULL (staff, not a student).
-- ═══════════════════════════════════════

CREATE OR REPLACE FUNCTION public.mark_mentor_participants()
RETURNS TABLE (updated_count BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_updated BIGINT;
BEGIN
  -- Match unmatched zoom participants against mentor names:
  -- 1. Exact full name match (case-insensitive, accent-stripped)
  -- 2. Participant starts with mentor name (e.g. "Day Cavalcanti @handle" → "Day Cavalcanti")
  -- 3. Mentor name starts with participant name (e.g. "Fran" → "Fran Martins")
  -- 4. First word of participant = full mentor name (e.g. "Klaus" → "Klaus Deor" won't match this,
  --    but "Diego" → "Diego Diniz" will match via rule 3)

  WITH mentor_norms AS (
    SELECT
      id,
      name,
      -- Normalized full name
      LOWER(TRANSLATE(
        UNACCENT(TRIM(name)),
        '_', ' '
      )) AS norm_name,
      -- Normalized first word only
      LOWER(UNACCENT(SPLIT_PART(TRIM(name), ' ', 1))) AS first_word
    FROM public.mentors
    WHERE active = true
  ),
  participant_norms AS (
    SELECT
      zp.id,
      LOWER(TRANSLATE(
        UNACCENT(TRIM(zp.participant_name)),
        '_', ' '
      )) AS norm_pname,
      LOWER(UNACCENT(SPLIT_PART(TRIM(zp.participant_name), ' ', 1))) AS p_first_word
    FROM public.zoom_participants zp
    WHERE zp.matched = false
      AND zp.participant_name IS NOT NULL
      AND TRIM(zp.participant_name) != ''
  ),
  matches AS (
    SELECT DISTINCT pn.id
    FROM participant_norms pn
    JOIN mentor_norms mn ON (
      -- Rule 1: exact match
      pn.norm_pname = mn.norm_name
      -- Rule 2: participant starts with mentor name (handles "Day Cavalcanti @adaycavalcanti")
      OR pn.norm_pname LIKE mn.norm_name || ' %'
      -- Rule 3: mentor name starts with participant (handles "Diego" → "Diego Diniz")
      OR mn.norm_name LIKE pn.norm_pname || ' %'
      -- Rule 4: participant first word = mentor full name (single-name mentors like "Douglas")
      OR (pn.p_first_word = mn.norm_name AND LENGTH(mn.norm_name) >= 4)
    )
  )
  UPDATE public.zoom_participants
  SET matched = true
  WHERE id IN (SELECT id FROM matches);

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  RETURN QUERY SELECT v_updated;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_mentor_participants() TO service_role;
