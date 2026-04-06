## UX Specialist Review — lesson-pages

> **Revisado por:** @ux-design-expert (Uma)
> **Data:** 2026-04-06
> **Base:** technical-debt-DRAFT.md + análise de estrutura de arquivos

---

### Parecer Geral

O lesson-pages entrega valor funcional real: o sistema de notificações WhatsApp opera, o calendário está acessível e os fluxos de presença e zoom funcionam. O problema não é ausência de funcionalidade — é que o crescimento foi orgânico e acelerado, resultando em um frontend que acumula complexidade estrutural silenciosamente.

O risco principal não é estético: é de manutenibilidade. O `admin.html` com 2844 linhas de JS/CSS inline representa um gargalo de produtividade imediato — qualquer mudança de comportamento exige navegação por um arquivo monolítico sem separação de responsabilidades. O `abstracts/index.html` com ~4800 linhas hardcoded é um problema diferente: é conteúdo que deveria estar no banco, e cada atualização de turma exige edição manual de HTML — alto risco de erro humano e baixa escalabilidade.

O que funciona bem: os design tokens existem (`--accent`, `--bg-primary`, etc.) e há uma intenção clara de sistema visual. O problema é que esses tokens não são aplicados consistentemente — cada página reinventa seu próprio CSS.

---

### Débitos Validados

| ID | Débito | Severidade | Horas | Prioridade | Impacto UX |
|---|---|---|---|---|---|
| UX-C1 | `admin.html` com 2844 linhas — monolito JS/CSS inline | CRÍTICO (manutenção) | 20h | P1 — próximo ciclo | Cada bugfix ou feature nova leva 2-3x mais tempo; risco alto de regressão |
| UX-H1 | Zero consistência visual — cada página tem CSS independente | ALTO | 16h | P2 | Experiência fragmentada; usuário percebe inconsistência mesmo sem verbalizar |
| UX-H2 | `abstracts/index.html` ~4800 linhas hardcoded | ALTO | 8h | P2 | Atualização manual de conteúdo = risco de erro; não escala para novas turmas |
| UX-H3 | Sem estados de loading padronizados | ALTO | 4h | P2 | Usuário não sabe se ação foi processada; percepção de sistema lento ou travado |
| UX-H4 | Sem error handling visual padronizado | ALTO | incluído em UX-H3 | P2 | Erros silenciosos ou mensagens de console que o usuário nunca vê |
| UX-M1 | Design tokens existem mas não são aplicados | MÉDIO | incluído em UX-H1 | P2 | Quick win: aplicar tokens existentes antes de criar design system novo |
| UX-M2 | Responsividade não garantida | MÉDIO | 4h | P3 | Mentores acessam via mobile; falhas de layout em telas menores |
| UX-M3 | Páginas duplicadas (`aios-install` vs `aiox-install`) | MÉDIO | 1h | P3 | Confusão de navegação; risco de manter conteúdo desatualizado em uma das versões |
| UX-M4 | Backup files no repo | BAIXO | 0.5h | P4 | Poluição de repositório; sem impacto direto no usuário |

---

### Débitos Adicionados

| ID | Débito | Severidade | Horas | Notas |
|---|---|---|---|---|
| UX-NEW-A1 | Ausência de feedback visual para ações críticas (envio de WhatsApp, marcação de presença) | ALTO | 3h | Operações assíncronas não comunicam resultado ao admin; o usuário não sabe se a ação foi bem-sucedida sem verificar logs |
| UX-NEW-A2 | Falta de confirmação antes de ações destrutivas no admin | MÉDIO | 2h | Ações como cancelar notificação ou remover participante não têm modal de confirmação |

---

### Respostas ao Architect

**Q: O `admin.html` deveria ser quebrado agora ou numa fase futura?**

A: **Fase futura, após resolver os débitos de segurança (Fase 1).** O monolito atual é funcional — ele não está causando falhas visíveis para o usuário final hoje. Quebrar o `admin.html` em componentes é um refactor de alto esforço (20h) com risco de introduzir regressões se feito em paralelo com correções de segurança críticas. A sequência correta é: (1) resolver credenciais hardcoded e schema crítico primeiro, (2) então abordar o refactor do admin como uma story dedicada com testes de smoke antes e depois. O custo de não fazer a separação agora é pagável — o custo de introduzir bugs no admin enquanto resolve segurança não é.

---

### Recomendações de Design

#### Quick Wins (sem refatoração estrutural — Fase 1/2, baixo risco)

1. **Aplicar design tokens existentes** nas páginas que os ignoram: substituir hex colors hardcoded por variáveis CSS já definidas. Impacto visual imediato com risco zero de regressão.
2. **Adicionar feedback visual para envio de WhatsApp**: um spinner simples + mensagem "Enviando..." + confirmação "Enviado ✓" no botão de disparo de notificações. Resolve UX-NEW-A1 para o fluxo mais crítico sem refatoração.
3. **Estados de loading para queries Supabase**: adicionar `opacity: 0.5; pointer-events: none` no container enquanto aguarda resposta. Pattern simples, replicável em todas as páginas em ~1h por página.
4. **Resolver páginas duplicadas** (`aios-install` vs `aiox-install`): decidir qual é canônica, redirecionar a outra, remover backup files.

#### Fase Futura (requer planejamento dedicado)

5. **Design System unificado**: criar `css/design-system.css` com os tokens já existentes + componentes base (botões, inputs, cards, badges, modais). Cada página passa a importar esse arquivo em vez de redefinir estilos.
6. **Componentização do admin.html**: separar em módulos lógicos — `admin-presenca.js`, `admin-notificacoes.js`, `admin-turmas.js` — mantendo HTML como shell simples.
7. **Abstracts DB-driven**: mover conteúdo do `abstracts/index.html` para tabela no Supabase com template HTML mínimo. Admin consegue atualizar conteúdo sem tocar em código.
8. **Modal de confirmação padrão**: componente reutilizável para todas as ações destrutivas.

---

### Estimativa Total UX

| Categoria | Débitos | Horas | Custo (R$150/h) |
|---|---|---|---|
| Quick wins (Fase 1/2) | UX-NEW-A1 parcial, tokens, duplicatas | 3h | R$ 450 |
| Altos — loading/error states | UX-H3, UX-H4, UX-NEW-A1 completo, UX-NEW-A2 | 9h | R$ 1.350 |
| Design System | UX-H1, UX-M1 | 16h | R$ 2.400 |
| Admin refactor | UX-C1 | 20h | R$ 3.000 |
| Abstracts DB-driven | UX-H2 | 8h | R$ 1.200 |
| Responsividade + limpeza | UX-M2, UX-M3, UX-M4 | 5.5h | R$ 825 |
| **Total** | **11 débitos** | **61.5h** | **R$ 9.225** |

> **Nota:** O refactor do `admin.html` (20h) e o design system (16h) respondem por 59% do esforço total de UX. Ambos têm alto valor de manutenibilidade a longo prazo, mas podem ser postergados sem impacto funcional imediato.
