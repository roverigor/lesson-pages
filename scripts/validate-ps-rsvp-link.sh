#!/usr/bin/env bash
# Pre-flight validation — Pré PS RSVP + Pós PS NPS end-to-end check.
# Uso: bash scripts/validate-ps-rsvp-link.sh [token-de-teste]
# Sem args: pega último link PS RSVP 'sent' no DB.

set -euo pipefail

SUPA_URL="https://gpufcipkajppykmnmdeh.supabase.co"
MGMT="https://api.supabase.com/v1/projects/gpufcipkajppykmnmdeh"
BASE_URL="https://painel.academialendaria.ai"

G="\033[32m"; R="\033[31m"; Y="\033[33m"; B="\033[34m"; N="\033[0m"
PASS=0; FAIL=0; WARN=0
log_pass() { echo -e "${G}✓ PASS${N} $1"; PASS=$((PASS+1)); }
log_fail() { echo -e "${R}✗ FAIL${N} $1"; FAIL=$((FAIL+1)); }
log_warn() { echo -e "${Y}⚠ WARN${N} $1"; WARN=$((WARN+1)); }
log_info() { echo -e "${B}ℹ${N} $1"; }
section() { echo; echo -e "${B}═══ $1 ═══${N}"; }

echo "═════════════════════════════════════════════════════"
echo " PRE-FLIGHT VALIDATION — Pré PS + Pós PS NPS"
echo "═════════════════════════════════════════════════════"

section "1. Secrets cofre"
SUPA_TOKEN=$(pass show apis/supabase-access-token 2>/dev/null || echo "")
META_KEY=$(pass show apis/meta-whatsapp/api-key 2>/dev/null || echo "")
WABA=$(pass show apis/meta-whatsapp/waba-id 2>/dev/null || echo "")

if [ -z "$SUPA_TOKEN" ]; then log_fail "apis/supabase-access-token ausente"; else log_pass "Supabase token OK"; fi
if [ -z "$META_KEY" ]; then log_fail "apis/meta-whatsapp/api-key ausente"; else log_pass "Meta API key OK"; fi
if [ -z "$WABA" ]; then log_fail "apis/meta-whatsapp/waba-id ausente"; else log_pass "Meta WABA OK"; fi
[ "$FAIL" -gt 0 ] && { echo; echo "Abort: secrets faltando."; exit 1; }

ANON_LEGACY=$(curl -sS "$MGMT/api-keys" -H "Authorization: Bearer $SUPA_TOKEN" | jq -r '.[] | select(.name=="anon" and .type=="legacy") | .api_key')
if [ -z "$ANON_LEGACY" ]; then log_fail "Anon legacy JWT ausente"; exit 1; else log_pass "Anon legacy JWT OK"; fi

# ───────────── Pré PS RSVP ─────────────
section "2. PRÉ PS RSVP — token + form"
if [ "${1:-}" ]; then
  TEST_TOKEN="$1"
else
  TEST_TOKEN=$(curl -sS -X POST "$MGMT/database/query" \
    -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
    --data-binary '{"query":"SELECT token::text FROM ps_rsvp_links WHERE send_status='"'"'sent'"'"' ORDER BY sent_at DESC LIMIT 1;"}' | jq -r '.[0].token // empty')
fi
[ -z "$TEST_TOKEN" ] && { log_fail "Nenhum token PS RSVP encontrado"; exit 1; }
log_pass "Token: $TEST_TOKEN"

RPC=$(curl -sS -X POST "$SUPA_URL/rest/v1/rpc/get_ps_rsvp_metadata" \
  -H "apikey: $ANON_LEGACY" -H "Authorization: Bearer $ANON_LEGACY" \
  -H "Content-Type: application/json" -d "{\"p_token\":\"$TEST_TOKEN\"}")
[ "$(echo "$RPC" | jq -r '.[0].valid')" = "true" ] && log_pass "RPC get_ps_rsvp_metadata valid=true" || log_fail "RPC PS RSVP inválido: $RPC"

HTTP=$(curl -sS -o /tmp/psrsvp.html -w "%{http_code}" "$BASE_URL/ps-rsvp/?token=$TEST_TOKEN")
[ "$HTTP" = "200" ] && log_pass "Form PS RSVP HTTP 200" || log_fail "Form PS RSVP HTTP $HTTP"
grep -q 'Authorization.*Bearer' /tmp/psrsvp.html && log_pass "PS RSVP form: Authorization header presente" || log_fail "PS RSVP form: SEM Authorization header (401 risk)"

section "3. PRÉ PS — Meta templates + variants"
PS_VARIANTS=$(curl -sS -X POST "$MGMT/database/query" \
  -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  --data-binary '{"query":"SELECT id, meta_template_name FROM ps_rsvp_variants WHERE active=true;"}')
N_PS=$(echo "$PS_VARIANTS" | jq 'length')
[ "$N_PS" -eq 0 ] && log_fail "ZERO ps_rsvp_variants ativos" || log_pass "$N_PS PS RSVP variant(s) ativo(s)"
for tname in $(echo "$PS_VARIANTS" | jq -r '.[].meta_template_name'); do
  STATUS=$(curl -sS "https://graph.facebook.com/v18.0/$WABA/message_templates?name=$tname" -H "Authorization: Bearer $META_KEY" | jq -r '.data[0].status // "NOT_FOUND"')
  case "$STATUS" in
    APPROVED) log_pass "Meta template $tname = APPROVED" ;;
    PENDING)  log_warn "Meta $tname = PENDING" ;;
    *)        log_fail "Meta $tname = $STATUS" ;;
  esac
done

section "4. PRÉ PS — submit endpoint + classes hoje"
SUBMIT_CODE=$(curl -sS -o /dev/null -w "%{http_code}" -X OPTIONS "$SUPA_URL/functions/v1/submit-ps-rsvp" -H "Authorization: Bearer $ANON_LEGACY")
[ "$SUBMIT_CODE" = "200" -o "$SUBMIT_CODE" = "204" ] && log_pass "submit-ps-rsvp OPTIONS $SUBMIT_CODE" || log_warn "submit-ps-rsvp OPTIONS $SUBMIT_CODE"

TODAY_WD=$(date +%u); [ "$TODAY_WD" = "7" ] && TODAY_WD=0
PS_CLASSES=$(curl -sS -X POST "$MGMT/database/query" \
  -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  --data-binary "{\"query\":\"SELECT c.name FROM classes c WHERE c.active=true AND c.kind='ps' AND EXISTS (SELECT 1 FROM class_mentors cm WHERE cm.class_id=c.id AND cm.weekday=$TODAY_WD AND cm.valid_from <= CURRENT_DATE AND (cm.valid_until IS NULL OR cm.valid_until >= CURRENT_DATE));\"}")
N_C=$(echo "$PS_CLASSES" | jq 'length')
[ "$N_C" -gt 0 ] && log_pass "$N_C PS class(es) hoje (wd=$TODAY_WD)" || log_warn "Sem PS hoje (wd=$TODAY_WD)"

# ───────────── Pós PS NPS ─────────────
section "5. PÓS PS NPS — config + trigger"
ENABLED=$(curl -sS -X POST "$MGMT/database/query" \
  -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  --data-binary '{"query":"SELECT public.nps_config_bool('"'"'nps_dispatch_enabled'"'"', false) AS v;"}' | jq -r '.[0].v // "missing"')
[ "$ENABLED" = "true" ] && log_pass "nps_dispatch_enabled=true" || log_fail "nps_dispatch_enabled=$ENABLED"

TRIG=$(curl -sS -X POST "$MGMT/database/query" \
  -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  --data-binary '{"query":"SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname='"'"'trg_enqueue_nps_after_zoom_processed'"'"';"}' | jq -r '.[0].pg_get_functiondef // ""')
echo "$TRIG" | grep -q "class_cohorts" && log_pass "Trigger usa class_cohorts (cobre todas cohorts)" || log_fail "Trigger ainda usa class_cohort_access (cobre menos cohorts)"

CRONS=$(curl -sS -X POST "$MGMT/database/query" \
  -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  --data-binary '{"query":"SELECT jobname FROM cron.job WHERE jobname IN ('"'"'dispatch-class-nps-tick'"'"','"'"'zoom-auto-import'"'"','"'"'dispatch-ps-rsvp'"'"') AND active=true;"}' | jq -r '.[].jobname')
echo "$CRONS" | grep -q "dispatch-class-nps-tick" && log_pass "Cron dispatch-class-nps-tick ativo" || log_fail "Cron dispatch-class-nps-tick INATIVO"
echo "$CRONS" | grep -q "zoom-auto-import" && log_pass "Cron zoom-auto-import ativo" || log_fail "Cron zoom-auto-import INATIVO"
echo "$CRONS" | grep -q "dispatch-ps-rsvp" && log_pass "Cron dispatch-ps-rsvp ativo (8h BRT Ter+Sex)" || log_fail "Cron dispatch-ps-rsvp INATIVO"

section "6. PÓS PS NPS — Meta templates + variants"
NPS_VARIANTS=$(curl -sS -X POST "$MGMT/database/query" \
  -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  --data-binary '{"query":"SELECT id, channel, meta_template_name FROM nps_message_variants WHERE active=true;"}')
N_DM=$(echo "$NPS_VARIANTS" | jq '[.[] | select(.channel=="dm")] | length')
N_GP=$(echo "$NPS_VARIANTS" | jq '[.[] | select(.channel=="group")] | length')
[ "$N_DM" -gt 0 ] && log_pass "$N_DM variant DM ativo(s)" || log_fail "Nenhum variant DM ativo"
[ "$N_GP" -gt 0 ] && log_pass "$N_GP variant(s) group ativo(s)" || log_warn "Sem variants group (texto livre Evolution)"

for tname in $(echo "$NPS_VARIANTS" | jq -r '.[] | select(.meta_template_name != null) | .meta_template_name'); do
  STATUS=$(curl -sS "https://graph.facebook.com/v18.0/$WABA/message_templates?name=$tname" -H "Authorization: Bearer $META_KEY" | jq -r '.data[0].status // "NOT_FOUND"')
  case "$STATUS" in
    APPROVED) log_pass "Meta $tname = APPROVED" ;;
    PENDING)  log_warn "Meta $tname = PENDING" ;;
    *)        log_fail "Meta $tname = $STATUS" ;;
  esac
done

section "7. PÓS PS NPS — form survey + submit"
HTTP_S=$(curl -sS -o /tmp/survey.html -w "%{http_code}" "$BASE_URL/survey/?token=test")
[ "$HTTP_S" = "200" ] && log_pass "Form survey HTTP 200" || log_fail "Form survey HTTP $HTTP_S"
N_AUTH=$(grep -c 'Authorization.*Bearer' /tmp/survey.html || echo 0)
[ "$N_AUTH" -ge 3 ] && log_pass "Survey form: $N_AUTH Authorization headers (fetchMeta + submit + retry)" || log_fail "Survey form: só $N_AUTH Authorization (esperado 3+)"

SURVEY_OPTS=$(curl -sS -o /dev/null -w "%{http_code}" -X OPTIONS "$SUPA_URL/functions/v1/submit-survey-group" -H "Authorization: Bearer $ANON_LEGACY")
[ "$SURVEY_OPTS" = "200" -o "$SURVEY_OPTS" = "204" ] && log_pass "submit-survey-group OPTIONS $SURVEY_OPTS" || log_warn "submit-survey-group OPTIONS $SURVEY_OPTS"

section "8. PÓS PS NPS — cobertura cohorts PS (class_cohorts)"
PS_COH=$(curl -sS -X POST "$MGMT/database/query" \
  -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  --data-binary '{"query":"SELECT c.name, COUNT(DISTINCT cc.cohort_id) AS n FROM classes c JOIN class_cohorts cc ON cc.class_id=c.id WHERE c.kind='"'"'ps'"'"' AND c.active=true GROUP BY c.name;"}')
echo "$PS_COH" | jq -r '.[] | "  \(.name): \(.n) cohort(s)"'
TOTAL_PS=$(echo "$PS_COH" | jq '[.[] | .n] | add')
[ "$TOTAL_PS" -ge 10 ] && log_pass "PS classes cobrem $TOTAL_PS cohorts no total" || log_warn "PS classes só $TOTAL_PS cohorts — review class_cohorts"

section "9. Filtros segurança"
COUNT_BAD=$(curl -sS -X POST "$MGMT/database/query" \
  -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  --data-binary '{"query":"SELECT COUNT(*) FROM students WHERE active=true AND name ~ '"'"'^WA [0-9]+$'"'"';"}' | jq -r '.[0].count')
[ "$COUNT_BAD" = "0" ] && log_pass "Zero students active com nome 'WA NNNN'" || log_warn "$COUNT_BAD students active com nome placeholder (cleanup recomendado)"

CSV_TOTAL=$(curl -sS -X POST "$MGMT/database/query" \
  -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  --data-binary '{"query":"SELECT COUNT(DISTINCT phone) FROM student_imports WHERE phone IS NOT NULL;"}' | jq -r '.[0].count')
log_pass "student_imports tem $CSV_TOTAL phones (CSV-allowlist)"

# ───────────── Sumário ─────────────
section "RESUMO"
echo -e "  ${G}PASS: $PASS${N}  ${R}FAIL: $FAIL${N}  ${Y}WARN: $WARN${N}"
echo "═════════════════════════════════════════════════════"
[ "$FAIL" -eq 0 ] && echo -e "${G}✓ READY pra dispatch (Pré + Pós PS)${N}" || echo -e "${R}✗ Corrige FAILs antes de disparar${N}"
exit "$FAIL"
