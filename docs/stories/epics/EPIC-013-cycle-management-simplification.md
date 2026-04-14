# EPIC-013 — Simplificação da Gestão de Equipe/Ciclos

## Metadata

```yaml
epic_id: EPIC-013
title: Simplificação da gestão de equipe com edição granular preservando histórico
status: Ready
created_by: "@pm (Morgan)"
created_at: 2026-04-14
priority: High
estimated_stories: 3
```

---

## Objetivo

Eliminar o conceito de "ciclo" da UI do painel admin, substituindo por edição granular de membros da equipe. Quando o usuário troca um mentor/host, o sistema automaticamente preserva o histórico (valid_from/valid_until) sem exigir ações manuais como "Novo Ciclo" ou "Reabrir".

## Problema

O mecanismo atual de ciclos causa perda silenciosa de dados:
- `saveClassV2()` auto-fecha ciclos e recria registros — se o formulário estiver incompleto, mentores desaparecem
- "Novo Ciclo" fecha tudo e duplica para amanhã — cria gaps de 1 dia
- Editar qualquer membro fecha TODO o ciclo, poluindo o histórico
- Resultado real: PS Fundamentals ficou sem equipe ativa em 14/04/2026

## Requisito de Negócio

O calendário deve continuar mostrando corretamente quem era mentor/host em cada data. Quando há troca de equipe, o registro anterior deve ser preservado para que o calendário mostre:
- "Mentor A" nas aulas até dia X
- "Mentor B" nas aulas a partir do dia Y

## Escopo

### IN
- Refatorar `saveClassV2()` com diff granular (membro a membro)
- Remover botões "Novo Ciclo", "Reabrir" e badges de ciclo fechado
- Adicionar seção "Histórico" no card da turma
- Migration para limpar registros órfãos/inconsistentes

### OUT
- Alterações no calendário (`buildEventsFromDB`) — já funciona corretamente
- Alterações na tabela `class_mentors` (schema mantido)
- Alterações no sistema de attendance

## Stories

- [x] **13.1** — Refatorar saveClassV2 com diff granular
- [ ] **13.2** — Remover UI de ciclos e adicionar histórico visual
- [ ] **13.3** — Migration de limpeza e validação end-to-end

## Dependências

- EPIC-012 (Full Automation Pipeline) — concluído

## Riscos

| Risco | Mitigação |
|-------|-----------|
| Perda de dados históricos na migration | Migration apenas limpa órfãos, não remove registros válidos |
| Regressão no calendário | Zero alterações em buildEventsFromDB |
