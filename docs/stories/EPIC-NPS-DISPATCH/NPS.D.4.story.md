# Story NPS.D.4 — Set `app_config.supabase_service_key`

**Epic:** EPIC-NPS-DISPATCH
**Status:** Ready
**Type:** Configuration / Deployment
**Wave:** 1
**Estimated:** 15min (S)
**Primary Agent:** @devops
**Severity:** HIGH — retry + cron paths fail silent without this

## O que fazer

Cron tick `dispatch-class-nps-tick` e RPC `retry_dispatch` chamam `net.http_post` lendo `app_config.supabase_service_key`. Se row não existir, request sai sem `Authorization` header → 401 (após NPS.D.3) → cron sempre fail silent.

## Fix

Inserir row em `app_config` com service-role JWT key:

```sql
INSERT INTO public.app_config (key, value)
VALUES ('supabase_service_key', '<SERVICE_ROLE_KEY_AQUI>')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
```

**Source:** Supabase Studio → Project Settings → API → `service_role` secret.

## Acceptance Criteria

- [ ] **AC-1:** Row existe: `SELECT 1 FROM app_config WHERE key='supabase_service_key'` retorna 1.
- [ ] **AC-2:** Cron tick `dispatch-class-nps-tick` executa sem 401 (verificar logs Supabase).
- [ ] **AC-3:** `retry_dispatch` chamado do dashboard P4 enfileira request com sucesso (`dispatch_retry_audit.queued = true`).
- [ ] **AC-4:** Documentar processo no runbook `nps-post-class-activation.md` (NPS.O.1).

## Dependencies

NPS.D.3 (sem auth essa story é no-op, com auth essa story é obrigatória)

## Risk

LOW — operação de configuração, idempotente

## Security note

Service role key dá full DB access. Quem tiver acesso a `app_config` consegue ler. RLS deve garantir só `service_role` lê. Verificar `app_config` RLS antes.
