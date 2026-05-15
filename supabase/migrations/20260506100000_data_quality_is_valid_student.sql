-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-020 Story 20.0 — Data Quality Cleanup (BLOQUEADOR)
-- Adiciona is_valid_student computed column pra filtrar fantasmas/leads/lixo.
--
-- Critério: email IS NOT NULL AND name não é só números AND name não vazio.
-- Spike 2026-05-05 detectou 35% das entries em students são lixo.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.students
  ADD COLUMN IF NOT EXISTS is_valid_student BOOLEAN
  GENERATED ALWAYS AS (
    email IS NOT NULL
    AND name !~ '^[0-9\s]+$'
    AND TRIM(COALESCE(name, '')) != ''
    AND name ~ '[a-zA-ZÀ-ÿ]'
  ) STORED;

CREATE INDEX IF NOT EXISTS idx_students_is_valid
  ON public.students (is_valid_student) WHERE is_valid_student = true;

-- View conveniência pra dashboards/queries (default scope)
CREATE OR REPLACE VIEW public.v_valid_students AS
  SELECT * FROM public.students WHERE is_valid_student = true;

GRANT SELECT ON public.v_valid_students TO authenticated;

COMMENT ON COLUMN public.students.is_valid_student IS
  'EPIC-020 Story 20.0: aluno tem email + nome alfa válido. Filtro pra dashboards/scoring evitar falsos positivos por dados poluídos.';

COMMENT ON VIEW public.v_valid_students IS
  'Filtro convenience: students com is_valid_student=true. Use por default em queries operacionais.';
