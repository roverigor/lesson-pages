# Component Primitives v1 — Spec
> Atomic methodology (Brad Frost). Cada primitivo consome tokens, não literais.
> A11y obrigatório: WCAG 2.1 AA. Focus visible. Keyboard navigable.
> Implementação: CSS classes em `assets/css/primitives/*.css` v1. Componente JS opcional v1.1+.

## Atoms

### Button
- **Props (data-attrs):** `variant` (primary | secondary | ghost | danger | success), `size` (sm | md | lg), `loading`, `disabled`, `iconLeft`, `iconRight`, `fullWidth`
- **States:** default, hover, active, focus-visible, disabled, loading (spinner replace icon)
- **Tokens:** `--color-accent-emphasis` (primary bg), `--color-surface-2` (secondary bg), `--color-danger-emphasis`, `--radius-md`, `--space-2/3/4`, `--font-size-sm/md`, `--font-weight-semibold`, `--elevation-glow-accent` (hover primary)
- **A11y:** `<button>` nativo. `aria-busy="true"` quando loading. `aria-disabled` se `disabled`. Focus ring 2px via `--color-border-focus`.

### Input (text, email, number, password, search)
- **Props:** `type`, `size` (sm | md | lg), `state` (default | error | success), `prefix`, `suffix` (icon slots), `disabled`, `readonly`
- **States:** default, hover, focus, filled, error, disabled
- **Tokens:** `--color-surface-3` (bg), `--color-border-strong` (border), `--color-content-default` (text), `--color-content-subtle` (placeholder), `--radius-md`, `--space-3` (padding-y), `--space-4` (padding-x)
- **A11y:** SEMPRE acompanhado de `<label for="...">` (via FormField molecule). `aria-invalid="true"` quando error. `aria-describedby` apontando pro error text.

### Textarea
- Mesma API/tokens do Input. `rows` prop default 4. `resize: vertical`.

### Select
- **Props:** `size`, `state`, `disabled`, `placeholder`
- **Tokens:** mesmos do Input + chevron icon usando `--color-content-muted`
- **A11y:** native `<select>` (acessibilidade gratuita). Custom dropdown só em v1.1 com Radix.

### Checkbox / Radio
- **Props:** `checked`, `indeterminate` (checkbox apenas), `disabled`, `label`
- **Tokens:** `--color-accent-emphasis` (checked fill), `--color-border-strong` (unchecked border), `--radius-sm` (checkbox), `--radius-circle` (radio)
- **A11y:** native input + label wrapper. Focus ring visível. Tamanho mínimo 18x18px (touch target via padding).

### Switch
- **Props:** `checked`, `disabled`, `size` (sm | md), `label`
- **States:** off, on, focus, disabled
- **Tokens:** `--color-surface-3` (track off), `--color-accent-emphasis` (track on), `--color-content-strong` (thumb), `--duration-normal`
- **A11y:** `role="switch"` em `<button>` + `aria-checked`. Keyboard: Space toggla.

### Badge
- **Props:** `variant` (neutral | accent | success | warning | danger | info), `size` (sm | md)
- **Tokens:** `*-muted` bg + `*-fg` text. `--radius-pill`. `--font-size-2xs`, `--font-weight-semibold`, `--letter-spacing-wide`, `text-transform: uppercase`
- **Uso:** status de dispatch, NPS category (promoter/passive/detractor), severity.

### Avatar
- **Props:** `name` (para iniciais + hash → mentorColor), `src`, `size` (xs | sm | md | lg), `shape` (circle | square)
- **Tokens:** `--mentor-1..8` via `mentorColor(name)` JS helper. `--radius-circle`, `--font-weight-semibold`
- **A11y:** `<img alt>` quando src. Iniciais wrap em `<span aria-hidden>` + `aria-label="Nome completo"`.

### Spinner
- **Props:** `size` (xs | sm | md | lg), `tone` (default | accent | onAccent)
- **Tokens:** `--color-content-muted`, `--duration-slow`
- **A11y:** `role="status"` + `aria-label="Carregando"`. `aria-hidden` quando dentro de botão com `aria-busy`.

### Icon
- SVG 24px viewBox, `currentColor` fill/stroke. `aria-hidden="true"` por default. Stroke-width via `--icon-stroke` (1.5 default, 2 emphasized).
- Lib: heroicons outline + custom AL set. Inline SVG (no icon font).

### Label
- **Props:** `htmlFor` (required), `required` (mostra `*`), `optional` (mostra "(opcional)")
- **Tokens:** `--font-size-xs`, `--font-weight-semibold`, `--color-content-default`, `--letter-spacing-wide`, `text-transform: uppercase`, `--space-2` margin-bottom

### Link
- **Props:** `variant` (default | subtle | inverse), `external`
- **Tokens:** `--color-accent-fg` (default), `--color-content-default` underline `--color-border-strong`
- **A11y:** `external` adiciona `rel="noopener noreferrer"` + ícone visível.

### Divider
- **Props:** `orientation` (horizontal | vertical), `tone` (subtle | default)
- **Tokens:** `--color-border-subtle/default`, `--space-4` margin

## Molecules

### FormField
- Wrapper: `Label` + `Input/Select/Textarea` + `HelpText` + `ErrorMessage`
- **A11y:** auto-wire `id` ↔ `htmlFor` ↔ `aria-describedby` ↔ `aria-invalid`. Garante associação WCAG 1.3.1.
- **Tokens:** `--space-2` entre label e input; `--space-1` entre input e help/error; `--color-danger-fg` em error; `--font-size-xs` em help/error

### SearchBar
- Input + leading search icon + clear button (×) quando filled
- **Tokens:** mesmos do Input + `--color-content-muted` icon
- **A11y:** `role="search"` no wrapper. `aria-label="Buscar"` no input. Clear button `aria-label="Limpar busca"`.

### StatCard (KPI)
- **Slots:** label (top, small caps), value (hero), delta (badge + arrow), helper
- **Variants:** default | accent | success | warning | danger (border-left 3px tinted)
- **Tokens:** `--color-surface-1`, `--radius-lg`, `--space-6` padding, `--font-size-3xl` value, `--font-weight-bold`. Delta usa Badge.
- **Unifica:** `.kpi-card`, `.stat-card`, `.kpi-num` (3 nomes legacy → 1 primitivo)

### Tag / Chip
- **Props:** `removable`, `selected` (toggle state), `onClick`
- **Tokens:** `--radius-pill`, `--space-2` padding-y, `--space-3` padding-x, `--font-size-xs`. Selected = `--color-accent-muted` bg + `--color-accent-fg` text.
- **A11y:** se interativo, `<button>` com `aria-pressed`. Remove × tem `aria-label`.

### Tooltip
- **Props:** `content`, `placement` (top | right | bottom | left), `delay` (default 400ms)
- **Tokens:** `--color-surface-3`, `--elevation-2`, `--radius-md`, `--font-size-xs`, `--z-tooltip`
- **A11y:** `role="tooltip"` + `aria-describedby` no trigger. Aparece em focus E hover. Escape fecha.

### Menu (dropdown items)
- **Props:** items: `{label, icon?, onClick, destructive?, disabled?}`
- **Tokens:** `--color-surface-2`, `--elevation-2`, `--radius-md`, `--space-2` item padding-y. Destructive = `--color-danger-fg`.
- **A11y:** `role="menu"`, items `role="menuitem"`. Arrow keys navigation. Escape fecha. Focus restore ao trigger.

### EmptyState
- **Slots:** icon (lg, muted), title, description, action (Button optional)
- **Tokens:** `--space-8` padding, `--color-content-muted`, `--font-size-lg` title

## Organisms

### Modal
- **Props:** `title`, `size` (sm | md | lg | full), `dismissible`, `onClose`
- **Slots:** header (close X), body, footer (actions)
- **Tokens:** `--color-surface-1` (modal), `--color-surface-overlay` (backdrop), `--radius-xl`, `--elevation-3`, `--z-modal`, `--space-6` padding
- **A11y:** `role="dialog"` + `aria-modal="true"` + `aria-labelledby` (apontando pro título). Focus trap obrigatório. Escape fecha. Focus restore ao trigger. Backdrop click fecha (se `dismissible`).
- **Unifica:** 15+ modals inline atuais (attendance, dispatch detail, group verify, etc.)

### Drawer
- **Props:** `side` (left | right), `size`, `dismissible`, `onClose`
- Mesma a11y do Modal. Slide animation `--duration-normal` `--ease-emphasized`.
- **Uso:** filters drawer (envios), settings panel

### Toast
- **Props:** `tone` (default | success | warning | danger | info), `title`, `description`, `duration` (default 5000ms), `action`
- **Tokens:** `--color-surface-2` + tinted border-left 3px (`*-emphasis`), `--elevation-4`, `--z-toast`, `--radius-lg`
- **A11y:** `role="status"` (info/success) ou `role="alert"` (warning/danger). `aria-live="polite/assertive"`. Não auto-dismiss em `prefers-reduced-motion`.

### DataTable
- **Slots:** caption, thead (sticky), tbody, footer (pagination/summary)
- **Features:** sortable headers (Button-like th com aria-sort), row selection (Checkbox col), sticky-first-col, density (compact | comfortable), responsive wrapper (overflow-x)
- **Tokens:** `--color-surface-1` bg, `--color-border-subtle` row separator, `--space-3` cell padding (compact) / `--space-4` (comfortable), `--font-size-sm`
- **A11y:** `<table>` + `<caption class="visually-hidden">`. `scope="col"` em th, `scope="row"` em primeira td. `aria-sort` em sortable headers. Row checkbox `aria-label="Selecionar linha N"`.
- **Unifica:** 4 tables nps-results + 3 nps-monitor + ps-rsvp + envios + lembretes (10+ instances)

### Sidebar
- **Props:** `items: [{section, links: [{label, href, icon, badge?}]}]`, `collapsed`
- **Tokens:** `--color-surface-1`, `--space-3` item padding, `--color-accent-muted` active bg, `--color-accent-fg` active text
- **A11y:** `<nav aria-label="Principal">`. Active item `aria-current="page"`. Section headers `<h2>` visually-hidden ou small caps. Collapse toggle `aria-expanded`.
- **Decisão crítica:** Sidebar persiste em TODAS rotas `/admin/*` (fix do gap audit: "sidebar perde quando navega").

### TopNav
- **Slots:** logo (left), breadcrumbs (center-left), actions (right: search, notifications, user menu)
- **Tokens:** `--color-surface-glass` + `backdrop-filter`, `--elevation-1`, `--z-sticky`, height `--space-12` (48px)
- **A11y:** `<header role="banner">`. User menu Menu primitive.

### Breadcrumbs
- **Props:** `items: [{label, href}]` (último item sem href = current)
- **Tokens:** `--font-size-sm`, `--color-content-muted` (intermediate), `--color-content-default` (current), `/` separator `--color-content-subtle`
- **A11y:** `<nav aria-label="Breadcrumbs">` + `<ol>`. Current item `aria-current="page"`.
- **GAP-fix:** Não existe hoje em nenhuma página. Mandatory v1.

### FormGroup
- Container de múltiplos FormField + grid responsivo (1col mobile, 2col desktop) + fieldset semântico se grupo lógico
- **Tokens:** `--space-5` gap entre fields, `--space-8` entre fieldsets
- **A11y:** `<fieldset>` + `<legend>` quando grupo lógico (ex: "Dados pessoais", "Endereço").

### PageHeader
- **Slots:** breadcrumbs, title (h1), description, actions (right cluster de Buttons)
- **Tokens:** `--space-6` padding-block, `--font-size-4xl` h1, border-bottom `--color-border-subtle`
- **Uso:** unifica os 4 topbar custom atuais (nps-results, nps-monitor, ps-rsvp, envios)

## Token consumption matrix (resumo)
- **Surface:** Card, Modal, Drawer, Toast, Input, DataTable, Sidebar, TopNav
- **Content:** Todo texto (Button label, Input value, Label, Badge)
- **Border:** Card, Input, Divider, DataTable rows, Focus ring (todos interactive)
- **Accent:** Button primary, Switch on, Checkbox checked, Tag selected, Sidebar active item, focus rings
- **State (success/warning/danger/info):** Badge, Toast, StatCard variant, Button danger, FormField error

## Out-of-scope v1 (deferred)
DatePicker (Radix v1.1), Combobox/Autocomplete (v1.1), Command palette (v1.2), RichTextEditor (nunca? avaliar). Charts: usar lib (Chart.js já no projeto) — tokenizar cores via `--mentor-*` e `--color-accent-*`.
