-- EPIC-005 Story 5.x — Survey accent color
ALTER TABLE surveys ADD COLUMN IF NOT EXISTS accent_color TEXT DEFAULT '#6366f1';
