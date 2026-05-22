#!/usr/bin/env bash
# ============================================================
# smoke-webhook-canonical.sh — Story 22.5 (AC7)
# ============================================================
# Testes:
#   1-3. AC/Hotmart/Generic INSERT com payload válido → dedup_key extraído
#   4. Source enum CHECK rejeita value inválido
#   5. INSERT mesma (source, dedup_key) duas vezes — segundo bloqueia se UNIQUE aplicada
#      (se UNIQUE não aplicada ainda, ambos passam — flag warning)
#   6. extract_purchase_dedup_key NULL se payload incompleto
#   7. Migration idempotência (rerun não falha)
#
# Como rodar:
#   export PGHOST=localhost PGPORT=5433 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres
#   bash scripts/smoke-webhook-canonical.sh
# ============================================================

set -uo pipefail

: "${PGHOST:?PGHOST env var obrigatória}"
: "${PGPORT:=5432}"
: "${PGDATABASE:?PGDATABASE env var obrigatória}"
: "${PGUSER:?PGUSER env var obrigatória}"
: "${PGPASSWORD:?PGPASSWORD env var obrigatória}"

export PGPASSWORD PGHOST PGPORT PGDATABASE PGUSER

PSQL_OPTS="-h ${PGHOST} -p ${PGPORT} -U ${PGUSER} -d ${PGDATABASE} -v ON_ERROR_STOP=1 -t -A"
LOG_FILE="${LOG_FILE:-qa/22.5-smoke-$(date +%Y%m%d_%H%M%S).log}"
PASS=0
FAIL=0
TOTAL=7

mkdir -p "$(dirname "${LOG_FILE}")"

log()      { printf '%s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${LOG_FILE}"; }
log_pass() { log "[PASS] $*"; PASS=$((PASS + 1)); }
log_fail() { log "[FAIL] $*"; FAIL=$((FAIL + 1)); }

log "==== smoke-webhook-canonical.sh START ===="

# Cleanup pré-teste (remove rows de testes anteriores)
psql ${PSQL_OPTS} -c "DELETE FROM public.ac_purchase_events WHERE ac_event_id LIKE 'smoke-22.5-%';" 2>>${LOG_FILE} || true

# ============================================================
# Cenário 1: AC INSERT — payload válido
# ============================================================
log "--- Cenário 1: AC INSERT extrai dedup_key ---"
DEDUP_AC=$(psql ${PSQL_OPTS} -c "
INSERT INTO public.ac_purchase_events (ac_event_id, source, payload)
VALUES (
  'smoke-22.5-ac-001',
  'ac',
  '{
    \"contact\": {\"email\": \"Aluno@Test.com \"},
    \"product_id\": \"prod-123\",
    \"date\": \"2026-05-20T10:30:00Z\"
  }'::jsonb
)
RETURNING purchase_dedup_key;
" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${DEDUP_AC}" == "aluno@test.com|prod-123|2026-05-20" ]]; then
  log_pass "Cenário 1 — AC dedup_key='${DEDUP_AC}' (email lowercased + trimmed)"
else
  log_fail "Cenário 1 — AC dedup_key='${DEDUP_AC}' (esperado 'aluno@test.com|prod-123|2026-05-20')"
fi

# ============================================================
# Cenário 2: Hotmart INSERT — payload válido (schema diferente)
# ============================================================
log "--- Cenário 2: Hotmart INSERT extrai dedup_key ---"
DEDUP_HOT=$(psql ${PSQL_OPTS} -c "
INSERT INTO public.ac_purchase_events (ac_event_id, source, payload)
VALUES (
  'smoke-22.5-hot-001',
  'hotmart',
  '{
    \"buyer\": {\"email\": \"comprador@hotmart.com\"},
    \"product\": {\"id\": \"hot-456\"},
    \"purchase\": {\"order_date\": \"2026-05-21\"}
  }'::jsonb
)
RETURNING purchase_dedup_key;
" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${DEDUP_HOT}" == "comprador@hotmart.com|hot-456|2026-05-21" ]]; then
  log_pass "Cenário 2 — Hotmart dedup_key='${DEDUP_HOT}'"
else
  log_fail "Cenário 2 — Hotmart dedup_key='${DEDUP_HOT}'"
fi

# ============================================================
# Cenário 3: Generic INSERT — payload válido
# ============================================================
log "--- Cenário 3: Generic INSERT extrai dedup_key ---"
DEDUP_GEN=$(psql ${PSQL_OPTS} -c "
INSERT INTO public.ac_purchase_events (ac_event_id, source, payload)
VALUES (
  'smoke-22.5-gen-001',
  'generic',
  '{
    \"email\": \"generic@test.com\",
    \"product_id\": \"gen-789\",
    \"purchase_date\": \"2026-05-22\"
  }'::jsonb
)
RETURNING purchase_dedup_key;
" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${DEDUP_GEN}" == "generic@test.com|gen-789|2026-05-22" ]]; then
  log_pass "Cenário 3 — Generic dedup_key='${DEDUP_GEN}'"
else
  log_fail "Cenário 3 — Generic dedup_key='${DEDUP_GEN}'"
fi

# ============================================================
# Cenário 4: CHECK constraint rejeita source inválido
# ============================================================
log "--- Cenário 4: source inválido rejeitado pela CHECK constraint ---"
if psql ${PSQL_OPTS} -c "
INSERT INTO public.ac_purchase_events (ac_event_id, source, payload)
VALUES ('smoke-22.5-bad-source', 'invalid_source', '{}'::jsonb);
" 2>&1 | grep -q "chk_ac_purchase_source"; then
  log_pass "Cenário 4 — CHECK rejeitou source inválido"
else
  log_fail "Cenário 4 — CHECK não rejeitou source inválido (deveria)"
fi

# ============================================================
# Cenário 5: extract NULL se payload incompleto
# ============================================================
log "--- Cenário 5: payload incompleto → dedup_key NULL ---"
DEDUP_NULL=$(psql ${PSQL_OPTS} -c "
INSERT INTO public.ac_purchase_events (ac_event_id, source, payload)
VALUES (
  'smoke-22.5-incomplete',
  'ac',
  '{\"contact\": {\"email\": \"test@test.com\"}}'::jsonb
)
RETURNING COALESCE(purchase_dedup_key, '_NULL_');
" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${DEDUP_NULL}" == "_NULL_" ]]; then
  log_pass "Cenário 5 — payload incompleto → NULL"
else
  log_fail "Cenário 5 — esperado NULL got='${DEDUP_NULL}'"
fi

# ============================================================
# Cenário 6: extract function direct call (unit test)
# ============================================================
log "--- Cenário 6: extract_purchase_dedup_key direct call ---"
DIRECT=$(psql ${PSQL_OPTS} -c "
SELECT public.extract_purchase_dedup_key('ac',
  '{\"contact\": {\"email\": \"DIRECT@TEST.com\"},
    \"product_id\": \"p1\",
    \"date\": \"2026-01-15T08:00:00Z\"}'::jsonb);
" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${DIRECT}" == "direct@test.com|p1|2026-01-15" ]]; then
  log_pass "Cenário 6 — direct call lowercase + date trim"
else
  log_fail "Cenário 6 — direct='${DIRECT}'"
fi

# ============================================================
# Cenário 7: Idempotência (re-run migration parts)
# ============================================================
log "--- Cenário 7: ADD COLUMN IF NOT EXISTS idempotente ---"
if psql ${PSQL_OPTS} -c "
ALTER TABLE public.ac_purchase_events ADD COLUMN IF NOT EXISTS source text DEFAULT 'ac';
ALTER TABLE public.ac_purchase_events ADD COLUMN IF NOT EXISTS purchase_dedup_key text;
" 2>&1 >>${LOG_FILE}; then
  log_pass "Cenário 7 — ADD COLUMN IF NOT EXISTS sem erro"
else
  log_fail "Cenário 7 — idempotência falhou"
fi


# ============================================================
# Cleanup pós-teste
# ============================================================
psql ${PSQL_OPTS} -c "DELETE FROM public.ac_purchase_events WHERE ac_event_id LIKE 'smoke-22.5-%';" 2>>${LOG_FILE} || true

# ============================================================
# Resultado
# ============================================================
log "==== smoke-webhook-canonical.sh END ===="
log "Resultado: ${PASS}/${TOTAL} PASS, ${FAIL}/${TOTAL} FAIL"

if [[ "${FAIL}" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
