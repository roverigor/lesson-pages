-- ═══════════════════════════════════════
-- LESSON PAGES — Seed: Mentores da Equipe Pedagógica
-- Story 1.1 — EPIC-001
-- Roles válidos: Professor | Host | Both
-- ═══════════════════════════════════════

INSERT INTO mentors (name, phone, role, active) VALUES
  ('Adavio',          '558296838800',   'Professor', true),
  ('Adriano',         '5515997425595',  'Professor', true),
  ('Alan Nicolas',    '554891642424',   'Professor', true),
  ('Bruno Gentil',    '556199331574',   'Host',      true),
  ('Day',             '5511978031078',  'Both',      true),
  ('Diego',           '558386181165',   'Professor', true),
  ('Douglas',         '5521998628489',  'Professor', true),
  ('Fran',            '5518988119126',  'Professor', true),
  ('José Amorim',     '559281951096',   'Professor', true),
  ('Klaus',           '5516996308617',  'Professor', true),
  ('Lucas Charão',    '555191882447',   'Professor', true),
  ('Rodrigo Feldman', '5511952961036',  'Professor', true),
  ('Sidney',          '556199496931',   'Professor', true),
  ('Talles',          '556499425822',   'Professor', true)
ON CONFLICT (phone) DO UPDATE SET
  name   = EXCLUDED.name,
  role   = EXCLUDED.role,
  active = EXCLUDED.active;
