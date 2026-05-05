# ADR-015: Tech Stack do Repo `cs-portal`

**Status:** Accepted
**Date:** 2026-05-04
**Deciders:** @architect (Aria), informado por @pm (Morgan), @qa (Quinn)
**Context:** EPIC-015 — Área CS Dedicada (Spec Pipeline Phase 6 — Plan)
**Resolves:** Critique CRIT-1

---

## 1. Contexto

EPIC-015 introduz repositório separado `cs-portal` para autonomia do time de CS (CON-13, NFR-20). Repo deve permitir:

1. CS team trabalhar com Claude Code próprio sem acesso ao painel admin (`lesson-pages`)
2. Reuso direto do design system existente (`design-tokens-dark-premium.css`, `admin-shared.css`)
3. Build/deploy independente em container Docker dedicado (`:3081` na VPS Contabo)
4. Form builder com drag-drop (Story 15.6) — requer biblioteca de DnD ou implementação custom
5. SPA-like UX para tabs (Dashboard, Cohorts, Alunos, Forms, Pendentes, Disparos, Histórico, Integrações)
6. Curva de aprendizado mínima — CS team não é dev senior

## 2. Opções Consideradas

### Opção A — Vanilla JS + esbuild + ES Modules + SortableJS

**Pró:**
- Alinhamento total com `lesson-pages/admin/` atual (14 módulos JS plain em `js/admin/`)
- Reuso ZERO-FRICTION de `design-tokens-dark-premium.css` + `admin-shared.css` (CSS @import)
- Bundle minúsculo (~30 KB total estimado para 8 telas)
- Zero curva de aprendizado para Claude Code do CS — leitura direta de HTML/JS
- esbuild = configuração trivial (1 arquivo, ~10 linhas)
- SortableJS para drag-drop = ~10 KB, API simples, sem peer deps
- Sem virtual DOM, sem framework runtime — debugging direto no browser DevTools
- Article IV (No Invention): pattern já existe e funciona

**Contra:**
- Estado UI tem que ser gerenciado manualmente (sem reactivity)
- Forms complexos (builder) exigem mais código boilerplate vs Vue/React
- Sem JSX/template syntax — concatenação de strings ou `<template>` tags

### Opção B — Vue 3 + Vite + SortableJS

**Pró:**
- Reactivity built-in simplifica form builder dynamic state
- Single File Components (.vue) organizados
- Vite HMR rápido, DX ótima
- Comunidade ampla, docs em pt-BR

**Contra:**
- Bundle ~80 KB runtime + Vue ecosystem
- CS team precisa aprender Composition API + reactivity primitives
- Reuso de CSS exige envolver em `<style scoped>` ou desabilitar scoping
- Quebra de padrão atual do projeto — lesson-pages é puro vanilla
- Mais um stack para Claude Code do CS estudar antes de iterar

### Opção C — React + Vite + SortableJS

**Pró:**
- Ecosystem mais amplo
- TypeScript first-class

**Contra:**
- Bundle maior (~140 KB com React DOM)
- JSX exige build step + curva de aprendizado
- State management exige Context/Redux/Zustand
- Maior complexidade para o uso simples necessário
- Quebra ainda mais o padrão do projeto

## 3. Decisão

**Adotamos Opção A — Vanilla JS + esbuild + ES Modules + SortableJS.**

### Stack Final

| Camada | Tecnologia | Versão Pinned | Bundle Cost |
|---|---|---|---|
| Bundler | esbuild | `^0.21.0` | dev-only |
| Drag-drop | SortableJS | `^1.15.0` | ~10 KB |
| Auth client | @supabase/supabase-js | `^2.39.0` (mesmo lesson-pages) | ~30 KB |
| Module system | ES Modules nativo | — | 0 KB |
| CSS | Plain CSS + @import design tokens | — | reuso direto |
| HTTP | Fetch API nativo | — | 0 KB |
| Forms validation | Zod-light alternative ou custom | TBD | <5 KB |
| Total runtime | — | — | **~45 KB** |

### Estrutura de Repo

```
cs-portal/
├── Dockerfile
├── nginx.conf                      # serve static + proxy edge functions Supabase
├── package.json                    # esbuild + sortablejs + supabase-js
├── esbuild.config.js               # ~10 linhas, bundle multi-entry
├── public/
│   ├── index.html                  # SPA shell + sidebar
│   ├── login.html                  # redirect-only (auth real é em /admin/login)
│   └── assets/
│       └── design-tokens.css       # symlink ou copy de lesson-pages
├── src/
│   ├── main.js                     # entry, hash router
│   ├── shared/
│   │   ├── supabase-client.js      # init Supabase
│   │   ├── auth-guard.js           # role check 'cs' OR 'admin'
│   │   ├── api.js                  # wrappers para edge functions
│   │   └── utils.js
│   ├── pages/
│   │   ├── dashboard.js
│   │   ├── cohorts.js              # Story 15.2
│   │   ├── students.js             # Story 15.3
│   │   ├── dispatch.js             # Story 15.4
│   │   ├── forms-list.js           # Story 15.6
│   │   ├── forms-builder.js        # Story 15.6 (DnD via SortableJS)
│   │   ├── pending.js              # Story 15.F
│   │   ├── history.js              # Story 15.7
│   │   └── integrations.js         # Story 15.D + 15.E
│   └── styles/
│       └── cs-shared.css           # estilos CS-only + import design tokens
├── .github/
│   └── workflows/
│       └── deploy.yml              # build + push Docker + SSH deploy
├── CLAUDE.md                       # regras Claude Code CS team
└── README.md
```

### Build Pipeline

```bash
# Dev local
npm run dev   # esbuild --watch + serve

# Produção
npm run build # esbuild bundle → public/dist/
docker build -t cs-portal .
```

### Routing

Hash-based router (`#/cohorts`, `#/forms`) em ~30 linhas de JS. Não precisa server-side routing — nginx serve `index.html` para todas rotas client-side.

### Reuso de Design Tokens

`cs-portal` consome via:

```css
/* cs-portal/src/styles/cs-shared.css */
@import url('https://painel.igorrover.com.br/css/design-tokens-dark-premium.css');
@import url('https://painel.igorrover.com.br/css/admin-shared.css');
```

Alternativa offline (preferida): copia tokens via build step `npm run sync-tokens` que faz fetch e salva em `public/assets/`. Versão imutável snapshot — não quebra se lesson-pages mudar.

## 4. Consequências

### Positivas

- ✅ Curva aprendizado CS team Claude Code = zero (mesma stack)
- ✅ Bundle menor que opções B/C → load mais rápido
- ✅ Reuso máximo design system + utility functions
- ✅ Article IV honrado — pattern existente
- ✅ Debugging direto, sem source maps complexos
- ✅ Migração futura para framework é trivial se necessário

### Negativas Aceitas

- ⚠️ Form builder exige mais código manual de state — mitigação: criar utility `createReactiveStore()` minimal (~50 linhas)
- ⚠️ Não há tipagem TypeScript — mitigação: JSDoc opcional para crítico
- ⚠️ Reactivity manual em `forms-builder.js` — mitigação: padrão event-driven simples (subscribe/publish)

### Riscos Endereçados

- **R-Tech-1 — Form builder code complexity:** mitigação via biblioteca minimalista de "reactive store" interna (~50 LoC)
- **R-Tech-2 — DOM updates verbosos:** mitigação via helpers `el(tag, props, children)` minimal (~30 LoC)

## 5. Implementation Notes

### Story 15.J Bootstrap deve incluir:

1. `package.json` com deps: `esbuild`, `sortablejs`, `@supabase/supabase-js`
2. `esbuild.config.js` com multi-entry build
3. `Dockerfile` 2-stage: build → nginx alpine serve static
4. `.github/workflows/deploy.yml` com SSH deploy para VPS Contabo porta 3081
5. `CLAUDE.md` próprio com regras: NÃO modificar `supabase/migrations/*` (esse fica em lesson-pages)
6. Sync-tokens script: fetch design tokens em build time
7. `index.html` shell + sidebar HTML estático
8. Hash router minimal em `main.js`
9. Auth guard chamando Supabase Auth + valida role

### Padrões Obrigatórios

- ES Modules (`import`/`export` nativo, sem CommonJS)
- Async/await > .then chains
- Constants em UPPER_CASE em arquivo `shared/constants.js`
- Funções exportadas nomeadas (não default exports — facilita refactor)
- Sem framework reactivity — usar event listeners + manual DOM diff quando precisar

## 6. Alternativas Futuras

Se em V2 form builder ficar grande demais para vanilla:
- Migrar APENAS `forms-builder.js` para Lit-element (~5 KB) ou Alpine.js (~14 KB) sem refazer resto

Se time CS crescer e DX virar gargalo:
- Avaliar Astro 5 (islands) — permite vanilla + componentes interativos isolados sem refazer

## 7. References

- Spec: `docs/stories/EPIC-015-cs-area/spec/spec.md` §4.6
- Critique: `docs/stories/EPIC-015-cs-area/spec/critique.json` CRIT-1
- Lesson-pages admin pattern: `lesson-pages/admin/index.html` + `lesson-pages/js/admin/`
- Constitution Article IV (No Invention): `.aiox-core/constitution.md`
- SortableJS: https://sortablejs.github.io/Sortable/
- esbuild: https://esbuild.github.io/
