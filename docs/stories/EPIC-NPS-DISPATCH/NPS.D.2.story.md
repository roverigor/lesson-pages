# Story NPS.D.2 — Fix `classes.title` Bug (3 Migrations)

**Epic:** EPIC-NPS-DISPATCH
**Status:** Ready
**Type:** Migration / Backend
**Wave:** 1 (BLOCKER)
**Estimated:** 1h (S)
**Primary Agent:** @data-engineer
**Assist Agents:** @qa
**Severity:** CRITICAL — survey landing + dashboard 500s

## O que fazer

3 migrations referenciam `classes.title` mas a tabela tem `name`:

1. `supabase/migrations/20260516010200_get_nps_link_metadata_rpc.sql:42`
2. `supabase/migrations/20260516020500_dispatch_rpcs_part1.sql:56` (`list_dispatch_history`)
3. `supabase/migrations/20260516020600_dispatch_rpcs_part2.sql:21,27` (`dispatch_top_classes`)

Cada chamada de RPC retorna `ERROR: column c.title does not exist`. Landing page de survey mostra "Link inválido" pra todos os tokens válidos. Dashboard P4 não carrega.

## Fix

- Trocar `c.title` por `c.name AS class_name` em todas as 3 migrations
- Renomear column de saída `class_title` → `class_name` pra consistência
- Atualizar consumers: `survey/app.js` + `admin/envios/app.js`

## Acceptance Criteria

- [ ] **AC-1:** `get_nps_link_metadata` retorna `class_name` (não erra)
- [ ] **AC-2:** `list_dispatch_history` retorna `class_name`
- [ ] **AC-3:** `dispatch_top_classes` retorna `class_name`
- [ ] **AC-4:** `survey/app.js` lê `class_name` no rendering
- [ ] **AC-5:** `admin/envios/app.js` lê `class_name` na tabela
- [ ] **AC-6:** Smoke test landing /survey/{grupo|aluno}/{token} mostra título da aula correto

## Dependencies

NPS.D.1 (precisa VIEW funcional antes de testar P4 RPCs)

## Risk

LOW — substituição mecânica. Renames precisam cuidado nos consumers.

## Files

- `supabase/migrations/20260516010200_get_nps_link_metadata_rpc.sql`
- `supabase/migrations/20260516020500_dispatch_rpcs_part1.sql`
- `supabase/migrations/20260516020600_dispatch_rpcs_part2.sql`
- `survey/app.js`
- `admin/envios/app.js`
