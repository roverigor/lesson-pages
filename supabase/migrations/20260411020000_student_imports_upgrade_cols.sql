-- Add turma_origin and upgrade columns to student_imports
-- Supports CSV format: nome;email;telefone;programa;turma;data de compra;upgrade

ALTER TABLE public.student_imports
  ADD COLUMN IF NOT EXISTS turma_origin TEXT,
  ADD COLUMN IF NOT EXISTS upgrade TEXT;
