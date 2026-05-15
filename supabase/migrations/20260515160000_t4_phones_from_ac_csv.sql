-- ============================================================================
-- T4 Phones Sync — CSV "cohort_fundamentals_t4.csv" (ActiveCampaign export)
-- Date: 2026-05-15
-- Cohort: Fundamental T4 (7e807cad-483e-4248-a534-a03d13752731)
-- ============================================================================
-- Purpose:
--   1. UPDATE phones reais nos 11 email-records (sobrescrever pending_*)
--   2. UPDATE ac_contact_id quando disponível
--   3. UPDATE phone Raiza (memory: 393397351323 IT)
--   4. AUDIT LOG: insert 16 CSV rows em student_imports com phones
-- ============================================================================

BEGIN;

-- 0. Archive WA-only duplicates (Ligia + Raiza)
--    Unique index idx_students_phone_cohort (phone, cohort_id) is global,
--    not filtered by active. Prefix phone with 'archived_' to free the slot
--    while preserving original data, and deactivate the record.
UPDATE public.students
   SET phone = 'archived_' || phone,
       active = false
 WHERE id IN (
   '31f19423-a2dd-4423-a15f-c492d8fcfbe5', -- "Raíza" WA-only 393397351323
   'f413e7e9-e3a3-4310-a5bf-2299082ebc4b'  -- "Ligia Covre" WA-only 5517996278301
 );

-- 1. UPDATE phones reais (11 alunos com phone válido)
UPDATE public.students SET phone = '5541992558377', phone_issue = NULL
 WHERE LOWER(email) = 'andre.lmm@gmail.com';

UPDATE public.students SET phone = '5581999123088', phone_issue = NULL
 WHERE LOWER(email) = 'diogo@bquintella.com.br';

UPDATE public.students SET phone = '5548999250105', phone_issue = NULL
 WHERE LOWER(email) = 'diogo@inovacaonet.com';

UPDATE public.students SET phone = '5531988881015', phone_issue = NULL
 WHERE LOWER(email) = 'ed.alves@yahoo.com.br';

UPDATE public.students SET phone = '5531987794049', phone_issue = NULL
 WHERE LOWER(email) = 'eigorgomes@gmail.com';

UPDATE public.students SET phone = '5517996278301', phone_issue = NULL
 WHERE LOWER(email) = 'ligiacovre.s@gmail.com';

UPDATE public.students SET phone = '5548999845315', phone_issue = NULL
 WHERE LOWER(email) = 'lobo_nessa@hotmail.com';

UPDATE public.students SET phone = '5561998811811', phone_issue = NULL
 WHERE LOWER(email) = 'marcos.guita@gmail.com';

UPDATE public.students SET phone = '5547991229779', phone_issue = NULL
 WHERE LOWER(email) = 'mgrah@hotmail.com';

UPDATE public.students SET phone = '5565998130132', phone_issue = NULL
 WHERE LOWER(email) = 'rodolfolima9@gmail.com';

UPDATE public.students SET phone = '5595991169628', phone_issue = NULL
 WHERE LOWER(email) = 'soares_55@yahoo.com.br';

-- 2. Raiza: CSV phone corrompido ('39'), usar phone IT da memória
UPDATE public.students SET phone = '393397351323', phone_issue = NULL
 WHERE LOWER(email) = 'raizarochaa@gmail.com';

-- 3. UPDATE ac_contact_id (Student ID do ActiveCampaign)
UPDATE public.students SET ac_contact_id = '3a6087d6-bbd2-4349-9654-118cb0fe2e66'
 WHERE LOWER(email) = 'anderstarkpy@gmail.com';
UPDATE public.students SET ac_contact_id = '5bb93452-e33c-4828-8cfd-fcf0e0f94ac6'
 WHERE LOWER(email) = 'andre.lmm@gmail.com';
UPDATE public.students SET ac_contact_id = 'ad521316-df7b-4bff-8d1a-84f8a44bb192'
 WHERE LOWER(email) = 'diogo@bquintella.com.br';
UPDATE public.students SET ac_contact_id = 'ecab661d-4a40-4a0d-b1cc-55678efa3915'
 WHERE LOWER(email) = 'diogo@inovacaonet.com';
UPDATE public.students SET ac_contact_id = 'dcca35a9-5ce8-4c96-9843-33ee1e931c45'
 WHERE LOWER(email) = 'ed.alves@yahoo.com.br';
UPDATE public.students SET ac_contact_id = '33effd01-49aa-4fc9-89d5-555ca1bd30ec'
 WHERE LOWER(email) = 'eigorgomes@gmail.com';
UPDATE public.students SET ac_contact_id = '6f05d6bf-ce14-4039-9cd0-430380b7c35f'
 WHERE LOWER(email) = 'i.fraga@me.com';
UPDATE public.students SET ac_contact_id = '1902dcf9-4803-41c6-b71e-ea52a1de3385'
 WHERE LOWER(email) = 'jhonata.bueno.r@gmail.com';
UPDATE public.students SET ac_contact_id = 'e665b48e-6f88-4981-8b3b-81c6b3058825'
 WHERE LOWER(email) = 'ligiacovre.s@gmail.com';
UPDATE public.students SET ac_contact_id = 'd4e9d8e2-1046-4cdd-9a1e-0e43c195e50a'
 WHERE LOWER(email) = 'lobo_nessa@hotmail.com';
UPDATE public.students SET ac_contact_id = 'ffb8918c-733f-4498-82b0-f837ca7d9c4c'
 WHERE LOWER(email) = 'marcos.guita@gmail.com';
UPDATE public.students SET ac_contact_id = 'afcf1d36-1090-4099-9e41-2817ea985851'
 WHERE LOWER(email) = 'mgrah@hotmail.com';
UPDATE public.students SET ac_contact_id = '50d0f804-b731-4141-ad21-c502468351c4'
 WHERE LOWER(email) = 'raizarochaa@gmail.com';
UPDATE public.students SET ac_contact_id = '0cc75392-5b58-45d2-a763-a1f313a92ec8'
 WHERE LOWER(email) = 'rodolfolima9@gmail.com';
UPDATE public.students SET ac_contact_id = '7dbbb23d-737f-4d93-8937-2280b9792a79'
 WHERE LOWER(email) = 'samuelguimaraespr@gmail.com';
UPDATE public.students SET ac_contact_id = '6d10b0d9-7323-4463-9dee-d7af27bed416'
 WHERE LOWER(email) = 'soares_55@yahoo.com.br';

-- 4. AUDIT LOG: 16 AC CSV rows
INSERT INTO public.student_imports
  (cohort_id, name, email, phone, source, turma_origin, raw_data, created_at)
VALUES
  ('7e807cad-483e-4248-a534-a03d13752731', 'Anderson Brizuela Candia', 'anderstarkpy@gmail.com', NULL, 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":162596,"ac_contact_id":"3a6087d6-bbd2-4349-9654-118cb0fe2e66","origin":"purchase_event/backfill_historico","sub_id":"sub_301a97f7-d317-4369-ae54-de81efe7492a"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Andre Mello', 'andre.lmm@gmail.com', '5541992558377', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":100957,"ac_contact_id":"5bb93452-e33c-4828-8cfd-fcf0e0f94ac6","city":"Curitiba","sub_id":"sub_9c2eac4b-67c4-44ee-8b57-669c2636607b"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Diogo Quintella', 'diogo@bquintella.com.br', '5581999123088', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":60722,"ac_contact_id":"ad521316-df7b-4bff-8d1a-84f8a44bb192","sub_id":"sub_9ebff586-6ac4-4f40-b90b-88060ce4cc49"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Diogo Pereira Morais', 'diogo@inovacaonet.com', '5548999250105', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":162611,"ac_contact_id":"ecab661d-4a40-4a0d-b1cc-55678efa3915","sub_id":"sub_d5a4da6f-eadb-4cd4-a481-5992fbc768f3"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Ednaldo Ferreira Alves', 'ed.alves@yahoo.com.br', '5531988881015', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":8978,"ac_contact_id":"dcca35a9-5ce8-4c96-9843-33ee1e931c45","city":"Ipatinga","sub_id":"sub_c62236a5-439b-4684-b0eb-00776ccc3a9b"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'EDUARDO IGOR GOMES CARDOSO', 'eigorgomes@gmail.com', '5531987794049', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":162364,"ac_contact_id":"33effd01-49aa-4fc9-89d5-555ca1bd30ec","sub_id":"sub_d2920a30-f4ce-4868-8935-a42ed878b210"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Igor Fraga', 'i.fraga@me.com', NULL, 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":162421,"ac_contact_id":"6f05d6bf-ce14-4039-9cd0-430380b7c35f","sub_id":"sub_b555baef-1cee-46a7-95ad-b2ccecf717a8"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Jhonata Bueno dos Reis', 'jhonata.bueno.r@gmail.com', NULL, 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":119045,"ac_contact_id":"1902dcf9-4803-41c6-b71e-ea52a1de3385","sub_id":"sub_478e1164-1789-4fc0-9e34-cbb7e947bed2"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'LIGIA COVRE DA SILVA', 'ligiacovre.s@gmail.com', '5517996278301', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":42130,"ac_contact_id":"e665b48e-6f88-4981-8b3b-81c6b3058825","city":"Emilio Ribas","sub_id":"sub_8eba2fec-99bf-4d0e-9ec5-623c8da39d70"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', E'Vanessa de Souza Lobo', 'lobo_nessa@hotmail.com', '5548999845315', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', E'{"ac_id":2248,"ac_contact_id":"d4e9d8e2-1046-4cdd-9a1e-0e43c195e50a","city":"Criciúma","sub_id":null}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'MARCOS BRITO', 'marcos.guita@gmail.com', '5561998811811', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":133274,"ac_contact_id":"ffb8918c-733f-4498-82b0-f837ca7d9c4c","sub_id":"sub_c3b1c0dd-53de-41c7-8368-3d0966f17531"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Marcelo Grah', 'mgrah@hotmail.com', '5547991229779', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":6471,"ac_contact_id":"afcf1d36-1090-4099-9e41-2817ea985851","sub_id":"sub_2746dea6-de9b-4d4c-8ecb-63f495d9c7d8"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Raiza D.', 'raizarochaa@gmail.com', '393397351323', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', E'{"ac_id":18165,"ac_contact_id":"50d0f804-b731-4141-ad21-c502468351c4","csv_phone_corrupt":"39","phone_resolved_from":"memory","city":"Milan","country":"Italy","sub_id":"sub_8b0fef28-5b3e-4813-9177-8df1bc1f1731"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Rodolfo Pedroso de Lima', 'rodolfolima9@gmail.com', '5565998130132', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', E'{"ac_id":53489,"ac_contact_id":"0cc75392-5b58-45d2-a763-a1f313a92ec8","city":"São Paulo","sub_id":"sub_c0734467-be2e-45fb-980a-73b8b5408c94"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', E'Samuel Guimarães Pereira Ribeiro', 'samuelguimaraespr@gmail.com', NULL, 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":192,"ac_contact_id":"7dbbb23d-737f-4d93-8937-2280b9792a79","csv_phone_corrupt":"+55330754461745","csv_wa_phone_suspect":"+556291216700","city":"Anapolis","sub_id":"sub_088b614e-cac7-4fac-86e2-838e321b50e0"}'::jsonb, NOW()),
  ('7e807cad-483e-4248-a534-a03d13752731', 'Ideglan Araujo Lopes', 'soares_55@yahoo.com.br', '5595991169628', 'csv:ac-cohort-fundamentals-t4-20260515', 'Fundamental T4', '{"ac_id":162614,"ac_contact_id":"6d10b0d9-7323-4463-9dee-d7af27bed416","sub_id":"sub_230f4692-c75e-482f-b4a9-f526ea3dcba8"}'::jsonb, NOW());

COMMIT;
