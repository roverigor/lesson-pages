-- ═══════════════════════════════════════
-- Add missing mentors: Taís and Luh_Arrais
-- These appear as Zoom participants but were not in the mentors table.
-- Phones are placeholders — update via admin UI when available.
-- ═══════════════════════════════════════

INSERT INTO public.mentors (name, phone, role, active) VALUES
  ('Taís',       'placeholder_tais',     'Professor', true),
  ('Luh_Arrais', 'placeholder_luharrais','Professor', true)
ON CONFLICT (phone) DO NOTHING;
