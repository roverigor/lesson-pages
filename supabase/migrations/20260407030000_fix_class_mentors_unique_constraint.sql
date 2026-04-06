-- ═══════════════════════════════════════
-- Fix class_mentors unique constraint to support temporal cycles
-- The original UNIQUE(class_id, mentor_id, role, weekday) prevents the same
-- mentor from appearing in multiple cycles (different valid_from values).
-- Replace with UNIQUE(class_id, mentor_id, role, weekday, valid_from).
-- ═══════════════════════════════════════

-- Drop old constraint (may exist under this name from the CREATE TABLE)
DO $$ BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'class_mentors_class_id_mentor_id_role_weekday_key'
      AND conrelid = 'public.class_mentors'::regclass
  ) THEN
    ALTER TABLE public.class_mentors
      DROP CONSTRAINT class_mentors_class_id_mentor_id_role_weekday_key;
  END IF;
END $$;

-- Add new constraint that includes valid_from so the same mentor can exist
-- in multiple cycles as long as valid_from differs
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'class_mentors_cycle_unique'
      AND conrelid = 'public.class_mentors'::regclass
  ) THEN
    ALTER TABLE public.class_mentors
      ADD CONSTRAINT class_mentors_cycle_unique
      UNIQUE (class_id, mentor_id, role, weekday, valid_from);
  END IF;
END $$;
