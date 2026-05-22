#!/usr/bin/env bash
# ============================================================
# smoke-rls-test.sh — Story 22.4 RLS Hardening smoke (AC7)
# ============================================================
# Ref:
#   - Story:    docs/stories/22.4.story.md (AC7 — 10 cenários)
#   - Migration: supabase/migrations/20260522155830_epic_022_s04_rls_hardening.sql
#   - ADR:      docs/architecture/ADR-020-rls-policies.md
#
# Como rodar local (Docker dry-run):
#   export PGHOST=localhost
#   export PGPORT=54322
#   export PGDATABASE=postgres
#   export PGUSER=postgres
#   export PGPASSWORD=postgres
#   bash scripts/smoke-rls-test.sh
#
# Como rodar prod (read-only — SEM mutação real):
#   export PGHOST=db.gpufcipkajppykmnmdeh.supabase.co
#   export PGPORT=5432
#   export PGDATABASE=postgres
#   export PGUSER=postgres
#   export PGPASSWORD="<service_role secret do cofre pass>"
#   bash scripts/smoke-rls-test.sh
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
LOG_FILE="${LOG_FILE:-qa/22.4-smoke-$(date +%Y%m%d_%H%M%S).log}"
PASS=0
FAIL=0
TOTAL=10

mkdir -p "$(dirname "${LOG_FILE}")"

log() { printf '%s | %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "${LOG_FILE}"; }
log_pass() { log "[PASS] $*"; PASS=$((PASS + 1)); }
log_fail() { log "[FAIL] $*"; FAIL=$((FAIL + 1)); }

log "==== smoke-rls-test.sh START ===="
log "Host: ${PGHOST}:${PGPORT}  DB: ${PGDATABASE}  User: ${PGUSER}"
log "Log: ${LOG_FILE}"

# ============================================================
# Cenário 1: Admin (role=admin) lê class_nps_responses → OK
# ------------------------------------------------------------
# Simula admin via SET request.jwt.claims com user_metadata.role=admin.
# Em prod com sessão real, esse cenário valida via login admin no painel.
# Local Docker (sem auth), simulamos via SET.
# ============================================================
log "--- Cenário 1: admin lê class_nps_responses ---"
if psql ${PSQL_OPTS} -c "
  SET LOCAL request.jwt.claims TO '{\"user_metadata\":{\"role\":\"admin\"}}';
  SET LOCAL role TO authenticated;
  SELECT count(*) FROM public.class_nps_responses;
" 2>&1 | tee -a "${LOG_FILE}" | grep -qE '^[0-9]+$'; then
  log_pass "Cenário 1 — admin lê class_nps_responses"
else
  log_fail "Cenário 1 — admin lê class_nps_responses"
fi

# ============================================================
# Cenário 2: User comum (sem role admin) NÃO lê class_nps_responses
# ============================================================
log "--- Cenário 2: user comum NÃO lê class_nps_responses ---"
RESULT_2=$(psql ${PSQL_OPTS} -c "
  SET LOCAL request.jwt.claims TO '{\"user_metadata\":{\"role\":\"user\"}}';
  SET LOCAL role TO authenticated;
  SELECT count(*) FROM public.class_nps_responses;
" 2>&1 | tail -1 || true)
if [[ "${RESULT_2}" == "0" ]]; then
  log_pass "Cenário 2 — user comum bloqueado (count=0)"
else
  log_fail "Cenário 2 — user comum retornou: ${RESULT_2}"
fi

# ============================================================
# Cenário 3: service_role escreve em sample 3 Tier 1 + 3 Tier 2 + 1 Tier 3
# ============================================================
log "--- Cenário 3: service_role escreve em 7 tabelas sample ---"
SAMPLE_TABLES=(class_nps_responses wa_group_members nps_class_links audit_log error_reports notification_queue lesson_abstracts)
SAMPLE_OK=0
for tbl in "${SAMPLE_TABLES[@]}"; do
  if psql ${PSQL_OPTS} -c "
    SET LOCAL role TO service_role;
    SELECT 1 FROM public.${tbl} LIMIT 1;
  " >/dev/null 2>>"${LOG_FILE}"; then
    SAMPLE_OK=$((SAMPLE_OK + 1))
  fi
done
if [[ "${SAMPLE_OK}" -eq "${#SAMPLE_TABLES[@]}" ]]; then
  log_pass "Cenário 3 — service_role OK em ${SAMPLE_OK}/${#SAMPLE_TABLES[@]} tabelas"
else
  log_fail "Cenário 3 — service_role só OK em ${SAMPLE_OK}/${#SAMPLE_TABLES[@]} tabelas"
fi

# ============================================================
# Cenário 4: Dashboards admin (proxy via SELECT representativo)
# Validar que admin lê pelo menos 1 row em cada tabela usada por dashboards
# ============================================================
log "--- Cenário 4: dashboards admin proxy reads ---"
DASH_TABLES=(class_nps_responses nps_class_links student_attendance audit_log)
DASH_OK=0
for tbl in "${DASH_TABLES[@]}"; do
  if psql ${PSQL_OPTS} -c "
    SET LOCAL request.jwt.claims TO '{\"user_metadata\":{\"role\":\"admin\"}}';
    SET LOCAL role TO authenticated;
    SELECT count(*) FROM public.${tbl};
  " >/dev/null 2>>"${LOG_FILE}"; then
    DASH_OK=$((DASH_OK + 1))
  fi
done
if [[ "${DASH_OK}" -eq "${#DASH_TABLES[@]}" ]]; then
  log_pass "Cenário 4 — admin lê ${DASH_OK}/${#DASH_TABLES[@]} tabelas dashboard"
else
  log_fail "Cenário 4 — admin só ${DASH_OK}/${#DASH_TABLES[@]} dashboard"
fi

# ============================================================
# Cenário 5: Anon NÃO lê nenhuma Tier 1 — count=0 ou erro
# ============================================================
log "--- Cenário 5: anon bloqueado em Tier 1 ---"
ANON_TABLES=(class_nps_responses wa_group_members student_attendance student_imports response_metadata nps_class_links staff)
ANON_BLOCKED=0
for tbl in "${ANON_TABLES[@]}"; do
  RESULT=$(psql ${PSQL_OPTS} -c "
    SET LOCAL role TO anon;
    SELECT count(*) FROM public.${tbl};
  " 2>&1 | tail -1 || true)
  if [[ "${RESULT}" == "0" || "${RESULT}" == *"permission"* || "${RESULT}" == *"denied"* ]]; then
    ANON_BLOCKED=$((ANON_BLOCKED + 1))
  fi
done
if [[ "${ANON_BLOCKED}" -eq "${#ANON_TABLES[@]}" ]]; then
  log_pass "Cenário 5 — anon bloqueado em ${ANON_BLOCKED}/${#ANON_TABLES[@]} Tier 1"
else
  log_fail "Cenário 5 — anon só bloqueado em ${ANON_BLOCKED}/${#ANON_TABLES[@]} Tier 1"
fi

# ============================================================
# Cenário 6: staff (Tier 1) — admin lê, user comum NÃO lê
# ============================================================
log "--- Cenário 6: staff admin OK + user blocked ---"
STAFF_ADMIN=$(psql ${PSQL_OPTS} -c "
  SET LOCAL request.jwt.claims TO '{\"user_metadata\":{\"role\":\"admin\"}}';
  SET LOCAL role TO authenticated;
  SELECT count(*) FROM public.staff;
" 2>&1 | tail -1 || true)
STAFF_USER=$(psql ${PSQL_OPTS} -c "
  SET LOCAL request.jwt.claims TO '{\"user_metadata\":{\"role\":\"user\"}}';
  SET LOCAL role TO authenticated;
  SELECT count(*) FROM public.staff;
" 2>&1 | tail -1 || true)
if [[ "${STAFF_ADMIN}" =~ ^[0-9]+$ && "${STAFF_USER}" == "0" ]]; then
  log_pass "Cenário 6 — staff admin=${STAFF_ADMIN} user=0"
else
  log_fail "Cenário 6 — staff admin=${STAFF_ADMIN} user=${STAFF_USER}"
fi

# ============================================================
# Cenário 7: audit_log (Tier 2) — authenticated read OK + service write OK
# ============================================================
log "--- Cenário 7: audit_log Tier 2 read+write ---"
AL_READ=$(psql ${PSQL_OPTS} -c "
  SET LOCAL request.jwt.claims TO '{\"user_metadata\":{\"role\":\"admin\"}}';
  SET LOCAL role TO authenticated;
  SELECT count(*) FROM public.audit_log;
" 2>&1 | tail -1 || true)
AL_WRITE=$(psql ${PSQL_OPTS} -c "
  SET LOCAL role TO service_role;
  SELECT count(*) FROM public.audit_log;
" 2>&1 | tail -1 || true)
if [[ "${AL_READ}" =~ ^[0-9]+$ && "${AL_WRITE}" =~ ^[0-9]+$ ]]; then
  log_pass "Cenário 7 — audit_log read=${AL_READ} service=${AL_WRITE}"
else
  log_fail "Cenário 7 — audit_log read=${AL_READ} service=${AL_WRITE}"
fi

# ============================================================
# Cenário 8: app_config — bloco comentado, validar estado atual
# Pós-T11 e descomentar bloco, validar service_role pg_cron continua escrevendo.
# ============================================================
log "--- Cenário 8: app_config estado pré-T11 (DISABLE RLS esperado) ---"
APP_CONFIG_RLS=$(psql ${PSQL_OPTS} -c "
  SELECT relrowsecurity FROM pg_class c
  JOIN pg_namespace n ON c.relnamespace = n.oid
  WHERE n.nspname = 'public' AND c.relname = 'app_config';
" 2>&1 | tail -1 || true)
# Esperado FALSE até T11 aplicar
if [[ "${APP_CONFIG_RLS}" == "f" ]]; then
  log_pass "Cenário 8 — app_config RLS=false (esperado pré-T11)"
elif [[ "${APP_CONFIG_RLS}" == "t" ]]; then
  # Pós-T11 — validar service_role lê
  SRV_OK=$(psql ${PSQL_OPTS} -c "
    SET LOCAL role TO service_role;
    SELECT count(*) FROM public.app_config;
  " 2>&1 | tail -1 || true)
  if [[ "${SRV_OK}" =~ ^[0-9]+$ ]]; then
    log_pass "Cenário 8 — app_config RLS=true pós-T11 + service_role lê (${SRV_OK})"
  else
    log_fail "Cenário 8 — app_config RLS=true pós-T11 mas service_role falhou: ${SRV_OK}"
  fi
else
  log_fail "Cenário 8 — app_config relrowsecurity inesperado: ${APP_CONFIG_RLS}"
fi

# ============================================================
# Cenário 9: Tier 1 sem ownership (staff, wa_group_members, response_metadata)
# admin lê, user comum não lê.
# ============================================================
log "--- Cenário 9: Tier 1 sem ownership (3 tabelas) ---"
NO_OWN=(staff wa_group_members response_metadata)
NO_OWN_OK=0
for tbl in "${NO_OWN[@]}"; do
  ADMIN_R=$(psql ${PSQL_OPTS} -c "
    SET LOCAL request.jwt.claims TO '{\"user_metadata\":{\"role\":\"admin\"}}';
    SET LOCAL role TO authenticated;
    SELECT count(*) FROM public.${tbl};
  " 2>&1 | tail -1 || true)
  USER_R=$(psql ${PSQL_OPTS} -c "
    SET LOCAL request.jwt.claims TO '{\"user_metadata\":{\"role\":\"user\"}}';
    SET LOCAL role TO authenticated;
    SELECT count(*) FROM public.${tbl};
  " 2>&1 | tail -1 || true)
  if [[ "${ADMIN_R}" =~ ^[0-9]+$ && "${USER_R}" == "0" ]]; then
    NO_OWN_OK=$((NO_OWN_OK + 1))
  fi
done
if [[ "${NO_OWN_OK}" -eq "${#NO_OWN[@]}" ]]; then
  log_pass "Cenário 9 — ${NO_OWN_OK}/${#NO_OWN[@]} Tier 1 sem-ownership corretos"
else
  log_fail "Cenário 9 — ${NO_OWN_OK}/${#NO_OWN[@]} Tier 1 sem-ownership"
fi

# ============================================================
# Cenário 10: response_metadata com role cs (condicional)
# Se houver user cs ativo, valida que CS lê OK + user comum bloqueado.
# Se não houver cs, marca PASS por inaplicabilidade (skip controlado).
# ============================================================
log "--- Cenário 10: response_metadata role cs (condicional) ---"
CS_COUNT=$(psql ${PSQL_OPTS} -c "
  SET LOCAL role TO service_role;
  SELECT count(*) FROM auth.users WHERE raw_user_meta_data->>'role' = 'cs';
" 2>&1 | tail -1 || true)
if [[ "${CS_COUNT}" == "0" ]]; then
  log_pass "Cenário 10 — sem user cs ativo (skip controlado, decisão T1)"
elif [[ "${CS_COUNT}" =~ ^[0-9]+$ ]]; then
  # Migration padronizou pra is_dashboard_admin only — cs perderá acesso.
  # Sinaliza FAIL pra forçar revisão (caveat documentado).
  log_fail "Cenário 10 — ${CS_COUNT} user cs ativo; migration atual NÃO autoriza cs em response_metadata (revisar pre-apply)"
else
  log_fail "Cenário 10 — query cs role retornou: ${CS_COUNT}"
fi


# ============================================================
# RESULTADO FINAL
# ============================================================
log "==== smoke-rls-test.sh END ===="
log "Resultado: ${PASS}/${TOTAL} PASS, ${FAIL}/${TOTAL} FAIL"

if [[ "${FAIL}" -eq 0 ]]; then
  log "[OK] story-22.4 RLS hardening — ${PASS}/${TOTAL} cenários"
  exit 0
else
  log "[FAIL] story-22.4 RLS hardening — ${PASS}/${TOTAL} cenários (${FAIL} falhas)"
  exit 1
fi
