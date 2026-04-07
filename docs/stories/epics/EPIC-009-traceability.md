# EPIC-009 — Rastreabilidade e Reporting

## Metadata

```yaml
epic_id: EPIC-009
title: Rastreabilidade e Reporting — Audit trail e export de presença
status: Ready
created_by: "@pm (Morgan)"
created_at: 2026-04-07
priority: P2
estimated_complexity: S (4 pontos)
dependency: EPIC-007 (Done)
```

---

## Visão Estratégica

O sistema não possui nenhuma forma de auditoria sobre quem vinculou participantes a alunos, nem de exportar dados de presença para stakeholders externos. Coordenadores precisam copiar dados manualmente para Excel toda vez que precisam de um relatório.

Este épico adiciona rastreabilidade básica (quem fez o quê) e exportação de presença em CSV.

---

## Problema que Resolve

| Situação Atual | Situação Alvo |
|----------------|--------------|
| Sem log de quem vinculou participante X ao aluno Y | Tooltip com "Vinculado por Admin em DD/MM" em cada vínculo |
| Relatório de presença = exportação manual para Excel | Botão "Exportar CSV" com filtros respeitados |

---

## Escopo do Épico

### IN — O que este épico entrega

- **Audit trail de vinculações**: tabela `zoom_link_audit` + tooltip em `/presenca`
- **Export CSV de presença**: botão que gera CSV com aluno, turma, total aulas, presenças, %

### OUT — O que este épico NÃO entrega

- Audit trail de todas as operações admin (muito amplo)
- Export PDF (complexidade alta, P3)
- Relatório executivo automático por ciclo

---

## Stories

| Story | Título | Prioridade | Complexidade | Dependência |
|-------|--------|-----------|-------------|------------|
| 9.1 | Audit trail de vinculações Zoom→Aluno | P2 | S (2pts) | — |
| 9.2 | Export CSV de presença por cohort | P2 | S (2pts) | — |

**Total estimado:** 4 pontos

---

## Métricas de Sucesso

- **Vinculações com histórico rastreável:** hoje 0% → alvo 100% (a partir da implementação)
- **Tempo para gerar relatório de presença:** hoje ~15min (manual) → alvo <30s

---

## Riscos

| Risco | Probabilidade | Mitigação |
|-------|-------------|-----------|
| Tabela de audit crescer muito | Baixo | Índice por student_id + data; sem purge automático por ora |
| CSV com encoding incorreto para Excel | Baixo | Usar BOM UTF-8 para compatibilidade com Excel brasileiro |
