# Atomic Structure & Naming — v1
> File organization, naming conventions, decisão de tech stack.
> Brad Frost atomic methodology mapeada pra realidade do projeto (vanilla HTML + CSS custom).

## 1. Decisão de stack — **CSS-first, framework-optional**

### 1.1 Stack atual (descoberto, não Next.js)
- HTML estático em diretórios (`/admin/`, `/aluno/`, `/relatorio/`, etc.)
- CSS custom (sem Tailwind, sem CSS-in-JS)
- JS vanilla em `/js/admin/*.js` (ES modules)
- Build: terser minify via `scripts/minify.mjs`. ESLint configured.
- Deploy: Docker container porta 3080, nginx, GitHub Actions.

### 1.2 Decisão: **NÃO migrar pra Next.js/React em v1**
**Razão:** audit identifica "remanufaturar layout" mas não migração de stack. Risk-reward de full SPA migration é alto (deploy CI/CD, SEO landing, mental model do time). DS v1 entrega **CSS primitivo + class-based components** que funcionam no HTML atual. Migração pra framework fica como opção v2.

### 1.3 Headless lib? **Não em v1. Sim em v1.1+ se necessário.**
- **shadcn/ui**: requer React + Tailwind. Fora do escopo v1.
- **Radix UI Primitives**: requer React. Avaliar em v1.1 se precisarmos de focus trap / select dropdown / dialog complexo.
- **Headless UI**: idem Radix.
- **Decisão v1**: componentes nativos HTML (`<button>`, `<select>`, `<dialog>`) + JS vanilla mínimo pra Modal focus-trap, Toast queue, Menu keyboard nav. `<dialog>` element nativo cobre 80% do Modal use case com a11y grátis (browser support 95%+).

### 1.4 Path de migração (v2 — opcional)
Quando/se migrar pra Next.js + Tailwind + shadcn:
- Tokens CSS continuam source of truth (Tailwind config referencia `var(--color-*)`)
- Primitive classes viram componentes React 1:1 (`.btn-primary` → `<Button variant="primary">`)
- Migração página-a-página, não big bang

## 2. Estrutura de pastas

### 2.1 Layout proposto
```
lesson-pages/
├─ assets/
│  └─ css/
│     ├─ tokens.css                 # Source of truth — :root vars
│     ├─ tokens.legacy.css          # Aliases pros tokens antigos (deprecate v2)
│     ├─ reset.css                  # Normalize + a11y resets
│     ├─ utilities.css              # Helpers (.visually-hidden, .stack, .cluster)
│     ├─ primitives/                # Atomic components (1 arquivo por primitive)
│     │  ├─ atoms/
│     │  │  ├─ button.css
│     │  │  ├─ input.css
│     │  │  ├─ badge.css
│     │  │  ├─ avatar.css
│     │  │  ├─ spinner.css
│     │  │  └─ ...
│     │  ├─ molecules/
│     │  │  ├─ form-field.css
│     │  │  ├─ search-bar.css
│     │  │  ├─ stat-card.css
│     │  │  ├─ tag.css
│     │  │  ├─ tooltip.css
│     │  │  └─ ...
│     │  └─ organisms/
│     │     ├─ modal.css
│     │     ├─ drawer.css
│     │     ├─ toast.css
│     │     ├─ data-table.css
│     │     ├─ sidebar.css
│     │     ├─ top-nav.css
│     │     ├─ breadcrumbs.css
│     │     ├─ page-header.css
│     │     └─ form-group.css
│     ├─ pages/                     # Page-specific, MINIMAL — só layout/composition
│     │  ├─ admin-dashboard.css
│     │  ├─ admin-nps-results.css
│     │  └─ ...
│     └─ index.css                  # @import cascade master
├─ js/
│  ├─ primitives/
│  │  ├─ modal.js                   # focus trap, esc close
│  │  ├─ toast.js                   # queue manager
│  │  ├─ menu.js                    # keyboard nav
│  │  ├─ tooltip.js                 # show/hide
│  │  └─ form-field.js              # auto-wire aria
│  ├─ admin/                        # existente — refactor pra usar primitives
│  └─ utils.js                      # mentorColor, etc
├─ templates/
│  └─ partials/                     # HTML snippets reusáveis (sidebar, topnav)
│     ├─ sidebar.html
│     ├─ topnav.html
│     └─ login-overlay.html
└─ docs/design-system/v1/           # Este diretório (specs)
```

### 2.2 Cascade order (CRITICAL)
Em `assets/css/index.css`:
```css
@layer reset, tokens, utilities, primitives, pages, overrides;

@import "reset.css"        layer(reset);
@import "tokens.css"        layer(tokens);
@import "tokens.legacy.css" layer(tokens);
@import "utilities.css"     layer(utilities);
@import "primitives/atoms/button.css"     layer(primitives);
/* ... todos primitives ... */
@import "pages/admin-dashboard.css" layer(pages);
```
**Layers garantem ordem determinística**, independente de import order. Especificidade local não vaza.

## 3. Naming conventions

### 3.1 CSS classes — **utility-first híbrido com BEM-light**
- **Primitives:** kebab-case, prefix opcional `ui-` (curto, sem namespace verboso)
  - `.btn`, `.btn--primary`, `.btn--sm`, `.btn--loading`
  - `.card`, `.card__header`, `.card__body`, `.card--accent`
  - `.modal`, `.modal__backdrop`, `.modal__close`
- **Modifiers:** double-dash `--variant`. Estados: prefix `is-` (`.is-active`, `.is-loading`, `.is-error`)
- **Utilities:** prefix `u-` (`.u-visually-hidden`, `.u-flex`, `.u-stack-4`)
- **Pages:** prefix `p-` ou nome da rota (`.p-nps-results__hero`, `.p-admin-dashboard__grid`)

**Por que BEM-light (não pure utility tipo Tailwind):**
1. Sem build step CSS — Tailwind requer PostCSS no pipeline (não temos).
2. HTML legível pra ops/admin (`<button class="btn btn--primary btn--lg">` vs `<button class="bg-yellow-500 text-black rounded-full px-6 py-3 font-bold">`).
3. Refactor mais barato: muda 1 regra no CSS, atinge todos os elementos.

### 3.2 CSS variables — 3-tier semantic
Já especificado em `01-tokens.md` §1. Recap:
- Pattern: `--<categoria>-<role>-<modifier>`
- Categoria: `color`, `font-size`, `font-weight`, `space`, `radius`, `elevation`, `z`, `duration`, `ease`
- Role: `surface-1`, `content-muted`, `accent-emphasis`, etc
- Modifier: `-hover`, `-disabled`, `-strong`

### 3.3 JS files — kebab-case módulos, PascalCase classes
- `modal.js` exporta `class Modal { ... }`
- `toast.js` exporta `function showToast({tone, title, ...})` + `class ToastQueue`
- Import paths: relativos no setup atual (`import { Modal } from '/js/primitives/modal.js'`)
- Quando/se migrar: alias `@/primitives/*` configurado no bundler

### 3.4 HTML partials
- kebab-case files: `sidebar.html`, `top-nav.html`
- Server-side include via nginx SSI ou build-time injection. **Decisão v1.1** — por ora copiar HTML é aceitável (audit já mostra duplicação atual).

## 4. File structure por componente (v1.1+ se migrar React)
Quando/se componentizar em React:
```
components/ui/atoms/Button/
├─ Button.tsx          # Componente
├─ Button.stories.tsx  # Storybook
├─ Button.test.tsx     # Vitest + Testing Library
├─ Button.module.css   # OU import classes do primitives/
└─ index.ts            # re-export
```
**Em v1 (CSS-first):**
```
assets/css/primitives/atoms/button.css   # única fonte
js/primitives/button.js                  # OPCIONAL — só se tiver state/keyboard logic
```

## 5. Import paths e aliases

### 5.1 v1 (vanilla)
- CSS: paths absolutos do root (`/assets/css/index.css`)
- JS: paths absolutos (`/js/primitives/modal.js`) — funciona em ES modules nativos

### 5.2 v1.1+ (se houver bundler)
- Alias `@css/*` → `assets/css/*`
- Alias `@js/*` → `js/*`
- Alias `@/components/ui/*` → `components/ui/*` (futuro React)

## 6. Discovery e migration plan

### 6.1 Refactor sweep (não destrutivo)
Ordem proposta de migração página-a-página (paralelo ao trabalho normal):
1. **`/admin/index.html`** — homepage, sidebar canônica (highest visibility)
2. **`/admin/envios/`** — mais tráfego operacional
3. **`/admin/nps-monitor/`** + **`/admin/nps-results/`** — consolidar 15+ modals
4. **`/admin/ps-rsvp/`** + **`/admin/lembretes-aulas/`**
5. **`/aluno/*`** — surface low, pode esperar

### 6.2 Per-page checklist
- [ ] Remover inline `<style>` que reescreve buttons/cards/modals
- [ ] Trocar hex literals → tokens (find/replace + ESLint custom rule futuramente)
- [ ] Adicionar `PageHeader` + `Breadcrumbs` no topo
- [ ] Sidebar persistente (include partial)
- [ ] Inputs com `<label for>` correto
- [ ] Modals com `<dialog>` nativo + JS focus trap
- [ ] Tables com `scope="col/row"`

## 7. Quality gates
- ESLint custom rule (v1.1): disallow `style="color: #..."` inline
- Stylelint setup (v1.1): disallow color literals fora de `tokens.css`
- Visual regression (v1.2 — se Storybook entrar): Chromatic ou Playwright snapshots
