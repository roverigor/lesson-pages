# Frontend Specification — lesson-pages

> **Gerado por:** @architect (Aria) — Análise de Débitos UX/UI
> **Data:** 2026-04-06
> **Projeto:** lesson-pages (Plataforma Educacional AIOS Avançado — Cohort 2026)
> **Escopo:** Especificação completa do frontend para base de análise e priorização de refatoração

---

## 1. Visão Geral do Frontend

**lesson-pages** é um site educacional estático com ~36 arquivos HTML, sem framework de frontend, sem bundler e sem sistema de componentes. Todo código HTML, CSS e JS é inline por página. A plataforma atende três perfis de usuário distintos (admin, mentor, aluno) em páginas separadas, sem roteamento SPA.

### Características fundamentais

- **Paradigma:** Multi-page application (MPA) clássica — uma URL por página
- **CSS:** `<style>` inline por arquivo HTML; sem folhas de estilo compartilhadas (exceto o design tokens não adotado)
- **JS:** `<script>` inline por arquivo HTML; funções duplicadas entre páginas
- **Auth:** Supabase Auth com verificação de `user_metadata.role` no carregamento de cada página protegida
- **Tema visual:** Dark premium (`#0a0a0a` / `#111` base, `#00d4ff` accent)
- **Linha de código total (frontend):** ~15.000+ linhas entre os arquivos HTML principais

---

## 2. Páginas e seus Propósitos

| URL | Arquivo | Audiência | Auth necessária | Supabase | Linhas |
|---|---|---|---|---|---|
| `/` | `index.html` | Todos | Não | Não | 239 |
| `/calendario` | `calendario/index.html` | Público | Não | Sim (leitura) | 811 |
| `/calendario/admin` | `calendario/admin.html` | Admin | Sim (admin) | Sim (leitura + escrita) | 2.844 |
| `/presenca` | `presenca/index.html` | Mentor / Admin | Sim | Sim | 963 |
| `/alunos` | `alunos/index.html` | Admin | Sim (admin) | Sim | 616 |
| `/aulas` | `aulas/index.html` | Admin | Sim (admin) | Sim | 318 |
| `/escala` | `escala/index.html` | Admin | Sim (admin) | Sim | 690 |
| `/abstracts` | `abstracts/index.html` | Aluno / Mentor | Não | Não | 4.973 |
| `/avaliacao` | `avaliacao/index.html` | Aluno | Não | Não | — |
| `/equipe` | `equipe/index.html` | Público | Não | Não | — |
| `/relatorio` | `relatorio/index.html` | Admin | Sim (admin) | Sim | — |
| `/aula-01` | `aula-01/page-aluno.html` | Aluno | Não | Não | — |
| `/aula-preparatorio` | `aula-preparatorio/page-aluno.html` | Aluno | Não | Não | — |
| `/ps-10-02-2026` | `ps-10-02-2026/index.html` | Aluno | Não | Não | — |
| `/ps-pronto-socorro` | `ps-pronto-socorro/page-aluno.html` | Aluno | Não | Não | — |
| `/aios-install` | `aios-install/index.html` | Aluno | Não | Não | — |
| `/aiox-install` | `aiox-install/index.html` | Aluno | Não | Não | — |
| `/ai-cli-tools` | `ai-cli-tools/index.html` | Aluno | Não | Não | — |
| `/manual-aios` | `manual-aios/index.html` | Aluno | Não | Não | — |
| `/kestra` | `kestra/index.html` | Aluno | Não | Não | — |
| `/openclaw` | `openclaw/index.html` | Aluno | Não | Não | — |
| `/analise-interna` | `analise-interna/index.html` | Interno | Sim | Sim | — |
| `/squad-creator` | `squad-creator/index.html` | Admin | Sim | Sim | — |
| `/cohort-fundamentals-c3` | `cohort-fundamentals-c3/index.html` | Aluno | Não | Não | — |
| `/api/zoom/callback` | `api/zoom/callback.html` | Sistema (OAuth) | Não | Sim | — |
| `/interno/aula-01` | `interno/aula-01/index.html` | Mentor | Sim | Sim | — |
| `/interno/ps-10-02-2026/faq` | `interno/ps-10-02-2026/faq.html` | Interno | Sim | Não | — |
| `/interno/ps-10-02-2026/glossario` | `interno/ps-10-02-2026/glossario.html` | Interno | Sim | Não | — |
| `/interno/ps-10-02-2026/qa-completa` | `interno/ps-10-02-2026/qa-completa.html` | Interno | Sim | Não | — |

> ⚠️ Páginas duplicadas identificadas: `ps-10-02-2026` + `ps-pronto-socorro`; `aios-install` + `aiox-install` (ver UX-M3).

---

## 3. Design System Atual

### Tokens CSS Definidos

O arquivo `design-tokens-dark-premium.css` define a seguinte paleta (não importado universalmente):

```css
/* Cores base */
--bg-primary:    #0a0a0a
--bg-secondary:  #111111
--bg-card:       #1a1a2e
--bg-elevated:   #16213e

/* Accent */
--accent-primary: #00d4ff
--accent-secondary: #7b2fff

/* Texto */
--text-primary:   #ffffff
--text-secondary: #a0a0b0
--text-muted:     #606070

/* Status */
--success: #00ff88
--warning: #ffaa00
--error:   #ff4466
--info:    #00d4ff

/* Tipografia */
--font-family: 'Inter', sans-serif
--font-size-xs: 0.75rem
--font-size-sm: 0.875rem
--font-size-md: 1rem
--font-size-lg: 1.125rem
--font-size-xl: 1.25rem
--font-size-2xl: 1.5rem
--font-size-3xl: 1.875rem

/* Espaçamento */
--spacing-xs: 4px
--spacing-sm: 8px
--spacing-md: 16px
--spacing-lg: 24px
--spacing-xl: 32px
--spacing-2xl: 48px

/* Border radius */
--radius-sm: 6px
--radius-md: 12px
--radius-lg: 16px
--radius-full: 9999px
```

### Uso Real vs Tokens

| Aspecto | Situação Real |
|---|---|
| Cores | Cada página define seus próprios valores hex — `#0a0a0a`, `#111`, `#1a1a2e` repetidos inline sem usar `var()` |
| Tipografia | `font-family: 'Inter', sans-serif` repetido inline em cada `<style>` |
| Espaçamento | Valores `px` hardcoded por página (ex: `padding: 20px`, `gap: 16px`) — sem tokens |
| Border radius | `border-radius: 8px`, `12px`, `16px` por página — sem tokens |
| Status colors | `#00ff88`, `#ff4466` hardcoded inline — sem tokens |

> ⚠️ UX-M1: Os tokens existem mas não estão sendo aplicados. O visual é consistente por acidente (valores copiados), não por sistema.

---

## 4. Padrões de Layout

### O que funciona

| Padrão | Descrição |
|---|---|
| **Dark premium** | Paleta escura consistente entre páginas — visualmente coerente |
| **Cards com borda** | `border: 1px solid rgba(255,255,255,0.1)` + `border-radius` — padrão replicado bem |
| **Header fixo** | Barra de navegação no topo com logo + links — presente nas páginas principais |
| **Tabelas de dados** | Tabelas HTML estilizadas com `thead` destacado e linhas `hover` — funciona em desktop |
| **Botões de ação** | CTA com `background: linear-gradient(...)` e efeito `hover` — identidade visual clara |

### O que é inconsistente

| Problema | Ocorrência |
|---|---|
| **Padding de cards** | Varia entre `16px`, `20px`, `24px` e `32px` sem critério |
| **Tamanho de fonte** | `h1` varia de `1.5rem` a `2.5rem` por página |
| **Espaçamento entre seções** | `margin-bottom` de `20px` a `60px` — sem sistema |
| **Indicadores de loading** | Alguns usam spinner CSS, outros alteram texto do botão, a maioria não tem nada |
| **Mensagens de erro** | Alguns usam `alert()` nativo, outros criam `div` inline, a maioria ignora erros silenciosamente |
| **Formulários** | Sem padrão de validação; cada página implementa do zero |
| **Responsividade** | Inconsistente — algumas páginas usam `@media`, outras não |

---

## 5. Fluxos de Usuário Principais

### Admin Flow

```
Login (Supabase Auth)
    │
    ▼
index.html (hub)
    │
    ├─► /calendario/admin
    │       ├─ Gestão de aulas (CRUD)
    │       ├─ Gestão de cohorts (CRUD)
    │       ├─ Gestão de mentores (CRUD)
    │       ├─ Envio de notificações WhatsApp (manual)
    │       └─ Agendamento de notificações (pg_cron)
    │
    ├─► /presenca
    │       ├─ Selecionar aula + buscar participantes Zoom
    │       └─ Confirmar presença / ausência
    │
    ├─► /alunos
    │       └─ Listar / buscar alunos por cohort
    │
    ├─► /escala
    │       └─ Visualizar escala de mentores por semana
    │
    └─► /relatorio
            └─ Relatórios de presença e NPS
```

### Mentor Flow

```
Login (Supabase Auth, role=mentor)
    │
    ▼
index.html
    │
    ├─► /presenca
    │       ├─ Conectar conta Zoom (OAuth)
    │       └─ Registrar presença da própria aula
    │
    └─► /interno/aula-*
            └─ Materiais internos da aula
```

### Aluno Flow (sem auth)

```
Link direto ou /calendario (público)
    │
    ├─► /abstracts (conteúdo das aulas — hardcoded)
    ├─► /aula-01, /aula-preparatorio (página da aula)
    ├─► /ps-pronto-socorro (material de pronto-socorro)
    ├─► /aios-install (guia de instalação)
    └─► /avaliacao (NPS / CSAT — Tally embed)
```

---

## 6. Responsividade

| Página | Status responsivo | Observação |
|---|---|---|
| `index.html` | Parcial | Grid com `flex-wrap`, legível em mobile |
| `calendario/index.html` | Parcial | Tabela semanal scroll horizontal em mobile |
| `calendario/admin.html` | Não responsivo | 2844 linhas sem media queries adequadas; colunas quebram |
| `presenca/index.html` | Parcial | Formulário legível; tabela de participantes com overflow |
| `alunos/index.html` | Parcial | Lista funcional em mobile |
| `abstracts/index.html` | Sim | Conteúdo textual — responsivo por natureza |
| `escala/index.html` | Não responsivo | Grade semanal — não usável em mobile |
| Páginas de aula (`aula-01`, etc.) | Sim | Conteúdo simples, funciona em mobile |

**Avaliação geral:** Páginas de conteúdo (aluno) são acidentalmente responsivas. Páginas de gestão (admin) não são.

---

## 7. Acessibilidade

Estado atual: **não auditado formalmente**. Observações visuais:

| Critério | Estado |
|---|---|
| Contraste de cores | Provavelmente adequado (fundo escuro + texto branco) — não verificado via ferramentas |
| Labels em formulários | Ausentes em vários inputs — `placeholder` usado como substituto de `<label>` |
| Atributos ARIA | Não utilizados |
| Navegação por teclado | Não testada |
| Alt text em imagens | Ausente (onde existem imagens) |
| Foco visível | CSS de foco padrão suprimido em vários lugares |
| Skip links | Ausentes |
| Headings hierarchy | Inconsistente — vários `h1` por página, saltos de heading level |

---

## 8. Performance Frontend

### Carregamento

| Recurso | Estratégia atual | Impacto |
|---|---|---|
| Supabase JS | CDN `@2` sem versão fixada | Cache pode ser inválido em updates |
| Lucide Icons | CDN `@0.511.0` (pinado) | Carregado mesmo em páginas que não usam ícones |
| Google Fonts (Inter) | CDN externo | Bloqueante; sem `font-display: swap` consistente |
| CSS | Inline por página | Sem cache entre páginas; sem minificação |
| JS | Inline por página | Sem cache; sem minificação; lógica duplicada |
| Imagens | Poucas; sem lazy loading | Impacto baixo atualmente |

### Ausências notáveis

- Sem minificação de HTML/CSS/JS
- Sem compressão de assets (Gzip é feito pelo Nginx, mas sem pré-compressão)
- Sem preload de recursos críticos
- Sem service worker / cache offline
- Sem bundle splitting (irrelevante hoje, mas bloqueio para crescimento)

---

## 9. Débitos UX/UI Identificados

| ID | Débito | Severidade | Impacto | Horas estimadas |
|---|---|---|---|---|
| **UX-C1** | `admin.html` com 2.844 linhas — monolito JS/CSS inline impossível de manter. Todo o painel admin (calendário, cohorts, mentores, notificações, agendamentos) está em um único arquivo sem separação de responsabilidades. | 🔴 Crítico | Cada mudança no admin exige navegar 2844 linhas; risco de regressão alto; revisão de código inviável | 40–80h |
| **UX-H1** | Zero consistência visual entre páginas. Cada arquivo tem seu próprio `<style>` com valores hardcoded. Mesmo o visual "consistente" é por cópia manual, não por sistema. | 🟠 Alto | Qualquer mudança de design requer editar ~36 arquivos. Uma cor de botão diferente por página passa despercebida. | 20–40h |
| **UX-H2** | `abstracts/index.html` com ~4.973 linhas de conteúdo 100% hardcoded em HTML. Atualização de conteúdo exige deploy. Sem busca, sem filtro, sem versioning. | 🟠 Alto | Impossível atualizar conteúdo sem desenvolvedor. Não escala para novos cohorts. | 16–24h |
| **UX-H3** | Sem estados de loading padronizados. Cada página implementa diferente (ou não implementa). Usuário não tem feedback durante queries Supabase. | 🟠 Alto | UX confusa; usuário clica múltiplas vezes pensando que não funcionou; erros silenciosos | 8–12h |
| **UX-H4** | Sem error handling visual padronizado. Erros de rede, auth e Supabase tratados de forma inconsistente — alguns com `alert()`, outros silenciosos, outros com `console.error()` apenas. | 🟠 Alto | Usuários não sabem quando algo falhou; suporte difícil sem mensagens de erro visíveis | 8–12h |
| **UX-M1** | Sem design system real. Os tokens CSS existem no arquivo `design-tokens-dark-premium.css` mas não são importados nas páginas. Tokens não são usados em nenhum `var()`. | 🟡 Médio | Inconsistências visuais acumulam; impossível fazer mudança global de tema | 12–20h |
| **UX-M2** | Responsividade não garantida em páginas de gestão. `admin.html` e `escala/index.html` não têm media queries adequadas para mobile. | 🟡 Médio | Inutilizável em smartphones para admins/mentores em campo | 6–10h |
| **UX-M3** | Páginas duplicadas no repositório: `ps-10-02-2026/` e `ps-pronto-socorro/` (mesmo conteúdo); `aios-install/` e `aiox-install/` (mesmo guia). Conteúdo pode divergir silenciosamente. | 🟡 Médio | Confusão de usuários; SEO duplicado; manutenção dobrada | 2–4h |
| **UX-M4** | Arquivos de backup no repositório (`page-aluno-backup.html` em `aula-01/`). Não servem nenhum propósito em produção. | 🟡 Médio | Poluição do repositório; confusão sobre qual é o arquivo correto | 1h |
| **UX-L1** | Sem SEO básico. Meta tags `description`, `og:title`, `og:image` ausentes na maioria das páginas. Título da aba não descritivo em várias páginas. | 🟢 Baixo | Impacto baixo para plataforma fechada; relevante se houver landing pages públicas | 3–5h |

### Resumo por Severidade

| Severidade | Quantidade | Horas totais estimadas |
|---|---|---|
| 🔴 Crítico | 1 | 40–80h |
| 🟠 Alto | 4 | 32–48h |
| 🟡 Médio | 4 | 21–35h |
| 🟢 Baixo | 1 | 3–5h |
| **Total** | **10** | **96–168h** |

---

## 10. Recomendações de Priorização

Para o próximo ciclo de desenvolvimento, a ordem recomendada de endereçamento dos débitos é:

1. **UX-H3 + UX-H4** (loading + error handling): Alto impacto com esforço relativamente baixo. Criar `js/ui-utils.js` com funções `showLoading()`, `hideLoading()`, `showError()`, `showSuccess()` e adotar em todas as páginas.

2. **UX-M1** (design tokens): Criar `css/design-system.css` e importar nas páginas. Substituir valores hardcoded por `var()`. Esforço médio, benefício de longo prazo enorme.

3. **UX-H2** (abstracts hardcoded): Criar tabela `abstracts` no Supabase e migrar conteúdo. Elimina 4.973 linhas de HTML.

4. **UX-C1** (admin.html monolito): Separar em múltiplos arquivos HTML por seção (notificações, cohorts, classes, mentores) ou modularizar via `<template>` + JS loader. É o maior débito técnico UX do projeto.

5. **UX-M3** (duplicados): Quick win — consolidar em 1–2h.

---

*Documento gerado por @architect (Aria) — Synkra AIOX v2.0*
*Próxima revisão: após implementação de UX-H3 e UX-M1*
