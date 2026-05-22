#!/usr/bin/env bash
# ============================================================
# test-local.sh — Lesson Pages Local Testing Workflow
# ============================================================
# Detecta ambiente (Docker | PG15 nativo | nada) e roda smoke
# tests das migrations EPIC-022 (RLS Hardening + Identity Unif).
#
# Uso:
#   bash scripts/test-local.sh                  # auto-detect + run
#   bash scripts/test-local.sh setup           # mostra como instalar PG15/Docker
#   bash scripts/test-local.sh schema          # apenas restore schema prod (precisa token)
#   bash scripts/test-local.sh rls             # apply 22.4 RLS + smoke
#   bash scripts/test-local.sh identity        # apply 22.1 Identity + smoke
#   bash scripts/test-local.sh down            # rollback ambos
#   bash scripts/test-local.sh frontend        # apenas inicia http server
# ============================================================

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log()    { printf "${GREEN}[test-local]${NC} %s\n" "$*"; }
warn()   { printf "${YELLOW}[test-local WARN]${NC} %s\n" "$*"; }
error()  { printf "${RED}[test-local ERR]${NC} %s\n" "$*"; }

# ============================================================
# Environment detection
# ============================================================
detect_env() {
  if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "docker"
  elif command -v psql >/dev/null 2>&1 && pg_isready -h localhost -p 5433 >/dev/null 2>&1; then
    echo "pg15-native"
  elif command -v psql >/dev/null 2>&1 && pg_isready -h localhost -p 5432 >/dev/null 2>&1; then
    echo "pg-default"
  else
    echo "none"
  fi
}

CMD="${1:-auto}"
ENV=$(detect_env)
log "Detected environment: ${ENV}"

# ============================================================
# Frontend server
# ============================================================
start_frontend() {
  if pgrep -f "http.server 8080" >/dev/null; then
    log "Frontend already running on :8080"
    return 0
  fi
  log "Starting frontend http.server on :8080"
  nohup python3 -m http.server 8080 --bind 127.0.0.1 > /tmp/lesson-pages-server.log 2>&1 &
  sleep 2
  if curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/admin/index.html | grep -q 200; then
    log "Frontend OK: http://localhost:8080"
    log "DS preview: http://localhost:8080/admin/_ds-preview.html"
  else
    error "Frontend failed to start (check /tmp/lesson-pages-server.log)"
    return 1
  fi
}

# ============================================================
# PG connection vars
# ============================================================
case "${ENV}" in
  pg15-native)
    PG_PORT=5433
    ;;
  pg-default)
    PG_PORT=5432
    warn "Using default PG (port 5432) — pode não ser PG 15"
    ;;
  docker)
    PG_PORT=5433
    ;;
  *)
    PG_PORT=""
    ;;
esac

export PGHOST=localhost
export PGPORT="${PG_PORT}"
export PGUSER=postgres
export PGPASSWORD=postgres
export PGDATABASE=postgres

# ============================================================
# Commands
# ============================================================
cmd_setup() {
  log "Setup options:"
  echo ""
  echo "  Opção A — PG15 nativo WSL (recomendado se Docker indisponível):"
  echo "    ! bash scripts/setup-pg15-wsl.sh"
  echo "    (precisa sudo, ~5min, instala via PGDG repo)"
  echo ""
  echo "  Opção B — Docker Desktop Windows:"
  echo "    1. Abre Docker Desktop no Windows"
  echo "    2. docker-compose -f docker-compose.local.yml up -d"
  echo "    3. Aguarda ~30s pra PG healthy"
  echo ""
  echo "  Opção C — Postgres remoto (Supabase prod schema):"
  echo "    1. pass insert apis/supabase-access-token  # se não cadastrou"
  echo "    2. export SUPABASE_ACCESS_TOKEN=\$(pass show apis/supabase-access-token)"
  echo "    3. supabase link --project-ref gpufcipkajppykmnmdeh"
}

cmd_schema() {
  if [[ -z "${PG_PORT}" ]]; then
    error "Sem PG local. Roda 'bash scripts/test-local.sh setup' primeiro."
    return 1
  fi
  if [[ -z "${SUPABASE_ACCESS_TOKEN:-}" ]]; then
    warn "SUPABASE_ACCESS_TOKEN não setado — restore schema vazio (apenas migrations apply)"
    return 0
  fi
  log "Restoring schema from prod via pg_dump..."
  # supabase db pull cria migration combinada
  # OR: pg_dump direct se tem connection string prod
  warn "TODO: implementar pg_dump prod restore quando token disponível"
}

cmd_rls() {
  if [[ -z "${PG_PORT}" ]]; then
    error "Sem PG local."
    return 1
  fi
  log "Applying 22.4 RLS Hardening migration..."
  psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260522155830_epic_022_s04_rls_hardening.sql
  log "Running smoke-rls-test.sh..."
  bash scripts/smoke-rls-test.sh
}

cmd_identity() {
  if [[ -z "${PG_PORT}" ]]; then
    error "Sem PG local."
    return 1
  fi
  log "Applying 22.1 Identity Unification migration..."
  psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260522220000_epic_022_s01_identity_unification.sql
  log "Running smoke-identity-test.sh..."
  bash scripts/smoke-identity-test.sh
}

cmd_down() {
  if [[ -z "${PG_PORT}" ]]; then
    error "Sem PG local."
    return 1
  fi
  log "Rolling back 22.1 + 22.4..."
  psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260522220000_epic_022_s01_identity_unification.down.sql || true
  psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260522155830_epic_022_s04_rls_hardening.down.sql || true
  log "Rollback complete"
}

cmd_auto() {
  log "Auto workflow: frontend + (rls + identity se PG disponível)"
  start_frontend
  if [[ -n "${PG_PORT}" ]]; then
    cmd_rls && cmd_identity
  else
    warn "PG local indisponível — apenas frontend rodando"
    cmd_setup
  fi
}

# ============================================================
# Dispatch
# ============================================================
case "${CMD}" in
  auto)     cmd_auto ;;
  setup)    cmd_setup ;;
  schema)   cmd_schema ;;
  rls)      cmd_rls ;;
  identity) cmd_identity ;;
  down)     cmd_down ;;
  frontend) start_frontend ;;
  *)
    error "Unknown command: ${CMD}"
    echo "Available: auto | setup | schema | rls | identity | down | frontend"
    exit 1
    ;;
esac
