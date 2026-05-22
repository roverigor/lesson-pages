# Design Tokens v1 — Academia Lendária Painel
> Foundation layer. Dark-first. Semantic naming. CSS variables.
> Status: Spec. Implementação em `assets/css/tokens.css` (próxima fase).

## 1. Princípios
1. **Semantic over literal** — `--color-surface-1` em vez de `--gray-900`. Componente NUNCA cita hex.
2. **Dark mode first** — valores default em `:root`. Light é override em `[data-theme="light"]` (estrutura pronta, valores TBD na v1.1).
3. **3-tier naming** — `<categoria>-<role>-<modifier>`: `color-surface-1`, `color-content-muted`, `color-accent-emphasis-hover`.
4. **No magic numbers** — qualquer `padding/margin/gap/radius/font-size` literal em código novo é bug.
5. **Migração não-destrutiva** — tokens legacy (`--color-bg-page`, `--font-size-md`) ficam aliased durante v1, removidos na v2.

## 2. Color tokens

### 2.1 Surface (backgrounds — z-ascending)
| Token | Valor (dark) | Uso |
|---|---|---|
| `--color-surface-0` | `#0A0A0A` | Page background |
| `--color-surface-1` | `#141414` | Cards, containers default |
| `--color-surface-2` | `#1A1A1A` | Cards hover / nested cards |
| `--color-surface-3` | `#222222` | Inputs, dropdowns, modals body |
| `--color-surface-overlay` | `rgba(0,0,0,0.72)` | Modal backdrop |
| `--color-surface-glass` | `rgba(20,20,20,0.7)` | Topbar/sidebar com blur |

### 2.2 Content (foreground/text)
| Token | Valor | Uso | Contrast vs surface-0 |
|---|---|---|---|
| `--color-content-strong` | `#FFFFFF` | Headlines, hero metrics | 21:1 |
| `--color-content-default` | `#E5E5E5` | Body text padrão | 16:1 |
| `--color-content-muted` | `#999999` | Captions, helper text | 6.4:1 ✅ AA |
| `--color-content-subtle` | `#888888` | Placeholder, disabled label | 5.1:1 ✅ AA |
| `--color-content-on-accent` | `#000000` | Texto sobre `accent-emphasis` (CTA amarelo) | n/a |
| `--color-content-on-danger` | `#FFFFFF` | Texto sobre danger fill | n/a |

> ⚠️ Cores abaixo de `--color-content-subtle` (`#777`, `#666`, `#555`) são **banidas** em texto. Permitidas apenas em ícones decorativos.

### 2.3 Border
| Token | Valor | Uso |
|---|---|---|
| `--color-border-subtle` | `rgba(255,255,255,0.06)` | Separator entre rows de tabela |
| `--color-border-default` | `rgba(255,255,255,0.10)` | Card border |
| `--color-border-strong` | `rgba(255,255,255,0.18)` | Input border, hover state |
| `--color-border-focus` | `var(--color-accent-emphasis)` | Focus ring |

### 2.4 Accent (brand)
| Token | Valor | Uso |
|---|---|---|
| `--color-accent-emphasis` | `#F5C518` | CTA primário (dourado AL) |
| `--color-accent-emphasis-hover` | `#FFD700` | Hover CTA primário |
| `--color-accent-muted` | `rgba(245,197,24,0.12)` | Background subtle accent (badge, tag) |
| `--color-accent-fg` | `#F5C518` | Texto/icon accent |

### 2.5 State
| Token | Valor | Uso |
|---|---|---|
| `--color-success-fg` | `#22C55E` | Texto sucesso, NPS promoter |
| `--color-success-emphasis` | `#10B981` | Botão success, badge fill |
| `--color-success-muted` | `rgba(34,197,94,0.12)` | Background success subtle |
| `--color-warning-fg` | `#F59E0B` | Texto aviso, NPS passivo |
| `--color-warning-emphasis` | `#F59E0B` | Badge warning fill |
| `--color-warning-muted` | `rgba(245,158,11,0.15)` | Background warning subtle |
| `--color-danger-fg` | `#EF4444` | Texto erro, NPS detractor |
| `--color-danger-emphasis` | `#DC2626` | Botão danger, badge fill |
| `--color-danger-muted` | `rgba(239,68,68,0.12)` | Background danger subtle |
| `--color-info-fg` | `#3B82F6` | Info text |
| `--color-info-emphasis` | `#2563EB` | Info button |
| `--color-info-muted` | `rgba(59,130,246,0.12)` | Info background subtle |

### 2.6 Brand mentor palette (data viz)
Reusa `MENTOR_COLORS` existente de `templates/utils.js`. Promovido a tokens:
```
--mentor-1: #6366F1 (indigo)   --mentor-5: #10B981 (emerald)
--mentor-2: #8B5CF6 (violet)   --mentor-6: #3B82F6 (blue)
--mentor-3: #EC4899 (pink)     --mentor-7: #EF4444 (red)
--mentor-4: #F59E0B (amber)    --mentor-8: #14B8A6 (teal)
```
> Função `mentorColor(name)` em `utils.js` continua autoritativa pra hash → cor.

## 3. Typography tokens

### 3.1 Family
- `--font-sans`: `'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif`
- `--font-mono`: `'JetBrains Mono', 'Fira Code', 'Courier New', monospace`

### 3.2 Scale (rem-based, 1rem = 16px)
| Token | Valor | px | Uso |
|---|---|---|---|
| `--font-size-2xs` | `0.6875rem` | 11 | Microcopy, tag |
| `--font-size-xs` | `0.75rem` | 12 | Caption, label, helper |
| `--font-size-sm` | `0.8125rem` | 13 | Table cell, dense UI |
| `--font-size-md` | `0.875rem` | 14 | Body default (admin) |
| `--font-size-lg` | `1rem` | 16 | Body comfortable, form input |
| `--font-size-xl` | `1.125rem` | 18 | Subheading |
| `--font-size-2xl` | `1.5rem` | 24 | H3, KPI value médio |
| `--font-size-3xl` | `2rem` | 32 | H2, KPI hero |
| `--font-size-4xl` | `2.5rem` | 40 | H1 página admin |
| `--font-size-display` | `3.5rem` | 56 | Hero score (NPS) |

### 3.3 Weight, line-height, letter-spacing
```
--font-weight-regular: 400; --font-weight-medium: 500;
--font-weight-semibold: 600; --font-weight-bold: 700;
--line-height-tight: 1.1;   --line-height-snug: 1.3;
--line-height-normal: 1.5;  --line-height-relaxed: 1.7;
--letter-spacing-tight: -0.02em; --letter-spacing-wide: 0.08em;
```

## 4. Spacing tokens (4px base)
| Token | px | Uso típico |
|---|---|---|
| `--space-0` | 0 | reset |
| `--space-1` | 4 | gap micro (icon ↔ label) |
| `--space-2` | 8 | padding inline button sm |
| `--space-3` | 12 | input padding vertical |
| `--space-4` | 16 | card padding md, gap default |
| `--space-5` | 20 | gap entre form fields |
| `--space-6` | 24 | card padding lg, section gap |
| `--space-8` | 32 | gap entre seções |
| `--space-10` | 40 | page padding top |
| `--space-12` | 48 | gap entre blocos hero |
| `--space-16` | 64 | gap entre megasecções |

> Banidos em código novo: `padding: 10px 12px`, `gap: 5px`, etc. **Sempre token**.

## 5. Radius
| Token | Valor | Uso |
|---|---|---|
| `--radius-sm` | 4px | Tag, badge inline |
| `--radius-md` | 8px | Input, button default |
| `--radius-lg` | 12px | Card |
| `--radius-xl` | 16px | Modal, drawer |
| `--radius-2xl` | 24px | Hero card |
| `--radius-pill` | 9999px | Pill button, chip |
| `--radius-circle` | 50% | Avatar, icon-circle |

## 6. Shadow / elevation
| Token | Valor | Uso |
|---|---|---|
| `--elevation-0` | `none` | Flat (default cards no dark) |
| `--elevation-1` | `0 1px 2px rgba(0,0,0,0.4)` | Sticky topbar |
| `--elevation-2` | `0 4px 12px rgba(0,0,0,0.5)` | Dropdown, popover |
| `--elevation-3` | `0 8px 24px rgba(0,0,0,0.6)` | Modal, drawer |
| `--elevation-4` | `0 16px 48px rgba(0,0,0,0.7)` | Toast, command palette |
| `--elevation-glow-accent` | `0 0 20px rgba(245,197,24,0.3)` | CTA hover glow |
| `--elevation-glow-danger` | `0 0 16px rgba(239,68,68,0.25)` | Destrutivo focus |

## 7. Z-index (named layers)
```
--z-base: 0;     --z-raised: 10;   --z-dropdown: 100;
--z-sticky: 200; --z-overlay: 800; --z-modal: 900;
--z-toast: 1000; --z-tooltip: 1100;
```

## 8. Motion
```
--duration-instant: 80ms;  --duration-fast: 150ms;
--duration-normal: 240ms;  --duration-slow: 400ms;
--ease-standard: cubic-bezier(0.2, 0, 0, 1);
--ease-emphasized: cubic-bezier(0.3, 0, 0, 1);
--ease-decelerate: cubic-bezier(0, 0, 0, 1);
```

> Respeitar `prefers-reduced-motion: reduce` — duration vira `0.01ms`, opacity-only transitions.

## 9. Implementação

### 9.1 Arquivo canonical
`assets/css/tokens.css` (novo). Imports cascateiam: `tokens.css` → `reset.css` → `primitives/*.css` → `pages/*.css`.

### 9.2 Light mode skeleton (v1.1, valores TBD)
```css
:root { /* dark default */ ... }
[data-theme="light"] {
  --color-surface-0: #FFFFFF;
  --color-surface-1: #F8F8F8;
  /* etc — calibrar contraste */
}
```
Toggle via `document.documentElement.dataset.theme`. Persist `localStorage`.

### 9.3 Migração legacy (`design-tokens-dark-premium.css`)
Criar `assets/css/tokens.legacy.css` com aliases:
```css
:root {
  --color-bg-page: var(--color-surface-0);
  --color-bg-card: var(--color-surface-1);
  --color-text-headline: var(--color-content-strong);
  --color-cta-primary: var(--color-accent-emphasis);
  /* ...todos os 25+ tokens antigos */
}
```
Páginas legacy continuam funcionando. Refactor file-by-file na sweep v1.

### 9.4 Tailwind config (se/quando migrar — NÃO obrigatório v1)
Mapping previsto em `04-storybook-plan.md`. Tokens CSS continuam source of truth; Tailwind apenas referencia via `theme.extend.colors['surface-1']: 'var(--color-surface-1)'`.

## 10. Token usage checklist (PR review)
- [ ] Zero hex literals em CSS novo (exceto em `tokens.css`)
- [ ] Zero `px` literais em padding/margin/gap (exceto bordas 1-2px, radius já tokenizado)
- [ ] Nenhum `font-size: NNpx` — sempre `var(--font-size-*)`
- [ ] Color em texto: usar `content-*` tokens (não `surface-*`)
- [ ] State color via `*-fg/-emphasis/-muted` triplet
- [ ] Focus ring usa `--color-border-focus` (consistência WCAG)
