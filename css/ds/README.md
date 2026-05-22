# Design System v1 — Academia Lendária Painel

> **Status:** Foundation entregue. Adoção gradual. Não aplicado em telas live ainda.
> **Stack:** Vanilla CSS + BEM-light. Zero build step. Compatível com HTML estático atual.
> **Specs:** [`docs/design-system/v1/`](../../docs/design-system/v1/)

---

## 1. O que tem hoje (v1.0 — starter)

| Categoria | Arquivo | Status |
|---|---|---|
| Tokens | `tokens.css` | Pronto (color, typography, spacing, radius, shadow, z, motion, mentor) |
| Tokens legacy | `tokens.legacy.css` | Aliases pros tokens antigos de `templates/design-tokens-dark-premium.css` |
| Reset | `reset.css` | Modern minimal (box-sizing, focus-visible, scrollbar, selection) |
| Atom: Button | `primitives/button.css` | 5 variantes × 3 sizes × loading/disabled |
| Atom: Card | `primitives/card.css` | flat/raised/floating × accent/success/warning/danger/info |
| Molecule: StatCard (KPI) | `primitives/stat-card.css` | trend up/down/flat × tones × sizes (unifica `.kpi-card`, `.stat-card`, `.kpi-num`) |
| Entry point | `index.css` | `@layer` cascade orquestrado |

### Pendente (próximos PRs — não bloqueia adoção)
- Atoms: Input, Textarea, Select, Checkbox, Radio, Switch, Badge, Avatar, Spinner, Icon, Label, Link, Divider
- Molecules: FormField, SearchBar, Tag, Tooltip, Menu, EmptyState
- Organisms: Modal, Drawer, Toast, DataTable, Sidebar, TopNav, Breadcrumbs, FormGroup, PageHeader
- Utilities layer (.u-stack, .u-cluster, .u-flex)
- Light theme (skeleton já está em `tokens.css`, valores TBD v1.1)

---

## 2. Como adotar gradualmente

### 2.1 Linkar em UMA página HTML existente
No `<head>` da página alvo, **antes** dos CSS antigos:

```html
<link rel="stylesheet" href="/css/ds/index.css">
<!-- CSS legacy continua funcionando via tokens.legacy.css aliases -->
<link rel="stylesheet" href="/templates/admin-shared.css">
```

A camada `tokens.legacy.css` aliasa nomes antigos (`--color-bg-page`, `--spacing-md`, etc) pros novos tokens. Páginas legacy continuam visualmente idênticas.

### 2.2 Trocar um componente legacy por primitive
Exemplo: botão antigo → `.btn`:

```html
<!-- Antes -->
<button style="background:#F5C518;color:#000;padding:14px 24px;border-radius:8px;">
  Salvar
</button>

<!-- Depois -->
<button class="btn btn--primary">Salvar</button>
```

### 2.3 Migrar uma página completa
Per-page checklist (de `docs/design-system/v1/03-atomic-structure.md` §6.2):

1. Remover `<style>` inline que reescreve buttons/cards/modals
2. Trocar hex literals → `var(--color-*)` tokens
3. Adicionar PageHeader + Breadcrumbs no topo (quando primitive existir)
4. Inputs com `<label for="...">` correto (a11y)
5. Modals com `<dialog>` nativo + JS focus trap
6. Tables com `scope="col/row"`

**Ordem sugerida de adoção:**
1. `/admin/index.html` (homepage, sidebar canônica)
2. `/admin/envios/`
3. `/admin/nps-monitor/` + `/admin/nps-results/`
4. `/admin/ps-rsvp/` + `/admin/lembretes-aulas/`
5. `/aluno/*` (surface low)

---

## 3. Convenções de uso

### 3.1 Regras inegociáveis

| Regra | Exemplo errado | Exemplo certo |
|---|---|---|
| Nunca hex em código novo | `color: #F5C518;` | `color: var(--color-accent-fg);` |
| Nunca px em spacing | `padding: 16px 24px;` | `padding: var(--space-4) var(--space-6);` |
| Nunca px em font-size | `font-size: 14px;` | `font-size: var(--font-size-md);` |
| Texto usa `--color-content-*` | `color: var(--color-surface-1);` | `color: var(--color-content-strong);` |
| Estado via triplet `*-fg/-emphasis/-muted` | inventar `--color-error` | `--color-danger-fg`, `--color-danger-emphasis`, `--color-danger-muted` |
| Focus ring usa `--color-border-focus` | `outline: 1px solid blue;` | `outline: 2px solid var(--color-border-focus);` |

### 3.2 BEM-light naming

```
.bloco                   /* primitive base */
.bloco__elemento         /* descendant */
.bloco--variante         /* modifier */
.bloco.is-estado         /* state (is-active, is-loading, is-error) */
.u-utility               /* utility helper */
```

Exemplo composto:
```html
<article class="card card--accent card--floating">
  <header class="card__header">
    <h3 class="card__title">…</h3>
  </header>
  <div class="card__body is-loading">…</div>
</article>
```

### 3.3 A11y obrigatório

- `:focus-visible` em todo interactive
- `aria-busy="true"` em loading
- `aria-disabled` em disabled (além de atributo `disabled` quando aplicável)
- `prefers-reduced-motion` respeitado (já está nos primitives)
- Contraste WCAG AA mínimo (tokens já calibrados)

---

## 4. Como contribuir um novo primitive

### 4.1 Antes de codar
1. Confere se já tem spec em `docs/design-system/v1/02-primitives.md`
2. Se não tem, abre PR de spec **antes** de implementar
3. Identifica nomes legacy que esse primitive vai unificar (auditoria)

### 4.2 Implementação
1. Cria arquivo em `css/ds/primitives/<nome>.css`
2. **ZERO hex literals.** Sempre `var(--token-name)`
3. **ZERO px magic numbers** em padding/margin/gap/font-size. Sempre token
4. Estrutura BEM: `.bloco`, `.bloco__elem`, `.bloco--variante`
5. Estados: `:hover`, `:active`, `:focus-visible`, `:disabled` cobertos
6. A11y: focus ring visível, aria attrs documentados em comments
7. Respeita `prefers-reduced-motion` em qualquer transition/animation
8. Comenta em português onde necessário

### 4.3 Registrar
1. Adiciona `@import` em `css/ds/index.css` na layer `primitives`
2. Atualiza tabela "O que tem hoje" deste README
3. Documenta uso com exemplo HTML no header do arquivo CSS

### 4.4 Quality checklist (PR review)
- [ ] Zero hex literals (rodar `grep -E '#[0-9a-fA-F]{3,8}' css/ds/primitives/<nome>.css` → vazio)
- [ ] Zero `px` em spacing (`grep -E ':\s*[0-9]+px' css/ds/primitives/<nome>.css` → só bordas 1-2px tipo `border-left: 3px solid var(--…)`)
- [ ] focus-visible ring presente
- [ ] reduced-motion respeitado
- [ ] BEM-light naming consistente
- [ ] Comentário com exemplo HTML no header

---

## 5. Tokens — referência rápida

> Lista completa em [`tokens.css`](./tokens.css). Aqui só o essencial.

### Cores
- **Surface:** `--color-surface-0/1/2/3`, `--color-surface-overlay`, `--color-surface-glass`
- **Content:** `--color-content-strong/default/muted/subtle/on-accent/on-danger`
- **Border:** `--color-border-subtle/default/strong/focus`
- **Accent:** `--color-accent-emphasis(-hover)`, `--color-accent-muted`, `--color-accent-fg`
- **State:** `--color-{success,warning,danger,info}-{fg,emphasis,muted}`
- **Mentor (data viz):** `--mentor-1..8`

### Tipografia
- **Family:** `--font-sans`, `--font-mono`
- **Size:** `--font-size-{2xs,xs,sm,md,lg,xl,2xl,3xl,4xl,display}`
- **Weight:** `--font-weight-{regular,medium,semibold,bold}`
- **Line height:** `--line-height-{tight,snug,normal,relaxed}`
- **Letter spacing:** `--letter-spacing-{tight,normal,wide}`

### Spacing (4px base)
`--space-{0,1,2,3,4,5,6,8,10,12,16}` — `0 / 4 / 8 / 12 / 16 / 20 / 24 / 32 / 40 / 48 / 64 px`

### Radius
`--radius-{sm,md,lg,xl,2xl,pill,circle}` — `4 / 8 / 12 / 16 / 24 / 9999 / 50% px`

### Elevation
`--elevation-{0,1,2,3,4}`, `--elevation-glow-{accent,danger}`

### Z-index
`--z-{base,raised,dropdown,sticky,overlay,modal,toast,tooltip}` — `0 / 10 / 100 / 200 / 800 / 900 / 1000 / 1100`

### Motion
- **Duration:** `--duration-{instant,fast,normal,slow}` — `80 / 150 / 240 / 400 ms`
- **Easing:** `--ease-{standard,emphasized,decelerate}`

---

## 6. Roadmap

- **v1.0** (now): tokens + reset + button + card + stat-card → starter foundation
- **v1.1**: light theme calibrado, todos atoms restantes (input/select/badge/avatar/spinner/icon/label/link/divider), molecules (form-field/search-bar/tag/tooltip/menu/empty-state)
- **v1.2**: organisms (modal/drawer/toast/data-table/sidebar/top-nav/breadcrumbs/form-group/page-header) + JS primitives (focus trap, toast queue, keyboard nav)
- **v1.3**: utilities layer completa, Storybook (diferido — ver `04-storybook-plan.md`)
- **v2.0** (opcional): migração para Next.js + Tailwind + shadcn (tokens permanecem source of truth)

---

## 7. Suporte e dúvidas

- Specs: `docs/design-system/v1/01-tokens.md` (tokens), `02-primitives.md` (componentes), `03-atomic-structure.md` (decisões de stack)
- Storybook plan: `docs/design-system/v1/04-storybook-plan.md`
- Squad responsável: Design System v1 (vanilla CSS)
