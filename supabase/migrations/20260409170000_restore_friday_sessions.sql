-- ═══════════════════════════════════════════════════════
-- Restore Friday sessions lost during cycle closure
--
-- The cycle closure migration deleted the old-cycle entries
-- for Friday sessions. The attendance records confirm these
-- sessions existed consistently throughout Feb-Mar 2026.
--
-- PS Advanced Fridays (wd=5): Adavio, Talles, Klaus
-- PS Fund Fridays (wd=5): Bruno Gentil, Rodrigo Feldman
--   (Sidney already exists in old cycle with weekday=5)
-- ═══════════════════════════════════════════════════════

-- ── PS Advanced — Friday mentors (cycle before 2026-04-06) ──
INSERT INTO public.class_mentors (class_id, mentor_id, role, weekday, valid_from, valid_until)
VALUES
  ('985cb305-bcbb-4997-b7d6-60afa4ee9b29', '9afa21dd-4aa2-4301-92d5-2931bd3e6dd4', 'Mentor', 5, '2000-01-01', '2026-04-05'), -- Adavio Tittoni
  ('985cb305-bcbb-4997-b7d6-60afa4ee9b29', 'e68d7517-63c2-47b3-b1b5-1cf6ff21f734', 'Mentor', 5, '2000-01-01', '2026-04-05'), -- Talles Souza
  ('985cb305-bcbb-4997-b7d6-60afa4ee9b29', '88b644dd-b799-4eee-abb1-923b046aabeb', 'Mentor', 5, '2000-01-01', '2026-04-05')  -- Klaus Deor
ON CONFLICT DO NOTHING;

-- ── PS Fundamentals — Friday mentors (cycle before 2026-04-02) ──
-- (Sidney Fernandes already has weekday=5 in old cycle — not duplicating)
INSERT INTO public.class_mentors (class_id, mentor_id, role, weekday, valid_from, valid_until)
VALUES
  ('0e5df244-8068-4839-a1b1-2bf36616e0ab', '42ac9f4d-be31-4387-a193-b9a6b3b1a75c', 'Mentor', 5, '2000-01-01', '2026-04-02'), -- Bruno Gentil
  ('0e5df244-8068-4839-a1b1-2bf36616e0ab', 'a616cd72-7230-41a1-a9f4-6ccd52ca7fcc', 'Mentor', 5, '2000-01-01', '2026-04-02')  -- Rodrigo Feldman
ON CONFLICT DO NOTHING;

-- ── Also update existing PS Advanced null-weekday old-cycle entries to explicit weekday=2 ──
-- (weekday=null falls back to cls.weekday=2 anyway, but explicit is cleaner)
UPDATE public.class_mentors
SET weekday = 2
WHERE class_id = '985cb305-bcbb-4997-b7d6-60afa4ee9b29'
  AND valid_from = '2000-01-01'
  AND valid_until = '2026-04-05'
  AND weekday IS NULL;
