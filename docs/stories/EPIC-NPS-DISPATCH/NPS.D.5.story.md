# Story NPS.D.5 — Cron-After-Flag-Flip (Move Schedule Out of Migration)

**Epic:** EPIC-NPS-DISPATCH
**Status:** Ready
**Type:** Migration / Process
**Wave:** 1 (BLOCKER per CLAUDE.md)
**Estimated:** 30min (S)
**Primary Agent:** @data-engineer
**Severity:** HIGH — CLAUDE.md gate violation

## O que fazer

Migration `20260517010400_dispatch_class_nps_cron.sql` faz `cron.schedule(...)` direto no apply. Cron fica armado em produção no momento que `db push` roda — antes de qualquer aprovação humana.

Mesmo que function bail por flag off, agendamento de worker de envio é mexer infra de comm externa — viola CLAUDE.md.

## Fix

Dividir em 2 etapas:

1. **Migration** apenas registra URL: `INSERT INTO app_config (key, value) VALUES ('dispatch_class_nps_url', '...')`. Sem cron.schedule.
2. **Runbook step** explícito (`docs/runbooks/nps-post-class-activation.md`): rodar SQL pra criar cron DEPOIS de aprovar flag.

## Acceptance Criteria

### Bloco A — Migration Cleanup

- [ ] **AC-1:** Reescrever `20260517010400_dispatch_class_nps_cron.sql` removendo `cron.schedule(...)`. Manter apenas `INSERT INTO app_config`.
- [ ] **AC-2:** Adicionar comment topo: "Cron schedule moved to runbook NPS.D.5 — see nps-post-class-activation.md".

### Bloco B — Runbook Update

- [ ] **AC-3:** `nps-post-class-activation.md` ganha nova section "Step 6: Schedule cron (após flag flip)" com SQL `SELECT cron.schedule('dispatch-class-nps-tick', '*/5 * * * *', ...)`.
- [ ] **AC-4:** Section inclui unschedule command pra rollback: `SELECT cron.unschedule('dispatch-class-nps-tick')`.
- [ ] **AC-5:** Ordem do runbook: flag flip → smoke test → cron schedule (não antes).

### Bloco C — Cleanup if Already Applied

- [ ] **AC-6:** SQL idempotente safe-removal incluído: `DO $$ BEGIN IF EXISTS (SELECT 1 FROM cron.job WHERE jobname='dispatch-class-nps-tick') THEN PERFORM cron.unschedule('dispatch-class-nps-tick'); END IF; END $$;`

## Dependencies

Nenhuma — pode rodar em paralelo a D.1-D.4

## Risk

LOW

## Files

- `supabase/migrations/20260517010400_dispatch_class_nps_cron.sql` (rewrite)
- `docs/runbooks/nps-post-class-activation.md` (update)
