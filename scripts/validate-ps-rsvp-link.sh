#!/usr/bin/env bash
# Pre-flight validation script — testa caminho completo Pré PS RSVP antes de dispatch em massa.
# Uso: bash scripts/validate-ps-rsvp-link.sh [token-de-teste]
# Sem args: pega último link 'sent' no DB. Com arg: usa esse token.

set -euo pipefail

SUPA_URL="https://gpufcipkajppykmnmdeh.supabase.co"
MGMT="https://api.supabase.com/v1/projects/gpufcipkajppykmnmdeh"
BASE_URL="https://painel.academialendaria.ai"

# Cores
G="\033[32m"; R="\033[31m"; Y="\033[33m"; B="\033[34m"; N="\033[0m"
PASS=0; FAIL=0; WARN=0
log_pass() { echo -e "${G}✓ PASS${N} $1"; PASS=$((PASS+1)); }
log_fail() { echo -e "${R}✗ FAIL${N} $1"; FAIL=$((FAIL+1)); }
log_warn() { echo -e "${Y}⚠ WARN${N} $1"; WARN=$((WARN+1)); }
log_info() { echo -e "${B}ℹ${N} $1"; }

echo "═════════════════════════════════════════════════════"
echo " VALIDAÇÃO PRÉ PS RSVP — pre-flight check"
echo "═════════════════════════════════════════════════════"
echo

# ─── 1. Secrets cofre ─────────────────────────────────────
log_info "1. Verificando secrets cofre"
SUPA_TOKEN=$(pass show apis/supabase-access-token 2>/dev/null || echo "")
META_KEY=$(pass show apis/meta-whatsapp/api-key 2>/dev/null || echo "")
WABA=$(pass show apis/meta-whatsapp/waba-id 2>/dev/null || echo "")
ANON=$(pass show supabase/academia-lendaria/calendario-aulas/anon 2>/dev/null || echo "")

if [ -z "$SUPA_TOKEN" ]; then log_fail "apis/supabase-access-token ausente"; else log_pass "Supabase token OK (${#SUPA_TOKEN} chars)"; fi
if [ -z "$META_KEY" ]; then log_fail "apis/meta-whatsapp/api-key ausente"; else log_pass "Meta API key OK (${#META_KEY} chars)"; fi
if [ -z "$WABA" ]; then log_fail "apis/meta-whatsapp/waba-id ausente"; else log_pass "Meta WABA OK"; fi
if [ -z "$ANON" ]; then log_fail "Supabase anon ausente"; else log_pass "Supabase anon OK"; fi

[ "$FAIL" -gt 0 ] && { echo; echo "Abort: secrets faltando."; exit 1; }

# ─── 2. Pegar token de teste ─────────────────────────────
echo; log_info "2. Selecionando token de teste"
if [ "${1:-}" ]; then
  TEST_TOKEN="$1"
  log_info "Usando token fornecido: $TEST_TOKEN"
else
  TEST_TOKEN=$(curl -sS -X POST "$MGMT/database/query" \
    -H "Authorization: Bearer $SUPA_TOKEN" \
    -H "Content-Type: application/json" \
    --data-binary '{"query":"SELECT token::text FROM ps_rsvp_links WHERE send_status='"'"'sent'"'"' ORDER BY sent_at DESC LIMIT 1;"}' | jq -r '.[0].token // empty')
  if [ -z "$TEST_TOKEN" ]; then log_fail "Nenhum link sent recente no DB"; exit 1; fi
  log_pass "Token escolhido: $TEST_TOKEN"
fi

# ─── 3. RPC get_ps_rsvp_metadata responde valid:true ─────
echo; log_info "3. RPC get_ps_rsvp_metadata"
RPC_RESP=$(curl -sS -X POST "$SUPA_URL/rest/v1/rpc/get_ps_rsvp_metadata" \
  -H "apikey: $ANON" -H "Authorization: Bearer $ANON" \
  -H "Content-Type: application/json" \
  -d "{\"p_token\":\"$TEST_TOKEN\"}")
VALID=$(echo "$RPC_RESP" | jq -r '.[0].valid // empty')
EXPIRED=$(echo "$RPC_RESP" | jq -r '.[0].expired // empty')
CLASS_NAME=$(echo "$RPC_RESP" | jq -r '.[0].class_name // empty')
STUDENT=$(echo "$RPC_RESP" | jq -r '.[0].student_name // empty')

if [ "$VALID" = "true" ]; then
  log_pass "RPC valid=true — class=$CLASS_NAME aluno=$STUDENT"
elif [ "$EXPIRED" = "true" ]; then
  log_fail "RPC expired=true — token venceu"
else
  log_fail "RPC retornou invalid — resposta: $RPC_RESP"
fi

# ─── 4. Form HTTP GET retorna 200 + parser preview mode ──
echo; log_info "4. Form HTTP GET"
FORM_URL="$BASE_URL/ps-rsvp/?token=$TEST_TOKEN"
HTTP_CODE=$(curl -sS -o /tmp/ps-rsvp-form.html -w "%{http_code}" "$FORM_URL")
if [ "$HTTP_CODE" = "200" ]; then
  log_pass "Form HTTP $HTTP_CODE — $FORM_URL"
else
  log_fail "Form HTTP $HTTP_CODE inesperado"
fi
if grep -q 'class="brand brand-dyn"' /tmp/ps-rsvp-form.html; then
  log_pass "Brand dinâmico presente (template novo deployed)"
else
  log_warn "Brand dinâmico ausente — pode estar com versão antiga cacheada"
fi
if grep -q 'get_ps_rsvp_metadata' /tmp/ps-rsvp-form.html; then
  log_pass "Script init OK (RPC fetch presente)"
else
  log_fail "Script init ausente — form quebrado"
fi

# ─── 5. Meta template aprovado ────────────────────────────
echo; log_info "5. Variants ativos + Meta template APPROVED"
VARIANTS=$(curl -sS -X POST "$MGMT/database/query" \
  -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  --data-binary '{"query":"SELECT id, meta_template_name FROM ps_rsvp_variants WHERE active=true;"}')
N_ACTIVE=$(echo "$VARIANTS" | jq 'length')
if [ "$N_ACTIVE" -eq 0 ]; then
  log_fail "ZERO variants ativos em ps_rsvp_variants → dispatcher aborta"
else
  log_pass "$N_ACTIVE variant(s) ativo(s)"
  for tname in $(echo "$VARIANTS" | jq -r '.[].meta_template_name'); do
    META_STATUS=$(curl -sS "https://graph.facebook.com/v18.0/$WABA/message_templates?name=$tname" \
      -H "Authorization: Bearer $META_KEY" | jq -r '.data[0].status // "NOT_FOUND"')
    case "$META_STATUS" in
      APPROVED) log_pass "Meta template $tname = APPROVED" ;;
      PENDING)  log_warn "Meta template $tname = PENDING (aguarda aprovação)" ;;
      *)        log_fail "Meta template $tname = $META_STATUS (não pode enviar)" ;;
    esac
  done
fi

# ─── 6. Button URL pattern correto no Meta ───────────────
echo; log_info "6. Pattern URL botão Meta template"
FIRST_TEMPLATE=$(echo "$VARIANTS" | jq -r '.[0].meta_template_name // empty')
if [ -n "$FIRST_TEMPLATE" ]; then
  BTN_URL=$(curl -sS "https://graph.facebook.com/v18.0/$WABA/message_templates?name=$FIRST_TEMPLATE" \
    -H "Authorization: Bearer $META_KEY" | jq -r '.data[0].components[] | select(.type=="BUTTONS") | .buttons[0].url // empty')
  if [ "$BTN_URL" = "$BASE_URL/ps-rsvp/?token={{1}}" ]; then
    log_pass "Button URL = $BTN_URL"
  else
    log_fail "Button URL pattern inesperado: $BTN_URL"
  fi
fi

# ─── 7. PS classes ativas hoje (weekday) ──────────────────
echo; log_info "7. Classes PS ativas pra hoje (via class_mentors)"
TODAY_WD=$(date +%u)  # 1=Mon..7=Sun; pg DOW = 0=Sun..6=Sat; map: Mon=1=1, Sat=6=6, Sun=7=0
[ "$TODAY_WD" = "7" ] && TODAY_WD=0
CLASSES=$(curl -sS -X POST "$MGMT/database/query" \
  -H "Authorization: Bearer $SUPA_TOKEN" -H "Content-Type: application/json" \
  --data-binary "{\"query\":\"SELECT c.name FROM classes c WHERE c.active=true AND c.kind='ps' AND EXISTS (SELECT 1 FROM class_mentors cm WHERE cm.class_id=c.id AND cm.weekday=$TODAY_WD AND cm.valid_from <= CURRENT_DATE AND (cm.valid_until IS NULL OR cm.valid_until >= CURRENT_DATE));\"}")
N_CLASSES=$(echo "$CLASSES" | jq 'length')
if [ "$N_CLASSES" -gt 0 ]; then
  log_pass "$N_CLASSES classe(s) PS hoje (wd=$TODAY_WD): $(echo "$CLASSES" | jq -r '.[].name' | paste -sd ', ')"
else
  log_warn "Nenhuma classe PS hoje pra weekday=$TODAY_WD (próximo cron pode não fazer nada)"
fi

# ─── 8. submit-ps-rsvp endpoint vivo ──────────────────────
echo; log_info "8. Endpoint submit-ps-rsvp (sem submeter)"
SUBMIT_CODE=$(curl -sS -o /dev/null -w "%{http_code}" -X OPTIONS "$SUPA_URL/functions/v1/submit-ps-rsvp" \
  -H "Authorization: Bearer $ANON")
if [ "$SUBMIT_CODE" = "200" ] || [ "$SUBMIT_CODE" = "204" ]; then
  log_pass "Edge fn submit-ps-rsvp respondeu OPTIONS ($SUBMIT_CODE)"
else
  log_warn "submit-ps-rsvp OPTIONS code=$SUBMIT_CODE (esperado 200/204)"
fi

# ─── Sumário ──────────────────────────────────────────────
echo
echo "═════════════════════════════════════════════════════"
echo -e "  ${G}PASS: $PASS${N}  ${R}FAIL: $FAIL${N}  ${Y}WARN: $WARN${N}"
echo "═════════════════════════════════════════════════════"
[ "$FAIL" -eq 0 ] && echo -e "${G}✓ READY pra dispatch${N}" || echo -e "${R}✗ Corrige FAILs antes de disparar${N}"
exit "$FAIL"
