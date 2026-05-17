# BACKLOG Chapter O — Operational / Runbook Polish

**Epic:** EPIC-NPS-DISPATCH
**Wave:** 2-3 (parallel to D/T)
**Owner:** @pm + @devops

---

## NPS.O.1 — Update nps-post-class-activation.md runbook

**Effort:** S (30min)
**Status:** Ready (after D.5)

Runbook atual ainda mostra cron schedulado em migration. Após D.5, ordem muda: flag flip → smoke → cron schedule.

**AC:**
- [ ] Section "Pre-activation checklist" inclui auth env var (D.3)
- [ ] Section "Activation sequence" tem GO/NO-GO gate explícito antes flag flip
- [ ] Section "Step 6: Schedule cron" criada com SQL pós-flag
- [ ] Section "Rollback" inclui `cron.unschedule`
- [ ] Reference NPS.T.2 (activate variants) na sequência

---

## NPS.O.2 — Document admin monitor in runbook

**Effort:** S (20min)
**Status:** Ready (after U.2/U.3)

Criar `docs/runbooks/nps-admin-monitor.md` com screenshots + walkthrough de cada control.

**AC:**
- [ ] Como acessar (/admin/nps-monitor)
- [ ] Significado de cada toggle/control
- [ ] Quando usar "Disparar agora" vs "Cancelar" vs "Reset stuck"
- [ ] FAQ: cooldown, holiday skip, variant rotation

---

## NPS.O.3 — Smoke test plan for first cohort

**Effort:** S (1h)
**Status:** Ready (after T.2)

Documento step-by-step pra primeiro live test.

**AC:**
- [ ] Identificar cohort interno (mentors apenas) com 1-2 alunos teste
- [ ] Definir aula teste com Zoom meeting agendado
- [ ] Checklist pre-test: variants ativas, flag ON, slack webhook configurado
- [ ] Checklist during-test: observar logs, msg chegou, link clicável
- [ ] Checklist post-test: response registrada, opens contados, sem 401
- [ ] Rollback plan se quebrar
