-- ═══════════════════════════════════════
-- Migration: Fix RLS policy on mentor_attendance + attendance.lesson_date type
-- ═══════════════════════════════════════

-- ─── 1. Fix mentor_attendance RLS ───
-- Remove a policy aberta que permite qualquer autenticado escrever/deletar
DROP POLICY IF EXISTS "Allow all on mentor_attendance" ON mentor_attendance;

-- SELECT: qualquer autenticado pode ler
CREATE POLICY "Authenticated read mentor_attendance"
  ON mentor_attendance FOR SELECT TO authenticated
  USING (true);

-- INSERT: mentor pode inserir sua própria presença
CREATE POLICY "Mentor insert own attendance"
  ON mentor_attendance FOR INSERT TO authenticated
  WITH CHECK (
    mentor_id IN (
      SELECT id FROM mentors
      WHERE (auth.jwt() -> 'user_metadata' ->> 'mentor_id')::uuid = id
         OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'
    )
  );

-- UPDATE: mentor pode atualizar sua própria presença; admin pode tudo
CREATE POLICY "Mentor update own attendance"
  ON mentor_attendance FOR UPDATE TO authenticated
  USING (
    mentor_id IN (
      SELECT id FROM mentors
      WHERE (auth.jwt() -> 'user_metadata' ->> 'mentor_id')::uuid = id
         OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'
    )
  );

-- DELETE: apenas admin
CREATE POLICY "Admin delete mentor_attendance"
  ON mentor_attendance FOR DELETE TO authenticated
  USING (
    (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'
  );

-- ─── 2. Fix attendance.lesson_date — TEXT → DATE ───
-- Converte os valores existentes (formato esperado: 'YYYY-MM-DD' ou 'DD/MM/YYYY')
-- Backup seguro: renomeia coluna antiga, cria nova, migra, remove antiga

ALTER TABLE attendance ADD COLUMN lesson_date_new DATE;

-- Tenta converter TEXT → DATE (assume formato ISO YYYY-MM-DD)
-- Se houver formatos diferentes, ajuste o CASE abaixo
UPDATE attendance
SET lesson_date_new = CASE
  WHEN lesson_date ~ '^\d{4}-\d{2}-\d{2}$' THEN lesson_date::DATE
  WHEN lesson_date ~ '^\d{2}/\d{2}/\d{4}$' THEN to_date(lesson_date, 'DD/MM/YYYY')
  ELSE NULL
END;

-- Recria index na nova coluna
DROP INDEX IF EXISTS idx_attendance_date;
CREATE INDEX idx_attendance_date_new ON attendance(lesson_date_new);

-- Troca as colunas
ALTER TABLE attendance DROP COLUMN lesson_date;
ALTER TABLE attendance RENAME COLUMN lesson_date_new TO lesson_date;
ALTER TABLE attendance ALTER COLUMN lesson_date SET NOT NULL;

-- Recria o index com o nome original
DROP INDEX IF EXISTS idx_attendance_date_new;
CREATE INDEX idx_attendance_date ON attendance(lesson_date);

-- Recria a constraint UNIQUE
ALTER TABLE attendance
  DROP CONSTRAINT IF EXISTS attendance_lesson_date_course_teacher_name_key;

ALTER TABLE attendance
  ADD CONSTRAINT attendance_lesson_date_course_teacher_name_key
  UNIQUE (lesson_date, course, teacher_name);
