# EPIC-010 — Aulas e Gravações Automatizadas

## Metadata

```yaml
epic_id: EPIC-010
title: Aulas e Gravações — Coleta automática, IA e distribuição de conteúdo
status: Ready
created_by: "@pm (Morgan)"
created_at: 2026-04-07
priority: P1
estimated_complexity: XL (18 pontos)
dependency: EPIC-006 (Done)
```

---

## Visão Estratégica

O painel `/aulas` existe mas está praticamente vazio — apenas 1 aula com materiais cadastrados. O motivo é simples: todo o processo é manual. Ninguém lembra de copiar o link da gravação do Zoom, escrever o resumo da aula e subir os slides depois de cada sessão.

Este épico automatiza o ciclo completo de pós-aula: captura automática das gravações via webhook Zoom, geração de resumo via IA, notificação automática aos alunos e interface de upload para materiais complementares.

---

## Problema que Resolve

| Situação Atual | Situação Alvo |
|----------------|--------------|
| 1 de N aulas com materiais cadastrados | 100% das aulas com gravação automática |
| Resumos de aula inexistentes | Resumo gerado por IA em < 2 min após a aula |
| Alunos não sabem quando a gravação está disponível | WhatsApp automático quando gravação fica disponível |
| Slides/materiais sem interface de upload | Upload de PDFs/slides diretamente no painel |
| Sem visão de completude do conteúdo | Dashboard para admin ver o que falta por aula |

---

## Escopo do Épico

### IN — O que este épico entrega

- **Coleta automática de gravações** via webhook `recording.completed` do Zoom
- **Resumo IA** gerado a partir do transcript usando OpenAI (ou edge function com Anthropic)
- **Upload de materiais** (slides, PDFs) com storage no Supabase Storage
- **Notificação WhatsApp** quando a gravação fica disponível para os alunos
- **Dashboard de completude** para admin visualizar o que falta por aula

### OUT — O que este épico NÃO entrega

- Player de vídeo customizado (link para Zoom Cloud, não hospedagem)
- Transcrição em português (usa transcript do Zoom, se disponível)
- Integração com outros provedores de conferência (apenas Zoom)
- Edição do resumo gerado pela IA (apenas leitura por alunos)

---

## Stories

| Story | Título | Prioridade | Complexidade | Dependência |
|-------|--------|-----------|-------------|------------|
| 10.1 | Coleta automática de gravações Zoom | P1 | M (5pts) | webhook Zoom configurado |
| 10.2 | Resumo IA da aula via transcript | P1 | M (4pts) | 10.1 |
| 10.3 | Upload de materiais da aula (slides/PDFs) | P2 | S (3pts) | — |
| 10.4 | WhatsApp quando gravação disponível | P1 | S (3pts) | 10.1 |
| 10.5 | Dashboard de completude de conteúdo | P2 | S (3pts) | 10.1 |

**Total estimado:** 18 pontos

---

## Dependências Externas

- **Zoom Webhook** — `recording.completed` event deve estar habilitado no Zoom App
- **Zoom Cloud Recordings API** — `GET /meetings/{meetingId}/recordings`
- **Anthropic API** (claude-haiku-4-5 ou superior) — para geração de resumo
- **Evolution API** — já integrada, para notificação WhatsApp
- **Supabase Storage** — para upload de materiais (bucket `class-materials`)
- **`class_recordings` table** — já existe, campos: recording_date, title, cohort_id, summary, transcript_text, video_url, audio_url, duration_minutes

---

## Métricas de Sucesso

- **% aulas com gravação disponível:** hoje ~5% → alvo 100% após nova temporada
- **Tempo médio para gravação disponível após aula:** hoje indefinido → alvo < 30 min
- **Alunos notificados quando gravação fica disponível:** hoje 0 → alvo 100% com opt-in

---

## Riscos

| Risco | Probabilidade | Mitigação |
|-------|-------------|-----------|
| Gravação Zoom não disponível imediatamente após reunião | Alta | Delay de 15-30 min + retry; webhook tenta depois |
| Transcript não disponível (reunião sem transcrição ativada) | Média | Resumo IA é opcional; campo nullable em class_recordings |
| Storage Supabase com limite free tier | Baixa | PDFs/slides são pequenos; monitorar uso |
| WhatsApp spam se enviado múltiplas vezes | Baixa | Controle de envio único por recording_id (igual ao EPIC-006 anti-spam) |

---

## Ordem de Execução Recomendada

```
10.1 (coleta automática) → 10.2 (resumo IA) paralelo com 10.4 (WhatsApp)
                        ↓
                   10.3 (upload) e 10.5 (dashboard) — independentes, podem ser paralelos
```
