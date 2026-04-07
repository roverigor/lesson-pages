# EPIC-008 — Responsividade e Acesso Mobile

## Metadata

```yaml
epic_id: EPIC-008
title: Responsividade e Acesso Mobile — Calendário e Presença utilizáveis em celular
status: Ready
created_by: "@pm (Morgan)"
created_at: 2026-04-07
priority: P1
estimated_complexity: M (5 pontos)
dependency: EPIC-007 (Done)
```

---

## Visão Estratégica

Mentores e coordenadores acessam o sistema principalmente pelo celular para verificar horários, confirmar presenças e revisar participantes. Hoje o calendário é inutilizável em telas menores que 768px (grid de 7 colunas colapsa) e a tabela de presença exige scroll horizontal para completar qualquer ação.

Este épico torna os dois painéis mais usados — calendário e presença — plenamente funcionais em dispositivos móveis.

---

## Problema que Resolve

| Situação Atual | Situação Alvo |
|----------------|--------------|
| Grade mensal do calendário colapsa em mobile (7 colunas ilegíveis) | Vista semanal empilhada em mobile, legível em 375px |
| Tabela de participantes exige scroll horizontal para vincular | Cards empilhados com botão "vincular" sempre visível |
| Mentores não conseguem fazer check-in pelo celular | Todas as ações principais completáveis sem zoom/scroll horizontal |

---

## Escopo do Épico

### IN — O que este épico entrega

- **Calendário responsivo**: vista semanal em mobile (≤768px), grade mensal em desktop
- **Presença responsiva**: tabela de participantes vira cards em mobile

### OUT — O que este épico NÃO entrega

- PWA / app nativa
- Offline support
- Push notifications mobile
- Redesign completo do sistema

---

## Stories

| Story | Título | Prioridade | Complexidade | Dependência |
|-------|--------|-----------|-------------|------------|
| 8.1 | Calendário responsivo com vista semanal em mobile | P1 | M (3pts) | — |
| 8.2 | Painel de presença responsivo em mobile | P1 | S (2pts) | — |

**Total estimado:** 5 pontos

---

## Métricas de Sucesso

- **Calendário navegável em iPhone SE (375px):** hoje ❌ → alvo ✅
- **Ação de vincular participante completável sem scroll horizontal:** hoje ❌ → alvo ✅
- **Todas as ações do painel equipe completáveis em mobile:** já ✅ (manter)

---

## Riscos

| Risco | Probabilidade | Mitigação |
|-------|-------------|-----------|
| Vista semanal ocultar eventos que o usuário espera ver | Baixo | Mostrar semana atual por padrão + nav para semanas anteriores/próximas |
| Cards de presença ocuparem muito espaço vertical | Baixo | Colapsar campos secundários por padrão, expandir on-click |
