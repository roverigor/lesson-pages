-- Migration: Cleanup class_mentors orphans and duplicates (EPIC-013, Story 13.3)
-- Idempotent: safe to run multiple times

-- 1) Remove orphan records (class or mentor deleted)
DELETE FROM public.class_mentors cm
WHERE NOT EXISTS (SELECT 1 FROM public.classes c WHERE c.id = cm.class_id)
   OR NOT EXISTS (SELECT 1 FROM public.mentors m WHERE m.id = cm.mentor_id);

-- 2) Remove exact duplicates (keep the one with lowest ctid)
DELETE FROM public.class_mentors
WHERE id IN (
  SELECT id FROM (
    SELECT id,
      ROW_NUMBER() OVER (
        PARTITION BY class_id, mentor_id, role, weekday, valid_from
        ORDER BY id
      ) AS rn
    FROM public.class_mentors
  ) sub
  WHERE rn > 1
);

-- 3) Add unique constraint to prevent future duplicates (if not exists)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'class_mentors_unique_active'
  ) THEN
    CREATE UNIQUE INDEX class_mentors_unique_active
      ON public.class_mentors (class_id, mentor_id, role, weekday, valid_from);
  END IF;
END $$;
