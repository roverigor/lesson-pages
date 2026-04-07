# EPIC-006 — Zoom Intelligence: Presença Automática e Engajamento

## Metadata

```yaml
epic_id: EPIC-006
title: Zoom Intelligence — Presença Automática, Dashboard e Alertas de Engajamento
status: Ready
created_by: "@pm (Morgan)"
created_at: 2026-04-07
priority: P1
estimated_complexity: XL (21+ pontos)
dependency: EPIC-005 (Done)
```

---

## Visão Estratégica

O sistema Zoom atual está sólido na fundação — coleta dados, faz matching e registra presença. Mas o processo todo é **manual e reativo**: o admin precisa clicar para importar cada reunião, e nenhuma inteligência é gerada a partir dos dados coletados.

Este épico transforma o Zoom de "ferramenta de registro" para **sistema de inteligência de engajamento** da Academia Lendária. O objetivo é que, ao terminar uma aula, a plataforma já saiba quem esteve presente, quem faltou, e tome ação proativa.

---

## Problema que Resolve

| Situação Atual | Situação Alvo |
|----------------|--------------|
| Admin faz 4 cliques por reunião para importar presença | Presença registrada automaticamente ao fim de cada aula |
| Mentor não sabe quem está sumindo da turma | Dashboard com radar de alunos em risco |
| Aluno não sabe sua própria taxa de presença | Aluno vê presença em /perfil |
| Aluno falta 3 semanas e ninguém avisa | Alerta automático no WhatsApp após 2 faltas consecutivas |
| Nomes unmatched dependem de intervenção admin | Aluno pode se identificar em self-service |

---

## Escopo do Épico

### IN — O que este épico entrega

- **Importação automática** de participantes quando `meeting.ended` chega via webhook
- **Dashboard de presença** por turma para mentores/admin (taxa, alunos em risco, evolução)
- **Presença visível para o aluno** em /perfil (X de Y aulas, % de presença)
- **Alerta WhatsApp automático** ao aluno após 2 faltas consecutivas
- **"Sou eu" para alunos** — self-service de identificação de nomes unmatched

### OUT — O que este épico NÃO entrega

- Coleta de `attentiveness_score` (verificar disponibilidade da API Zoom antes de planejar)
- Relatório exportável por ciclo (P3 — future epic)
- Integração com Cal.com para cruzar presença com agendamentos
- Modificações no algoritmo de matching (coberto por EPIC-005)

---

## Stories

| Story | Título | Prioridade | Complexidade | Dependência |
|-------|--------|-----------|-------------|------------|
| 6.1 | Importação Automática de Participantes Pós-Aula | P1 | M (5pts) | — |
| 6.2 | Dashboard de Presença por Turma | P1 | M (5pts) | 6.1 |
| 6.3 | Aluno Vê Própria Presença em /perfil | P2 | S (3pts) | 6.1 |
| 6.4 | Alerta WhatsApp por Ausência Consecutiva | P1 | M (5pts) | 6.1 |
| 6.5 | "Sou eu" para Alunos Unmatched | P2 | M (5pts) | 6.1 |

**Total estimado:** 23 pontos

---

## Dependências Externas

- **EPIC-005 Done** ✅ — matching de mentores e aliases funcionando
- **Evolution API** — já integrada no sistema (EPIC-001), necessária para Story 6.4
- **Zoom webhook `meeting.ended`** — já recebido pelo zoom-webhook, necessário para Story 6.1
- **`student_attendance` table** — já existe e populada, base para Stories 6.2, 6.3, 6.4

---

## Métricas de Sucesso

- **Tempo médio para presença disponível após aula:** hoje ~24h (manual) → alvo <5min (automático)
- **Taxa de cobertura de presença:** % de reuniões importadas / total de reuniões realizadas → alvo 100%
- **Alunos em risco identificados proativamente:** hoje 0 → alvo: todos os alunos com <60% presença notificados
- **Intervenções manuais de importação:** hoje N por semana → alvo 0

---

## Riscos

| Risco | Probabilidade | Mitigação |
|-------|-------------|-----------|
| Webhook `meeting.ended` não chegar (Zoom delay/falha) | Médio | pg_cron de fallback importa reuniões das últimas 24h não processadas |
| Matching errado na importação automática (sem revisão humana) | Baixo | Guardrails existentes são conservadores — prefere não matchear a matchear errado |
| Alerta WhatsApp percebido como spam | Baixo | Limite de 1 mensagem por ciclo de ausência; tom cuidadoso |
| `attentiveness_score` descontinuado pela Zoom | Alto | Fora do escopo deste épico — avaliar separadamente |

---

## Ordem de Execução Recomendada

```
6.1 (automação) → 6.2 (dashboard) em paralelo com 6.3 (aluno/perfil)
                → 6.4 (alertas WhatsApp)
                → 6.5 (self-service alunos)
```

6.1 é o fundamento — as demais dependem dos dados chegarem automaticamente.
