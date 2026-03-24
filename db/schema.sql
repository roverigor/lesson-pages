-- ═══════════════════════════════════════
-- LESSON PAGES — Attendance Tracking Schema
-- Run this in Supabase SQL Editor
-- ═══════════════════════════════════════

-- Tabela de presença (core da funcionalidade)
CREATE TABLE IF NOT EXISTS attendance (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  lesson_date TEXT NOT NULL,
  course TEXT NOT NULL,
  teacher_name TEXT NOT NULL,
  role TEXT NOT NULL DEFAULT 'Professor',
  status TEXT NOT NULL CHECK (status IN ('present', 'absent')),
  substitute_name TEXT,
  notes TEXT,
  recorded_by UUID REFERENCES auth.users(id),
  recorded_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(lesson_date, course, teacher_name)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_attendance_date ON attendance(lesson_date);
CREATE INDEX IF NOT EXISTS idx_attendance_status ON attendance(status);
CREATE INDEX IF NOT EXISTS idx_attendance_teacher ON attendance(teacher_name);

-- RLS
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;

-- Leitura para usuários autenticados
CREATE POLICY "Authenticated read" ON attendance
  FOR SELECT TO authenticated USING (true);

-- Insert/Update apenas para admins
CREATE POLICY "Admin insert" ON attendance
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM auth.users
      WHERE id = auth.uid()
      AND raw_user_meta_data->>'role' = 'admin'
    )
  );

CREATE POLICY "Admin update" ON attendance
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM auth.users
      WHERE id = auth.uid()
      AND raw_user_meta_data->>'role' = 'admin'
    )
  );

CREATE POLICY "Admin delete" ON attendance
  FOR DELETE TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM auth.users
      WHERE id = auth.uid()
      AND raw_user_meta_data->>'role' = 'admin'
    )
  );

-- Function para updated_at automático
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER attendance_updated_at
  BEFORE UPDATE ON attendance
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ═══════════════════════════════════════
-- SETUP ADMIN USER
-- ═══════════════════════════════════════
-- Após criar o usuário no Supabase Auth (Dashboard > Authentication > Users),
-- execute este SQL para definir o role como admin:
--
-- UPDATE auth.users
-- SET raw_user_meta_data = raw_user_meta_data || '{"role": "admin"}'::jsonb
-- WHERE email = 'seu-email@exemplo.com';
