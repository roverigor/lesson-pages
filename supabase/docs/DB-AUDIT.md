# Database Audit — lesson-pages

> **Gerado por:** @data-engineer (Dara) — Brownfield Discovery, Fase 2 (atualizado)
> **Data original:** 2026-04-01
> **Ultima atualizacao:** 2026-04-06
> **Supabase project:** `gpufcipkajppykmnmdeh` (calendario-aulas)

---

## 1. Debitos CRITICOS

| ID | Debito | Severidade | Tabela(s) | Detalhes |
|----|--------|-----------|-----------|----------|
| DB-C1 | **Tabela `classes` sem schema file** | CRITICO | classes | Referenciada por class_cohorts, class_mentors, zoom_meetings, notifications. Nao ha DDL documentado em nenhum migration ou schema file. Schema inferido do codigo JS. |
| DB-C3 | **Telefones reais no seed** | ALTO | mentors | 14 numeros de telefone reais hardcoded na migration baseline |
| DB-C4 | **WhatsApp JIDs no seed** | ALTO | cohorts | Group JIDs reais hardcoded na migration baseline |
| DB-NEW-C1 | **`notifications.evolution_message_ids` e `delivered_at` sem DDL** | CRITICO | notifications | `delivery-webhook` usa `.contains("evolution_message_ids", [msgId])` e `update({delivered_at: ...})` mas essas colunas nao existem em nenhum schema file ou migration. Possivel que a tabela em producao tenha as colunas mas sem documentacao — estado desconhecido. |
| DB-NEW-C2 | **`notifications.status` CHECK constraint nao inclui `delivered` e `read`** | CRITICO | notifications | O `delivery-webhook` atualiza `status` para `'delivered'` e `'read'`, mas o CHECK constraint da coluna (`pending`, `processing`, `sent`, `partial`, `failed`, `cancelled`) nao inclui esses valores. Se o CHECK esta ativo em producao, **TODAS as atualizacoes do delivery-webhook FALHAM silenciosamente** — confirmacoes de entrega nunca sao registradas. |

> **NOTA:** DB-C2 (SERVICE_ROLE_KEY no frontend) foi **RESOLVIDO** — ver Secao 7.

---

## 2. Debitos de Schema

| ID | Debito | Severidade | Detalhes |
|----|--------|-----------|----------|
| DB-S1 | **`attendance.lesson_date` como TEXT** | MEDIO | Deveria ser DATE para queries por intervalo, ordenacao e comparacao. Formato atual nao e validado. |
| DB-S2 | **`attendance.teacher_name` como TEXT (desnormalizado)** | MEDIO | Referencia mentor por nome livre, nao por FK para `mentors`. Impossibilita joins e causa inconsistencias com renomeacoes. |
| DB-S3 | **`classes.professor` e `classes.host` como TEXT** | MEDIO | Campos legados — `class_mentors` ja resolve o relacionamento com FK. Ambos convivem sem policy de deprecacao. |
| DB-S4 | **`students.name DEFAULT ''`** | BAIXO | Permite alunos sem nome no banco sem erro. |
| DB-S5 | **Sem tabela `class_recordings` no schema** | MEDIO | Codigo referencia `class_recordings` mas nao ha DDL. |
| DB-S6 | **`zoom_meeting_id` como TEXT vs BIGINT** | BAIXO | Zoom IDs sao numericos; TEXT pode causar comparacoes erradas (ordenacao lexicografica). |
| DB-NEW-M1 | **`notification_schedules` sem schema file documentado** | MEDIO | Tabela existe e esta operacional (EPIC-002 Done), mas o DDL completo nao esta em nenhum schema file de referencia — apenas na migration baseline. |

---

## 3. Debitos de Indexes

| ID | Debito | Severidade | Detalhes |
|----|--------|-----------|----------|
| DB-I1 | **Sem index em `notifications.processed_at`** | BAIXO | Queries de auditoria e monitoramento de filas nao otimizadas. |
| DB-I2 | **Sem composite index `attendance(course, lesson_date)`** | BAIXO | Queries por curso + data nao otimizadas. |
| DB-NEW-L1 | **`notification_schedules.last_triggered_at` sem index** | BAIXO | O pg_cron job `process_notification_schedules()` filtra por `last_triggered_at` periodicamente. Sem index, cada execucao faz seq scan na tabela. |

---

## 4. Debitos de RLS

| ID | Debito | Severidade | Detalhes |
|----|--------|-----------|----------|
| DB-R1 | **RLS uniforme "admin-only write"** | MEDIO | Nao ha roles intermediarios (mentor, host). Mentores nao conseguem registrar propria presenca sem ser admin. |
| DB-R2 | **Sem RLS para `classes`** | ALTO | Tabela sem schema file = sem RLS documentado. Qualquer usuario autenticado pode ler; escrita nao controlada. |
| DB-R3 | **`zoom_tokens` acessivel a qualquer admin** | MEDIO | Tokens OAuth de mentores deveriam ser scoped por `mentor_id` — admin pode ver tokens de qualquer mentor. |

---

## 5. Debitos de Edge Functions

| ID | Debito | Severidade | Detalhes |
|----|--------|-----------|----------|
| DB-E1 | **Credenciais Zoom hardcoded como fallback** | CRITICO | `zoom-oauth`: `client_id`/`secret`; `zoom-attendance`: credenciais S2S. Fallback no codigo fonte = exposicao em historico git. |
| DB-E2 | **Evolution API credentials hardcoded** | CRITICO | `send-whatsapp`: URL, API key e nome da instancia hardcoded. |
| DB-E3 | **CORS: `Access-Control-Allow-Origin: *`** | ALTO | Todas as 3 Edge Functions aceitam requisicoes de qualquer origem. |
| DB-E4 | **Sem rate limiting** | MEDIO | Edge Functions sem protecao contra abuso ou DDoS. |
| DB-E5 | **Sem retry backoff exponencial** | BAIXO | `send-whatsapp` tem `retry_count` mas sem exponential backoff — retries podem sobrecarregar Evolution API. |

---

## 6. Debitos de Migrations

| ID | Debito | Severidade | Detalhes |
|----|--------|-----------|----------|
| DB-M1 | **Schema files avulsos em `db/` nao sao migrations Supabase CLI** | ALTO | Os arquivos em `db/` sao SQL manuais, sem controle de versao via `supabase migration`. A unica migration real e a baseline `20260402175137_notifications_schema.sql`. |
| DB-M2 | **Sem `supabase/config.toml`** | MEDIO | Impossibilita reproducao do ambiente local com `supabase start`. |
| DB-M3 | **Ordem de execucao manual** | MEDIO | `notifications-schema` depende de `classes` (sem DDL). Execucao fora de ordem causaria falha. |
| DB-M4 | **Seeds com dados reais na migration baseline** | ALTO | Telefones e JIDs reais na migration `20260402175137` — expostos no historico git. Ver DB-C3 e DB-C4. |

---

## 7. Debitos RESOLVIDOS (desde 2026-04-01)

| ID | Debito Original | Resolucao | Data |
|----|----------------|-----------|------|
| DB-C2 | **SERVICE_ROLE_KEY exposta no frontend** | Chave removida de `presenca/index.html` e demais paginas publicas (SYS-C1) | ~2026-04-03 |
| EPIC-001 | **Tabelas mentors, class_cohorts, class_mentors, notifications ausentes** | Criadas e operacionais com DDL documentado | 2026-04-01 |
| EPIC-002 | **Sem agendamento de notificacoes** | `notification_schedules` + pg_cron instalado + `process_notification_schedules()` criada | 2026-04-04 |
| SYS-H4 | **CDN sem pin de versao** | CDN pinado para versao fixa | ~2026-04-03 |

> **Nao resolvidos:** DB-C3 e DB-C4 (seeds com dados reais) ainda estao abertos — os dados existem na migration baseline `20260402175137`.

---

## 8. Resumo

| Categoria | Critico | Alto | Medio | Baixo | Total |
|-----------|---------|------|-------|-------|-------|
| Schema / DDL | 3 | 0 | 4 | 2 | 9 |
| Seguranca | 2 | 2 | 0 | 0 | 4 |
| RLS | 0 | 1 | 2 | 0 | 3 |
| Edge Functions | 2 | 1 | 1 | 1 | 5 |
| Migrations | 0 | 2 | 2 | 0 | 4 |
| Indexes | 0 | 0 | 0 | 3 | 3 |
| **TOTAL** | **7** | **6** | **9** | **6** | **28** |

> **Debitos criticos ativos:** DB-C1, DB-C3\*, DB-C4\*, DB-NEW-C1, DB-NEW-C2, DB-E1, DB-E2
> \*Dados em producao — seeds nao sao revertidos automaticamente.

---

*Documento mantido por @data-engineer (Dara) — Synkra AIOX Brownfield Discovery*
*Proximo review recomendado: apos confirmacao do estado das colunas `evolution_message_ids` e `delivered_at` em producao*
