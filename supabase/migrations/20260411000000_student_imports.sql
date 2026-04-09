-- student_imports: stores CSV purchase upload data per cohort
-- Used by "Fontes" tab to cross-reference students across sources

CREATE TABLE IF NOT EXISTS public.student_imports (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  cohort_id UUID NOT NULL REFERENCES public.cohorts(id),
  name TEXT NOT NULL,
  email TEXT,
  phone TEXT,
  product TEXT,
  purchase_date DATE,
  source TEXT DEFAULT 'csv',
  raw_data JSONB,
  created_at TIMESTAMPTZ DEFAULT now(),
  imported_by UUID REFERENCES auth.users(id)
);

-- Index for cross-reference queries
CREATE INDEX IF NOT EXISTS idx_student_imports_cohort ON public.student_imports(cohort_id);
CREATE INDEX IF NOT EXISTS idx_student_imports_phone ON public.student_imports(phone) WHERE phone IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_student_imports_email ON public.student_imports(email) WHERE email IS NOT NULL;

-- RLS
ALTER TABLE public.student_imports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Admin full access on student_imports"
  ON public.student_imports
  FOR ALL
  USING (
    (SELECT (raw_user_meta_data->>'role')::text FROM auth.users WHERE id = auth.uid()) = 'admin'
  )
  WITH CHECK (
    (SELECT (raw_user_meta_data->>'role')::text FROM auth.users WHERE id = auth.uid()) = 'admin'
  );
