# Frontend Spec — lesson-pages (Brownfield Discovery Fase 3)

> **Data:** 2026-04-13
> **Agente:** @ux-design-expert (Uma)

---

## 1. Stack Frontend

- **HTML/CSS/JS vanilla** — sem framework
- **Design system:** `design-tokens-dark-premium.css` (dark theme premium)
- **Fontes:** Inter (Google Fonts CDN)
- **Supabase JS SDK:** v2.39.0 (CDN)
- **Responsividade:** Parcial (media queries em algumas paginas)

---

## 2. Problemas de UX Identificados

### UX1 — Navegacao Fragmentada (ALTO)

O sistema nao tem uma estrutura de navegacao unificada. Cada pagina tem seu proprio header e links. O admin tenta centralizar tudo, mas usa iframes para 4 views, o que causa:

- Scroll duplo (iframe + parent)
- URL nao muda (impossivel compartilhar deep link)
- Sessao desconectada entre parent e iframe
- Back button nao funciona dentro do iframe

**Mapa de navegacao atual:**
```
index.html (links manuais)
  ├── /admin (SPA manual)
  │     ├── [iframe] /alunos
  │     ├── [iframe] /presenca
  │     ├── [iframe] /aulas (nao existe mais?)
  │     └── [iframe] /relatorio
  ├── /turma (standalone)
  ├── /calendario (standalone)
  ├── /equipe (standalone)
  └── /perfil (standalone)
```

### UX2 — Login Repetitivo (MEDIO)

Coordenador que navega de `/turma` para `/presenca` precisa logar novamente (sessao Supabase e compartilhada via localStorage, mas o overlay aparece antes de verificar). Algumas paginas checam `getSession()` antes de mostrar overlay, outras nao.

### UX3 — Inconsistencia Visual (MEDIO)

- `showToast` tem 10 implementacoes diferentes com comportamentos sutilmente distintos
- `MENTOR_COLORS` tem 8 cores em utils.js e 15 em config.js — mesma pessoa pode ter cor diferente
- Login overlay CSS e reescrito inline em 8 paginas (template existe mas ninguem importa)
- Algumas paginas usam `admin-shared.css`, outras nao

### UX4 — turma/detalhe.html Monolito (ALTO)

2.358 linhas em um unico arquivo com:
- ~150 linhas de CSS inline
- ~200 linhas de HTML
- ~2.000 linhas de JS

9 tabs com logica complexa (presenca, WA matching, fontes, surveys). Impossivel manter, testar ou reusar componentes.

### UX5 — Paginas de Conteudo Desatualizadas (BAIXO)

Varias paginas parecem ser de iteracoes anteriores do produto:
- `analise-interna/` (9.075 LOC — maior arquivo do projeto, analise GPS/ML)
- `cohort-fundamentals-c3/` (pagina de cohort especifico)
- `aula-01/`, `aula-preparatorio/`, `ps-10-02-2026/` (aulas especificas)

Nao esta claro se ainda sao usadas ou se sao artefatos historicos.

---

## 3. Padrao de Componentes Reutilizaveis

### O que existe (templates/)

| Arquivo | LOC | Adocao |
|---------|-----|--------|
| `design-tokens-dark-premium.css` | 400 | ~18 paginas (quase universal) |
| `admin-shared.css` | 270 | 4 paginas |
| `login-overlay.css` | 19 | **0 paginas** (morto) |
| `utils.js` | 41 | 3 paginas |

### O que deveria existir

| Componente | Duplicado em | Proposta |
|-----------|-------------|---------|
| Login overlay (HTML+CSS+JS) | 8 paginas | `templates/login-component.js` |
| showToast | 10 lugares | `templates/utils.js` (ja existe, ninguem usa) |
| Supabase init (URL+key) | 6 paginas hardcoded | `js/config.js` (ja existe, ninguem usa) |
| MENTOR_COLORS | 4 lugares | `templates/utils.js` (unificar) |
| generateDates/fmtDate | 6 lugares | `templates/utils.js` (unificar) |
| nameMatch | 3 lugares | Extrair para `templates/utils.js` |

---

## 4. Responsividade

| Pagina | Mobile | Observacao |
|--------|--------|-----------|
| admin/index.html | Parcial | Sidebar colapsa, tabelas overflow |
| turma/detalhe.html | Parcial | Tabs scrollam, tabelas overflow |
| calendario/index.html | Bom | Grid responsivo |
| Paginas de conteudo | Bom | Layout simples |
| presenca/index.html | Fraco | Tabela larga sem scroll horizontal |

---

## 5. Acessibilidade

| Aspecto | Status |
|---------|--------|
| Semantica HTML | Fraco — divs em vez de nav, main, section |
| ARIA labels | Ausente |
| Contraste | Adequado (dark theme com bom contraste) |
| Keyboard nav | Parcial (tabs nao focaveis via keyboard) |
| Screen reader | Nao testado |

---

*Documento gerado por @ux-design-expert (Uma) — Brownfield Discovery Fase 3*
