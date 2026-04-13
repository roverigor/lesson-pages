-- TD-03: Merge staff table into mentors
-- Staff and mentors are near-identical (15 rows each). After this migration,
-- mentors becomes the single table for all pedagogical team members.

-- Step 1: Add missing columns to mentors
ALTER TABLE public.mentors ADD COLUMN IF NOT EXISTS email TEXT;
ALTER TABLE public.mentors ADD COLUMN IF NOT EXISTS category TEXT NOT NULL DEFAULT 'Professor';

-- Step 2: Backfill mentors from staff data (match by phone or name)
-- Update email and category from staff for existing mentors
UPDATE public.mentors m
SET
  email    = COALESCE(m.email, s.email),
  category = COALESCE(s.category, m.category)
FROM public.staff s
WHERE s.active = true
  AND (
    (s.phone IS NOT NULL AND m.phone IS NOT NULL AND
     regexp_replace(s.phone, '\D', '', 'g') = regexp_replace(m.phone, '\D', '', 'g'))
    OR lower(trim(s.name)) = lower(trim(m.name))
  );

-- Step 3: Merge aliases from staff into mentors (union, no duplicates)
UPDATE public.mentors m
SET aliases = (
  SELECT array_agg(DISTINCT a)
  FROM unnest(m.aliases || s.aliases) AS a
)
FROM public.staff s
WHERE s.active = true
  AND (
    (s.phone IS NOT NULL AND m.phone IS NOT NULL AND
     regexp_replace(s.phone, '\D', '', 'g') = regexp_replace(m.phone, '\D', '', 'g'))
    OR lower(trim(s.name)) = lower(trim(m.name))
  )
  AND array_length(s.aliases, 1) > 0;

-- Step 4: Insert staff members that don't exist in mentors yet
INSERT INTO public.mentors (name, phone, email, role, category, aliases, active)
SELECT
  s.name,
  s.phone,
  s.email,
  CASE s.category
    WHEN 'Host' THEN 'Host'
    WHEN 'Both' THEN 'Both'
    ELSE 'Professor'
  END,
  s.category,
  COALESCE(s.aliases, ARRAY[]::TEXT[]),
  s.active
FROM public.staff s
WHERE NOT EXISTS (
  SELECT 1 FROM public.mentors m
  WHERE (s.phone IS NOT NULL AND m.phone IS NOT NULL AND
         regexp_replace(s.phone, '\D', '', 'g') = regexp_replace(m.phone, '\D', '', 'g'))
     OR lower(trim(s.name)) = lower(trim(m.name))
);

-- Step 5: Drop the sync RPC (no longer needed)
DROP FUNCTION IF EXISTS public.upsert_mentor_from_staff(text, text, text);

-- Step 6: Mark staff as deprecated (keep table for now, drop in future sprint)
COMMENT ON TABLE public.staff IS 'DEPRECATED — merged into mentors table (TD-03, 2026-04-13). Will be dropped after frontend migration is verified.';
