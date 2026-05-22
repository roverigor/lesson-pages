# Storybook Setup Plan — v1
> Componente library docs + visual workbench. Tier opcional do DS (alto valor, custo médio).
> **Decisão v1:** Storybook 8 + HTML/Web Components stories (não React) — alinhado ao stack atual.

## 1. Avaliação valor/custo

### 1.1 Por que Storybook
1. **Docs viva** dos primitives sem precisar abrir 8 páginas admin diferentes
2. **Sandbox a11y** — axe addon roda em cada story, identifica regressões
3. **Force componentização** — pra criar story precisa isolar HTML/CSS do contexto da página (mata o "inline CSS por página" que é a doença atual)
4. **Onboarding** — novo dev abre Storybook e entende DS em 15min
5. **Visual reference** pro user — "quando você diz 'card', é ESSE card"

### 1.2 Custo real
- Setup inicial: 1 dia (config + 5-10 stories iniciais)
- Manutenção: ~15min por novo primitive (escrever .stories file)
- Build pipeline: extra ~30s no CI (build-storybook)
- Hosting: GitHub Pages grátis OU Chromatic free tier (5k snapshots/mês)

### 1.3 Veredito
✅ **VAI** em v1.1 (após primitives implementados). **NÃO BLOQUEIA** v1 de DS — pode rodar em paralelo. Razão pra adiar pra v1.1: primeiro precisa ter primitives CSS escritos pra documentar.

## 2. Versão e renderer

### 2.1 Storybook 8.x
- Latest stable. Vite-based (`@storybook/builder-vite`) — rápido, sem webpack config.
- Renderer: **`@storybook/html-vite`** (não React). Stories escritas em template literals retornando HTML string. Funciona com CSS classes do primitives diretamente.
- Alternative future: `@storybook/web-components-vite` se evoluir pra Lit/custom elements.
- Se migrar pra React (v2): swap pra `@storybook/react-vite`, stories ficam mais ergonômicas.

### 2.2 Install (referência, NÃO executar agora)
```bash
npx storybook@latest init --type html-vite
```

## 3. Addons obrigatórios

| Addon | Why |
|---|---|
| `@storybook/addon-essentials` | Controls, Actions, Viewport, Backgrounds, Toolbars, Measure, Outline (bundle padrão) |
| `@storybook/addon-a11y` | Axe-core inline em cada story — flag de contrast, ARIA, focus order |
| `@storybook/addon-interactions` | Play functions: testar focus, keyboard, click handlers |
| `@storybook/addon-themes` | Toggle dark/light (mesmo dark sendo primary, queremos testar light fallback) |
| `@storybook/addon-viewport` | Mobile/tablet/desktop preview (admin é desktop-first, mas form aluno é mobile) |
| `storybook-addon-pseudo-states` | Hover, focus, active sem ter que interagir |
| `@storybook/addon-docs` | Auto-docs MDX por componente |

### 3.1 Não usar (v1)
- `@chromatic-com/storybook` — adiar pra v1.2 (Visual regression é nice-to-have, custo de setup chromatic.com não justifica até primitives estarem estáveis)

## 4. Theme provider setup (dark/light)

### 4.1 preview.js
```js
import '../assets/css/index.css';  // tokens + primitives globais

export const decorators = [
  (story, ctx) => {
    document.documentElement.dataset.theme = ctx.globals.theme || 'dark';
    return story();
  },
];

export const globalTypes = {
  theme: {
    name: 'Theme',
    defaultValue: 'dark',
    toolbar: {
      icon: 'mirror',
      items: [
        { value: 'dark', title: 'Dark (default)' },
        { value: 'light', title: 'Light (v1.1)' },
      ],
    },
  },
};

export const parameters = {
  backgrounds: {
    default: 'surface-0',
    values: [
      { name: 'surface-0', value: '#0A0A0A' },
      { name: 'surface-1', value: '#141414' },
      { name: 'surface-2', value: '#1A1A1A' },
      { name: 'light',     value: '#FFFFFF' },
    ],
  },
  a11y: { config: { rules: [{ id: 'color-contrast', enabled: true }] } },
};
```

## 5. Estrutura de stories (atomic-aligned)

### 5.1 Hierarquia Storybook
```
Foundations/
  ├─ Colors           # Swatch grid de todos --color-* tokens
  ├─ Typography       # Scale showcase + family preview
  ├─ Spacing          # Visual scale
  ├─ Radius
  ├─ Elevation
  └─ Motion           # Demo de durations + easings
Atoms/
  ├─ Button           # Variants, sizes, states (default/hover/active/disabled/loading)
  ├─ Input
  ├─ Badge
  ├─ Avatar           # showcase mentor colors
  └─ ...
Molecules/
  ├─ FormField
  ├─ StatCard
  ├─ Tooltip
  └─ ...
Organisms/
  ├─ Modal            # dialog nativo + custom
  ├─ DataTable
  ├─ Sidebar
  ├─ TopNav + Breadcrumbs
  └─ PageHeader
Patterns/              # Page-level compositions (v1.2)
  ├─ Empty State
  ├─ Login Overlay
  └─ Dispatcher Wizard
```

### 5.2 Story file structure (HTML renderer)
`assets/css/primitives/atoms/button.stories.js`:
```js
export default {
  title: 'Atoms/Button',
  argTypes: {
    variant: { control: 'select', options: ['primary','secondary','ghost','danger','success'] },
    size: { control: 'select', options: ['sm','md','lg'] },
    loading: { control: 'boolean' },
    disabled: { control: 'boolean' },
    label: { control: 'text' },
  },
};

const Template = ({ variant, size, loading, disabled, label }) => `
  <button class="btn btn--${variant} btn--${size}"
          ${disabled ? 'disabled' : ''}
          ${loading ? 'aria-busy="true"' : ''}>
    ${loading ? '<span class="spinner spinner--sm"></span>' : ''}
    ${label}
  </button>
`;

export const Primary = Template.bind({});
Primary.args = { variant: 'primary', size: 'md', label: 'Disparar lembrete' };

export const AllVariants = () => `
  <div class="u-cluster u-gap-4">
    <button class="btn btn--primary">Primary</button>
    <button class="btn btn--secondary">Secondary</button>
    <button class="btn btn--ghost">Ghost</button>
    <button class="btn btn--danger">Danger</button>
    <button class="btn btn--success">Success</button>
  </div>
`;
```

### 5.3 MDX docs file (1 por primitive)
`button.mdx`:
```mdx
import { Meta, Story, Canvas, Controls } from '@storybook/blocks';
import * as ButtonStories from './button.stories.js';

<Meta of={ButtonStories} />

# Button

CTA primitive. Consome `--color-accent-emphasis`, `--radius-md`, `--space-3/4`.

## Anatomia
- Container `<button>`
- (opcional) Icon left/right
- Label

## Variants
<Canvas of={ButtonStories.AllVariants} />

## A11y
- Sempre usar `<button>` nativo (não `<div onClick>`)
- `aria-busy="true"` quando loading
- Focus ring 2px (`--color-border-focus`)
- Touch target mínimo 44x44px (sm = padding adjusts)

<Controls />
```

## 6. Naming convention de stories
- File: `<component>.stories.js`
- Default export `title`: hierarquia path (`Atoms/Button`)
- Story names: PascalCase descritivo
  - `Default` — primeiro showcase
  - `<Variant>` — `Primary`, `Secondary`, `Danger`
  - `<State>` — `Loading`, `Disabled`, `WithIcon`
  - `AllVariants` — overview side-by-side
  - `Playground` — args fully controllable (interactive)

## 7. Workflow dev → DS

```
1. Dev abre PR adicionando novo primitive
   ├─ Adiciona CSS em assets/css/primitives/<atom|molecule|organism>/foo.css
   ├─ (opcional) JS em js/primitives/foo.js
   ├─ Cria foo.stories.js (cobertura: default + variants + states)
   └─ Cria foo.mdx (docs + a11y notes)
2. CI roda: lint + build-storybook (smoke check)
3. PR review: revisor abre preview Storybook (deployed via PR)
4. Merge → main → Storybook prod redeploy
5. Dev usa primitive via classes em página existente — pode adicionar story de pattern em Patterns/
```

## 8. CI integration (v1.1)

### 8.1 GitHub Actions workflow
`.github/workflows/storybook.yml`:
```yaml
on: [push, pull_request]
jobs:
  storybook:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: 20 }
      - run: npm ci
      - run: npm run build-storybook
      - if: github.ref == 'refs/heads/main'
        uses: peaceiris/actions-gh-pages@v3
        with:
          github_token: ${{ secrets.GITHUB_TOKEN }}
          publish_dir: ./storybook-static
```
Deploy em `https://academialendaria.github.io/lesson-pages-storybook/` (ou similar).

### 8.2 Chromatic (v1.2 — diferido)
Setup `@chromatic-com/storybook` + secret `CHROMATIC_PROJECT_TOKEN`. Visual regression em PRs. **Adiar** até primitives terem estabilizado (>2 sprints sem changes estruturais).

## 9. Coverage target v1.1 launch
Foundations stories (Colors, Typography, Spacing, Radius, Elevation, Motion) + 8 atoms (Button, Input, Textarea, Select, Checkbox, Badge, Avatar, Spinner) + 4 molecules (FormField, StatCard, Tooltip, Tag) + 4 organisms (Modal, DataTable, Sidebar, PageHeader).

= **22 primitives docs** = ~2-3 dias de trabalho focado após primitives CSS implementados.

## 10. Out-of-scope explícito
- ❌ Snapshot testing v1 (defer Chromatic v1.2)
- ❌ Component performance benchmarks
- ❌ Storybook test runner (Vitest replacement) — usar tests/smoke.test.mjs existente
- ❌ i18n addon (UI é pt-BR único)
- ❌ MDX completo pra pages — só primitives recebem docs MDX
