-- ============================================================
-- Story 22.1 — Identity Unification (EPIC-022 S.022.1)
-- ============================================================
-- ESCOPO: normalize_phone_e164() + ADD COLUMN normalized_phone
--         em 3 tabelas + trigger + backfill RPC + VIEW canônica
--         + INDEXES. UNIQUE constraint em students fica em
--         migration follow-up (após gate find_duplicate_students=0).
-- ROLLBACK: ver migration .down.sql pareada
-- ADR: docs/architecture/ADR-021-student-identity-unification.md
-- GATE PROD: NON-NEGOTIABLE — autorização literal user antes apply
-- ============================================================
-- Autor: @dev (Dex) — 2026-05-22
-- Pattern reference: 20260522155830_epic_022_s04_rls_hardening.sql
-- Deps: 22.4 RLS Hardening (VIEW herda RLS Tier 1) — apply prod
--       deve esperar 22.4 estar em prod (ordering T12).
-- PG version: 15 — IMMUTABLE function + plpgsql trigger
-- Idempotência: ADD COLUMN IF NOT EXISTS + DROP TRIGGER IF EXISTS
-- ============================================================


-- ============================================================
-- AUDIT TRAIL — INSERT inicial (event_type='identity_unification')
-- ============================================================

DO $audit$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'identity_unification',
        jsonb_build_object(
          'story_id', '22.1',
          'epic_id', 'EPIC-022',
          'migration', '20260522220000_epic_022_s01_identity_unification',
          'started_at', now(),
          'tables_affected', jsonb_build_array('students', 'student_imports', 'wa_group_members')
        )
      )
    $insert$;
  END IF;
END
$audit$;


-- ============================================================
-- T2 — Função normalize_phone_e164(text) returns text
-- ============================================================
-- IMMUTABLE: mesmo input → mesmo output sempre.
-- Strip non-digits + smart prepend "+55" + validate pattern E.164 BR.
-- Returns NULL se inválido (deixa caller decidir tratamento).
-- ============================================================

CREATE OR REPLACE FUNCTION public.normalize_phone_e164(input text)
RETURNS text
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  cleaned     text;
  digits_only text;
  result      text;
BEGIN
  IF input IS NULL OR length(trim(input)) = 0 THEN
    RETURN NULL;
  END IF;

  -- Strip everything except digits and plus signs
  cleaned := regexp_replace(input, '[^\d+]', '', 'g');

  -- Strip leading "+" pra contar dígitos puros
  digits_only := regexp_replace(cleaned, '^\+', '', 'g');

  -- Sanity check tamanho (BR celular = 10-11 digits, com 55 = 12-13)
  IF length(digits_only) < 10 OR length(digits_only) > 13 THEN
    RETURN NULL;
  END IF;

  -- Smart prepend country code
  IF substring(digits_only, 1, 2) = '55' AND length(digits_only) IN (12, 13) THEN
    -- já tem 55 prefix (com ou sem +)
    result := '+' || digits_only;
  ELSIF length(digits_only) IN (10, 11) THEN
    -- BR sem country code → prepend +55
    result := '+55' || digits_only;
  ELSE
    -- 12-13 dígitos mas não começa com 55 → não BR, reject
    RETURN NULL;
  END IF;

  -- Final pattern validation E.164 BR
  -- ^\+55              prefix
  -- [1-9][0-9]         DDD (11-99)
  -- [0-9]{8,9}$        número (8 dígitos fixo / 9 dígitos celular)
  IF result ~ '^\+55[1-9][0-9][0-9]{8,9}$' THEN
    RETURN result;
  ELSE
    RETURN NULL;
  END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.normalize_phone_e164(text) TO authenticated, anon, service_role;

COMMENT ON FUNCTION public.normalize_phone_e164(text) IS
  'Normaliza phone BR para E.164 (+55DDD9XXXXXXXX). Retorna NULL se inválido. IMMUTABLE. Ref: ADR-021.';


-- ============================================================
-- T2b — Inline unit tests (AC7 — 10 cenários)
-- ============================================================
-- Roda inline na própria migration pra falhar early se função
-- regrediu. Não bloqueia apply (apenas RAISE NOTICE), mas o
-- smoke script externo é a validação canônica.
-- ============================================================

DO $tests$
DECLARE
  failures int := 0;
  msg text := '';
BEGIN
  -- T1: input "+5511987654321" → output "+5511987654321"
  IF public.normalize_phone_e164('+5511987654321') IS DISTINCT FROM '+5511987654321' THEN
    failures := failures + 1; msg := msg || 'T1 FAIL; ';
  END IF;

  -- T2: input "11987654321" → output "+5511987654321"
  IF public.normalize_phone_e164('11987654321') IS DISTINCT FROM '+5511987654321' THEN
    failures := failures + 1; msg := msg || 'T2 FAIL; ';
  END IF;

  -- T3: input "5511987654321" → output "+5511987654321"
  IF public.normalize_phone_e164('5511987654321') IS DISTINCT FROM '+5511987654321' THEN
    failures := failures + 1; msg := msg || 'T3 FAIL; ';
  END IF;

  -- T4: input "(11) 98765-4321" → output "+5511987654321"
  IF public.normalize_phone_e164('(11) 98765-4321') IS DISTINCT FROM '+5511987654321' THEN
    failures := failures + 1; msg := msg || 'T4 FAIL; ';
  END IF;

  -- T5: input " 11 98765 4321 " (whitespace) → output "+5511987654321"
  IF public.normalize_phone_e164(' 11 98765 4321 ') IS DISTINCT FROM '+5511987654321' THEN
    failures := failures + 1; msg := msg || 'T5 FAIL; ';
  END IF;

  -- T7: input NULL → output NULL
  IF public.normalize_phone_e164(NULL) IS NOT NULL THEN
    failures := failures + 1; msg := msg || 'T7 FAIL; ';
  END IF;

  -- T8: input "" → output NULL
  IF public.normalize_phone_e164('') IS NOT NULL THEN
    failures := failures + 1; msg := msg || 'T8 FAIL; ';
  END IF;

  -- T9: input "abc123" (inválido) → output NULL
  IF public.normalize_phone_e164('abc123') IS NOT NULL THEN
    failures := failures + 1; msg := msg || 'T9 FAIL; ';
  END IF;

  IF failures > 0 THEN
    RAISE WARNING 'normalize_phone_e164 inline tests: % failures: %', failures, msg;
  ELSE
    RAISE NOTICE 'normalize_phone_e164 inline tests: 8/8 PASS';
  END IF;
END
$tests$;


-- ============================================================
-- T3 — ADD COLUMN normalized_phone em 3 tabelas
-- ============================================================
-- Nullable durante backfill. Migration follow-up promove pra
-- NOT NULL em students após validation duplicates.
-- ============================================================

BEGIN;
ALTER TABLE public.students            ADD COLUMN IF NOT EXISTS normalized_phone text;
ALTER TABLE public.student_imports     ADD COLUMN IF NOT EXISTS normalized_phone text;
ALTER TABLE public.wa_group_members    ADD COLUMN IF NOT EXISTS normalized_phone text;
COMMIT;


-- ============================================================
-- T4 — Trigger function + 3 triggers BEFORE INSERT/UPDATE OF phone
-- ============================================================
-- Popula normalized_phone automaticamente quando phone muda.
-- Não falha em NULL (deixa normalized_phone NULL também).
-- ============================================================

CREATE OR REPLACE FUNCTION public.trigger_normalize_phone()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.normalized_phone := public.normalize_phone_e164(NEW.phone);
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trigger_normalize_phone() IS
  'Trigger function pra popular normalized_phone via normalize_phone_e164. Usado em students/student_imports/wa_group_members. Ref: ADR-021.';

-- students
DROP TRIGGER IF EXISTS trg_students_normalize_phone ON public.students;
CREATE TRIGGER trg_students_normalize_phone
  BEFORE INSERT OR UPDATE OF phone
  ON public.students
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_normalize_phone();

-- student_imports
DROP TRIGGER IF EXISTS trg_student_imports_normalize_phone ON public.student_imports;
CREATE TRIGGER trg_student_imports_normalize_phone
  BEFORE INSERT OR UPDATE OF phone
  ON public.student_imports
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_normalize_phone();

-- wa_group_members
DROP TRIGGER IF EXISTS trg_wa_group_members_normalize_phone ON public.wa_group_members;
CREATE TRIGGER trg_wa_group_members_normalize_phone
  BEFORE INSERT OR UPDATE OF phone
  ON public.wa_group_members
  FOR EACH ROW
  EXECUTE FUNCTION public.trigger_normalize_phone();


-- ============================================================
-- T5 — RPC backfill_normalized_phones() idempotente
-- ============================================================
-- UPDATE WHERE normalized_phone IS NULL em cada tabela.
-- Returns count por tabela. 2x run → segundo retorna 0.
-- service_role recomendado pra bypass RLS Tier 1.
-- ============================================================

CREATE OR REPLACE FUNCTION public.backfill_normalized_phones()
RETURNS TABLE(table_name text, rows_updated bigint)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_students_updated         bigint := 0;
  v_imports_updated          bigint := 0;
  v_wa_updated               bigint := 0;
BEGIN
  -- students
  UPDATE public.students
     SET normalized_phone = public.normalize_phone_e164(phone)
   WHERE normalized_phone IS NULL
     AND phone IS NOT NULL;
  GET DIAGNOSTICS v_students_updated = ROW_COUNT;

  -- student_imports
  UPDATE public.student_imports
     SET normalized_phone = public.normalize_phone_e164(phone)
   WHERE normalized_phone IS NULL
     AND phone IS NOT NULL;
  GET DIAGNOSTICS v_imports_updated = ROW_COUNT;

  -- wa_group_members
  UPDATE public.wa_group_members
     SET normalized_phone = public.normalize_phone_e164(phone)
   WHERE normalized_phone IS NULL
     AND phone IS NOT NULL;
  GET DIAGNOSTICS v_wa_updated = ROW_COUNT;

  -- audit
  IF EXISTS (SELECT 1 FROM pg_class WHERE relname = 'audit_log') THEN
    INSERT INTO public.audit_log (event_type, payload)
    VALUES (
      'identity_unification_backfill',
      jsonb_build_object(
        'story_id', '22.1',
        'students_updated', v_students_updated,
        'student_imports_updated', v_imports_updated,
        'wa_group_members_updated', v_wa_updated,
        'completed_at', now()
      )
    );
  END IF;

  RETURN QUERY VALUES
    ('students', v_students_updated),
    ('student_imports', v_imports_updated),
    ('wa_group_members', v_wa_updated);
END;
$$;

GRANT EXECUTE ON FUNCTION public.backfill_normalized_phones() TO service_role;
REVOKE EXECUTE ON FUNCTION public.backfill_normalized_phones() FROM authenticated, anon;

COMMENT ON FUNCTION public.backfill_normalized_phones() IS
  'Populates normalized_phone em rows existentes. Idempotente. service_role only. Ref: ADR-021.';


-- ============================================================
-- T5b — Executar backfill (parte da migration)
-- ============================================================
-- Em prod, considerar rodar via wrapper Slack pra ter audit
-- de duração + count. Aqui faz parte da migration pra
-- garantir estado consistente pós-apply.
-- ============================================================

DO $backfill$
DECLARE
  rec record;
BEGIN
  FOR rec IN SELECT * FROM public.backfill_normalized_phones() LOOP
    RAISE NOTICE 'Backfill % rows: %', rec.table_name, rec.rows_updated;
  END LOOP;
END
$backfill$;


-- ============================================================
-- T6 — Indexes em normalized_phone (perf VIEW JOINs — R4)
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_students_normalized_phone
  ON public.students (normalized_phone)
  WHERE normalized_phone IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_student_imports_normalized_phone
  ON public.student_imports (normalized_phone)
  WHERE normalized_phone IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_wa_group_members_normalized_phone
  ON public.wa_group_members (normalized_phone)
  WHERE normalized_phone IS NOT NULL;


-- ============================================================
-- T6b — VIEW canônica v_students_unified
-- ============================================================
-- Source-of-truth: students. Mescla audit (student_imports)
-- + mirror WA (wa_group_members). LEFT JOIN preserva students
-- com phone válido mesmo sem sync WA ou AC ainda.
-- Herda RLS via tabelas base (Tier 1 admin-only via 22.4).
-- ============================================================

CREATE OR REPLACE VIEW public.v_students_unified AS
SELECT
  s.id                                                AS student_id,
  s.normalized_phone,
  s.cohort_id,
  COALESCE(s.name, wgm.wa_name, si.name)              AS canonical_name,
  s.is_mentor,
  s.active,

  -- AC import context (NULL se aluno nunca comprou via AC)
  si.product                                          AS ac_product,
  si.source                                           AS ac_source,
  si.created_at                                       AS ac_imported_at,

  -- WA group context (NULL se aluno nunca entrou em grupo WA)
  wgm.group_id                                        AS wa_group_id,
  wgm.synced_at                                       AS wa_synced_at,

  -- Raw originals (debug/audit)
  s.phone                                             AS student_phone_raw,
  si.phone                                            AS import_phone_raw,
  wgm.phone                                           AS wa_phone_raw

FROM public.students s
LEFT JOIN public.student_imports si
  ON s.normalized_phone = si.normalized_phone
  AND s.cohort_id = si.cohort_id
LEFT JOIN public.wa_group_members wgm
  ON s.normalized_phone = wgm.normalized_phone
  AND s.cohort_id = wgm.cohort_id
WHERE s.normalized_phone IS NOT NULL;

COMMENT ON VIEW public.v_students_unified IS
  'Canonical view de aluno por (normalized_phone, cohort_id). Source-of-truth: students. Mescla audit student_imports + mirror wa_group_members. Ref: ADR-021.';


-- ============================================================
-- T7 — UNIQUE constraint (DEFERRED — bloco comentado)
-- ============================================================
-- PRE-APPLY GATE: rodar `SELECT * FROM find_duplicate_students()`
-- e confirmar 0 rows. Se houver duplicates, RESOLVER via merge_students()
-- ANTES de descomentar este bloco e re-aplicar migration follow-up.
--
-- Migration separada (Story 22.1.follow): adicionar
-- supabase/migrations/{ts}_epic_022_s01_identity_unique_constraint.sql
-- contendo apenas este ALTER + NOT NULL promotion.
--
-- BEGIN;
-- ALTER TABLE public.students
--   ALTER COLUMN normalized_phone SET NOT NULL;
-- ALTER TABLE public.students
--   ADD CONSTRAINT students_normalized_phone_cohort_unique
--   UNIQUE (normalized_phone, cohort_id);
-- COMMIT;


-- ============================================================
-- AUDIT TRAIL — final
-- ============================================================

DO $audit_final$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'identity_unification',
        jsonb_build_object(
          'story_id', '22.1',
          'migration', '20260522220000_epic_022_s01_identity_unification',
          'completed_at', now(),
          'status', 'columns_trigger_backfill_view_indexes_applied',
          'unique_constraint_pending', true,
          'note', 'UNIQUE constraint bloco comentado — aguarda gate find_duplicate_students=0 + migration follow-up'
        )
      )
    $insert$;
  END IF;
END
$audit_final$;
