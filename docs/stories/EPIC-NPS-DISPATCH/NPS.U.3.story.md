# Story NPS.U.3 — Admin Monitor CSS + JS + Responsive

**Epic:** EPIC-NPS-DISPATCH
**Status:** Ready
**Type:** Frontend / CSS / JS
**Wave:** 2
**Estimated:** 3-4h (M)
**Primary Agent:** @dev
**Assist Agents:** @ux-design-expert

## O que fazer

Implementar `admin/nps-monitor/styles.css` + `admin/nps-monitor/app.js` baseado no HTML criado em NPS.U.2.

## Acceptance Criteria

### Bloco A — CSS (Dark Theme + Design System)

- [ ] **AC-1:** Dark theme matching `admin/envios/styles.css` (mesmas vars CSS de cor + spacing).
- [ ] **AC-2:** Layout grid responsivo:
  - Desktop (>=1024px): 3 colunas (master switch + config + stats no topo, variants editor 2 cols, jobs full width)
  - Tablet (768-1023): 2 colunas
  - Mobile (<768): 1 coluna stack
- [ ] **AC-3:** Toggle switches estilizados (mesma estética modal P4 confirm).
- [ ] **AC-4:** Variant cards com border accent: verde se active, cinza se inativo, badge "última rotação" amarelo.
- [ ] **AC-5:** Pending jobs com badge colorida por status (yellow=pending, blue=in_progress).
- [ ] **AC-6:** Modal de confirmação reaproveita estilos `.modal-overlay` + `.modal-card` do P4.
- [ ] **AC-7:** Toast notifications top-right (success green, error red, info blue).

### Bloco B — JS (RPC Layer)

- [ ] **AC-8:** Module pattern: `const NpsMonitor = (() => { ... return { init } })();`
- [ ] **AC-9:** State management: `state.config`, `state.variants`, `state.jobs`, `state.stats` — reactive via render functions.
- [ ] **AC-10:** Auth gate: redirect `/admin/login` se não admin (mesmo padrão `/admin/envios/app.js`).
- [ ] **AC-11:** Init flow: auth check → fetch `nps_admin_dashboard` → render todas seções.
- [ ] **AC-12:** Wrapper `rpc(name, args)` que faz `supabase.rpc(name, args)` + lança erro consistente.
- [ ] **AC-13:** Toggle handler: confirm modal → `rpc('nps_admin_set_config', ...)` → re-fetch dashboard → toast.
- [ ] **AC-14:** Variant edit handler: modal aberta com textarea → submit → `rpc('nps_admin_update_variant', ...)` → toast.
- [ ] **AC-15:** Job actions: confirm → `rpc('nps_admin_*_job', ...)` → re-fetch → toast.

### Bloco C — UX

- [ ] **AC-16:** Auto-refresh a cada 30s via `setInterval` (pausável via header button).
- [ ] **AC-17:** Pause auto-refresh quando alguma modal estiver aberta (race condition prevention).
- [ ] **AC-18:** Loading skeleton renderiza pre-fetch.
- [ ] **AC-19:** Error states explícitos (banner topo se RPC 401, 500, ou network fail).
- [ ] **AC-20:** Disable buttons durante request inflight (não permitir double-click).

### Bloco D — Accessibility

- [ ] **AC-21:** `aria-label` em ícone-only buttons.
- [ ] **AC-22:** Focus trap em modals.
- [ ] **AC-23:** ESC fecha modal.
- [ ] **AC-24:** Lighthouse a11y >= 90.

### Bloco E — Quality

- [ ] **AC-25:** Zero console.error em fluxo happy path.
- [ ] **AC-26:** Bundle JS < 50KB (sem framework, vanilla).
- [ ] **AC-27:** FCP < 1.5s em conexão 4G simulada.

## Dependencies

NPS.U.2 (HTML pronto)

## Risk

LOW

## Files

- New: `admin/nps-monitor/styles.css`
- New: `admin/nps-monitor/app.js`
