# UX Audit — painel.academialendaria.ai
> Discovery Parte 1 — 2026-05-22 — by @ux-design-expert (Uma)

## 1. Inventário de telas

| Rota | Tipo | Propósito | Status |
|------|------|----------|--------|
| `/admin/` | Admin | Dashboard homescreen + view switcher (16 funcionalidades) | Ativo |
| `/admin/nps-results/` | Admin | Análise NPS pós-aula: hero score, trend chart, breakdown por cohort/classe, comentários | Ativo |
| `/admin/nps-monitor/` | Admin | **Dispatcher NPS + smoke test wizard + master switch** + config tunables + zooom map | Ativo |
| `/admin/ps-rsvp/` | Admin | RSVP pré-PS: respostas + setup turmas + grupos WA, KPIs presença | Ativo |
| `/admin/envios/` | Admin | **Histórico de envios unificado**: NPS + Lembretes + PS RSVP + Surveys + Avisos manuais | Ativo |
| `/admin/lembretes-aulas/` | Admin | **Gerador batch de lembretes**: preview, aprovação, agendamento automático | Ativo |
| `/aluno/perfil.html` | Public | Perfil aluno (nome, turma, apelido Zoom) | Ativo |
| `/aluno/aula-20260203-2100/` | Public | Conteúdo aula (gravação, resumo IA, materiais) | Ativo |

---

## 2. 🔴 Jornadas duplicadas detectadas

### 2.1 **NPS — 3 telas para mesmo fluxo**
- **Telas envolvidas**: `/admin/nps-results/` (análise detalhada) | `/admin/nps-monitor/` (dispatcher + config) | `/admin/envios/` (histórico unificado)
- **Diferenças sutis**:
  - `nps-results`: foco em **análise de dados** (NPS score, trend chart, comentários, breakdown por turma/aula, export CSV/MD)
  - `nps-monitor`: foco em **operacional** (wizard fumaça, master switch, config tunables, jobs pendentes/recentes, group verification)
  - `envios`: foco em **auditoria** (log de TODOS os envios, não apenas NPS — filtra por canal/status/tipo/período)
- **Confusão do user**: Admin precisa navegar 3 telas pra entender ciclo completo NPS. Não fica claro qual tela ir primeiro. Workflow não linear: setup → dispatch → análise → audit.

### 2.2 **Envios — 2 telas para histórico**
- **Telas envolvidas**: `/admin/envios/` (dispatch table centralizado + filtros) | `/admin/lembretes-aulas/` (batch preview + approval específico pra lembretes)
- **Diferenças sutis**:
  - `envios`: UI robusta (charts, KPIs, filters drawer, pagination), **todos os tipos de envio**
  - `lembretes-aulas`: UI minimalista (table simples), **só lembretes + setup aulas**
- **Redundância**: Lembretes pós-aprovação em `lembretes-aulas` aparecem depois em `envios` com os mesmos dados (batch_id, status, timestamp). Admin vê dados duplicados.

### 2.3 **PS RSVP — análise + setup em 2 lugares**
- **Telas envolvidas**: `/admin/ps-rsvp/` (respostas RSVP + setup cohorts + grupos WA) | `/admin/nps-results/` (aba "Pré PS RSVP" com tabela de respostas)
- **Diferenças sutis**:
  - `ps-rsvp`: foco em **operacional** (envios pendentes, setup por classe, botão "enviar pré-aula nos grupos")
  - `nps-results`: aba **PS RSVP** isolada dentro análise NPS (KPIs, tabela respostas, export)
- **Confusão**: Admin não sabe onde listar respostas PS. Duas telas servem esse mesmo dado.

---

## 3. Estado da componentização

### 3.1 **Framework UI e padrões**
- **Arquitetura**: HTML puro + CSS custom (SEM frameworks como shadcn/ui, Tailwind classes, ou Material)
- **CSS base**: 
  - `/templates/design-tokens-dark-premium.css` (164 linhas, **bem estruturado**)
  - `/templates/admin-shared.css` (270 linhas, componentes reutilizáveis)
  - Cada página HTML traz `<style>` **inline** com 300-1200 linhas de CSS específico
- **Problema**: Design tokens definidos em `:root` CSS vars, **mas largamente ignorados**. Páginas usam colors hardcoded em inline styles.

### 3.2 **Componentes detectados (duplicações)**
| Componente | Onde aparece | Variações | Status |
|-----------|-------------|----------|--------|
| **Login Overlay** | todas as 6 admin pages | Mesmo HTML, mesmo CSS, ícone/título mudam | ✅ Reutilizável |
| **Topbar** | `nps-results`, `nps-monitor`, `ps-rsvp`, `envios` | Ligeiramente diferente em cada página (links customizados) | ⚠️ Quase duplicado |
| **Modal (overlay)** | `index.html` (attendance), `envios` (dispatch detail), `nps-monitor` (6 modals), `ps-rsvp` (prebrief) | HTML estrutura similar, CSS varia 10-20% | ⚠️ Quase duplicado |
| **Data Table** | `nps-results` (4 tables), `nps-monitor` (3), `ps-rsvp`, `envios`, `lembretes-aulas` | Mesmo HTML, CSS muda (widths, spacing) | ⚠️ Quase duplicado |
| **Buttons** (btn-primary, btn-secondary, btn-tertiary) | todas | **Definidos em admin-shared.css**, mas homepage `index.html` redefine inline | ❌ Duplicado |
| **Stat Card / KPI Card** | `index.html`, `nps-monitor`, `ps-rsvp`, `envios`, `lembretes-aulas` | CSS redefinido em cada página (classes diferentes: `.kpi-card`, `.stat-card`, `.kpi-num`) | ❌ Duplicado |
| **Filter Chips** | `nps-results`, `envios` | Diferentes seletores CSS (`.chip`, `.filters-row label`) | ⚠️ Quase duplicado |
| **Sidebar / Nav** | APENAS `/admin/index.html` | Centralizado, bem feito | ✅ Único |
| **Form Inputs** | 10+ lugares | Classe `.login-field` reutilizada, mas form-specific CSS inline em cada page | ⚠️ Quase duplicado |

### 3.3 **Duplicações críticas identificadas**
1. **Button styles** redefinidos em `index.html` (inline `<style>`) vs admin-shared.css
2. **KPI/Stat cards**: 5 variações de `.kpi-card` vs `.stat-card` vs `.stat-num` vs `.kpi-val`
3. **Modal structure**: 15+ modals (attendance, dispatch detail, group verify, confirm master, variant edit, preview, job detail) — cada um com CSS inline
4. **Topbar**: 4 versões (nps-results, nps-monitor, ps-rsvp, envios) — `<header class="topbar">` com ligeiras variações

---

## 4. Design tokens — score 3/10

### 4.1 **Estado atual**
- ✅ **Cores tokenizadas**: `/templates/design-tokens-dark-premium.css` define 25+ CSS vars (backgrounds, texts, CTAs, borders)
- ✅ **Tipografia estruturada**: 7 font-sizes, 5 font-weights, 4 line-heights, 4 letter-spacings
- ✅ **Espaçamento**: 8 spacing tokens (`--spacing-xs` até `--spacing-8xl`)
- ✅ **Border radius**: 6 radius tokens
- ✅ **Transitions**: 3 timing tokens

### 4.2 **Problemas graves**
- **50%+ hardcoded colors** na inline CSS: `#0d0d0d`, `#1e1e1e`, `#222`, `#333`, `#444`, `#555`, `#666`, `#888`, `#aaa`, `#ccc`, `#ddd`, `#fff`, `rgba(x, x, x, 0.x)` aparecem em TODAS as páginas
- **Tipografia fora de token**: inline `font-size: 13px`, `font-weight: 600`, `font-family: 'Inter'` em dezenas de estilos
- **Espaçamento magic numbers**: `padding: 10px 12px`, `margin-bottom: 16px`, `gap: 8px` — não usam tokens
- **Border radius hardcoded**: `border-radius: 8px`, `border-radius: 10px`, `border-radius: 12px` em vez de vars
- **Sem nomenclatura consistente**: um botão é `.btn-primary`, outro é `.login-btn`, outro é `.btn-save`
- **Sem alias/derivative tokens**: ex: `--color-danger` deveria ser alias de `--color-text-cost` ou similar

### 4.3 **Score tokenização**: **3/10**
- Tokens existem na arquivo, mas **>60% do código ignora eles**
- Admin páginas redefinem tudo inline, criando "local design system"
- Nenhuma hierarquia ou namespace (ex: `--component-button-primary-bg`)

---

## 5. Navegação

### 5.1 **Sidebar (admin/index.html)**
- **Existe**: Sim, bem estruturado em 5 seções
  - Visão Geral (Dashboard)
  - Operações (Calendário, Turmas, Alunos, Presença Zoom, Aulas, Relatório)
  - Comunicação (Surveys, Avisos WA, Agendamentos, Feriados)
  - Customer Success (link externo)
  - Configurações (Staff, Classes, Zoom, Resumos, Automações)
  - Comunicação (repetido!) — Histórico envios, NPS Monitor, NPS Results, PS RSVP
- **Problema crítico**: "Comunicação" aparece **2x** (linhas 425 e 481), criando confusão. Links inline vs buttons em `switchView()`
- **Breadcrumbs**: Nenhum em nenhuma página ❌
- **Current page indicator**: Sidebar usa `.active` class, mas **perde quando navega pra outra page** (ex: `/admin/nps-results/` — sidebar não existe)

### 5.2 **Topbar (nps-results, nps-monitor, ps-rsvp, envios)**
- Cada página **redefine topbar** com back-link + custom action buttons
- Nenhuma breadcrumb, nenhuma "volta pra dashboard"
- Usuário entra em `/admin/nps-results/` direto, **sem contexto de onde está**

### 5.3 **Profundidade de cliques**
- Dashboard → qualquer tela: **1 click** (sidebar ou dashboard card)
- Qualquer página → página diferente: **2-3 cliques** (voltar Dashboard + acessar outra) ou **perder sidebar** (se entrar direto em URL)

---

## 6. Acessibilidade — quick wins

| Gap | Severidade | Exemplo | Fix |
|-----|-----------|---------|-----|
| **Inputs sem label associada** | Alta | Modais `/admin/index.html` (attendance edit form) | `<label for="input-id">` + `id=` no input |
| **Botões com ícones só** | Alta | Close buttons `×` em modals, refresh `↻`, logout | `aria-label="Fechar modal"` |
| **Contrast não testado** | Alta | Text `#555` ou `#666` em bg `#0d0d0d` — ratio < 4.5:1 | Paleta: `#888` minimum pra text no dark |
| **Modals sem focus trap** | Média | Modals podem sair do modal ao tab (não entra na modal stack) | `tabindex="-1"` fora, focus start ao open |
| **Selects com labels inline** | Média | Filters `/admin/envios/`: `<label>Período <input></label>` cria ambiguidade | Separar: label acima, input abaixo |
| **Tabelas sem scope** | Média | `<table>` em todas páginas, sem `scope="col"` / `scope="row"` | `scope="col"` em `<th>`, `scope="row"` em primeira `<td>` |
| **No skip-to-content** | Baixa | 500+ linhas de HTML antes de `<main>` | Adicionar `<a href="#main" class="skip-link">` no topo |

---

## 7. Recomendações top 5 pra novo Design System

### 7.1 **Prioridade URGENTE (foundation)**
1. **Design Tokens Enforcement** — Reescrever inline CSS pra usar vars. Criar:
   - Color palette aliased (danger = `--color-text-cost`, success = `--color-text-profit`, etc)
   - Spacing scale com namespace (`--space-input-padding`, `--space-card-padding`)
   - Component naming convention (`--btn-primary-bg`, `--btn-primary-hover-bg`, `--card-radius`)
   - Implement CSS layer `@layer tokens, components, overrides` pra enforce order

2. **Unified Component Library** (não precisa ser npm, pode ser CSS + HTML patterns):
   - `.button` com variantes `--primary`, `--secondary`, `--danger` (via data-attribute ou class)
   - `.input` com associated label (WCAG 2.1 AA)
   - `.modal` com slot para header/body/footer
   - `.stat-card` / `.kpi-card` (um único nome, sem duplicação)
   - `.topbar` e `.sidebar` (se novo design mantiver navegação estruturada)
   - `.data-table` com responsive wrapper

3. **Navigation Restructure**:
   - **Option A (Bold)**: Converter `/admin/*` pra query params ou view state em `/admin/?view=nps-results` — SPA-like (se mudar pra Next.js app router)
   - **Option B (Safe)**: Manter `/admin/*` mas add breadcrumb + "Back to Dashboard" em TODAS páginas, e sync sidebar state com URL
   - **Decisão crítica**: Usuario quer "layout remanufacturado" — esta é chance pra simplificar deep linking

4. **Remove Duplicate UI Patterns**:
   - `nps-results` + `nps-monitor` + `ps-rsvp` + `envios` — consolidar em **2 páginas** max:
     - `/admin/dispatch/` — configuração, monitoramento, wizard fumaça (novo `nps-monitor` + `lembretes-aulas`)
     - `/admin/insights/` — análise (novo `nps-results` + PS RSVP analytics)
   - Lembretes não precisa de página separada — é apenas tipo de envio em `/admin/dispatch/`

5. **Acessibilidade (Quick Win)**:
   - Run axe-core ou WAVE em cada página, fix top 20 issues
   - Enforce label-input associations, button aria-labels, focus management em modals
   - Audit color contrast, min `#888` pra body text em dark mode

---

## 8. Open questions — precisa da decisão do User

1. **Prioridade redesign**: Admin ou painel aluno primeiro? (Aluno só tem 2 páginas simples — parecem OK. Admin é o gargalo.)

2. **Tech stack novo**: Manter HTML puro + CSS custom? Ou migrar pra:
   - Next.js App Router + Tailwind + shadcn/ui (moderna, componentizada, design tokens built-in)?
   - Svelte + Pico CSS (minimalista)?
   - React + Vite + custom CSS-in-JS (Styled Components, Emotion)?
   - **Impacto**: Escolha aqui **define se design system é baseado em CSS vars ou component props**

3. **Consolidação de dados NPS**: 
   - Manter 3 páginas separadas (`nps-results`, `nps-monitor`, `ps-rsvp`) como *specialized views* da mesma data?
   - Ou refatorar em 1-2 dashboards que mostram diferentes slices do mesmo dataset?
   - **Impacto na navegação e componentes compartilhados**

4. **Sidebar vs Top Nav**: Admin homepage tem sidebar — as outras 6 páginas perderam ela. Redesign mantém sidebar? Migra tudo pra top nav + breadcrumbs?

5. **Dark mode only?**: Tudo é dark mode — considerar light mode switch no DS novo? (Impacta token scale — 2x de cores ou usar CSS filters?)

---

## Resumo das dores críticas (≤150 palavras)

**Layout confuso**: Admin navega entre 8 páginas sem breadcrumbs. Sidebar só existe em `/admin/` — user perde contexto ao entrar em `/admin/nps-results/` direto.

**Telas duplicadas**: 3 dashboards (nps-results, nps-monitor, envios) mostram dados NPS com overlap. PS RSVP aparece em 2 lugares. User não sabe qual tela ir.

**Componentes reescritos 10x**: Buttons, cards, inputs, modals definidos em admin-shared.css mas **redefinidos inline em cada página**. 60% hardcoded colors ignoram tokens. Impossível manter consistência.

**Design system fraco**: Tokens existem mas não são usados. Sem nomenclatura, sem hierarquia, sem enforcement. Cada página é seu próprio design system.

**Acessibilidade**: Inputs sem labels, botões sem aria-labels, modals sem focus trap, contrast ratio baixo em texto cinza.

Precisa **consolidação urgente** em 2-3 telas max + 1 unified component library baseada em tokens.
