-- ============================================================================
-- T4 Cohort Sync — CSV "membros-grupo-74 (1).csv" (21 students)
-- Date: 2026-05-15
-- Cohort: Fundamental T4 (7e807cad-483e-4248-a534-a03d13752731)
-- ============================================================================
-- Purpose:
--   1. Sync canonical names from CSV (Hotmart membership export)
--   2. Add 5 missing students to T4 cohort (4 existing globally + 1 new)
--   3. Update Feldman record (no-email WA contact → add email)
--   4. Audit log: insert all 21 CSV rows into student_imports
-- ============================================================================

BEGIN;

-- 1. UPDATE canonical names from CSV (where current name is inferior)
UPDATE public.students SET name = 'Eduardo Igor Gomes Cardoso'
 WHERE LOWER(email) = 'eigorgomes@gmail.com';

UPDATE public.students SET name = 'Vanessa de Souza Lobo'
 WHERE LOWER(email) = 'lobo_nessa@hotmail.com';

UPDATE public.students SET name = 'Jhonata Bueno dos Reis'
 WHERE LOWER(email) = 'jhonata.bueno.r@gmail.com';

UPDATE public.students SET name = E'Samuel Guimarães Pereira Ribeiro'
 WHERE LOWER(email) = 'samuelguimaraespr@gmail.com';

UPDATE public.students SET name = 'Rodolfo Pedroso de Lima'
 WHERE LOWER(email) = 'rodolfolima9@gmail.com';

UPDATE public.students SET name = 'Ligia Covre da Silva'
 WHERE LOWER(email) = 'ligiacovre.s@gmail.com';

UPDATE public.students SET name = 'Anderson Brizuela Candia'
 WHERE LOWER(email) = 'anderstarkpy@gmail.com';

UPDATE public.students SET name = 'Igor Fraga'
 WHERE LOWER(email) = 'i.fraga@me.com';

UPDATE public.students SET name = 'Marcelo Grah'
 WHERE LOWER(email) = 'mgrah@hotmail.com';

-- 2. UPDATE Feldman WA-contact record: add email + canonical name
--    Original: "Feldman♾️" no-email, phone 5511952961036
--    Becomes: "Rodrigo Feldman" + email feldmanrodrigo@me.com (preserves phone)
UPDATE public.students
   SET name = 'Rodrigo Feldman',
       email = 'feldmanrodrigo@me.com'
 WHERE id = '2ab533db-adef-4474-9c77-7f33da86a079';

-- 3. INSERT new student: Romulo F Nuno (not in DB)
--    is_valid_student is a generated column — do not set explicitly
--    phone is NOT NULL — use 'pending_csv_phones' placeholder until real phone arrives
INSERT INTO public.students (name, email, phone, cohort_id, active)
SELECT 'Romulo F Nuno', 'cursos@multid3.com.br', 'pending_csv_phones',
       '7e807cad-483e-4248-a534-a03d13752731'::uuid, true
 WHERE NOT EXISTS (
   SELECT 1 FROM public.students WHERE LOWER(email) = 'cursos@multid3.com.br'
 );

-- 4. LINK 5 students to T4 cohort via student_cohorts bridge
INSERT INTO public.student_cohorts (student_id, cohort_id, enrolled_at)
VALUES
  -- Claudia Dumont (claudiadumont@hotmail.com) — existing, real phone 553191633000
  ('e7c85b6a-f25a-4c27-8bc8-0aecfe921a91', '7e807cad-483e-4248-a534-a03d13752731', NOW()),
  -- Jaynara Suassuna Nunes (jaynarasn@gmail.com) — existing, real phone 558481071301
  ('9d5386ad-ee41-48ef-be76-838831c97e84', '7e807cad-483e-4248-a534-a03d13752731', NOW()),
  -- Jhonata Matias Mata Campos (jhonata.matias@cffranquias.com.br) — existing, real phone 5522998771692
  ('a55a493b-176c-4419-9947-61d37d2ded52', '7e807cad-483e-4248-a534-a03d13752731', NOW()),
  -- Rafael Costa | UTI das Ideias (rafael@utidasideias.com.br) — existing, real phone 5516988148880
  ('c5ea37b5-99f2-43c5-8734-dfe4635a5b5f', '7e807cad-483e-4248-a534-a03d13752731', NOW()),
  -- Rodrigo Feldman (feldmanrodrigo@me.com) — was no-email WA contact, real phone 5511952961036
  ('2ab533db-adef-4474-9c77-7f33da86a079', '7e807cad-483e-4248-a534-a03d13752731', NOW())
ON CONFLICT (student_id, cohort_id) DO NOTHING;

-- 5. LINK new Romulo to T4
INSERT INTO public.student_cohorts (student_id, cohort_id, enrolled_at)
SELECT s.id, '7e807cad-483e-4248-a534-a03d13752731'::uuid, NOW()
  FROM public.students s
 WHERE LOWER(s.email) = 'cursos@multid3.com.br'
ON CONFLICT (student_id, cohort_id) DO NOTHING;

-- 6. AUDIT LOG: insert all 21 CSV rows into student_imports
--    Preserves CSV source data so re-import never loses cadastros again.
INSERT INTO public.student_imports
  (cohort_id, name, email, source, turma_origin, raw_data, created_at)
VALUES
  ('7e807cad-483e-4248-a534-a03d13752731', 'MARCOS AURELIO AMARO DE BRITO', 'marcos.guita@gmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":9928,"cpf":"56146930172","matriculas":5,"progresso":3.0,"entrada":"2026-05-08","expira":"2027-04-14"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Andre Luiz de Mello', 'andre.lmm@gmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":8433,"cpf":"00549915958","matriculas":4,"progresso":16.5,"entrada":"2026-04-20","expira":"2027-04-20"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'JHONATA MATIAS MATA CAMPOS', 'jhonata.matias@cffranquias.com.br', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":5563,"cpf":"55571071000136","matriculas":14,"progresso":35.2,"entrada":"2026-04-22","expira":"2027-05-01"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'EDUARDO IGOR GOMES CARDOSO', 'eigorgomes@gmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":9952,"cpf":"04033777652","matriculas":2,"progresso":0.0,"entrada":"2026-04-13","expira":"2027-04-13"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'VANESSA DE SOUZA LOBO', 'lobo_nessa@hotmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":8073,"cpf":"00974244988","matriculas":11,"progresso":44.1,"entrada":"2026-04-19","expira":"2027-04-19"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Ideglan Araujo Lopes', 'soares_55@yahoo.com.br', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":9960,"cpf":"87793857291","matriculas":2,"progresso":50.0,"entrada":"2026-04-20","expira":"2027-04-20"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Diogo Quintella', 'diogo@bquintella.com.br', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":3319,"cpf":null,"matriculas":13,"progresso":28.7,"entrada":"2026-04-22","expira":"2027-04-30"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Raiza da Rocha Oliveira Teixeira', 'raizarochaa@gmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":1912,"cpf":"07540567406","matriculas":10,"progresso":15.9,"entrada":"2026-04-09","expira":"2027-04-09"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Jhonata Bueno dos Reis', 'jhonata.bueno.r@gmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":9955,"cpf":"05960684926","matriculas":5,"progresso":0.0,"entrada":"2026-04-17","expira":"2027-04-17"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', E'Samuel Guimarães Pereira Ribeiro', 'samuelguimaraespr@gmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":9947,"cpf":"70200687158","matriculas":2,"progresso":0.0,"entrada":"2026-04-12","expira":"2027-04-13"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Rodolfo Pedroso de Lima', 'rodolfolima9@gmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":531,"cpf":"02305242140","matriculas":40,"progresso":30.5,"entrada":"2026-04-20","expira":"2027-04-20"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Diogo Pereira Morais', 'diogo@inovacaonet.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":9958,"cpf":"08241906960","matriculas":3,"progresso":0.0,"entrada":"2026-04-20","expira":"2027-04-20"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'LIGIA COVRE DA SILVA', 'ligiacovre.s@gmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":7160,"cpf":"41031574883","matriculas":31,"progresso":6.4,"entrada":"2026-04-19","expira":"2027-04-19"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Romulo F Nuno', 'cursos@multid3.com.br', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":9957,"cpf":null,"matriculas":1,"progresso":0.0,"entrada":"2026-04-19","expira":"2027-04-19"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Anderson Brizuela Candia', 'anderstarkpy@gmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":9956,"cpf":"00005773166","matriculas":3,"progresso":3.3,"entrada":"2026-04-18","expira":"2027-04-18"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Igor Fraga', 'i.fraga@me.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":9954,"cpf":"39134188819","matriculas":5,"progresso":23.2,"entrada":"2026-04-15","expira":"2027-04-15"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Marcelo Grah', 'mgrah@hotmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":9943,"cpf":"05232689983","matriculas":3,"progresso":13.0,"entrada":"2026-04-10","expira":"2027-04-10"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Claudia Dumont', 'claudiadumont@hotmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":9793,"cpf":"02687063606","matriculas":8,"progresso":28.3,"entrada":"2026-04-22","expira":"2027-04-22"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Jaynara Suassuna Nunes', 'jaynarasn@gmail.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":3942,"cpf":"06504128421","matriculas":13,"progresso":8.5,"entrada":"2026-04-22","expira":"2027-04-22"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Rodrigo Feldman', 'feldmanrodrigo@me.com', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":1211,"cpf":"22318861897","matriculas":166,"progresso":0.4,"entrada":"2026-04-26","expira":"2027-04-26"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Rafael Da Silva Costa', 'rafael@utidasideias.com.br', 'csv:membros-grupo-74-20260515', 'Fundamental T4', '{"hotmart_id":7183,"cpf":null,"matriculas":16,"progresso":9.1,"entrada":"2026-04-29","expira":"2026-12-31"}'::jsonb, NOW());

COMMIT;
