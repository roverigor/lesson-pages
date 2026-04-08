# EPIC-010 — Student Life: Turma como Hub, Perfil 360, NPS Tokenizado e Engagement Intelligence

## Metadata

```yaml
epic_id: EPIC-010
title: Student Life — Hub de turma, Perfil 360, NPS tokenizado, WhatsApp + Zoom chat monitoring
status: Ready
created_by: "@pm (Morgan)"
created_at: 2026-04-07
priority: P1
estimated_complexity: XXL (34+ pontos)
dependency: EPIC-006 (Done), EPIC-007 (Done)
```

---

## Decisões de Produto (registradas em sessão com Igor — 07/04/2026)

| Decisão | Escolha |
|---------|---------|
| NPS anônimo ou identificado? | Identificado via token — sem aviso ao aluno (anonimato nunca foi prometido) |
| Quem vê NPS individual? | Coordenador + Mentores da turma. Aluno NÃO acessa próprio perfil |
| Escopo do perfil 360? | Apenas dados do ecossistema atual (sem Cal.com, sem notas manuais por ora) |
| Tela de turma | Página separada (`/turma/[slug]`) — não dentro do admin existente |
| Prioridade | Ambos (perfil + NPS tokenizado) são P1 simultâneos |
| WhatsApp group monitoring | ✅ Incluído — capturar mensagens de grupo via Evolution API `messages.upsert` |
| Zoom chat monitoring | ⚠️ Pendente — requer scope `chat_message:read` no S2S app Zoom (a confirmar) |
| Granularidade ranking WA | Mensagens brutas por dia (contagem diária) |
| Período do ranking | Diário — ranking atualizado uma vez por dia pelo cron noturno |
| Cron de atualização | pg_cron roda entre 02h–04h AM: coleta Zoom chat do dia anterior + agrega WA |
| Visibilidade do ranking | Apenas coordenador e mentor — alunos não acessam o dashboard |

---

## Visão Estratégica

As turmas são o centro operacional da Academia Lendária, mas hoje não existe uma interface que as coloque como hub. Coordenadores navegam entre `/presenca`, `/calendario` e `/equipe` para montar manualmente a visão de um aluno.

Este épico cria três produtos novos integrados:
1. **Página de Turma** — hub central com alunos matriculados, presença agregada, rankings de engajamento e navegação para perfis individuais
2. **Perfil 360 do Aluno** — visão completa: aulas, presença, avaliações NPS, participação no grupo WhatsApp e chat do Zoom
3. **NPS Tokenizado** — link único por aluno/ciclo enviado via WhatsApp, resposta atribuída automaticamente sem login
4. **Engagement Intelligence** — monitoramento de participação nos grupos WhatsApp da turma e chat das reuniões Zoom

---

## Problema que Resolve

| Situação Atual | Situação Alvo |
|----------------|--------------|
| Coordenador monta visão do aluno manualmente em 3 painéis | 1 clique no nome do aluno → tudo visível |
| NPS anônimo — não há como saber quem avaliou o quê | Token único no link → resposta atribuída ao aluno automaticamente |
| Turma é só uma entrada no banco, não um hub navegável | `/turma/[slug]` mostra alunos, presença, rankings e atalhos de ação |
| Taxa de resposta de NPS incerta — aluno precisa informar dados | Um clique do WhatsApp → form pronto → submit → atribuído |
| Nenhum dado de participação no grupo WhatsApp da turma | Mensagens por aluno no grupo capturadas automaticamente via Evolution API |
| Nenhum dado de participação no chat das aulas Zoom | Chat da reunião capturado via Zoom API (dependente de scope) |
| Ranking de engajamento inexistente | Top alunos por presença + atividade WhatsApp visível na página da turma |

---

## Escopo do Épico

### IN — O que este épico entrega

- Página `/turma/[slug]` com lista de alunos, presença, rankings (presença + WhatsApp) e acesso ao perfil individual
- Página de Perfil 360 do Aluno (coordenador/mentor apenas): presença, NPS, participação WA, chat Zoom
- Geração de token único por aluno + ciclo/turma para NPS
- Form de NPS com token na URL (one-time use, expira em 7 dias)
- Atribuição automática de resposta NPS ao aluno no perfil 360
- Captura de mensagens no grupo WhatsApp da turma via Evolution API (`messages.upsert`)
- Ranking de engajamento: presença nas aulas + atividade no grupo WhatsApp
- Captura de chat das reuniões Zoom (condicional — depende de scope `chat_message:read`)

### OUT — O que este épico NÃO entrega

- Acesso do aluno ao próprio perfil
- Integração com Cal.com ou notas manuais de mentores
- Export PDF de perfil individual
- Sistema de alertas automáticos baseados em NPS baixo (future)
- Análise de conteúdo/sentimento das mensagens (apenas contagem)
- Moderação de grupo WhatsApp

---

## Stories

| Story | Título | Prioridade | Complexidade | Dependência | Status |
|-------|--------|-----------|-------------|------------|--------|
| 10.1 | Página de Turma — hub com alunos, presença e rankings | P1 | M (5pts) | — | Ready |
| 10.2 | Perfil 360 do Aluno — presença, histórico e avaliações | P1 | M (5pts) | 10.1 | Ready |
| 10.3 | NPS tokenizado — geração de link único por aluno/ciclo | P1 | M (5pts) | 10.2 | Ready |
| 10.4 | Form de NPS com token (one-time use, expira 7 dias) | P1 | S (3pts) | 10.3 | Ready |
| 10.5 | Atribuição de resposta NPS ao perfil 360 do aluno | P1 | S (3pts) | 10.4 | Ready |
| 10.6 | WhatsApp group monitoring — captura e ranking de participação | P1 | M (5pts) | 10.1 | Ready |
| 10.7 | Zoom chat monitoring — captura de mensagens por reunião | P1 | M (5pts) | 10.6 | Ready ✅ |
| 10.8 | Perfil 360 completo — WA + Zoom chat + NPS integrados | P1 | S (3pts) | 10.5, 10.6 | Ready |

**Total estimado:** 34 pontos (10.7 condicional ao scope Zoom)

### ✅ Story 10.7 — Desbloqueada

Zoom chat in-meeting acessível via `GET /report/meetings/{meetingId}/chat`.
Usa `report:read:admin` — scope já presente e testado no `debug_scopes` da função `zoom-attendance`.
Igor confirmou: app tem acesso total com relatórios incluindo chat.

---

## Arquitetura de Dados

```
classes
  └── cohort_students (alunos matriculados)
       └── student_attendance (presença por sessão)

nps_tokens (nova tabela)
  ├── id (uuid PK)
  ├── student_id → students
  ├── class_id → classes
  ├── cohort_id → cohorts
  ├── token (text UNIQUE — slug curto ex: "x7k2p9")
  ├── used (boolean default false)
  ├── used_at (timestamptz)
  ├── expires_at (timestamptz — sent_at + 7 dias)
  └── sent_at (timestamptz)

survey_responses (já existe — verificar schema antes de Story 10.3)
  └── nps_token_id → nps_tokens (FK nova)
       → permite JOIN para identificar respondente

whatsapp_group_messages (nova tabela — Story 10.6)
  ├── id (uuid PK)
  ├── group_jid (text — JID do grupo WhatsApp)
  ├── sender_phone (text — normalizado, ex: 5543999...)
  ├── student_id (uuid REFERENCES students — nullable, mapeado por phone)
  ├── cohort_id (uuid REFERENCES cohorts — mapeado por group_jid)
  ├── sent_at (timestamptz)
  ├── message_type (text — 'text' | 'image' | 'audio' | 'other')
  └── evolution_message_id (text UNIQUE — evita duplicatas)

zoom_chat_messages (nova tabela — Story 10.7, condicional)
  ├── id (uuid PK)
  ├── zoom_meeting_id (text)
  ├── sender_name (text)
  ├── student_id (uuid REFERENCES students — nullable)
  ├── sent_at (timestamptz)
  └── message_id (text UNIQUE)
```

### Queries de ranking (Story 10.1)

```sql
-- Ranking presença por turma
SELECT s.name, s.phone,
  COUNT(*) FILTER (WHERE sa.present) AS presencas,
  COUNT(*) AS total_aulas,
  ROUND(COUNT(*) FILTER (WHERE sa.present) * 100.0 / COUNT(*), 1) AS pct
FROM students s
JOIN student_attendance sa ON sa.student_id = s.id
WHERE sa.cohort_id = $1
GROUP BY s.id ORDER BY pct DESC;

-- Ranking WhatsApp por cohort (período)
SELECT s.name, COUNT(*) AS mensagens, COUNT(DISTINCT DATE(wm.sent_at)) AS dias_ativos
FROM whatsapp_group_messages wm
JOIN students s ON s.id = wm.student_id
WHERE wm.cohort_id = $1
AND wm.sent_at >= $2  -- início do período
GROUP BY s.id ORDER BY dias_ativos DESC, mensagens DESC;
```

---

## Fluxo WhatsApp Group Monitoring (Story 10.6)

```
CAPTURA (tempo real via webhook):
1. Aluno envia mensagem no grupo WhatsApp da turma
2. Evolution API dispara webhook messages.upsert → delivery-webhook (já existe)
3. Handler novo no delivery-webhook: se event = 'messages.upsert' E
   remoteJid termina em @g.us (grupo):
   a. Ignorar mensagens próprias (fromMe = true) e bots
   b. Extrair sender phone do JID (ex: 5543999...@s.whatsapp.net → 5543999...)
   c. Normalizar phone → buscar student_id em students
   d. Buscar cohort_id pelo group_jid em cohorts.whatsapp_group_jid
   e. INSERT em whatsapp_group_messages (deduplicado por evolution_message_id)

AGGREGAÇÃO (cron 02h–04h AM, junto com Zoom chat):
4. Cron calcula contagem do dia para cada student/cohort
5. Upsert em engagement_daily_ranking
```

## Arquitetura do Cron Noturno (pg_cron — 02h AM)

```sql
-- Job: engagement-nightly-sync
-- Schedule: '0 2 * * *'  (02:00 AM todos os dias)

-- Passo 1: Buscar chat Zoom de reuniões de ontem
SELECT zoom_meeting_id FROM zoom_meetings
WHERE start_time::date = CURRENT_DATE - 1
  AND chat_imported = false;
-- Para cada: chamar zoom-attendance?action=import_meeting_chat via pg_net

-- Passo 2: Recalcular ranking diário
INSERT INTO engagement_daily_ranking
  (student_id, cohort_id, ref_date, wa_messages, zoom_chat_messages,
   attendance_count, engagement_score)
SELECT
  s.id,
  ...,
  CURRENT_DATE - 1 AS ref_date,
  COUNT(wm.*) AS wa_messages,
  COUNT(zc.*) AS zoom_chat_messages,
  COUNT(sa.*) FILTER (WHERE sa.present) AS attendance_count,
  -- score composto: presença (peso 3) + wa (peso 1) + zoom chat (peso 1)
  (COUNT(sa.*) FILTER (WHERE sa.present) * 3
   + COUNT(wm.*) + COUNT(zc.*)) AS engagement_score
FROM students s
LEFT JOIN whatsapp_group_messages wm ON wm.student_id = s.id AND wm.sent_at::date = CURRENT_DATE - 1
LEFT JOIN zoom_chat_messages zc ON zc.student_id = s.id AND zc.sent_at::date = CURRENT_DATE - 1
LEFT JOIN student_attendance sa ON sa.student_id = s.id AND sa.class_date = CURRENT_DATE - 1
GROUP BY s.id, cohort_id
ON CONFLICT (student_id, cohort_id, ref_date) DO UPDATE SET ...;
```

## Tabela engagement_daily_ranking (nova — Story 10.6)

```sql
CREATE TABLE engagement_daily_ranking (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id           UUID REFERENCES students(id),
  cohort_id            UUID REFERENCES cohorts(id),
  ref_date             DATE NOT NULL,
  wa_messages          INT DEFAULT 0,
  zoom_chat_messages   INT DEFAULT 0,
  attendance_count     INT DEFAULT 0,
  engagement_score     INT DEFAULT 0,  -- composto: presença×3 + wa + zoom_chat
  UNIQUE (student_id, cohort_id, ref_date)
);

CREATE INDEX ON engagement_daily_ranking (cohort_id, ref_date DESC);
CREATE INDEX ON engagement_daily_ranking (student_id, ref_date DESC);
```

## Fluxo Zoom Chat Monitoring (Story 10.7)

```
Endpoint: GET /report/meetings/{meetingId}/chat
Scope: report:read:admin (já ativo)

Cron noturno (02h–04h AM):
1. Buscar zoom_meetings com start_time no dia anterior (já na tabela)
2. Para cada reunião: GET /report/meetings/{meetingId}/chat
3. Para cada mensagem do chat:
   - Extrair sender_name, time, message_id
   - Fuzzy match sender_name → student_id (mesmo algoritmo de participantes)
   - INSERT em zoom_chat_messages (deduplicado por message_id UNIQUE)
4. Após inserção, recalcular engagement_ranking para cohorts afetados
```

## Fluxo NPS Tokenizado

```
1. Coordenador dispara NPS para turma no admin
2. Sistema gera 1 token por aluno matriculado (nps_tokens)
3. WhatsApp enviado: "Avalie → https://calendario.igorrover.com.br/avaliacao?t=x7k2p9"
4. Aluno clica → form carrega sem login
5. Aluno submete → sistema valida token (não expirado, não usado)
6. Resposta salva em survey_responses com nps_token_id
7. Token marcado como used=true
8. Perfil 360 do aluno exibe a resposta atribuída
```

---

## Métricas de Sucesso

- **Tempo para coordenador ver situação completa de 1 aluno:** hoje ~5min → alvo <30s
- **Taxa de resposta NPS atribuída:** hoje 0% (anônimas) → alvo >60% dos alunos com token
- **Turma navegável em 1 clique:** hoje ❌ → alvo ✅
- **Mensagens WhatsApp capturadas automaticamente:** hoje 0% → alvo 100% (após habilitação)
- **Alunos com dados de engajamento visíveis no perfil:** hoje 0 → alvo 100% dos matriculados

---

## Riscos

| Risco | Probabilidade | Mitigação |
|-------|-------------|-----------|
| Aluno compartilha token com outro | Baixo | One-time use — segundo submit recebe "avaliação já registrada" |
| Token expirado quando aluno clica | Médio | Mensagem clara "prazo encerrado" + coordenador pode regenerar |
| Alunos não vinculados no Zoom não têm telefone confiável | Médio | NPS só enviado para alunos com phone validado; os demais ficam sem token |
| Survey_responses já tem schema incompatível | Baixo | Ler schema antes de Story 10.3; adaptar ou criar nova tabela se necessário |
| Zoom chat scope | **RESOLVIDO** — `report:read:admin` já ativo; endpoint `/report/meetings/{meetingId}/chat` confirmado |
| WhatsApp group JID não mapeado para cohort | Médio | Verificar se cohorts.whatsapp_group_jid está populado antes de Story 10.6 |
