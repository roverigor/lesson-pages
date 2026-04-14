-- ═══════════════════════════════════════
-- Add Zoom meeting link and ID to classes
-- Allows storing and displaying Zoom room info per class
-- ═══════════════════════════════════════

ALTER TABLE public.classes
  ADD COLUMN IF NOT EXISTS zoom_link TEXT,
  ADD COLUMN IF NOT EXISTS zoom_meeting_id TEXT;
