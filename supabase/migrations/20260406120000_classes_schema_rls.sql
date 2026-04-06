-- ═══════════════════════════════════════
-- LESSON PAGES — Classes Schema + RLS Formal
-- Story 3.3 — EPIC-003 Security Hardening
-- Formaliza colunas adicionadas manualmente, temporal cycles em class_mentors,
-- RLS completa (incluindo anon read para calendário público),
-- e índices de query frequente.
-- ═══════════════════════════════════════

-- ─── 1. CLASSES — colunas adicionadas após baseline ───
-- As colunas type, start_date, end_date foram adicionadas manualmente em produção.
-- Esta migration formaliza a adição de forma idempotente.

ALTER TABLE public.classes
  ADD COLUMN IF NOT EXISTS type       TEXT,
  ADD COLUMN IF NOT EXISTS start_date DATE,
  ADD COLUMN IF NOT EXISTS end_date   DATE;

-- CHECK constraint para o campo type (nomes dos tipos de aula)
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'classes_type_check'
      AND conrelid = 'public.classes'::regclass
  ) THEN
    ALTER TABLE public.classes
      ADD CONSTRAINT classes_type_check
      CHECK (type IN ('PS', 'Aula', 'Imersão', 'Workshop'));
  END IF;
END $$;

-- ─── 2. CLASSES — índices de consulta frequente ───
CREATE INDEX IF NOT EXISTS idx_classes_start_date ON public.classes(start_date);
CREATE INDEX IF NOT EXISTS idx_classes_end_date   ON public.classes(end_date);
CREATE INDEX IF NOT EXISTS idx_classes_type       ON public.classes(type);

-- ─── 3. CLASS_MENTORS — temporal cycle columns ───
-- valid_from/valid_until implementam histórico de equipe por ciclo.
-- valid_until IS NULL = ciclo ativo atual.

ALTER TABLE public.class_mentors
  ADD COLUMN IF NOT EXISTS valid_from  DATE NOT NULL DEFAULT '2000-01-01',
  ADD COLUMN IF NOT EXISTS valid_until DATE;

-- Índice para filtrar ciclo ativo eficientemente (IS NULL é sargable com índice parcial)
CREATE INDEX IF NOT EXISTS idx_class_mentors_active_cycle
  ON public.class_mentors(class_id)
  WHERE valid_until IS NULL;

CREATE INDEX IF NOT EXISTS idx_class_mentors_valid_from
  ON public.class_mentors(valid_from);

-- ─── 4. CLASS_COHORT_ACCESS — constraint única + índices ───
-- Garante que um cohort não aparece duas vezes para a mesma class.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'class_cohort_access_class_id_cohort_id_key'
      AND conrelid = 'public.class_cohort_access'::regclass
  ) THEN
    ALTER TABLE public.class_cohort_access
      ADD CONSTRAINT class_cohort_access_class_id_cohort_id_key
      UNIQUE (class_id, cohort_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_class_cohort_access_class
  ON public.class_cohort_access(class_id);
CREATE INDEX IF NOT EXISTS idx_class_cohort_access_cohort
  ON public.class_cohort_access(cohort_id);
CREATE INDEX IF NOT EXISTS idx_class_cohort_access_until
  ON public.class_cohort_access(access_until);

-- ─── 5. RLS — CLASSES ───
-- Leitura anônima: necessária para o calendário público (anon key, sem login).
-- Escrita: apenas admin (role = 'admin' em user_metadata).

ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read classes" ON public.classes;
CREATE POLICY "Public read classes"
  ON public.classes FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Authenticated read classes" ON public.classes;
-- Remove a política authenticated-only criada no baseline (substituída pela Public acima)
-- (já foi dropada na linha acima se existia)

DROP POLICY IF EXISTS "Admin insert classes" ON public.classes;
CREATE POLICY "Admin insert classes"
  ON public.classes FOR INSERT
  TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin update classes" ON public.classes;
CREATE POLICY "Admin update classes"
  ON public.classes FOR UPDATE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin delete classes" ON public.classes;
CREATE POLICY "Admin delete classes"
  ON public.classes FOR DELETE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── 6. RLS — CLASS_MENTORS ───
-- Leitura anônima: calendário público exibe professor/host por aula.
-- Escrita: apenas admin.

ALTER TABLE public.class_mentors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read class_mentors" ON public.class_mentors;
CREATE POLICY "Public read class_mentors"
  ON public.class_mentors FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Authenticated read class_mentors" ON public.class_mentors;

DROP POLICY IF EXISTS "Admin insert class_mentors" ON public.class_mentors;
CREATE POLICY "Admin insert class_mentors"
  ON public.class_mentors FOR INSERT
  TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin update class_mentors" ON public.class_mentors;
CREATE POLICY "Admin update class_mentors"
  ON public.class_mentors FOR UPDATE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin delete class_mentors" ON public.class_mentors;
CREATE POLICY "Admin delete class_mentors"
  ON public.class_mentors FOR DELETE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── 7. RLS — CLASS_COHORT_ACCESS ───
-- Leitura apenas para autenticados (dados de acesso por turma não são públicos).
-- Escrita: apenas admin.

ALTER TABLE public.class_cohort_access ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read class_cohort_access" ON public.class_cohort_access;
CREATE POLICY "Authenticated read class_cohort_access"
  ON public.class_cohort_access FOR SELECT
  TO authenticated
  USING (true);

DROP POLICY IF EXISTS "Admin insert class_cohort_access" ON public.class_cohort_access;
CREATE POLICY "Admin insert class_cohort_access"
  ON public.class_cohort_access FOR INSERT
  TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin update class_cohort_access" ON public.class_cohort_access;
CREATE POLICY "Admin update class_cohort_access"
  ON public.class_cohort_access FOR UPDATE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin delete class_cohort_access" ON public.class_cohort_access;
CREATE POLICY "Admin delete class_cohort_access"
  ON public.class_cohort_access FOR DELETE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── 8. RLS — MENTORS (necessário para calendário público) ───
-- O calendário público lê mentors (active=true) para exibir professor/host.

ALTER TABLE public.mentors ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Public read mentors" ON public.mentors;
CREATE POLICY "Public read mentors"
  ON public.mentors FOR SELECT
  TO anon, authenticated
  USING (true);

DROP POLICY IF EXISTS "Admin insert mentors" ON public.mentors;
CREATE POLICY "Admin insert mentors"
  ON public.mentors FOR INSERT
  TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin update mentors" ON public.mentors;
CREATE POLICY "Admin update mentors"
  ON public.mentors FOR UPDATE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin delete mentors" ON public.mentors;
CREATE POLICY "Admin delete mentors"
  ON public.mentors FOR DELETE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
