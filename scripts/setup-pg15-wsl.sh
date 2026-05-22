#!/usr/bin/env bash
# ============================================================
# setup-pg15-wsl.sh — Story 22.4 T8 dry-run prereq (v2 robusta)
# ============================================================
# Instala Postgres 15 nativo no WSL (sem Docker)
# Match versão Supabase managed (PG 15)
#
# Rode: ! bash scripts/setup-pg15-wsl.sh
# Pede sudo password 1x.
#
# Em caso de erro: script imprime exatamente qual passo falhou.
# ============================================================

set -uo pipefail

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_ok()   { printf "${GREEN}[OK]${NC} %s\n" "$*"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$*"; }
log_err()  { printf "${RED}[ERR]${NC} %s\n" "$*"; }
log_step() { printf "\n${GREEN}=== %s ===${NC}\n" "$*"; }

trap 'log_err "Falhou na linha ${LINENO}: comando \"${BASH_COMMAND}\""' ERR

log_step "setup-pg15-wsl.sh START — Ubuntu $(. /etc/os-release && echo $VERSION_CODENAME)"

# ============================================================
# Passo 0: dependências básicas (curl + ca-certificates)
# ============================================================
log_step "0/6 — Dependências básicas (curl + ca-certificates + gnupg)"
sudo apt-get install -y curl ca-certificates gnupg lsb-release
log_ok "Dependências básicas instaladas"

# ============================================================
# Passo 1: PGDG repo (apt.postgresql.org)
# ============================================================
log_step "1/6 — PGDG repo setup"

# Criar diretório target (force-create caso não exista)
sudo mkdir -p /usr/share/postgresql-common/pgdg
log_ok "Diretório /usr/share/postgresql-common/pgdg criado"

# Baixar key (com retry + verbose se falhar)
KEY_URL="https://www.postgresql.org/media/keys/ACCC4CF8.asc"
KEY_PATH="/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc"

if sudo curl -fsSL -o "${KEY_PATH}" "${KEY_URL}"; then
  log_ok "Key PGDG baixada"
else
  log_err "curl falhou ao baixar ${KEY_URL}"
  log_warn "Tentando fallback via apt-key adv (deprecated mas funciona)..."
  sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ACCC4CF8 || {
    log_err "Fallback também falhou. Verifique internet."
    exit 1
  }
fi

# Adicionar source list
CODENAME=$(. /etc/os-release && echo $VERSION_CODENAME)
SOURCE_LINE="deb [signed-by=${KEY_PATH}] https://apt.postgresql.org/pub/repos/apt ${CODENAME}-pgdg main"

echo "${SOURCE_LINE}" | sudo tee /etc/apt/sources.list.d/pgdg.list > /dev/null
log_ok "Source list pgdg.list criada: ${SOURCE_LINE}"

# ============================================================
# Passo 2: apt update
# ============================================================
log_step "2/6 — apt update (pode demorar)"
sudo apt-get update
log_ok "apt update OK"

# ============================================================
# Passo 3: Install PG 15 + common
# ============================================================
log_step "3/6 — Instalando postgresql-15"
sudo apt-get install -y postgresql-15 postgresql-common
log_ok "postgresql-15 instalado"

# ============================================================
# Passo 4: Configurar cluster + porta 5433 (evita conflito PG default 5432)
# ============================================================
log_step "4/6 — Configurando cluster main porta 5433"

# Verifica se cluster main já existe
if pg_lsclusters | grep -q "^15 *main"; then
  log_ok "Cluster 15/main já existe"
else
  log_warn "Cluster 15/main não detectado, criando..."
  sudo pg_createcluster 15 main --port 5433
fi

# Garantir porta 5433 no postgresql.conf
PG_CONF="/etc/postgresql/15/main/postgresql.conf"
if sudo grep -q "^port = 5432" "${PG_CONF}"; then
  sudo sed -i 's/^port = 5432/port = 5433/' "${PG_CONF}"
  log_ok "Porta alterada pra 5433 em ${PG_CONF}"
fi

# Start cluster
sudo pg_ctlcluster 15 main start || sudo pg_ctlcluster 15 main restart || true
sleep 2

if pg_isready -h localhost -p 5433 -U postgres > /dev/null 2>&1; then
  log_ok "Cluster 15/main rodando em :5433"
else
  log_err "pg_isready falhou em :5433. Status cluster:"
  pg_lsclusters
  log_warn "Tentando start manual..."
  sudo pg_ctlcluster 15 main start
  sleep 2
fi

# ============================================================
# Passo 5: Set password postgres (local-only)
# ============================================================
log_step "5/6 — Setando password 'postgres' user (LOCAL ONLY — não produção)"
sudo -u postgres psql -p 5433 -c "ALTER USER postgres WITH PASSWORD 'postgres';"
log_ok "Password setada"

# Configurar pg_hba.conf pra md5 local (permite PGPASSWORD funcionar)
HBA_CONF="/etc/postgresql/15/main/pg_hba.conf"
if ! sudo grep -q "^host.*all.*postgres.*127.0.0.1/32.*md5" "${HBA_CONF}"; then
  echo "host    all             postgres        127.0.0.1/32            md5" | sudo tee -a "${HBA_CONF}" > /dev/null
  sudo pg_ctlcluster 15 main reload
  log_ok "pg_hba.conf atualizado (md5 local)"
fi

# ============================================================
# Passo 6: Verify
# ============================================================
log_step "6/6 — Verificando conexão"
PGPASSWORD=postgres psql -h localhost -p 5433 -U postgres -d postgres -c "SELECT version();" || {
  log_err "psql verify falhou. Cluster status:"
  pg_lsclusters
  exit 1
}

log_ok "=== PG 15 INSTALADO E RODANDO ==="
echo ""
echo "Conexão:"
echo "  PGHOST=localhost PGPORT=5433 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres"
echo ""
echo "Próximo:"
echo "  bash scripts/test-local.sh        # auto workflow"
echo "  bash scripts/smoke-rls-test.sh    # smoke 22.4"
