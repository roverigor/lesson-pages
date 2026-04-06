-- ═══════════════════════════════════════
-- LESSON PAGES — Fix DB-S1: attendance.lesson_date TEXT → DATE
-- Story: DB-S1 (EPIC-003 backlog)
-- Todos os registros existentes estão no formato ISO 'YYYY-MM-DD'.
-- schedule_overrides.lesson_date permanece TEXT (formato 'DD/MM' sem ano — design intencional).
-- ═══════════════════════════════════════

-- Converte lesson_date de TEXT para DATE usando cast direto.
-- Falha explicitamente se houver algum valor não-ISO (proteção contra dados corrompidos).
ALTER TABLE public.attendance
  ALTER COLUMN lesson_date TYPE DATE USING lesson_date::DATE;

-- Recria o índice com tipo correto (o anterior era sobre TEXT)
DROP INDEX IF EXISTS idx_attendance_date;
CREATE INDEX IF NOT EXISTS idx_attendance_date ON public.attendance(lesson_date);

-- Garante que a UNIQUE constraint continua funcional com o novo tipo
-- (PostgreSQL mantém automaticamente, mas documentamos explicitamente)
-- UNIQUE(lesson_date, course, teacher_name) — já existe no baseline
