# Story NPS.T.2 — Activate DM Variants After Approval

**Epic:** EPIC-NPS-DISPATCH
**Status:** Blocked (depends on T.1 approval)
**Type:** Configuration
**Wave:** 3
**Estimated:** 15min (S)
**Primary Agent:** @admin user (via admin/nps-monitor) OR @data-engineer (via SQL)
**Severity:** HIGH — sem isso DM nunca dispara mesmo com flag ON

## O que fazer

Após Meta aprovar `nps_post_class_v1/v2/v3`, flipar `active=true` no `nps_message_variants` para variants DM correspondentes.

Sem isso, mesmo com `nps_dispatch_enabled='true'`, o `nps_next_variant('dm')` retorna empty (todas inativas no seed), DMs nunca disparam, só grupo manda mensagem.

## Fix

Via UI (após NPS.U.2/U.3): toggle "active" no card de cada variant DM.

Via SQL direto:

```sql
UPDATE public.nps_message_variants
   SET active = true
 WHERE channel = 'dm'
   AND id IN ('dm_v1','dm_v2','dm_v3');
```

## Acceptance Criteria

- [ ] **AC-1:** Verificar Meta status APPROVED pros 3 templates antes de ativar.
- [ ] **AC-2:** Flip `active=true` para os 3 dm variants.
- [ ] **AC-3:** Teste: `SELECT * FROM nps_next_variant('dm')` retorna row não-nula.
- [ ] **AC-4:** Smoke E2E: enqueue 1 job pra cohort teste, DM chega no celular alvo.

## Dependencies

- NPS.T.1 (templates aprovados)
- NPS.U.2/U.3 (preferível — sem UI, é SQL manual)

## Risk

LOW
