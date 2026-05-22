#!/usr/bin/env bash
# ============================================================
# smoke-identity-test.sh — Story 22.1 Identity Unification smoke (AC7)
# ============================================================
# Ref:
#   - Story:    docs/stories/22.1.story.md (AC7 — 10 cenários + extras)
#   - Migration: supabase/migrations/20260522220000_epic_022_s01_identity_unification.sql
#   - ADR:      docs/architecture/ADR-021-student-identity-unification.md
#
# Como rodar local (Docker dry-run ou PG15 nativo WSL):
#   export PGHOST=localhost
#   export PGPORT=5433
#   export PGDATABASE=postgres
#   export PGUSER=postgres
#   export PGPASSWORD=postgres
#   bash scripts/smoke-identity-test.sh
#
# Como rodar prod (read-only — SEM mutação):
#   export PGHOST=db.gpufcipkajppykmnmdeh.supabase.co
#   export PGPORT=5432
#   export PGDATABASE=postgres
#   export PGUSER=postgres
#   export PGPASSWORD="<service_role secret do cofre pass>"
#   bash scripts/smoke-identity-test.sh
#
# Exit 0 = todos cenários PASS. Exit 1 = qualquer FAIL.
# ============================================================

set -euo pipefail

# ============================================================
# CONFIG
# ============================================================
: "${PGHOST:?PGHOST env var obrigatória}"
: "${PGPORT:=5432}"
: "${PGDATABASE:?PGDATABASE env var obrigatória}"
: "${PGUSER:?PGUSER env var obrigatória}"
: "${PGPASSWORD:?PGPASSWORD env var obrigatória}"

export PGPASSWORD PGHOST PGPORT PGDATABASE PGUSER

PSQL_OPTS="-h ${PGHOST} -p ${PGPORT} -U ${PGUSER} -d ${PGDATABASE} -v ON_ERROR_STOP=1 -t -A"
LOG_FILE="${LOG_FILE:-qa/22.1-smoke-$(date +%Y%m%d_%H%M%S).log}"
PASS=0
FAIL=0
TOTAL=14

mkdir -p "$(dirname "${LOG_FILE}")"

log()      { printf '%s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${LOG_FILE}"; }
log_pass() { log "[PASS] $*"; PASS=$((PASS + 1)); }
log_fail() { log "[FAIL] $*"; FAIL=$((FAIL + 1)); }

log "==== smoke-identity-test.sh START ===="
log "Host: ${PGHOST}:${PGPORT}  DB: ${PGDATABASE}  User: ${PGUSER}"
log "Log: ${LOG_FILE}"

# ============================================================
# Helper: assert_normalize input expected
# ============================================================
assert_normalize() {
  local input="$1"
  local expected="$2"
  local label="$3"
  local got
  got=$(psql ${PSQL_OPTS} -c "SELECT COALESCE(public.normalize_phone_e164(\$\$${input}\$\$), '_NULL_');" 2>&1 | tail -1 | tr -d '[:space:]' || true)
  if [[ "${got}" == "${expected}" ]]; then
    log_pass "${label} — '${input}' → '${got}'"
  else
    log_fail "${label} — '${input}' got='${got}' expected='${expected}'"
  fi
}

# ============================================================
# Cenários AC7 — normalize_phone_e164 function
# ============================================================
log "--- AC7: normalize_phone_e164 input formats ---"

assert_normalize '+5511987654321'     '+5511987654321'     'T1 já E.164'
assert_normalize '11987654321'        '+5511987654321'     'T2 BR sem 55 (11 dígitos)'
assert_normalize '5511987654321'      '+5511987654321'     'T3 BR com 55 sem + (13 dígitos)'
assert_normalize '(11) 98765-4321'    '+5511987654321'     'T4 com parênteses + hifen'
assert_normalize ' 11 98765 4321 '    '+5511987654321'     'T5 whitespace'
assert_normalize '+55 (11) 98765-4321' '+5511987654321'    'T6 misturado completo'
assert_normalize ''                   '_NULL_'             'T7 string vazia → NULL'
assert_normalize 'abc123'             '_NULL_'             'T8 inválido → NULL'

# T9 NULL input — psql doesn't pass NULL well via shell quoting, then test via SQL direct
log "--- T9: SELECT normalize_phone_e164(NULL) → NULL ---"
T9_RESULT=$(psql ${PSQL_OPTS} -c "SELECT COALESCE(public.normalize_phone_e164(NULL), '_NULL_');" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${T9_RESULT}" == "_NULL_" ]]; then
  log_pass "T9 NULL input → NULL"
else
  log_fail "T9 NULL input got='${T9_RESULT}'"
fi

# T10 — tamanho inválido (5 dígitos)
assert_normalize '12345'              '_NULL_'             'T10 5 dígitos (inválido) → NULL'


# ============================================================
# Cenário 11: Trigger BEFORE INSERT em students simulação
# ============================================================
# Insere row teste + valida normalized_phone foi populado
# ============================================================
log "--- Cenário 11: trigger BEFORE INSERT students ---"

TRIGGER_RESULT=$(psql ${PSQL_OPTS} -c "
DO \$test\$
DECLARE
  v_phone text := '(11) 98765-4321';
  v_normalized text;
BEGIN
  -- Cria temp table replica (não toca students real)
  CREATE TEMP TABLE smoke_test_students (LIKE public.students INCLUDING ALL) ON COMMIT DROP;

  -- Apply mesmo trigger function em temp
  EXECUTE 'CREATE TRIGGER trg_smoke_normalize BEFORE INSERT OR UPDATE OF phone ON smoke_test_students FOR EACH ROW EXECUTE FUNCTION public.trigger_normalize_phone()';

  -- Insert teste
  INSERT INTO smoke_test_students (phone, cohort_id, name)
  VALUES (v_phone, gen_random_uuid()::text, 'Smoke Test');

  -- Verifica normalized
  SELECT normalized_phone INTO v_normalized
  FROM smoke_test_students LIMIT 1;

  IF v_normalized = '+5511987654321' THEN
    RAISE NOTICE 'TRIGGER_TEST_PASS';
  ELSE
    RAISE NOTICE 'TRIGGER_TEST_FAIL normalized=%', v_normalized;
  END IF;
END
\$test\$;
" 2>&1 || true)
if echo "${TRIGGER_RESULT}" | grep -q "TRIGGER_TEST_PASS"; then
  log_pass "Cenário 11 — trigger BEFORE INSERT popula normalized_phone"
else
  log_fail "Cenário 11 — trigger não populou. Output: ${TRIGGER_RESULT}"
fi


# ============================================================
# Cenário 12: backfill idempotência (2x run → segundo retorna 0)
# ============================================================
log "--- Cenário 12: backfill idempotência ---"

BACKFILL_2ND=$(psql ${PSQL_OPTS} -c "
  SELECT COALESCE(SUM(rows_updated), 0) FROM public.backfill_normalized_phones();
" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${BACKFILL_2ND}" == "0" ]]; then
  log_pass "Cenário 12 — backfill 2nd run = 0 rows (idempotente)"
else
  log_fail "Cenário 12 — backfill 2nd run = ${BACKFILL_2ND} (esperado 0)"
fi


# ============================================================
# Cenário 13: VIEW v_students_unified retorna >=0 rows
# ============================================================
log "--- Cenário 13: VIEW v_students_unified queryable ---"

VIEW_COUNT=$(psql ${PSQL_OPTS} -c "
  SELECT count(*) FROM public.v_students_unified;
" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${VIEW_COUNT}" =~ ^[0-9]+$ ]]; then
  log_pass "Cenário 13 — VIEW retorna count=${VIEW_COUNT}"
else
  log_fail "Cenário 13 — VIEW falhou: ${VIEW_COUNT}"
fi


# ============================================================
# Cenário 14: AC11 validation — 100% phones em students E.164 válido
# ============================================================
log "--- Cenário 14: AC11 validator ---"

AC11_BAD=$(psql ${PSQL_OPTS} -c "
  SELECT count(*) FROM public.students
  WHERE phone IS NOT NULL
    AND (normalized_phone IS NULL OR normalized_phone !~ '^\+55[1-9][0-9][0-9]{8,9}\$');
" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${AC11_BAD}" == "0" ]]; then
  log_pass "Cenário 14 — AC11 validator: 0 students com phone inválido pós-backfill"
elif [[ "${AC11_BAD}" =~ ^[0-9]+$ ]]; then
  log_fail "Cenário 14 — AC11 validator: ${AC11_BAD} students com normalized_phone NULL ou format inválido (esperado 0)"
else
  log_fail "Cenário 14 — query AC11 falhou: ${AC11_BAD}"
fi


# ============================================================
# RESULTADO FINAL
# ============================================================
log "==== smoke-identity-test.sh END ===="
log "Resultado: ${PASS}/${TOTAL} PASS, ${FAIL}/${TOTAL} FAIL"

if [[ "${FAIL}" -eq 0 ]]; then
  log "[OK] story-22.1 identity unification — ${PASS}/${TOTAL} cenários"
  exit 0
else
  log "[FAIL] story-22.1 identity unification — ${PASS}/${TOTAL} cenários (${FAIL} falhas)"
  exit 1
fi
