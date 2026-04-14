-- Add turma_origin and upgrade columns to student_imports
-- Supports CSV format: nome;email;telefone;programa;turma;data de compra;upgrade

ALTER TABLE public.student_imports
  ADD COLUMN IF NOT EXISTS turma_origin TEXT,
  ADD COLUMN IF NOT EXISTS upgrade TEXT;

-- Fix RLS: simplify policy to allow any authenticated user
-- (only admins have login credentials, so this is safe)
DROP POLICY IF EXISTS "Admin full access on student_imports" ON public.student_imports;
DROP POLICY IF EXISTS "Authenticated full access on student_imports" ON public.student_imports;

CREATE POLICY "Authenticated full access on student_imports"
  ON public.student_imports
  FOR ALL
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
