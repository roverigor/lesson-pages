# EPIC-007 — Estabilidade e Confiança do Admin

## Metadata

```yaml
epic_id: EPIC-007
title: Estabilidade e Confiança do Admin — Segurança, UX e Qualidade de Operação
status: Ready
created_by: "@pm (Morgan)"
created_at: 2026-04-07
priority: P1
estimated_complexity: L (8 pontos)
dependency: EPIC-006 (Done)
```

---

## Visão Estratégica

O sistema possui um painel de administração funcional e bem integrado, mas que opera sem guardrails de segurança para operações críticas. Deletar uma turma, enviar uma notificação WhatsApp errada ou deixar a sessão de um mentor aberta em dispositivo compartilhado são riscos reais de operação cotidiana.

Este épico resolve os bloqueadores de confiança do painel — não são features novas, são correções de comportamento que tornam o sistema **seguro para uso em produção por múltiplos operadores**.

---

## Problema que Resolve

| Situação Atual | Situação Alvo |
|----------------|--------------|
| Delete de turma/mentor sem confirmação — 1 clique apaga tudo | Modal de confirmação obrigatório em operações destrutivas |
| WhatsApp vai direto ao vivo sem preview com dados reais | Botão "Testar" envia para número de teste com variáveis interpoladas reais |
| Sessão de mentor salva em localStorage sem expiração | Sessão com expiração de 8h via Supabase Auth |
| Modal de dia no calendário não mostra horário da aula | Hora de início/fim visível em todos os modais de sessão |

---

## Escopo do Épico

### IN — O que este épico entrega

- **Confirmação em deletes**: modal de confirmação em todas as operações destrutivas do admin
- **Test send de WhatsApp**: envio de teste para número fixo com interpolação real de variáveis
- **Sessão segura para mentores**: JWT com expiração via Supabase Auth (substitui localStorage puro)
- **Horário em modais**: hora de início e fim de cada aula nos modais do calendário

### OUT — O que este épico NÃO entrega

- Audit trail completo de mudanças (planejado no EPIC-009)
- Refatoração completa do sistema de auth (fora do escopo — apenas sessão com expiração)
- Export de dados ou relatórios (EPIC-009)
- Modificações no algoritmo de matching de Zoom

---

## Stories

| Story | Título | Prioridade | Complexidade | Dependência |
|-------|--------|-----------|-------------|------------|
| 7.1 | Confirmação em operações destrutivas no admin | P1 | S (1pt) | — |
| 7.2 | Test send de notificação WhatsApp com dados reais | P1 | S (2pts) | — |
| 7.3 | Sessão segura com expiração para mentores | P1 | M (3pts) | — |
| 7.4 | Horário de início e fim em modais do calendário | P2 | S (2pts) | — |

**Total estimado:** 8 pontos

---

## Dependências Externas

- **Supabase Auth** — já habilitado no projeto, necessário para Story 7.3
- **Evolution API** — já integrada, necessária para Story 7.2 (test send)
- **`classes.start_time` / `classes.end_time`** — colunas já existem, necessárias para Story 7.4

---

## Métricas de Sucesso

- **Deletes acidentais reportados:** hoje N/A (sem log) → alvo 0 após Epic
- **Notificações enviadas com formatação errada:** → 0 (preview com dados reais)
- **Sessões de mentor ativas em dispositivo compartilhado > 8h:** → 0
- **Coordenadores que sabem o horário da aula sem navegar para outra página:** → 100%

---

## Riscos

| Risco | Probabilidade | Mitigação |
|-------|-------------|-----------|
| Migração para Supabase Auth quebrar login de mentores existentes | Médio | Manter fallback RPC por 1 semana; migração gradual |
| Test send atingir grupo errado se número de teste não for respeitado | Baixo | Hardcode do número de teste no backend (não configurável via UI) |

---

## Ordem de Execução Recomendada

```
7.1 (confirmação) e 7.4 (horários) — independentes, podem ser paralelos
7.2 (test send) — independente
7.3 (sessão segura) — maior esforço, executar por último
```
