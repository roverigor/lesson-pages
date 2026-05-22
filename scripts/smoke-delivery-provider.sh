#!/usr/bin/env bash
# ============================================================
# smoke-delivery-provider.sh — Story 22.9
# ============================================================
# Testes:
#   1. ADD COLUMN provider + meta_message_id (schema check)
#   2. CHECK constraint provider IN ('evolution','meta')
#   3. INSERT com evolution_message_ids populated → backfill set provider='evolution'
#   4. INSERT com meta_message_id populated → backfill set provider='meta'
#   5. INSERT sem nenhum → backfill default 'evolution' + audit ambíguo
#   6. UNIQUE meta_message_id sparse (NULL OK múltiplos, valor único)
#   7. Migration idempotência (rerun safe)
#
# Como rodar:
#   export PGHOST=localhost PGPORT=5433 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres
#   bash scripts/smoke-delivery-provider.sh
# ============================================================

set -uo pipefail

: "${PGHOST:?PGHOST env var obrigatória}"
: "${PGPORT:=5432}"
: "${PGDATABASE:?PGDATABASE env var obrigatória}"
: "${PGUSER:?PGUSER env var obrigatória}"
: "${PGPASSWORD:?PGPASSWORD env var obrigatória}"

export PGPASSWORD PGHOST PGPORT PGDATABASE PGUSER

PSQL_OPTS="-h ${PGHOST} -p ${PGPORT} -U ${PGUSER} -d ${PGDATABASE} -v ON_ERROR_STOP=1 -t -A"
LOG_FILE="${LOG_FILE:-qa/22.9-smoke-$(date +%Y%m%d_%H%M%S).log}"
PASS=0
FAIL=0
TOTAL=7

mkdir -p "$(dirname "${LOG_FILE}")"

log()      { printf '%s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${LOG_FILE}"; }
log_pass() { log "[PASS] $*"; PASS=$((PASS + 1)); }
log_fail() { log "[FAIL] $*"; FAIL=$((FAIL + 1)); }

log "==== smoke-delivery-provider.sh START ===="

# Cleanup pré-teste
psql ${PSQL_OPTS} -c "DELETE FROM public.notifications WHERE message_template LIKE 'smoke-22.9-%';" 2>>${LOG_FILE} || true

# ============================================================
# Cenário 1: schema columns existem
# ============================================================
log "--- Cenário 1: provider + meta_message_id columns existem ---"
COLS=$(psql ${PSQL_OPTS} -c "
SELECT count(*) FROM information_schema.columns
WHERE table_schema='public' AND table_name='notifications'
  AND column_name IN ('provider','meta_message_id');
" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${COLS}" == "2" ]]; then
  log_pass "Cenário 1 — ambas colunas existem"
else
  log_fail "Cenário 1 — esperado 2 colunas, got=${COLS}"
fi

# ============================================================
# Cenário 2: CHECK constraint rejeita value inválido
# ============================================================
log "--- Cenário 2: CHECK rejeita provider inválido ---"
if psql ${PSQL_OPTS} -c "
INSERT INTO public.notifications (type, target_type, message_template, provider, status)
VALUES ('custom', 'individual', 'smoke-22.9-bad', 'whatsapp-invalid', 'pending');
" 2>&1 | grep -q "chk_notifications_provider"; then
  log_pass "Cenário 2 — CHECK rejeitou provider inválido"
else
  log_fail "Cenário 2 — CHECK não rejeitou (deveria)"
fi

# ============================================================
# Cenário 3: row com evolution_message_ids → backfill 'evolution'
# ============================================================
log "--- Cenário 3: evolution_message_ids → provider='evolution' via backfill ---"
psql ${PSQL_OPTS} -c "
INSERT INTO public.notifications (type, target_type, message_template, status, evolution_message_ids, provider)
VALUES ('custom', 'individual', 'smoke-22.9-evo', 'sent', ARRAY['evo-id-001']::text[], NULL);
" 2>>${LOG_FILE} || true
psql ${PSQL_OPTS} -c "SELECT public.backfill_notifications_provider();" >>${LOG_FILE} 2>&1 || true
EVO_PROVIDER=$(psql ${PSQL_OPTS} -c "
SELECT provider FROM public.notifications WHERE message_template = 'smoke-22.9-evo' LIMIT 1;
" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${EVO_PROVIDER}" == "evolution" ]]; then
  log_pass "Cenário 3 — evolution_message_ids → provider=evolution"
else
  log_fail "Cenário 3 — got provider='${EVO_PROVIDER}'"
fi

# ============================================================
# Cenário 4: row com meta_message_id → backfill 'meta'
# ============================================================
log "--- Cenário 4: meta_message_id → provider='meta' via backfill ---"
psql ${PSQL_OPTS} -c "
INSERT INTO public.notifications (type, target_type, message_template, status, meta_message_id, provider)
VALUES ('custom', 'individual', 'smoke-22.9-meta', 'sent', 'wamid.HBgM' || floor(random()*100000)::text, NULL);
" 2>>${LOG_FILE} || true
psql ${PSQL_OPTS} -c "SELECT public.backfill_notifications_provider();" >>${LOG_FILE} 2>&1 || true
META_PROVIDER=$(psql ${PSQL_OPTS} -c "
SELECT provider FROM public.notifications WHERE message_template = 'smoke-22.9-meta' LIMIT 1;
" 2>&1 | tail -1 | tr -d '[:space:]' || true)
if [[ "${META_PROVIDER}" == "meta" ]]; then
  log_pass "Cenário 4 — meta_message_id → provider=meta"
else
  log_fail "Cenário 4 — got provider='${META_PROVIDER}'"
fi

# ============================================================
# Cenário 5: row sem nenhum → backfill ambíguo → default 'evolution' + audit
# ============================================================
log "--- Cenário 5: row ambígua → default evolution + audit ---"
psql ${PSQL_OPTS} -c "
INSERT INTO public.notifications (type, target_type, message_template, status, provider)
VALUES ('custom', 'individual', 'smoke-22.9-ambiguous', 'pending', NULL);
" 2>>${LOG_FILE} || true

# Run backfill (vai logar audit ambíguo)
psql ${PSQL_OPTS} -c "SELECT public.backfill_notifications_provider();" >>${LOG_FILE} 2>&1 || true

AMB_PROVIDER=$(psql ${PSQL_OPTS} -c "
SELECT provider FROM public.notifications WHERE message_template = 'smoke-22.9-ambiguous' LIMIT 1;
" 2>&1 | tail -1 | tr -d '[:space:]' || true)

# Check audit_log entry
AUDIT_AMB=$(psql ${PSQL_OPTS} -c "
SELECT count(*) FROM public.audit_log
WHERE event_type = 'notifications_provider_backfill_ambiguous'
  AND payload->>'story_id' = '22.9';
" 2>&1 | tail -1 | tr -d '[:space:]' || true)

if [[ "${AMB_PROVIDER}" == "evolution" ]] && [[ "${AUDIT_AMB}" =~ ^[1-9] ]]; then
  log_pass "Cenário 5 — ambíguo → default evolution + audit logged (${AUDIT_AMB} entries)"
else
  log_fail "Cenário 5 — provider='${AMB_PROVIDER}' audit_count='${AUDIT_AMB}'"
fi

# ============================================================
# Cenário 6: UNIQUE meta_message_id sparse (NULL OK múltiplos)
# ============================================================
log "--- Cenário 6: UNIQUE sparse — múltiplos NULL OK ---"
psql ${PSQL_OPTS} -c "
INSERT INTO public.notifications (type, target_type, message_template, status, provider)
VALUES
  ('custom', 'individual', 'smoke-22.9-null1', 'sent', 'evolution'),
  ('custom', 'individual', 'smoke-22.9-null2', 'sent', 'evolution');
" >>${LOG_FILE} 2>&1
NULL_COUNT=$(psql ${PSQL_OPTS} -c "
SELECT count(*) FROM public.notifications
WHERE message_template IN ('smoke-22.9-null1','smoke-22.9-null2');
" 2>&1 | tail -1 | tr -d '[:space:]' || true)

if [[ "${NULL_COUNT}" == "2" ]]; then
  # Tenta inserir 2 rows com mesmo meta_message_id (deve falhar)
  if psql ${PSQL_OPTS} -c "
  INSERT INTO public.notifications (type, target_type, message_template, status, meta_message_id, provider)
  VALUES
    ('custom', 'individual', 'smoke-22.9-dup1', 'sent', 'wamid.DUPLICATE_TEST', 'meta'),
    ('custom', 'individual', 'smoke-22.9-dup2', 'sent', 'wamid.DUPLICATE_TEST', 'meta');
  " 2>&1 | grep -q "duplicate key\|idx_notifications_meta_message"; then
    log_pass "Cenário 6 — NULL múltiplos OK + UNIQUE rejeita meta_id duplicado"
  else
    log_fail "Cenário 6 — UNIQUE não rejeitou duplicado"
  fi
else
  log_fail "Cenário 6 — multi-NULL falhou (${NULL_COUNT} rows inseridos)"
fi

# ============================================================
# Cenário 7: idempotência (rerun migration parts)
# ============================================================
log "--- Cenário 7: ADD COLUMN IF NOT EXISTS idempotente ---"
if psql ${PSQL_OPTS} -c "
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS provider text DEFAULT 'evolution';
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS meta_message_id text;
CREATE INDEX IF NOT EXISTS idx_notifications_provider ON public.notifications (provider);
" 2>&1 >>${LOG_FILE}; then
  log_pass "Cenário 7 — re-rerun sem erros"
else
  log_fail "Cenário 7 — idempotência falhou"
fi

# ============================================================
# Cleanup
# ============================================================
psql ${PSQL_OPTS} -c "DELETE FROM public.notifications WHERE message_template LIKE 'smoke-22.9-%';" 2>>${LOG_FILE} || true

# ============================================================
# Resultado
# ============================================================
log "==== smoke-delivery-provider.sh END ===="
log "Resultado: ${PASS}/${TOTAL} PASS, ${FAIL}/${TOTAL} FAIL"

if [[ "${FAIL}" -eq 0 ]]; then
  exit 0
else
  exit 1
fi
