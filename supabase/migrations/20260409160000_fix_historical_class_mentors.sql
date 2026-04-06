-- ═══════════════════════════════════════════════════════
-- Fix: add missing class_mentors for historical periods
--
-- 1. PS Advanced (Feb-Mar 2026): mentors had no class_mentors
--    entries before valid_from=2026-04-06. Attendance records
--    confirm Adavio, Talles, Klaus, Day were present.
--
-- 2. Aulas Advanced T1: class_mentors only had entries from
--    2026-04-03. Attendance shows Adriano, Alan Nicolas, Talles
--    taught all sessions Feb 4 – Apr 1.
--
-- 3. Aulas Fund T1: same issue. Attendance shows José Amorim,
--    Lucas Charão, Diego Diniz (Feb 12 – Mar 5).
-- ═══════════════════════════════════════════════════════

-- ── PS Advanced (Feb 6 – Apr 5 cycle) ──────────────────
-- class_id: 985cb305-bcbb-4997-b7d6-60afa4ee9b29
INSERT INTO public.class_mentors (class_id, mentor_id, role, valid_from, valid_until)
VALUES
  ('985cb305-bcbb-4997-b7d6-60afa4ee9b29', '9afa21dd-4aa2-4301-92d5-2931bd3e6dd4', 'Mentor', '2000-01-01', '2026-04-05'), -- Adavio Tittoni
  ('985cb305-bcbb-4997-b7d6-60afa4ee9b29', 'e68d7517-63c2-47b3-b1b5-1cf6ff21f734', 'Mentor', '2000-01-01', '2026-04-05'), -- Talles Souza
  ('985cb305-bcbb-4997-b7d6-60afa4ee9b29', '88b644dd-b799-4eee-abb1-923b046aabeb', 'Mentor', '2000-01-01', '2026-04-05'), -- Klaus Deor
  ('985cb305-bcbb-4997-b7d6-60afa4ee9b29', '2e691569-5c9d-451e-b934-f25a5038748b', 'Mentor', '2000-01-01', '2026-04-05')  -- Day Cavalcanti
ON CONFLICT DO NOTHING;

-- ── Aulas Advanced T1 (full run Feb 4 – Apr 1) ─────────
-- class_id: 8ce8180f-b1ae-4448-8e04-c1446b8cf92c
INSERT INTO public.class_mentors (class_id, mentor_id, role, valid_from, valid_until)
VALUES
  ('8ce8180f-b1ae-4448-8e04-c1446b8cf92c', '8fcd3681-22a6-4545-8124-9df998633428', 'Professor', '2000-01-01', '2026-04-01'), -- Adriano de Marqui
  ('8ce8180f-b1ae-4448-8e04-c1446b8cf92c', 'f77eeed4-9a2b-4834-8762-809ed0fa5d33', 'Professor', '2000-01-01', '2026-04-01'), -- Alan Nicolas
  ('8ce8180f-b1ae-4448-8e04-c1446b8cf92c', 'e68d7517-63c2-47b3-b1b5-1cf6ff21f734', 'Host',      '2000-01-01', '2026-04-01')  -- Talles Souza
ON CONFLICT DO NOTHING;

-- ── Aulas Fund T1 (Feb 12 – Mar 5) ────────────────────
-- class_id: d7c791f9-b550-4f78-9beb-6d5b5b1a605e
INSERT INTO public.class_mentors (class_id, mentor_id, role, valid_from, valid_until)
VALUES
  ('d7c791f9-b550-4f78-9beb-6d5b5b1a605e', '101350e4-1264-4599-bb28-1f73cb4d9b9f', 'Professor', '2000-01-01', '2026-03-05'), -- José Amorim
  ('d7c791f9-b550-4f78-9beb-6d5b5b1a605e', 'df67f26a-1826-45b5-8308-e8ceeab45273', 'Host',      '2000-01-01', '2026-03-05'), -- Lucas Charão
  ('d7c791f9-b550-4f78-9beb-6d5b5b1a605e', 'ac104c97-1ac1-4291-ade0-28103b14c677', 'Host',      '2000-01-01', '2026-03-05')  -- Diego Diniz
ON CONFLICT DO NOTHING;
