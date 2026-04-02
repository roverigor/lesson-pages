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
-- Converte os valores existentes. Executa em 3 passos seguros.

-- PASSO 1: Verificar quais valores não convertem (diagnóstico — rode antes)
-- SELECT lesson_date, count(*) FROM attendance
-- WHERE lesson_date !~ '^\d{4}-\d{2}-\d{2}$'
--   AND lesson_date !~ '^\d{2}/\d{2}/\d{4}$'
-- GROUP BY 1;

-- PASSO 2: Adicionar coluna nova nullable
ALTER TABLE attendance ADD COLUMN IF NOT EXISTS lesson_date_new DATE;

-- PASSO 3: Converter os valores que correspondem a formatos conhecidos
-- Valores não reconhecidos ficam NULL (veja PASSO 1 acima para identificar)
UPDATE attendance
SET lesson_date_new = CASE
  WHEN lesson_date ~ '^\d{4}-\d{2}-\d{2}$'         THEN lesson_date::DATE
  WHEN lesson_date ~ '^\d{2}/\d{2}/\d{4}$'          THEN to_date(lesson_date, 'DD/MM/YYYY')
  WHEN lesson_date ~ '^\d{2}-\d{2}-\d{4}$'          THEN to_date(lesson_date, 'DD-MM-YYYY')
  -- fallback: tenta cast direto (pode falhar para formatos desconhecidos)
  ELSE NULL
END
WHERE lesson_date_new IS NULL;

-- PASSO 4: Deletar ou corrigir rows com lesson_date_new NULL antes de continuar
-- Se houver NULLs, rode o diagnóstico acima e ajuste os dados primeiro.
-- Para deletar registros inválidos (cuidado!):
-- DELETE FROM attendance WHERE lesson_date_new IS NULL;

-- PASSO 5: Só execute se não houver NULLs em lesson_date_new
-- Verifique primeiro: SELECT count(*) FROM attendance WHERE lesson_date_new IS NULL;
-- Se retornar 0, pode prosseguir:

-- DROP INDEX IF EXISTS idx_attendance_date;
-- ALTER TABLE attendance DROP COLUMN lesson_date;
-- ALTER TABLE attendance RENAME COLUMN lesson_date_new TO lesson_date;
-- ALTER TABLE attendance ALTER COLUMN lesson_date SET NOT NULL;
-- CREATE INDEX idx_attendance_date ON attendance(lesson_date);
-- ALTER TABLE attendance
--   DROP CONSTRAINT IF EXISTS attendance_lesson_date_course_teacher_name_key;
-- ALTER TABLE attendance
--   ADD CONSTRAINT attendance_lesson_date_course_teacher_name_key
--   UNIQUE (lesson_date, course, teacher_name);
