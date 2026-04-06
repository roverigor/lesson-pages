-- ═══════════════════════════════════════
-- Add aliases TEXT[] to students and mentors
-- Allows storing Zoom display names / nicknames for better matching
-- Migrates zoom_alias → aliases[0] and drops zoom_alias column
-- ═══════════════════════════════════════

-- Students
ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS aliases TEXT[] NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_students_aliases ON public.students USING GIN(aliases);

-- Mentors
ALTER TABLE public.mentors
  ADD COLUMN IF NOT EXISTS aliases TEXT[] NOT NULL DEFAULT '{}';

CREATE INDEX IF NOT EXISTS idx_mentors_aliases ON public.mentors USING GIN(aliases);

-- Migrate zoom_alias → aliases[0] for mentors that already have it set
UPDATE public.mentors
SET aliases = ARRAY[TRIM(zoom_alias)]
WHERE zoom_alias IS NOT NULL
  AND TRIM(zoom_alias) != ''
  AND (aliases IS NULL OR aliases = '{}');

-- Drop zoom_alias (replaced by aliases[])
ALTER TABLE public.mentors DROP COLUMN IF EXISTS zoom_alias;

-- ═══════════════════════════════════════
-- Rewrite mark_mentor_participants() using aliases[]
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
      m.id,
      -- Normalized primary name
      LOWER(TRANSLATE(UNACCENT(TRIM(m.name)), '_', ' ')) AS norm_name,
      LOWER(UNACCENT(SPLIT_PART(TRIM(m.name), ' ', 1))) AS first_word,
      -- Expanded list: primary name + all aliases, normalized
      ARRAY(
        SELECT LOWER(TRANSLATE(UNACCENT(TRIM(a)), '_', ' '))
        FROM unnest(
          ARRAY[m.name] || COALESCE(m.aliases, '{}')
        ) AS a
        WHERE TRIM(a) != ''
      ) AS all_names
    FROM public.mentors m
    WHERE m.active = true
  ),
  participant_norms AS (
    SELECT
      zp.id,
      LOWER(TRANSLATE(UNACCENT(TRIM(zp.participant_name)), '_', ' ')) AS norm_pname,
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
      -- Rule 1-4: match against primary name
      pn.norm_pname = mn.norm_name
      OR pn.norm_pname LIKE mn.norm_name || ' %'
      OR mn.norm_name LIKE pn.norm_pname || ' %'
      OR (pn.p_first_word = mn.norm_name AND LENGTH(mn.norm_name) >= 4)
      -- Rule 5-8: match against any alias/extra name
      OR EXISTS (
        SELECT 1 FROM unnest(mn.all_names) AS an WHERE
          pn.norm_pname = an
          OR pn.norm_pname LIKE an || ' %'
          OR an LIKE pn.norm_pname || ' %'
          OR (pn.p_first_word = an AND LENGTH(an) >= 3)
      )
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
