#!/usr/bin/env bash
# ============================================================
# apply-with-slack-alert.sh — Story 22.4 (AC8)
# ============================================================
# Wrapper bash em torno de `supabase db push` que:
#   1. Posta alert pre-apply no Slack #devops (lista tabelas + operador + ts)
#   2. Roda supabase db push capturando stdout+stderr+duration
#   3. Posta alert post-apply (status + duration + stack truncado se erro)
#
# Pattern alinhado com memory: slack-always-on-dispatchers
#
# Env vars obrigatórias:
#   SLACK_WEBHOOK_URL  — webhook destino (cofre pass: apis/slack-devops-webhook)
#   SUPABASE_PROJECT_REF  — gpufcipkajppykmnmdeh (calendario-aulas)
#
# Env vars opcionais:
#   STORY_ID    — default 22.4
#   MIGRATION   — default 20260522155830_epic_022_s04_rls_hardening
#   DRY_RUN     — "true" pra simular sem rodar push
#
# Como rodar:
#   export SLACK_WEBHOOK_URL=$(pass show apis/slack-devops-webhook)
#   export SUPABASE_PROJECT_REF=gpufcipkajppykmnmdeh
#   bash scripts/apply-with-slack-alert.sh
# ============================================================

set -euo pipefail

# ============================================================
# CONFIG
# ============================================================
: "${SUPABASE_PROJECT_REF:?SUPABASE_PROJECT_REF env var obrigatória}"
STORY_ID="${STORY_ID:-22.4}"
MIGRATION="${MIGRATION:-20260522155830_epic_022_s04_rls_hardening}"
DRY_RUN="${DRY_RUN:-false}"
OPERATOR="${USER:-unknown}"
TS_START="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
LOG_FILE="qa/22.4-apply-$(date +%Y%m%d_%H%M%S).log"

mkdir -p "$(dirname "${LOG_FILE}")"

# Tabelas escopo (consistente com migration up)
TIER1_TABLES="staff, student_imports, wa_group_members, class_nps_responses, student_attendance, response_metadata, nps_class_links"
TIER2_TABLES="audit_log, class_reminder_batches, class_reminder_sends, notification_queue, schedule_overrides, zoom_absence_alerts, class_cohort_access, error_reports, whatsapp_group_messages, zoom_chat_messages, zoom_import_queue, automation_executions, automation_rules, automation_runs, alert_history, engagement_daily_ranking"
TIER3_TABLES="integration_sources, lesson_abstracts, survey_templates (app_config pendente T11)"
EXCEPTIONS="ac_dispatch_callbacks, oauth_states, ac_purchase_events, ac_product_mappings"

# ============================================================
# Slack notify helper (gracefully degrades se webhook indisponível)
# ============================================================
slack_notify() {
  local payload="$1"
  if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
    echo "WARN: SLACK_WEBHOOK_URL não setado — pulando notify" | tee -a "${LOG_FILE}"
    return 0
  fi
  if ! curl -sS -X POST -H 'Content-Type: application/json' \
        --max-time 10 \
        --data "${payload}" \
        "${SLACK_WEBHOOK_URL}" >>"${LOG_FILE}" 2>&1; then
    echo "WARN: Slack notify falhou (não bloqueia apply)" | tee -a "${LOG_FILE}"
  fi
}

# ============================================================
# Truncate large strings pra caber em Slack (4000 chars max)
# ============================================================
truncate_slack() {
  local input="$1"
  local maxlen=3800
  if [[ ${#input} -gt ${maxlen} ]]; then
    printf '%s\n... [truncated %d chars]' "${input:0:${maxlen}}" "$((${#input} - maxlen))"
  else
    printf '%s' "${input}"
  fi
}

# ============================================================
# PRE-APPLY notify
# ============================================================
echo "==== apply-with-slack-alert.sh START ${TS_START} ====" | tee -a "${LOG_FILE}"
echo "Operator: ${OPERATOR}" | tee -a "${LOG_FILE}"
echo "Story:    ${STORY_ID}" | tee -a "${LOG_FILE}"
echo "Migration: ${MIGRATION}" | tee -a "${LOG_FILE}"
echo "Project:  ${SUPABASE_PROJECT_REF}" | tee -a "${LOG_FILE}"
echo "DRY_RUN:  ${DRY_RUN}" | tee -a "${LOG_FILE}"

PRE_PAYLOAD=$(cat <<JSON
{
  "text": ":rocket: RLS Hardening apply START — Story ${STORY_ID}",
  "blocks": [
    {"type":"header","text":{"type":"plain_text","text":"RLS Hardening apply START"}},
    {"type":"section","fields":[
      {"type":"mrkdwn","text":"*Story:*\n${STORY_ID}"},
      {"type":"mrkdwn","text":"*Migration:*\n${MIGRATION}"},
      {"type":"mrkdwn","text":"*Operator:*\n${OPERATOR}"},
      {"type":"mrkdwn","text":"*Started at:*\n${TS_START}"},
      {"type":"mrkdwn","text":"*Project:*\n${SUPABASE_PROJECT_REF}"},
      {"type":"mrkdwn","text":"*Dry-run:*\n${DRY_RUN}"}
    ]},
    {"type":"section","text":{"type":"mrkdwn","text":"*Tier 1 (7):* ${TIER1_TABLES}"}},
    {"type":"section","text":{"type":"mrkdwn","text":"*Tier 2 (16):* ${TIER2_TABLES}"}},
    {"type":"section","text":{"type":"mrkdwn","text":"*Tier 3 (4):* ${TIER3_TABLES}"}},
    {"type":"section","text":{"type":"mrkdwn","text":"*Exceções (4):* ${EXCEPTIONS}"}}
  ]
}
JSON
)
slack_notify "${PRE_PAYLOAD}"

# ============================================================
# APPLY
# ============================================================
START_EPOCH=$(date +%s)
APPLY_STATUS="ok"
APPLY_OUTPUT=""

if [[ "${DRY_RUN}" == "true" ]]; then
  echo "[DRY_RUN] simulando supabase db push (SKIPPED)" | tee -a "${LOG_FILE}"
  APPLY_OUTPUT="DRY_RUN — comando seria: supabase db push --project-ref ${SUPABASE_PROJECT_REF}"
else
  echo "[APPLY] Running: supabase db push --project-ref ${SUPABASE_PROJECT_REF}" | tee -a "${LOG_FILE}"
  if APPLY_OUTPUT=$(supabase db push --project-ref "${SUPABASE_PROJECT_REF}" 2>&1); then
    APPLY_STATUS="ok"
  else
    APPLY_STATUS="failed"
  fi
  echo "${APPLY_OUTPUT}" | tee -a "${LOG_FILE}"
fi

END_EPOCH=$(date +%s)
DURATION=$((END_EPOCH - START_EPOCH))
TS_END="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ============================================================
# POST-APPLY notify
# ============================================================
APPLY_OUTPUT_TRUNC=$(truncate_slack "${APPLY_OUTPUT}")
EMOJI=":white_check_mark:"
[[ "${APPLY_STATUS}" == "failed" ]] && EMOJI=":x:"

POST_PAYLOAD=$(cat <<JSON
{
  "text": "${EMOJI} RLS Hardening apply ${APPLY_STATUS} — Story ${STORY_ID}",
  "blocks": [
    {"type":"header","text":{"type":"plain_text","text":"RLS Hardening apply ${APPLY_STATUS}"}},
    {"type":"section","fields":[
      {"type":"mrkdwn","text":"*Story:*\n${STORY_ID}"},
      {"type":"mrkdwn","text":"*Status:*\n${APPLY_STATUS}"},
      {"type":"mrkdwn","text":"*Duration:*\n${DURATION}s"},
      {"type":"mrkdwn","text":"*Ended at:*\n${TS_END}"}
    ]},
    {"type":"section","text":{"type":"mrkdwn","text":"*Output (trunc):*\n\`\`\`${APPLY_OUTPUT_TRUNC}\`\`\`"}}
  ]
}
JSON
)
slack_notify "${POST_PAYLOAD}"

echo "==== END ${TS_END} ====" | tee -a "${LOG_FILE}"
echo "Status: ${APPLY_STATUS}" | tee -a "${LOG_FILE}"
echo "Duration: ${DURATION}s" | tee -a "${LOG_FILE}"
echo "Log: ${LOG_FILE}" | tee -a "${LOG_FILE}"

if [[ "${APPLY_STATUS}" == "failed" ]]; then
  exit 1
fi
exit 0
