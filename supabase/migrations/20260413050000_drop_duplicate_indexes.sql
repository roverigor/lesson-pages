-- Remove duplicate indexes

-- class_mentors: two identical unique indexes on (class_id, mentor_id, role, weekday, valid_from)
-- Keep class_mentors_cycle_unique (shorter name), drop the auto-generated one
DROP INDEX IF EXISTS public.class_mentors_class_id_mentor_id_role_weekday_valid_from_key;

-- lesson_abstracts: unique index on slug already covers lookups, non-unique index is redundant
DROP INDEX IF EXISTS public.idx_lesson_abstracts_slug;
