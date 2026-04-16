# EPIC-014 — Fechamento de Gaps de Automação do Pipeline

## Metadata

```yaml
epic_id: EPIC-014
title: Fechamento de gaps de automação — presença de staff, overrides, alertas e transcrições
status: Draft
created_by: "@pm (Morgan)"
created_at: 2026-04-16
priority: P1
estimated_stories: 4
dependency: EPIC-012 (Done)
```

---

## Objetivo

O EPIC-012 automatizou o pipeline principal (Zoom → presença alunos, chat, engagement). Porém, durante validação em 2026-04-16, foram identificados 4 gaps que impedem a automação completa:

1. Presença do professor/host não é sincronizada automaticamente do Zoom para o relatório
2. O staff reminder diário não consulta `schedule_overrides` (pode divergir do calendário)
3. O alerta de ausência para alunos (`send_absence_alerts`) existe mas não está agendado
4. Transcrições de gravações históricas não podem ser importadas em batch

---

## Problema

| Situação Atual | Situação Alvo |
|----------------|--------------|
| Presença do professor no Zoom requer ação manual no admin | Cron diário marca presença de mentores automaticamente |
| Staff reminder ignora overrides de agenda | Reminder consulta `schedule_overrides` como o frontend |
| Nenhum aluno é alertado sobre faltas consecutivas | Alunos com 2+ faltas recebem mensagem automática |
| Transcrições antigas não têm resumo AI | Comando para importar e gerar resumos em batch |

---

## Stories

- [ ] **14.1** — Auto sync presença de staff do Zoom para relatório
- [ ] **14.2** — Incorporar schedule_overrides no staff reminder
- [ ] **14.3** — Agendar alerta de ausência para alunos no cron
- [ ] **14.4** — Import batch de transcrições históricas com resumo AI
