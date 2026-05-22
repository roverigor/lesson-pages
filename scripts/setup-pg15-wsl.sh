#!/usr/bin/env bash
# ============================================================
# setup-pg15-wsl.sh — Story 22.4 T8 dry-run prereq
# ============================================================
# Instala Postgres 15 nativo no WSL (sem Docker)
# Match versão Supabase managed (PG 15)
# Pede sudo password — rode com `! bash scripts/setup-pg15-wsl.sh`
# ============================================================

set -euo pipefail

echo "==== setup-pg15-wsl.sh START ===="

# 1. PGDG repo
echo "[1/6] Adding PGDG repo..."
sudo apt-get install -y curl ca-certificates
sudo install -d /usr/share/postgresql-common/pgdg
sudo curl -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc --fail https://www.postgresql.org/media/keys/ACCC4CF8.asc
sudo sh -c 'echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt $(. /etc/os-release && echo $VERSION_CODENAME)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'

# 2. apt update
echo "[2/6] apt update..."
sudo apt-get update

# 3. Install PG 15
echo "[3/6] Installing postgresql-15..."
sudo apt-get install -y postgresql-15

# 4. Start cluster
echo "[4/6] Starting PG 15 cluster..."
sudo pg_ctlcluster 15 main start || sudo systemctl start postgresql || true

# 5. Set postgres password local
echo "[5/6] Setting postgres password..."
sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"

# 6. Verify
echo "[6/6] Verifying..."
PGPASSWORD=postgres psql -h localhost -p 5433 -U postgres -d postgres -c "SELECT version();"

echo "==== setup-pg15-wsl.sh END ===="
echo ""
echo "PG 15 ready. Connect:"
echo "  PGHOST=localhost PGPORT=5433 PGUSER=postgres PGPASSWORD=postgres psql -d postgres"
