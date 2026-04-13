-- Add aliases column to staff table for Zoom name matching
ALTER TABLE public.staff ADD COLUMN IF NOT EXISTS aliases TEXT[] DEFAULT ARRAY[]::TEXT[];
