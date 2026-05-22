# Runbook — Local Development & Testing (EPIC-022)

> Setup local pra testar sistema lesson-pages antes deploy. Cobre frontend (vanilla HTML/CSS/JS) + backend (Postgres + migrations) + workflow smoke.

---

## TL;DR

```bash
# Auto-detect ambiente + start frontend + (opcional) migrations smoke
bash scripts/test-local.sh

# Apenas frontend (sem DB)
bash scripts/test-local.sh frontend

# Apenas migrations EPIC-022 (precisa PG local)
bash scripts/test-local.sh rls       # 22.4 RLS
bash scripts/test-local.sh identity  # 22.1 Identity
bash scripts/test-local.sh down      # rollback ambos
```

---

## 1. Componentes do Sistema

| Componente | Local Testável | Como |
|------------|:--------------:|------|
| Frontend (admin/, aluno/, survey/, css/, js/) | ✅ Sim | `python3 -m http.server 8080` |
| Postgres + migrations | ⚠️ Setup | PG15 nativo WSL ou Docker |
| Edge functions (Supabase) | ❌ Não | Sem Docker → deploy preview only |
| pg_cron jobs | ⚠️ Limitado | Funciona com PG15 + extension preload |
| Supabase Auth/Storage/Realtime | ❌ Não | Sem Docker → mock JWT manual |

---

## 2. Setup Opções

### Opção A — PG15 nativo WSL (RECOMENDADO se Docker indisponível)

**Pré-requisito:** sudo password (PGDG repo + apt install).

```bash
! bash scripts/setup-pg15-wsl.sh
```

Script faz:
1. Add PGDG repo (postgres official Ubuntu source)
2. `apt install postgresql-15` (+ extensions disponíveis)
3. Start cluster `main` em port **5433** (não 5432 — evita conflito)
4. Set postgres password = `postgres` (local-only)
5. Verify connection

**Conexão pós-setup:**
```bash
export PGHOST=localhost PGPORT=5433 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres
psql -c "SELECT version();"
# Esperado: PostgreSQL 15.x
```

### Opção B — Docker Desktop Windows

**Pré-requisito:** Docker Desktop instalado + rodando no Windows (WSL2 backend).

```bash
# 1. Abre Docker Desktop no Windows (clica ícone tray)
# 2. Aguarda "Docker Desktop is running"

# 3. WSL detecta docker via /var/run/docker.sock
docker info  # confirma WSL ↔ Docker comm OK

# 4. Sobe stack local
docker-compose -f docker-compose.local.yml up -d

# 5. Verify
docker ps  # postgres-15 + nginx (opcional)
PGHOST=localhost PGPORT=5433 PGPASSWORD=postgres psql -U postgres -c "SELECT version();"
```

**Cleanup:**
```bash
docker-compose -f docker-compose.local.yml down -v  # remove volumes
```

### Opção C — Schema pull de prod (precisa token cofre)

Se queres testar com schema real prod (sem dados sensíveis):

```bash
# 1. Cadastra token (uma vez)
pass insert apis/supabase-access-token
# Cola token de https://supabase.com/dashboard/account/tokens

# 2. Export + link
export SUPABASE_ACCESS_TOKEN=$(pass show apis/supabase-access-token)
supabase link --project-ref gpufcipkajppykmnmdeh

# 3. Pull schema (sem data sensível)
supabase db pull --schema public  # gera migration combinada local

# 4. Apply em PG local
psql -h localhost -p 5433 -U postgres -d postgres -f supabase/migrations/<ts>_remote_schema.sql
```

---

## 3. Frontend Local

### Quick start

```bash
# Inicia http.server bg
python3 -m http.server 8080 --bind 127.0.0.1 &

# Acessa:
# - http://localhost:8080/admin/                  → painel admin
# - http://localhost:8080/admin/_ds-preview.html  → DS v1 showcase
# - http://localhost:8080/admin/nps-results/      → NPS dashboard
# - http://localhost:8080/admin/ps-rsvp/          → PS RSVP
```

### Stop

```bash
pkill -f "http.server 8080"
```

### Live reload

Vanilla HTML/CSS/JS sem build step — edita arquivo + refresh browser. Cache-Control headers em produção podem servir stale; em dev usar Ctrl+Shift+R (hard refresh).

### Limitações local

- **Fetch a Supabase**: frontend tenta `https://gpufcipkajppykmnmdeh.supabase.co/rest/v1/...` — funciona se internet OK + anon key correto em `js/config.js`
- **Auth login**: usa Supabase Auth real (sessão prod) — admin entra com credentials prod
- **Edge fns**: rodam em Supabase prod — chamadas funcionam normalmente

---

## 4. Migrations EPIC-022 Local Test

### Workflow completo

```bash
# 1. Garante PG local up (Opção A ou B)
pg_isready -h localhost -p 5433
# Esperado: localhost:5433 - accepting connections

# 2. Variáveis de conexão
export PGHOST=localhost PGPORT=5433 PGUSER=postgres PGPASSWORD=postgres PGDATABASE=postgres

# 3. (Opcional) Carrega schema prod via pg_dump ou supabase db pull
# Sem schema prod, migrations criam tables/columns do zero quando aplicáveis,
# mas algumas migrations EPIC-022 assumem tables existentes (students, etc).

# 4. Apply migration 22.4 RLS Hardening
psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260522155830_epic_022_s04_rls_hardening.sql

# 5. Smoke 22.4
bash scripts/smoke-rls-test.sh
# Esperado: 10/10 cenários PASS

# 6. Apply migration 22.1 Identity Unification
psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260522220000_epic_022_s01_identity_unification.sql

# 7. Smoke 22.1
bash scripts/smoke-identity-test.sh
# Esperado: 14/14 cenários PASS

# 8. Rollback ambos (test reversibilidade)
psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260522220000_epic_022_s01_identity_unification.down.sql
psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260522155830_epic_022_s04_rls_hardening.down.sql

# 9. Re-apply (test idempotência)
psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260522155830_epic_022_s04_rls_hardening.sql
psql -v ON_ERROR_STOP=1 -f supabase/migrations/20260522220000_epic_022_s01_identity_unification.sql
```

### Wrapper test-local.sh

Auto-detect ambiente e roda tudo:

```bash
bash scripts/test-local.sh             # workflow completo
bash scripts/test-local.sh rls         # apenas 22.4
bash scripts/test-local.sh identity    # apenas 22.1
bash scripts/test-local.sh down        # rollback
bash scripts/test-local.sh frontend    # apenas http server
bash scripts/test-local.sh setup       # mostra opções setup
```

---

## 5. Troubleshooting

### "pg_isready: localhost:5433 - no response"
- PG 15 não está rodando local
- Solução: `sudo pg_ctlcluster 15 main start` (após setup-pg15-wsl.sh)
- OU `docker-compose -f docker-compose.local.yml up -d postgres`

### "psql: FATAL: password authentication failed"
- Password default no setup é `postgres`
- Se mudou: `sudo -u postgres psql -c "ALTER USER postgres WITH PASSWORD 'postgres';"`

### "ERROR: extension pg_cron is not available"
- pg_cron precisa ser instalado separadamente (Ubuntu: `apt install postgresql-15-cron`)
- Para test, comentar `shared_preload_libraries=pg_cron` no postgresql.conf
- Em produção Supabase managed, pg_cron está sempre disponível

### Smoke fail "request.jwt.claims" not recognized
- PG local não tem auth.jwt() function (apenas Supabase managed)
- Smoke script usa `SET LOCAL request.jwt.claims TO '{...}'` — funciona em PG nativo
- Se erro: confirma que função is_dashboard_admin foi criada (migration up deve criar)

### Edge functions chamadas falham
- Edge fns rodam em Supabase prod, não local
- Pra testar end-to-end com fns: deploy preview branch ou test via supabase functions invoke

### Frontend mostra dados antigos
- Browser cache — Ctrl+Shift+R (hard refresh)
- Service workers (se houver): DevTools → Application → Service Workers → Unregister

---

## 6. Workflow Recomendado (dev day)

```bash
# Morning setup
bash scripts/test-local.sh frontend           # http server bg
# (se PG não rodando)
sudo pg_ctlcluster 15 main start              # 1x por sessão

# Dev cycle (edit → test)
# 1. Edita arquivo (admin/, css/ds/, supabase/migrations/, etc)
# 2. Frontend: refresh browser
# 3. Migration: bash scripts/test-local.sh rls (ou identity)
# 4. Smoke: verifica 10/14 PASS
# 5. Se OK: commit
# 6. Se FAIL: debug → re-test

# End-of-day
bash scripts/test-local.sh down               # cleanup migrations (opcional)
pkill -f "http.server 8080"                   # stop frontend
sudo pg_ctlcluster 15 main stop               # stop PG (opcional — pode deixar rodando)
```

---

## 7. Próximos Passos pós-Setup

1. **Frontend QA** — abre `http://localhost:8080/admin/_ds-preview.html` no browser, valida tokens + buttons + cards + statcards
2. **22.4 + 22.1 dry-run** — `bash scripts/test-local.sh` → smoke completo
3. **Preview deploy** — após smoke local OK, push branch separada pra deploy preview prod-like
4. **Apply prod (GATE HUMANO)** — janela manutenção + autorização literal user

---

## Referências

- `scripts/setup-pg15-wsl.sh` — instala PG 15 nativo WSL
- `scripts/test-local.sh` — auto-detect + workflow completo
- `scripts/smoke-rls-test.sh` — smoke 22.4 (10 cenários)
- `scripts/smoke-identity-test.sh` — smoke 22.1 (14 cenários)
- `docker-compose.local.yml` — stack Docker (PG + nginx)
- `nginx-local.conf` — config nginx local
- `docs/architecture/ADR-020-rls-policies.md` — decisão RLS
- `docs/architecture/ADR-021-student-identity-unification.md` — decisão Identity
