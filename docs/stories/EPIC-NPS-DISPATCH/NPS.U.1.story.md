# Story NPS.U.1 — Fix `nps_admin_dashboard` `submitted_at` Bug

**Epic:** EPIC-NPS-DISPATCH
**Status:** Ready
**Type:** Migration / Backend
**Wave:** 2
**Estimated:** 15min (S)
**Primary Agent:** @data-engineer
**Severity:** HIGH — admin monitor 500 on load

## O que fazer

`supabase/migrations/20260517020000_nps_admin_rpcs.sql:118` filtra `WHERE created_at > NOW() - interval '24 hours'` em `class_nps_responses`, mas a tabela só tem `submitted_at` (não tem `created_at`).

Toda chamada de `nps_admin_dashboard()` quebra com `column created_at does not exist`. Monitor admin não renderiza.

## Fix

Trocar `created_at` → `submitted_at` na subquery `responses_24h` dentro de `nps_admin_dashboard`.

Como function é `CREATE OR REPLACE`, basta nova migration com a function reescrita:

```sql
-- 20260517020100_fix_nps_admin_dashboard_submitted_at.sql
CREATE OR REPLACE FUNCTION public.nps_admin_dashboard() ...
  -- linha 118: substituir 'created_at' por 'submitted_at'
```

## Acceptance Criteria

- [ ] **AC-1:** Nova migration `20260517020100_fix_nps_admin_dashboard_submitted_at.sql` com function reescrita.
- [ ] **AC-2:** Chamada `SELECT nps_admin_dashboard()` por user com role=admin retorna JSON sem erro.
- [ ] **AC-3:** Campo `stats.responses_24h` reflete contagem real de `class_nps_responses.submitted_at`.
- [ ] **AC-4:** Migration original `20260517020000_*` NÃO modificada (mantém histórico).

## Dependencies

NPS.D.1 (precisa VIEW consistente — admin RPC não depende diretamente, mas teste E2E precisa)

## Risk

LOW — fix mecânico

## Files

- New: `supabase/migrations/20260517020100_fix_nps_admin_dashboard_submitted_at.sql`
