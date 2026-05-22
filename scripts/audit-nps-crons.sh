#!/usr/bin/env bash
# ============================================================
# audit-nps-crons.sh — Story 22.7 (T1 + T2 investigation)
# ============================================================
# Lista TODOS crons NPS atuais (ativos + dormentes + comentados).
# Cross-check com dispatches efetivos nos últimos 30 dias.
#
# Gera 2 outputs:
#   - docs/22.7-cron-inventory.md (T1)
#   - docs/22.7-30d-report.md (T2)
#
# Como rodar:
#   export PGHOST=... PGPORT=... PGUSER=... PGPASSWORD=... PGDATABASE=...
#   bash scripts/audit-nps-crons.sh
#
# Local PG15 sem cron schema (extension não instalada):
#   audit grep-only (não consulta cron.job)
# ============================================================

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

: "${PGHOST:=}"
: "${PGPORT:=5432}"
: "${PGDATABASE:=postgres}"
: "${PGUSER:=postgres}"

INVENTORY_FILE="docs/22.7-cron-inventory.md"
REPORT_FILE="docs/22.7-30d-report.md"
TS=$(date -u +%Y-%m-%dT%H:%M:%SZ)

PSQL_OPTS="-h ${PGHOST} -p ${PGPORT} -U ${PGUSER} -d ${PGDATABASE} -v ON_ERROR_STOP=0 -t -A"

echo "==== audit-nps-crons.sh START ${TS} ===="

# ============================================================
# T1.1 — Grep migrations: cron.schedule comentados
# ============================================================
echo "[1/4] Greping migrations: cron.schedule comentados..."

mkdir -p docs

cat > "${INVENTORY_FILE}" <<HEADER
# Story 22.7 — NPS Cron Inventory (T1)

Generated: ${TS}
Source: \`scripts/audit-nps-crons.sh\`

## 1. Commented cron.schedule references (grep migrations)

\`\`\`
$(grep -rn "cron\.schedule" supabase/migrations/ 2>/dev/null | head -50 || echo "0 matches")
\`\`\`

## 2. cron.unschedule references

\`\`\`
$(grep -rn "cron\.unschedule" supabase/migrations/ 2>/dev/null | head -30 || echo "0 matches")
\`\`\`

## 3. NPS-related migration file names

\`\`\`
$(ls supabase/migrations/ | grep -iE "nps|cron|dispatch" | head -30)
\`\`\`

HEADER

# ============================================================
# T1.2 — Query pg_cron.job (se disponível)
# ============================================================
echo "[2/4] Querying pg_cron.job (if PG cron available)..."

if [[ -n "${PGHOST}" ]] && pg_isready -h "${PGHOST}" -p "${PGPORT}" >/dev/null 2>&1; then
  CRON_AVAILABLE=$(PGPASSWORD="${PGPASSWORD:-}" psql ${PSQL_OPTS} -c "
    SELECT count(*) FROM pg_extension WHERE extname='pg_cron';
  " 2>/dev/null | tail -1 | tr -d '[:space:]' || echo "0")

  if [[ "${CRON_AVAILABLE}" == "1" ]]; then
    cat >> "${INVENTORY_FILE}" <<EOF
## 4. Active pg_cron jobs (NPS-related)

\`\`\`
$(PGPASSWORD="${PGPASSWORD:-}" psql ${PSQL_OPTS} -c "
SELECT jobid, jobname, schedule, command, active
  FROM cron.job
 WHERE command ILIKE '%nps%' OR jobname ILIKE '%nps%'
 ORDER BY jobid;
" 2>/dev/null || echo "Query falhou — pg_cron pode não estar disponível neste env")
\`\`\`

## 5. All active cron jobs (full list — pra detectar NPS escondido)

\`\`\`
$(PGPASSWORD="${PGPASSWORD:-}" psql ${PSQL_OPTS} -c "
SELECT jobid, jobname, schedule, active FROM cron.job ORDER BY jobid;
" 2>/dev/null || echo "Query falhou")
\`\`\`
EOF
  else
    cat >> "${INVENTORY_FILE}" <<EOF
## 4. pg_cron extension not available in this DB

Skipped pg_cron.job query. Roda contra prod com:
\`\`\`bash
export SUPABASE_ACCESS_TOKEN=\$(pass show apis/supabase-access-token)
supabase link --project-ref gpufcipkajppykmnmdeh
# Then run this script with PGHOST=db.gpufcipkajppykmnmdeh.supabase.co etc
\`\`\`
EOF
  fi
else
  cat >> "${INVENTORY_FILE}" <<EOF
## 4. PG not reachable (skipped pg_cron query)

Run with PG connection vars set pra capturar cron.job state.
EOF
fi

# ============================================================
# T2 — Relatório 30d dispatches NPS
# ============================================================
echo "[3/4] Gerando relatório 30d dispatches..."

cat > "${REPORT_FILE}" <<HEADER
# Story 22.7 — NPS Dispatches 30d Report (T2)

Generated: ${TS}
Source: \`scripts/audit-nps-crons.sh\`

HEADER

if [[ -n "${PGHOST}" ]] && pg_isready -h "${PGHOST}" -p "${PGPORT}" >/dev/null 2>&1; then
  cat >> "${REPORT_FILE}" <<EOF
## 1. audit_log NPS dispatch events (30d)

\`\`\`
$(PGPASSWORD="${PGPASSWORD:-}" psql ${PSQL_OPTS} -c "
SELECT event_type, count(*) FROM public.audit_log
 WHERE created_at > now() - interval '30 days'
   AND event_type ILIKE '%nps%'
 GROUP BY 1 ORDER BY 2 DESC;
" 2>/dev/null || echo "Query falhou")
\`\`\`

## 2. dispatch_history NPS rows (30d)

\`\`\`
$(PGPASSWORD="${PGPASSWORD:-}" psql ${PSQL_OPTS} -c "
SELECT
  date_trunc('day', created_at)::date AS day,
  count(*) AS total
FROM public.dispatch_history
WHERE created_at > now() - interval '30 days'
GROUP BY 1 ORDER BY 1 DESC LIMIT 30;
" 2>/dev/null || echo "Query falhou ou tabela não existe")
\`\`\`

## 3. nps_class_links recent (legacy schema 22.2)

\`\`\`
$(PGPASSWORD="${PGPASSWORD:-}" psql ${PSQL_OPTS} -c "
SELECT date_trunc('day', created_at)::date AS day, count(*) FROM public.nps_class_links
WHERE created_at > now() - interval '30 days'
GROUP BY 1 ORDER BY 1 DESC LIMIT 30;
" 2>/dev/null || echo "Query falhou ou tabela não existe")
\`\`\`

## 4. Diff esperado vs efetivo

A preencher manualmente após review acima. Critérios:
- Esperado: # de aulas × cohorts × 1 NPS por aula
- Efetivo: rows em dispatch_history + audit_log
- Anomalia: diff > 10% ou crons supostos rodando sem produção

EOF
else
  cat >> "${REPORT_FILE}" <<EOF
## PG not reachable — skip dispatches query

Configurar PGHOST + token cofre pra rodar com prod.
EOF
fi

# ============================================================
# T3 — Classificação preliminar (placeholder pra ADR)
# ============================================================
echo "[4/4] Classificação preliminar pra ADR-025..."

cat >> "${INVENTORY_FILE}" <<EOF

## 6. Classificação preliminar (preencher manualmente após revisão)

Para cada cron identificado nas seções 1-4 acima:

| Cron | Status atual | Classificação | Razão | Action |
|------|--------------|---------------|-------|--------|
| (preencher) | active/dormant/commented | Intencional/Esquecido/A decidir | git blame + commit msg | UI button OR dormante comment OR no-action |

---

## 7. Próximos passos

1. Review manual deste inventário
2. Para cada cron: classificar (Intencional/Esquecido/A decidir)
3. Atualizar \`docs/architecture/ADR-025-nps-cron-status.md\` com decisão por cron
4. Para "Dormante intencional": adicionar comment SQL nas migrations originais
5. Para "Reativar": implementar UI button gate em /admin/dispatch (depends 22.3)
6. PROIBIDO descomentar cron.schedule diretamente (CLAUDE.md "Comunicação Externa")

Generated by audit-nps-crons.sh
EOF

echo ""
echo "==== audit-nps-crons.sh END ===="
echo ""
echo "Outputs:"
echo "  - ${INVENTORY_FILE}"
echo "  - ${REPORT_FILE}"
echo ""
echo "Próximo: review manual + preencher ADR-025"
