-- Add aliases column to student_imports for persistent Zoom name matching
-- When a coordinator manually links a Zoom participant to a CSV student,
-- the Zoom display name is saved here so future meetings auto-match.
ALTER TABLE public.student_imports ADD COLUMN IF NOT EXISTS aliases TEXT[] DEFAULT ARRAY[]::TEXT[];
