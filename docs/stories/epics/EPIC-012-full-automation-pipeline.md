# EPIC-012 — Full Automation Pipeline: Zero Manual Operations

## Metadata

```yaml
epic_id: EPIC-012
title: Full Automation Pipeline — Daily Cron Chain, WA Group Sync, Auto-Match & Transfer
status: Done
created_by: "@pm (Morgan)"
created_at: 2026-04-08
priority: P1
estimated_complexity: L (21 pontos)
dependency: EPIC-006 (Done), EPIC-011 (Done)
```

---

## Visao Estrategica

O lesson-pages possui todas as pecas individuais para um pipeline de dados completo — importacao de reunioes Zoom, matching de participantes, transferencia para presenca, importacao de chat, notificacao de gravacoes e sync de membros WhatsApp. Porem, **todas essas operacoes sao manuais**: exigem que o coordenador entre no painel, clique botoes e execute acoes sequenciais.

Este epico transforma o sistema de "toolkit manual" para **pipeline automatico** que roda diariamente sem intervencao humana.

---

## Problema que Resolve

| Situacao Atual | Situacao Alvo |
|----------------|--------------|
| Coordenador precisa clicar "Descobrir Reunioes" manualmente todo dia | pg_cron importa reunioes automaticamente toda madrugada |
| Apos importar, precisa clicar "Rematch" e "Propagar Links" | Matching e propagacao rodam automaticamente apos import |
| Transferencia para `student_attendance` exige acao manual | Transferencia automatica encadeada apos match |
| Chat do Zoom nao e coletado automaticamente | Importacao de chat roda apos fim de cada reuniao |
| Membros de grupos WhatsApp importados manualmente via Evolution API | Edge function + cron sincroniza membros automaticamente |
| Gravacao pronta mas notificacao nao e disparada automaticamente | Webhook `recording.completed` dispara notificacao para a turma |
| Nenhuma visibilidade sobre execucoes do pipeline | Dashboard de status mostra ultima execucao e resultados |

---

## Escopo do Epico

### IN — O que este epico entrega

- pg_cron que encadeia: import meetings → import participants → match → propagate → transfer → import chat
- Edge function `sync-wa-group-members` + pg_cron diario
- Wiring completo do webhook `recording.completed` → notificacao WhatsApp
- Tabela `automation_runs` para rastrear execucoes do pipeline
- Dashboard simples no admin mostrando status das automacoes

### OUT — O que este epico NAO entrega

- Mudancas no algoritmo de matching (fuzzy Jaro-Winkler ja implementado no EPIC-011)
- Novas paginas de UI alem do dashboard de status
- Alteracoes em RLS ou seguranca (coberto por EPIC-003)
- Novos webhooks Zoom alem dos ja registrados
- Retry automatico com dead-letter queue (future — manter simples com log de erro)

---

## Arquitetura do Pipeline

```
                    ┌─────────────────────────────────────────────────┐
                    │           DAILY CRON (03:00 AM)                 │
                    │                                                 │
                    │  1. list_meetings (ultimas 24h)                │
                    │  2. import_participants (para cada meeting)     │
                    │  3. rematch_all (fuzzy + exact)                 │
                    │  4. propagate_links                             │
                    │  5. transfer_to_attendance                      │
                    │  6. import_meeting_chat (para cada meeting)     │
                    │                                                 │
                    └─────────────────────────────────────────────────┘

                    ┌─────────────────────────────────────────────────┐
                    │        WA GROUP SYNC CRON (04:00 AM)            │
                    │                                                 │
                    │  Para cada cohort com whatsapp_group_jid:       │
                    │  1. GET /group/participants via Evolution API   │
                    │  2. Normalizar telefones                        │
                    │  3. Cruzar com students existentes              │
                    │  4. INSERT novos (student + student_cohorts)    │
                    │                                                 │
                    └─────────────────────────────────────────────────┘

                    ┌─────────────────────────────────────────────────┐
                    │     EVENT-DRIVEN (Webhook triggers)             │
                    │                                                 │
                    │  recording.completed →                          │
                    │    save recording + transcript + AI summary     │
                    │    → send_recording_notification (WA)           │
                    │                                                 │
                    └─────────────────────────────────────────────────┘
```

---

## Stories

### Story 12.1 — Automation Tracking Infrastructure

**Pontos:** 2
**Prioridade:** P0 (prerequisito para todas as outras)

**Descricao:**
Criar tabela `automation_runs` e funcao helper para registrar execucoes do pipeline. Cada step do cron registra inicio, fim, status (success/error), contadores (records_processed, records_created, records_failed) e mensagem de erro quando aplicavel.

**Acceptance Criteria:**

- [x] AC1: Tabela `automation_runs` criada via migration com campos: `id`, `run_type` (enum: daily_pipeline, wa_sync, recording_notification), `step_name`, `started_at`, `finished_at`, `status` (enum: running, success, error), `records_processed`, `records_created`, `records_failed`, `error_message`, `metadata` (jsonb)
- [x] AC2: Funcao SQL `log_automation_step(run_type, step_name, status, counts, error)` disponivel para uso nas edge functions e pg_cron
- [x] AC3: Index em `(run_type, started_at DESC)` para queries de dashboard
- [x] AC4: RLS: SELECT para authenticated, INSERT/UPDATE via service_role apenas

**Technical Notes:**
- Migration file em `supabase/migrations/`
- Nao precisa de edge function — e infraestrutura pura de banco

---

### Story 12.2 — Daily Zoom Pipeline Cron

**Pontos:** 5
**Prioridade:** P1
**Dependencia:** 12.1

**Descricao:**
Criar pg_cron job que invoca a edge function `zoom-attendance` com uma nova action `daily_pipeline` as 03:00 AM. Esta action encadeia sequencialmente: `list_meetings` (ultimas 24h) → para cada meeting: `import_participants` → `rematch_all` → `propagate_links` → `transfer_to_attendance` → `import_meeting_chat`. Cada step registra resultado em `automation_runs`.

**Acceptance Criteria:**

- [x] AC1: Nova action `daily_pipeline` na edge function `zoom-attendance` que executa os 6 steps em sequencia
- [x] AC2: `list_meetings` filtrado para reunioes das ultimas 24h (parametro `from` na Zoom Dashboard API)
- [x] AC3: Se `list_meetings` retorna 0 reunioes, pipeline termina com status `success` e `records_processed=0`
- [x] AC4: `import_participants` roda para cada meeting nova encontrada (skip se ja importada)
- [x] AC5: `rematch_all` roda apos todos os imports, usando algoritmo fuzzy existente
- [x] AC6: `propagate_links` roda apos rematch para espalhar vinculos por todas reunioes
- [x] AC7: `transfer_to_attendance` roda apos propagate — insere em `student_attendance` com `ON CONFLICT DO NOTHING`
- [x] AC8: `import_meeting_chat` roda para cada meeting nova (se scope disponivel; se nao, skip com log)
- [x] AC9: Cada step registra em `automation_runs`: records_processed, records_created, records_failed
- [x] AC10: Se qualquer step falha, pipeline continua nos demais steps e registra erro
- [x] AC11: pg_cron job `daily-zoom-pipeline` criado para rodar as 03:00 AM UTC-3
- [x] AC12: Timeout da edge function configurado para 300s (pipeline pode ser longo) — *Nota: requer ajuste no Supabase Dashboard > Edge Functions > zoom-attendance > Settings > Timeout*

**Technical Notes:**
- As actions `list_meetings`, `rematch_all`, `propagate_links`, `transfer_to_attendance`, `import_meeting_chat` ja existem — esta story as orquestra
- pg_cron invoca via `net.http_post` para a edge function (mesmo padrao do `nightly-engagement-sync`)
- Considerar usar `from`/`to` date params na Dashboard API para filtrar ultimas 24h
- Se uma reuniao ja tem participants importados (check `zoom_participants` count), skip import

---

### Story 12.3 — WhatsApp Group Members Auto-Sync

**Pontos:** 5
**Prioridade:** P1
**Dependencia:** 12.1

**Descricao:**
Criar edge function `sync-wa-group-members` que consulta a Evolution API para cada cohort com `whatsapp_group_jid` definido, obtem a lista de participantes do grupo, normaliza telefones, e sincroniza com a tabela `students`. Novos membros sao criados automaticamente. pg_cron roda as 04:00 AM.

**Acceptance Criteria:**

- [x] AC1: Edge function `sync-wa-group-members/index.ts` criada em `supabase/functions/` — *Implementada como action `auto_sync` na edge function `sync-wa-group` existente*
- [x] AC2: Query `cohorts` onde `whatsapp_group_jid IS NOT NULL`
- [x] AC3: Para cada cohort, GET `{EVOLUTION_API_URL}/group/participants/{instance}?groupJid={jid}`
- [x] AC4: Normalizar telefones: remover `@s.whatsapp.net`, garantir formato `55XXXXXXXXXXX`
- [x] AC5: Para cada participante WA, buscar em `students` por telefone normalizado
- [x] AC6: Se estudante existe mas nao esta na turma → INSERT em `student_cohorts`
- [x] AC7: Se estudante nao existe → INSERT em `students` (name do perfil WA, phone, active=true) + INSERT em `student_cohorts`
- [x] AC8: Nunca duplicar: usar `UNIQUE(phone, cohort_id)` em students e unique index `(student_id, cohort_id)` em student_cohorts
- [x] AC9: Registrar em `automation_runs`: cohort_id no metadata, records_processed (total WA members), records_created (novos estudantes)
- [x] AC10: pg_cron job `wa-group-sync` criado para rodar as 04:00 AM UTC-3
- [x] AC11: Credenciais Evolution API lidas de env vars (EVOLUTION_API_URL, EVOLUTION_API_KEY, EVOLUTION_INSTANCE)
- [x] AC12: Se Evolution API retorna erro para um grupo, log e continua para o proximo

**Technical Notes:**
- Evolution API endpoint: `GET /group/participants/{instanceName}?groupJid={jid}`
- Nome do participante WA pode vir no campo `pushName` — usar como fallback se nome nao informado
- Telefone no WA: `5543999999999@s.whatsapp.net` → normalizar para `5543999999999`
- Constraint UNIQUE em `students.phone` ja existe
- Tabela `student_cohorts` com unique `(student_id, cohort_id)` — confirmar ou criar

---

### Story 12.4 — Recording Notification Auto-Trigger

**Pontos:** 3
**Prioridade:** P1
**Dependencia:** nenhuma (pode rodar em paralelo)

**Descricao:**
Garantir que o webhook `recording.completed` (ja implementado em `zoom-webhook`) dispare automaticamente a notificacao WhatsApp para a turma apos salvar a gravacao. Atualmente o fluxo salva a gravacao e gera o resumo IA, mas a notificacao precisa ser chamada manualmente. Esta story completa o wiring.

**Acceptance Criteria:**

- [x] AC1: Apos `recording.completed` salvar em `class_recordings` e gerar AI summary, chamar `send_recording_notification` automaticamente
- [x] AC2: Identificar a turma (cohort) da gravacao via `zoom_meetings.cohort_id` ou matching do meeting topic
- [x] AC3: Notificacao enviada via `send-whatsapp` edge function para todos os alunos ativos da turma
- [x] AC4: Template da mensagem inclui: titulo da aula, link da gravacao, resumo curto (primeiros 200 chars do AI summary)
- [x] AC5: Registrar em `class_recording_notifications`: recording_id, cohort_id, sent_at, status
- [x] AC6: Se cohort nao encontrado, log warning e nao envia (nao falhar silenciosamente)
- [x] AC7: Cooldown: nao enviar notificacao se ja enviou para o mesmo recording_id (idempotente)
- [x] AC8: Registrar em `automation_runs` com run_type=`recording_notification`

**Technical Notes:**
- `zoom-webhook/index.ts` ja trata `recording.completed` — adicionar chamada a `send_recording_notification` no final do handler
- `send_recording_notification` pode chamar a edge function `send-whatsapp` via `net.http_post` do Supabase ou invocacao direta
- Verificar se `class_recording_notifications` ja existe ou precisa ser criada

---

### Story 12.5 — Automation Dashboard

**Pontos:** 3
**Prioridade:** P2
**Dependencia:** 12.1, 12.2, 12.3

**Descricao:**
Adicionar uma aba "Automacoes" no painel admin que mostra o status das ultimas execucoes do pipeline. Permite visualizar rapidamente se o pipeline diario rodou, quantos registros processou, e se houve erros.

**Acceptance Criteria:**

- [x] AC1: Nova aba "Automacoes" no menu principal do admin (ao lado de Zoom, WhatsApp etc.)
- [x] AC2: Secao "Pipeline Diario" mostrando ultima execucao: data/hora, status (badge verde/vermelho), contadores por step
- [x] AC3: Secao "Sync WhatsApp" mostrando ultima execucao: turmas sincronizadas, novos alunos criados
- [x] AC4: Secao "Notificacoes de Gravacao" mostrando ultimas 5 notificacoes enviadas
- [x] AC5: Historico: tabela com ultimas 30 execucoes de cada tipo, paginada
- [x] AC6: Botao "Executar Agora" para cada pipeline (chama a edge function manualmente)
- [x] AC7: Auto-refresh a cada 60 segundos quando a pagina esta aberta
- [x] AC8: Indicador visual de "proximo agendamento" baseado no horario do cron

**Technical Notes:**
- Pagina HTML pura seguindo padrao do projeto (vanilla JS, sem framework)
- Query `automation_runs` com `ORDER BY started_at DESC LIMIT 30`
- Agrupar por `run_type` para mostrar nas secoes corretas
- Botao "Executar Agora" faz POST para a edge function correspondente com action adequada

---

### Story 12.6 — Pipeline Health Alerts

**Pontos:** 3
**Prioridade:** P2
**Dependencia:** 12.2, 12.3, 12.4

**Descricao:**
Implementar alertas automaticos via WhatsApp quando o pipeline falha ou nao roda. Se o daily pipeline nao executou ate 06:00 AM, ou se executou com erros, enviar alerta para o numero do coordenador.

**Acceptance Criteria:**

- [x] AC1: pg_cron job `pipeline-health-check` roda as 06:00 AM UTC-3
- [x] AC2: Verifica se `automation_runs` tem registro de `daily_pipeline` com `started_at` no dia corrente
- [x] AC3: Se nao encontrou execucao → envia alerta "Pipeline diario NAO executou hoje"
- [x] AC4: Se encontrou com status=error → envia alerta com step que falhou e mensagem de erro
- [x] AC5: Se encontrou com status=success → nao envia nada (silencioso quando tudo OK)
- [x] AC6: Alertas enviados via Evolution API para numero do coordenador (env var `COORDINATOR_PHONE`)
- [x] AC7: Mesma logica para `wa_sync` — alertar se nao rodou ou falhou
- [x] AC8: Registrar o proprio health check em `automation_runs` com run_type=`health_check`

**Technical Notes:**
- pg_cron pode verificar via SQL puro: `SELECT * FROM automation_runs WHERE run_type='daily_pipeline' AND started_at >= CURRENT_DATE`
- Se nao encontrar, chamar `send-whatsapp` edge function via `net.http_post`
- Manter simples — sem escalation chain, apenas 1 alerta para o coordenador

---

## Ordem de Implementacao Recomendada

```
12.1 (infra) ──→ 12.2 (zoom pipeline) ──→ 12.5 (dashboard)
                                       ──→ 12.6 (alerts)
             ──→ 12.3 (WA sync)       ──→ 12.5, 12.6

12.4 (recording notification) ──→ independente, pode rodar em paralelo
```

**Sprint sugerido:**
- Sprint 1: 12.1 + 12.4 (5 pts) — infra + quick win de notificacao
- Sprint 2: 12.2 + 12.3 (10 pts) — automacoes core
- Sprint 3: 12.5 + 12.6 (6 pts) — visibilidade e alertas

**Total: 21 story points**

---

## Riscos

| Risco | Impacto | Mitigacao |
|-------|---------|-----------|
| Timeout da edge function no pipeline completo | Pipeline incompleto | Timeout 300s + continuar em caso de erro por step |
| Evolution API fora do ar durante sync WA | Sync falha | Retry no proximo dia + alerta via health check |
| Zoom Dashboard API rate limit | Import incompleto | Backoff exponencial + processar meetings em batch |
| Notificacao de gravacao duplicada | Spam para alunos | Check idempotente em `class_recording_notifications` |
| pg_cron nao dispara (Supabase instabilidade) | Pipeline nao roda | Health check as 06h AM detecta e alerta |

---

## Metricas de Sucesso

| Metrica | Antes | Depois |
|---------|-------|--------|
| Operacoes manuais diarias do coordenador | ~6 cliques/dia | 0 (automatico) |
| Tempo para dados de presenca ficarem disponiveis | D+1 (apos acao manual) | D+0 as 03h AM |
| Novos alunos WA sem registro no sistema | Detectados manualmente | Auto-importados em < 24h |
| Notificacao de gravacao | Manual ou esquecida | Automatica em < 5min apos gravacao pronta |
| Visibilidade sobre saude do pipeline | Nenhuma | Dashboard + alerta WA |
