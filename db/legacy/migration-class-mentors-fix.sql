-- Migration: Fix class_mentors table
-- Problem 1: role CHECK only accepts 'Professor' and 'Host', not 'Mentor'
-- Problem 2: weekday column missing (needed for multi-weekday schedules)
-- Problem 3: UNIQUE(class_id, mentor_id, role) blocks same mentor in same role on different weekdays

-- 1. Add weekday column
ALTER TABLE class_mentors ADD COLUMN IF NOT EXISTS weekday SMALLINT;

-- 2. Fix CHECK constraint to include 'Mentor'
ALTER TABLE class_mentors DROP CONSTRAINT IF EXISTS class_mentors_role_check;
ALTER TABLE class_mentors ADD CONSTRAINT class_mentors_role_check
  CHECK (role IN ('Professor', 'Host', 'Mentor'));

-- 3. Update UNIQUE constraint to include weekday
--    (same mentor can be Professor on Mon AND Professor on Tue)
ALTER TABLE class_mentors DROP CONSTRAINT IF EXISTS class_mentors_class_id_mentor_id_role_key;
ALTER TABLE class_mentors ADD CONSTRAINT class_mentors_class_id_mentor_id_role_weekday_key
  UNIQUE(class_id, mentor_id, role, weekday);
