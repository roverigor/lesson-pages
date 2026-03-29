-- ═══════════════════════════════════════
-- LESSON PAGES — Students & Cohorts Schema
-- Run this in Supabase SQL Editor
-- ═══════════════════════════════════════

-- Tabela de turmas/cohorts com vinculo ao WhatsApp
CREATE TABLE IF NOT EXISTS cohorts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL UNIQUE,
  whatsapp_group_jid TEXT,
  whatsapp_group_name TEXT,
  zoom_link TEXT,
  start_date DATE,
  end_date DATE,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- Tabela de alunos
CREATE TABLE IF NOT EXISTS students (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL DEFAULT '',
  phone TEXT NOT NULL,
  cohort_id UUID REFERENCES cohorts(id) ON DELETE SET NULL,
  is_mentor BOOLEAN DEFAULT false,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(phone, cohort_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_students_phone ON students(phone);
CREATE INDEX IF NOT EXISTS idx_students_cohort ON students(cohort_id);
CREATE INDEX IF NOT EXISTS idx_cohorts_active ON cohorts(active);

-- RLS
ALTER TABLE cohorts ENABLE ROW LEVEL SECURITY;
ALTER TABLE students ENABLE ROW LEVEL SECURITY;

-- Leitura para autenticados
CREATE POLICY "Authenticated read cohorts" ON cohorts
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Authenticated read students" ON students
  FOR SELECT TO authenticated USING (true);

-- Admin CRUD
CREATE POLICY "Admin insert cohorts" ON cohorts
  FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin update cohorts" ON cohorts
  FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin delete cohorts" ON cohorts
  FOR DELETE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

CREATE POLICY "Admin insert students" ON students
  FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin update students" ON students
  FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin delete students" ON students
  FOR DELETE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ═══════════════════════════════════════
-- SEED: Cohorts
-- ═══════════════════════════════════════
INSERT INTO cohorts (name, whatsapp_group_jid, whatsapp_group_name, start_date, end_date) VALUES
  ('Fundamental T1', '120363407322736559@g.us', 'AIOS Cohort Fundamental - T1', '2026-02-04', '2026-04-01'),
  ('Fundamental T2', '120363406009222289@g.us', 'AIOS Cohort Fundamental - T2', '2026-02-04', '2026-04-01'),
  ('Fundamental T3', '120363408861350309@g.us', 'AIOS Cohort Fundamental - T3', '2026-02-04', '2026-04-01'),
  ('Advanced T1',    '120363423250471692@g.us', 'AIOX Cohort Advanced',         '2026-02-04', '2026-05-29'),
  ('Advanced T2',    '120363423278234924@g.us', 'AIOX Cohort Advanced - T2',    '2026-04-07', '2026-05-29')
ON CONFLICT (name) DO NOTHING;
