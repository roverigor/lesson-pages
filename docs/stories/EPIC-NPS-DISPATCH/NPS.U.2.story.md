# Story NPS.U.2 — Admin Monitor HTML Page

**Epic:** EPIC-NPS-DISPATCH
**Status:** Ready
**Type:** Frontend / Admin
**Wave:** 2
**Estimated:** 3-4h (M)
**Primary Agent:** @dev
**Assist Agents:** @ux-design-expert (review layout)
**Severity:** HIGH — user-blocking (sem UI, controle = SQL only)

## O que fazer

Construir `admin/nps-monitor/index.html` — SPA leve (HTML + CSS + JS vanilla) que consome `nps_admin_dashboard` + 5 RPCs admin pra dar controle visual ao Igor sobre:

- Master flag toggle (`nps_dispatch_enabled`)
- Edit config (cooldown, delay, max_dm, throttle)
- View + edit message variants (router)
- View pending jobs + force-now / skip
- 24h stats KPIs
- Link pra `/admin/envios/` (dashboard de histórico)

## Business Value

- **Igor controla envios sem SQL.** Pausar mass dispatch em 1 clique.
- **Visibilidade router:** ver as 6 variants ativas/inativas + última rotação.
- **Confiança operacional:** UI explícita = menos chance de mexer flag errado.
- **Audit trail visual:** quando algo falha, troubleshoot mais rápido.

## Acceptance Criteria

### Bloco A — Page Structure

- [ ] **AC-1:** Arquivo `admin/nps-monitor/index.html` criado com login overlay (mesmo padrão `admin/envios/index.html`).
- [ ] **AC-2:** Imports: `js/config.js`, `https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2/dist/umd/supabase.min.js`, `admin/nps-monitor/styles.css`, `admin/nps-monitor/app.js`.
- [ ] **AC-3:** Topbar: título "NPS Dispatcher Monitor" + breadcrumb home + link `/admin/envios/` "ver histórico envios".

### Bloco B — Master Switch Section

- [ ] **AC-4:** Toggle visual (ON/OFF) lendo `config.nps_dispatch_enabled`.
- [ ] **AC-5:** Click no toggle abre confirm modal: "Confirmar ativar/desativar dispatcher?" com checkbox "Entendo que isso enviará mensagens reais".
- [ ] **AC-6:** Confirm chama `nps_admin_set_config('nps_dispatch_enabled', 'true'|'false')`.
- [ ] **AC-7:** Visual feedback: estado atual destacado (verde=ON, cinza=OFF).

### Bloco C — Config Editor

- [ ] **AC-8:** Cards numéricos com input + botão "Salvar" pra:
  - `nps_cohort_cooldown_hours` (12 default, min 0)
  - `nps_dispatch_delay_minutes` (5 default, min 0)
  - `nps_dispatch_max_dm_per_run` (50 default, min 1, max 200)
  - `nps_dispatch_dm_throttle_ms` (10000 default, min 1000)
- [ ] **AC-9:** Submit chama `nps_admin_set_config(key, value)` e mostra toast success/error.

### Bloco D — Variants Editor

- [ ] **AC-10:** 2 colunas: "Grupo (Evolution)" e "DM (Meta template)".
- [ ] **AC-11:** Cada variant card mostra: ID, active toggle, body_template (textarea preview ou edit), meta_template_name readonly, weight, count rotação.
- [ ] **AC-12:** Edit body opens modal com textarea + variables hint (`{{class_name}} {{cohort_name}} {{link}}`) + preview rendering.
- [ ] **AC-13:** Save chama `nps_admin_update_variant(id, body, active)`.
- [ ] **AC-14:** Indicador visual "última usada" na variant que `rotation.last_variant_id` aponta.

### Bloco E — Pending Jobs

- [ ] **AC-15:** Tabela com colunas: Cohort, Classe, Data, Status, Scheduled, Eligible Students, [actions].
- [ ] **AC-16:** Actions:
  - `pending` → botão "Disparar agora" (chama `nps_admin_force_job_now`)
  - `pending` ou `in_progress` → botão "Cancelar" (chama `nps_admin_skip_job(id, 'manual')`)
  - `in_progress` antigo (>15min) → botão "Reset" (chama `nps_admin_reset_stuck_job`)
- [ ] **AC-17:** Todas actions destrutivas (skip/reset) com confirm modal.

### Bloco F — Recent Jobs

- [ ] **AC-18:** Tabela compacta read-only com últimos 20 jobs finalizados.
- [ ] **AC-19:** Linha clicável → modal com detail (mesma estrutura do drawer P4 — group_send_status, dm_sent/failed/skipped, variant usada, error_detail).

### Bloco G — 24h Stats

- [ ] **AC-20:** 4 KPI cards no topo: Jobs (total/sent/failed), DMs (sent/failed), Opens, Responses.
- [ ] **AC-21:** Auto-refresh a cada 30s (toggle no header pra pausar).

### Bloco H — Empty States + Errors

- [ ] **AC-22:** "Nenhum job pendente" quando lista vazia.
- [ ] **AC-23:** Banner erro se `nps_admin_dashboard` 401/500.
- [ ] **AC-24:** Loading skeleton durante fetch inicial.

## Dependencies

- NPS.U.1 (admin RPC tem que funcionar)
- NPS.D.1 + D.2 (VIEW + title bugs — admin dashboard indireto depende)

## Risk

LOW — read/write a tabelas controladas, todas actions já têm RPC validada

## Files

- New: `admin/nps-monitor/index.html`
- (next stories) `admin/nps-monitor/styles.css`, `admin/nps-monitor/app.js`
