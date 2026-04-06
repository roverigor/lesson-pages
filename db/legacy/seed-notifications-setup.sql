-- ═══════════════════════════════════════
-- LESSON PAGES — Seed: Notifications Setup
-- Story 1.1 — EPIC-001
-- Execute no Supabase SQL Editor APÓS notifications-schema.sql
-- ═══════════════════════════════════════

-- ─── STEP 1: SEED DE MENTORES ───
-- 14 mentores da equipe pedagógica com phones no formato internacional
-- ON CONFLICT garante idempotência (pode re-executar sem duplicar)

INSERT INTO mentors (name, phone, role, active) VALUES
  ('Adavio',          '558296838800',   'Mentor',    true),
  ('Adriano',         '5515997425595',  'Professor', true),
  ('Alan Nicolas',    '554891642424',   'Mentor',    true),
  ('Bruno Gentil',    '556199331574',   'Host',      true),
  ('Day',             '5511978031078',  'Both',      true),
  ('Diego',           '558386181165',   'Mentor',    true),
  ('Douglas',         '5521998628489',  'Mentor',    true),
  ('Fran',            '5518988119126',  'Mentor',    true),
  ('José Amorim',     '559281951096',   'Mentor',    true),
  ('Klaus',           '5516996308617',  'Professor', true),
  ('Lucas Charão',    '555191882447',   'Mentor',    true),
  ('Rodrigo Feldman', '5511952961036',  'Professor', true),
  ('Sidney',          '556199496931',   'Mentor',    true),
  ('Talles',          '556499425822',   'Professor', true)
ON CONFLICT (phone) DO UPDATE SET
  name   = EXCLUDED.name,
  role   = EXCLUDED.role,
  active = EXCLUDED.active;

-- ─── STEP 2: SEED DE CLASS_COHORTS ───
-- Vincula classes existentes aos seus cohorts.
-- INSTRUÇÃO: Substitua os nomes abaixo pelos nomes reais das classes e cohorts
-- no seu banco. Use as queries de consulta no final deste arquivo para
-- descobrir os dados existentes antes de executar este bloco.

-- Exemplo de seed dinâmico (adaptar com dados reais):
-- INSERT INTO class_cohorts (class_id, cohort_id)
-- SELECT c.id, co.id
-- FROM classes c, cohorts co
-- WHERE c.name = 'Nome da Classe'
--   AND co.name = 'Nome do Cohort'
-- ON CONFLICT (class_id, cohort_id) DO NOTHING;

-- ─── STEP 3: SEED DE CLASS_MENTORS ───
-- Vincula mentores às classes que lecionam.
-- INSTRUÇÃO: Substitua os dados abaixo com os vínculos reais.

-- Exemplo de seed dinâmico (adaptar com dados reais):
-- INSERT INTO class_mentors (class_id, mentor_id, role)
-- SELECT c.id, m.id, 'Professor'
-- FROM classes c, mentors m
-- WHERE c.name = 'Nome da Classe'
--   AND m.phone = '556499425822'  -- Talles
-- ON CONFLICT DO NOTHING;

-- ─── STEP 4: VERIFICAÇÃO PÓS-EXECUÇÃO ───

-- 4.1: Confirmar tabelas criadas
SELECT table_name, (SELECT count(*) FROM information_schema.columns
  WHERE table_name = t.table_name AND table_schema = 'public') AS col_count
FROM (VALUES
  ('mentors'), ('class_cohorts'), ('class_mentors'), ('notifications')
) AS t(table_name)
JOIN information_schema.tables USING (table_name)
WHERE table_schema = 'public';

-- 4.2: Confirmar RLS ativa
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename IN ('mentors', 'class_cohorts', 'class_mentors', 'notifications')
ORDER BY tablename;

-- 4.3: Confirmar mentores inseridos
SELECT id, name, phone, role, active FROM mentors ORDER BY name;

-- 4.4: Consultar classes existentes (para popular class_cohorts / class_mentors)
SELECT id, name, weekday, professor, host FROM classes ORDER BY name;

-- 4.5: Consultar cohorts existentes (para popular class_cohorts)
SELECT id, name, whatsapp_group_jid FROM cohorts ORDER BY name;

-- 4.6: Teste de INSERT em notifications (verificar depois e deletar)
-- INSERT INTO notifications (type, target_type, message_template, status)
-- VALUES ('custom', 'group', 'Teste de schema Story 1.1', 'pending')
-- RETURNING id, status, created_at;
-- DELETE FROM notifications WHERE message_template = 'Teste de schema Story 1.1';
