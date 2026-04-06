-- ═══════════════════════════════════════
-- Add zoom_alias column to mentors table
-- For cases where the Zoom display name differs from the registered name.
-- Example: Luciana → "Luh Arrais" in Zoom
-- ═══════════════════════════════════════

ALTER TABLE public.mentors
  ADD COLUMN IF NOT EXISTS zoom_alias TEXT;

-- Set Luciana's Zoom alias
UPDATE public.mentors
SET zoom_alias = 'Luh Arrais'
WHERE LOWER(TRIM(name)) = 'luciana'
  AND zoom_alias IS NULL;

-- ═══════════════════════════════════════
-- Rewrite mark_mentor_participants() to also match against zoom_alias
-- ═══════════════════════════════════════

CREATE OR REPLACE FUNCTION public.mark_mentor_participants()
RETURNS TABLE (updated_count BIGINT)
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_updated BIGINT;
BEGIN
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
      LOWER(UNACCENT(SPLIT_PART(TRIM(name), ' ', 1))) AS first_word,
      -- Normalized zoom alias (if set)
      CASE
        WHEN zoom_alias IS NOT NULL AND TRIM(zoom_alias) != ''
        THEN LOWER(TRANSLATE(UNACCENT(TRIM(zoom_alias)), '_', ' '))
        ELSE NULL
      END AS norm_alias,
      -- First word of alias
      CASE
        WHEN zoom_alias IS NOT NULL AND TRIM(zoom_alias) != ''
        THEN LOWER(UNACCENT(SPLIT_PART(TRIM(zoom_alias), ' ', 1)))
        ELSE NULL
      END AS alias_first_word
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
      -- Rule 1: exact match on name
      pn.norm_pname = mn.norm_name
      -- Rule 2: participant starts with mentor name
      OR pn.norm_pname LIKE mn.norm_name || ' %'
      -- Rule 3: mentor name starts with participant
      OR mn.norm_name LIKE pn.norm_pname || ' %'
      -- Rule 4: participant first word = single-name mentor (min 4 chars)
      OR (pn.p_first_word = mn.norm_name AND LENGTH(mn.norm_name) >= 4)
      -- Rule 5: exact match on zoom_alias
      OR (mn.norm_alias IS NOT NULL AND pn.norm_pname = mn.norm_alias)
      -- Rule 6: participant starts with zoom_alias
      OR (mn.norm_alias IS NOT NULL AND pn.norm_pname LIKE mn.norm_alias || ' %')
      -- Rule 7: zoom_alias starts with participant
      OR (mn.norm_alias IS NOT NULL AND mn.norm_alias LIKE pn.norm_pname || ' %')
      -- Rule 8: participant first word = alias first word (min 3 chars)
      OR (mn.alias_first_word IS NOT NULL AND pn.p_first_word = mn.alias_first_word AND LENGTH(mn.alias_first_word) >= 3)
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
