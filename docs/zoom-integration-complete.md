# Integração Zoom — Documentação Completa do Sistema

> Documento gerado em 2026-04-07. Descreve toda a integração com o Zoom no projeto `lesson-pages` (Academia Lendária / calendario.igorrover.com.br).

---

## Sumário

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Fluxo de Dados Completo](#2-fluxo-de-dados-completo)
3. [Edge Functions](#3-edge-functions)
   - [zoom-oauth](#31-zoom-oauth)
   - [zoom-webhook](#32-zoom-webhook)
   - [zoom-attendance](#33-zoom-attendance)
4. [Banco de Dados — Tabelas](#4-banco-de-dados--tabelas)
5. [Banco de Dados — Funções PostgreSQL](#5-banco-de-dados--funções-postgresql)
6. [Algoritmo de Matching de Participantes](#6-algoritmo-de-matching-de-participantes)
7. [Vinculação de Mentores (EPIC-005)](#7-vinculação-de-mentores-epic-005)
8. [Frontend — Páginas com Integração Zoom](#8-frontend--páginas-com-integração-zoom)
9. [Variáveis de Ambiente Necessárias](#9-variáveis-de-ambiente-necessárias)
10. [Segurança](#10-segurança)
11. [Operações de Manutenção](#11-operações-de-manutenção)
12. [Limitações e Pontos de Atenção](#12-limitações-e-pontos-de-atenção)

---

## 1. Visão Geral da Arquitetura

O sistema Zoom é composto por **3 camadas principais**:

```
┌─────────────────────────────────────────────────────────────────┐
│                         ZOOM API                                 │
│   Dashboard Metrics API  |  Reports API  |  OAuth 2.0           │
└────────────┬─────────────────────┬──────────────────────────────┘
             │ S2S (admin)         │ Webhooks
             ▼                     ▼
┌──────────────────────────────────────────────────────────────────┐
│                    SUPABASE EDGE FUNCTIONS                        │
│  zoom-attendance          zoom-webhook         zoom-oauth         │
│  (coleta de dados,        (eventos em          (OAuth por         │
│   matching, ações)         tempo real)          mentor)           │
└────────────┬─────────────────────┬──────────────────────────────┘
             │                     │
             ▼                     ▼
┌──────────────────────────────────────────────────────────────────┐
│                       SUPABASE DATABASE                           │
│  zoom_meetings   zoom_participants   zoom_tokens                  │
│  zoom_host_sessions   student_attendance   oauth_states           │
│                                                                   │
│  Functions: mark_mentor_participants()  dedup_zoom_participants() │
│             propagate_zoom_links()      fix_student_phones()      │
└────────────┬─────────────────────────────────────────────────────┘
             │
             ▼
┌──────────────────────────────────────────────────────────────────┐
│                         FRONTEND                                  │
│  /calendario/admin  /aulas  /equipe  /perfil  /presenca          │
└──────────────────────────────────────────────────────────────────┘
```

### Dois modos de autenticação Zoom

| Modo | Uso | Credenciais |
|------|-----|-------------|
| **Server-to-Server (S2S)** | Coleta de relatórios (admin global) | `ZOOM_ACCOUNT_ID`, `ZOOM_CLIENT_ID`, `ZOOM_CLIENT_SECRET` |
| **OAuth 2.0 por mentor** | Identificação do host em sessões ao vivo | Código de autorização → `zoom_tokens` table |

---

## 2. Fluxo de Dados Completo

### 2.1 Importação de Relatório (fluxo principal)

```
Admin abre /calendario/admin
  └─> Clica "Buscar reuniões" (action: list_meetings)
        └─> zoom-attendance chama Zoom Dashboard Metrics API
              └─> Retorna lista de meetings com IDs
                    └─> Admin seleciona meeting e clica "Importar"
                          └─> zoom-attendance chama Zoom Reports API (/meetings/{id}/participants)
                                └─> Salva em zoom_meetings + zoom_participants
                                      └─> matchStudents() — 8 níveis de matching
                                            └─> student_id preenchido nos registros matched
                                                  └─> mark_mentor_participants() — marca mentores
                                                        └─> Response: { imported, matched, mentors_matched, unmatched_remaining }
```

### 2.2 Sessão ao Vivo (fluxo webhook)

```
Mentor entra em reunião no Zoom
  └─> Zoom dispara webhook meeting.started
        └─> zoom-webhook verifica HMAC-SHA256
              └─> Upsert em zoom_host_sessions (host_email, meeting_id, started_at)

Reunião termina
  └─> Zoom dispara webhook meeting.ended
        └─> zoom-webhook atualiza zoom_host_sessions (released_at, released_by='webhook')
              └─> Marca zoom_meetings.processed = false (pronto para importar)

[Fallback] Se webhook não chegar em 6h
  └─> pg_cron job "zoom-ghost-session-cleanup" libera sessão travada automaticamente
```

### 2.3 OAuth por Mentor

```
Admin/Mentor acessa /equipe e clica "Conectar Zoom"
  └─> zoom-oauth action: authorize
        └─> Gera state + salva em oauth_states (TTL 10min)
              └─> Redireciona para accounts.zoom.us/oauth/authorize
                    └─> Mentor autoriza → Zoom redireciona para /api/zoom/callback
                          └─> zoom-oauth action: callback
                                └─> Troca código por access_token + refresh_token
                                      └─> Busca zoom user info (email, account_id)
                                            └─> Salva em zoom_tokens (mentor_id, email, tokens, expires_at)
```

---

## 3. Edge Functions

### 3.1 zoom-oauth

**Arquivo:** `supabase/functions/zoom-oauth/index.ts`

**Propósito:** Gerenciar o fluxo OAuth 2.0 por mentor — autorização, troca de código, refresh de tokens.

**Actions disponíveis:**

| Action | Método | Descrição |
|--------|--------|-----------|
| `authorize` | GET/POST | Gera URL de autorização Zoom + salva state |
| `callback` | GET/POST | Recebe code, valida state, obtém tokens, salva no DB |
| `refresh` | POST | Atualiza access_token usando refresh_token |

**CORS:** Permite `lesson-pages.vercel.app` e `calendario.igorrover.com.br`

**Fluxo de segurança do state:**
- State UUID gerado aleatoriamente
- Salvo em `oauth_states` com TTL de 10 minutos
- Validado no callback antes de aceitar o código
- Expirados são limpos automaticamente

**Redirect URI:** `https://lesson-pages.vercel.app/api/zoom/callback`

---

### 3.2 zoom-webhook

**Arquivo:** `supabase/functions/zoom-webhook/index.ts`

**Propósito:** Receber eventos do Zoom em tempo real (meeting.started, meeting.ended).

**Verificação de assinatura:**
```
mensagem = "v0:" + timestamp + ":" + body_raw
hmac = HMAC-SHA256(ZOOM_WEBHOOK_SECRET, mensagem)
assinatura_esperada = "v0=" + hex(hmac)
comparar com header x-zm-signature
```

**Eventos tratados:**

| Evento | Ação |
|--------|------|
| `endpoint.url_validation` | Responde ao challenge do Zoom (registro do webhook) |
| `meeting.started` | Upsert em `zoom_host_sessions` |
| `meeting.ended` | Atualiza `released_at` + marca `zoom_meetings.processed = false` |
| `meeting.alert` | Log apenas (sem mudança de estado) |

**Fallback anti-travamento:**
- pg_cron: `zoom-ghost-session-cleanup` roda a cada hora
- Libera sessões com `started_at < now() - 6h` e `released_at IS NULL`
- Define `released_by = 'timeout'`

---

### 3.3 zoom-attendance

**Arquivo:** `supabase/functions/zoom-attendance/index.ts`

**Propósito:** A função principal do sistema — coleta dados do Zoom via S2S, realiza matching de participantes com alunos/mentores, e expõe ações administrativas.

**Autenticação:** Server-to-Server Account Credentials
```typescript
POST https://zoom.us/oauth/token?grant_type=account_credentials&account_id={ACCOUNT_ID}
Authorization: Basic base64(CLIENT_ID:CLIENT_SECRET)
```

**10 Actions disponíveis:**

#### `list_meetings`
- Chama `GET /metrics/meetings?type=past&from={from}&to={to}`
- Retorna lista de meetings com topic, host, start_time, participants
- Deduplicação por `uuid` (mesmo meeting pode aparecer duas vezes na API)

#### `debug_scopes`
- Chama `GET /users/me` e `GET /metrics/meetings` para testar escopos ativos
- Retorna quais permissões a aplicação S2S possui
- Uso: diagnóstico quando importação falha por falta de permissão

#### `mentor_unmatched_report`
- Lista todos os nomes de mentores cadastrados
- Lista participantes unmatched agrupados por nome
- Uso: debug manual para identificar aliases faltantes

#### `fix_phones`
- Chama função PostgreSQL `fix_student_phones()`
- Normaliza telefones para formato `55+DDD+número` (11 dígitos)
- Faz merge de alunos duplicados por telefone
- Retorna contadores: `fixed`, `merged`, `invalid`

#### `dedup_participants`
- Chama função PostgreSQL `dedup_zoom_participants()`
- Remove duplicatas dentro do mesmo meeting
- Mantém o registro com maior `duration_minutes`
- Retorna: `deleted_count`, `kept_count`

#### `propagate_links`
- Chama função PostgreSQL `propagate_zoom_links()`
- Pega participantes já vinculados manualmente (por nome/email)
- Aplica o mesmo link em todos os outros meetings onde o mesmo participante aparece
- Resolve conflitos: se mesmo nome ligado a alunos diferentes, usa o mais frequente
- Retorna: `updated_count`

#### `rematch_all`
- Re-executa o algoritmo de matching em todos os participantes `matched=false`
- Processado em páginas de 500 (paginação para evitar timeout)
- Útil após correção de dados ou adição de aliases

#### `transfer_to_attendance`
- Copia participantes matched de `zoom_participants` para `student_attendance`
- Campos: `student_id`, `class_date`, `zoom_meeting_id`, `duration_minutes`, `source='zoom'`
- Ignora registros já existentes (upsert por student_id + class_date)

#### `mark_mentor_participants`
- Marca participantes que são mentores/staff como `matched=true`
- Usa 8 regras de matching (ver seção 7)
- Retorna: `updated_count`

#### `zoom_mentor_candidates`
- Lista participantes unmatched que aparecem em 2+ meetings distintos
- Filtra bots, nomes já reconhecidos (mentores e aliases)
- Limpa nomes: remove sufixos de telefone/localização
- Retorna: `[{ name, meeting_count }]` ordenado por frequência
- Usado pela seção "Vinculação Zoom" em /equipe (Story 5.3)

**Importação de meeting (fluxo principal):**
```
POST { meeting_id: "abc123xyz" }
  1. Obtém token S2S do Zoom
  2. GET /report/meetings/{uuid}/participants
  3. Para cada participante:
     a. cleanParticipantName() — remove sufixos de telefone/localização
     b. normalize() — lowercase, sem acentos, sem pontuação
     c. isBot() — filtra bots/hosts/notetakers
     d. matchStudents() — 8 níveis de matching
  4. Upsert em zoom_meetings
  5. Upsert em zoom_participants (com student_id se matched)
  6. mark_mentor_participants() — segunda passada para mentores
  7. Retorna: { imported, matched, unmatched, mentors_matched, unmatched_remaining }
```

---

## 4. Banco de Dados — Tabelas

### zoom_meetings

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID PK | Identificador interno |
| `zoom_meeting_id` | TEXT UNIQUE | ID do Zoom (numérico) |
| `zoom_uuid` | TEXT | UUID da sessão específica |
| `topic` | TEXT | Título da reunião |
| `start_time` | TIMESTAMPTZ | Início da reunião |
| `duration` | INT | Duração em minutos |
| `cohort_id` | UUID FK | Turma vinculada (se identificada) |
| `processed` | BOOLEAN | Se os participantes já foram importados |
| `created_at` | TIMESTAMPTZ | — |

### zoom_participants

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID PK | — |
| `meeting_id` | TEXT FK | Referência a zoom_meetings |
| `participant_name` | TEXT | Nome exibido no Zoom |
| `participant_email` | TEXT | Email (se disponível) |
| `student_id` | UUID FK | Aluno vinculado (NULL se não matched) |
| `matched` | BOOLEAN | Se foi identificado |
| `match_score` | INT | Score do algoritmo (0-100) |
| `match_level` | TEXT | Nível de matching usado |
| `duration_minutes` | INT | Tempo na reunião |
| `join_time` | TIMESTAMPTZ | Horário de entrada |
| `leave_time` | TIMESTAMPTZ | Horário de saída |
| `is_mentor` | BOOLEAN | Marcado como mentor/staff |
| `created_at` | TIMESTAMPTZ | — |

### zoom_tokens

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID PK | — |
| `mentor_id` | UUID FK | Mentor proprietário do token |
| `zoom_email` | TEXT | Email da conta Zoom |
| `zoom_account_id` | TEXT | ID da conta Zoom |
| `access_token` | TEXT | Token de acesso (expira em 1h) |
| `refresh_token` | TEXT | Token de refresh |
| `expires_at` | TIMESTAMPTZ | Expiração do access_token |
| `active` | BOOLEAN | Se o token está ativo |
| `created_at` | TIMESTAMPTZ | — |
| `updated_at` | TIMESTAMPTZ | — |

**RLS:** Admins veem tudo; mentores veem apenas o próprio token.

### zoom_host_sessions

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID PK | — |
| `host_email` | TEXT | Email do host (indexed) |
| `meeting_id` | TEXT | ID do meeting em curso |
| `zoom_uuid` | TEXT | UUID da sessão |
| `topic` | TEXT | Título da reunião |
| `started_at` | TIMESTAMPTZ | Início via webhook |
| `released_at` | TIMESTAMPTZ | NULL = sessão ativa |
| `released_by` | ENUM | `webhook`, `timeout`, `manual` |
| `created_at` | TIMESTAMPTZ | — |

**Índices:** `host_email`, `meeting_id`, `host_email WHERE released_at IS NULL`

### oauth_states

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID PK | State UUID enviado ao Zoom |
| `mentor_id` | UUID FK | Mentor iniciando o OAuth |
| `expires_at` | TIMESTAMPTZ | TTL de 10 minutos |
| `used` | BOOLEAN | Se já foi consumido |

### student_attendance

| Coluna | Tipo | Descrição |
|--------|------|-----------|
| `id` | UUID PK | — |
| `student_id` | UUID FK | Aluno |
| `class_date` | DATE | Data da aula |
| `zoom_meeting_id` | TEXT | Origem |
| `duration_minutes` | INT | Tempo de presença |
| `source` | TEXT | `zoom` ou `manual` |

---

## 5. Banco de Dados — Funções PostgreSQL

### `mark_mentor_participants()`

**Arquivo de migration:** `20260409140000_mentor_zoom_alias.sql`

Marca como `matched=true` e `is_mentor=true` todos os `zoom_participants` que são mentores ou staff. Usa 8 regras de matching em cascata (da mais precisa à mais permissiva):

| Regra | Descrição |
|-------|-----------|
| 1 | Nome exato do mentor = nome do participante |
| 2 | Participante começa com o nome do mentor |
| 3 | Nome do mentor começa com o nome do participante |
| 4 | Match de primeiro nome único (mín. 4 chars) |
| 5 | Match exato de `zoom_alias` |
| 6 | Participante começa com `zoom_alias` |
| 7 | `zoom_alias` começa com o nome do participante |
| 8 | Primeira palavra do alias (mín. 3 chars) |
| 9 | Match por qualquer item do array `aliases[]` |

Usa `UNACCENT()` e `TRANSLATE()` para normalização de acentos/pontuação.

Retorna: `TABLE(updated_count INT)`

### `dedup_zoom_participants()`

**Arquivo de migration:** `20260409030000_zoom_cleanup_functions.sql`

Remove participantes duplicados dentro do mesmo meeting:
- Chave de deduplicação: `meeting_id + COALESCE(email, normalize(nome))`
- Mantém o registro com maior `duration_minutes`
- Retorna: `(deleted_count INT, kept_count INT)`

### `propagate_zoom_links()`

**Arquivo de migration:** `20260409030000_zoom_cleanup_functions.sql`

Propaga vínculos confirmados (manual ou automático) para todos os meetings:
- Encontra participantes matched (por nome+email)
- Aplica o mesmo `student_id` a todos os registros unmatched com mesmo nome/email
- Resolve conflitos por frequência (student_id mais comum vence)
- Retorna: `updated_count INT`

### `fix_student_phones()`

Normaliza telefones de alunos:
- Formato alvo: `55DDDDXXXXXXXX` (13 dígitos)
- Trata variações: com/sem +55, com/sem parênteses, com/sem traço
- Faz merge de alunos duplicados detectados por telefone
- Retorna: `(fixed INT, merged INT, invalid INT)`

---

## 6. Algoritmo de Matching de Participantes

O matching ocorre em `zoom-attendance/index.ts` na função `matchStudents()`. É executado para cada participante importado do Zoom, tentando vinculá-lo a um aluno cadastrado.

### Pré-processamento

```javascript
// 1. Limpar nome do participante (remove sufixos telefone/localização)
// "Diego Alves - 55 11 99999-9999" → "Diego Alves"
// "Maria - BNI Norte" → "Maria"
function cleanParticipantName(name) { ... }

// 2. Normalizar (lowercase, sem acentos, sem pontuação)
function normalize(str) {
  return str.toLowerCase()
    .normalize('NFD').replace(/\p{Mn}/gu, '')
    .replace(/[^a-z0-9\s]/g, '').trim();
}

// 3. Filtrar bots e usuários do sistema
const BOT_PATTERNS = /zoom|notetaker|recorder|moderator|host|otter\.ai|assistant/i;
function isBot(name) { return BOT_PATTERNS.test(name); }
```

### Hierarquia de Matching (8 níveis)

| Nível | Tipo | Score | Condição |
|-------|------|-------|----------|
| 0 | Alias exato | 100 | `normalize(alias) === normalize(participante)` |
| 0b | Prefixo de alias | 90 | Alias começa com o nome do participante |
| 1 | Nome completo exato | 100 | `normalize(nome_aluno) === normalize(participante)` |
| 2 | Primeiro + último nome | 80 | Primeiro e último palavras coincidem |
| 3 | Primeiro nome único + palavra compartilhada | 60 | Primeiro nome único entre alunos + palavra em comum |
| 4 | Jaro-Winkler fuzzy | 59-70 | Similaridade ≥ 0.85 (requer mín. 2 palavras) |
| — | Email exato | 100 | `email_aluno === email_participante` (prioridade máxima) |
| — | Email parcial | 85 | Domínio coincide + primeira parte coincide |

**Guardrails (proteções anti-falso-positivo):**
- Nunca fazer match por primeiro nome sozinho (muitos alunos com mesmo nome)
- Email match tem prioridade absoluta sobre nome match
- Jaro-Winkler requer mínimo 2 palavras no nome do participante
- Se mais de 1 aluno bate com score ≥ 80, o match é descartado (ambíguo)
- Mentores nunca são matcheados como alunos

### Implementação Jaro-Winkler

O algoritmo Jaro-Winkler está implementado no cliente (`/js/admin/zoom.js`) para uso no frontend, e replicado na edge function em TypeScript:

```typescript
function jaroWinkler(s1: string, s2: string): number {
  // Implementação completa em TypeScript
  // threshold: 0.85 para aceitar como match
}
```

---

## 7. Vinculação de Mentores (EPIC-005)

Implementado em Abril/2026. Resolve o problema de mentores que entram no Zoom com nomes diferentes do cadastro.

### Story 5.1 — Pipeline Feedback Pós-Importação

**Mudanças em `zoom-attendance/index.ts`:**
- Response da importação agora inclui `mentors_matched` e `unmatched_remaining`
- Nova action `zoom_mentor_candidates` retorna lista de participantes recorrentes não identificados

### Story 5.2 — UI CRUD de Aliases em /equipe

**Mudanças em `equipe/index.html`:**
- Cada card de mentor exibe seção "Nomes no Zoom" com aliases cadastrados como tags
- Botão [×] remove alias; input + "Adicionar" insere novo
- Validações: mínimo 3 caracteres, sem duplicatas no mesmo mentor
- Persiste em `mentors.aliases TEXT[]` via Supabase client

### Story 5.3 — Seção "Vinculação Zoom" em /equipe

**Mudanças em `equipe/index.html`:**
- Seção colapsável no final da página (carregamento lazy)
- Lista candidatos não reconhecidos com contagem de meetings
- Padrão "Sou eu" — mentor self-service se identifica
- Ao clicar "Sou eu": adiciona nome aos próprios aliases + chama `mark_mentor_participants()` via RPC
- Feedback: "N registros atualizados retroativamente"
- Botão "Ignorar" oculta candidato na sessão (não persiste)

### Campo `mentors.aliases TEXT[]`

```sql
-- Como o campo é usado no matching
SELECT id, name, aliases FROM mentors WHERE active = true;

-- Adição de alias (via UI em /equipe)
UPDATE mentors SET aliases = array_append(aliases, 'novo nome') WHERE id = $mentor_id;

-- Remoção de alias
UPDATE mentors SET aliases = array_remove(aliases, 'nome a remover') WHERE id = $mentor_id;
```

---

## 8. Frontend — Páginas com Integração Zoom

### /calendario/admin.html

**Funcionalidades:**
- Seletor de data range para buscar reuniões
- Botão "Buscar reuniões" → `list_meetings`
- Lista de meetings com botão "Importar" por item
- Exibe resultado: `imported / matched / mentors_matched / unmatched_remaining`
- Ações avançadas: fix_phones, dedup, propagate, rematch_all, transfer
- Diagnóstico: debug_scopes, mentor_unmatched_report

### /aulas (ou /presenca)

**Funcionalidades:**
- Exibe presença dos alunos por aula (dados de `student_attendance`)
- Mostra `duration_minutes` de cada aluno na reunião
- Indicador de fonte: `zoom` vs `manual`

### /equipe

**Funcionalidades:**
- Card de mentor com seção "Nomes no Zoom" (aliases) — Story 5.2
- Seção "Vinculação Zoom" colapsável com candidatos — Story 5.3
- Campo `zoom_alias` exibido/editável no card do mentor

### /perfil

**Funcionalidades:**
- Mentor vê próprio status de conexão Zoom
- Botão "Conectar Zoom" → inicia fluxo OAuth
- Exibe email da conta Zoom conectada

### /api/zoom/callback.html

**Funcionalidades:**
- Página de retorno após autorização OAuth
- Extrai `code` e `state` da URL
- Chama `zoom-oauth action: callback`
- Redireciona para /equipe após sucesso

### /js/admin/zoom.js

**Funcionalidades:**
- Implementação JavaScript do algoritmo Jaro-Winkler
- Funções de matching do lado cliente para preview
- Utilitários: normalize(), cleanParticipantName(), isBot()

---

## 9. Variáveis de Ambiente Necessárias

### Supabase Edge Functions (via `supabase secrets set`)

| Variável | Onde usada | Descrição |
|----------|-----------|-----------|
| `SUPABASE_URL` | zoom-oauth, zoom-webhook, zoom-attendance | URL do projeto Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | zoom-oauth, zoom-webhook, zoom-attendance | Chave service_role (bypass RLS) |
| `ZOOM_ACCOUNT_ID` | zoom-attendance | S2S OAuth account ID |
| `ZOOM_CLIENT_ID` | zoom-attendance, zoom-oauth | Client ID da app Zoom |
| `ZOOM_CLIENT_SECRET` | zoom-attendance, zoom-oauth | Client Secret da app Zoom |
| `ZOOM_WEBHOOK_SECRET` | zoom-webhook | Secret para verificar assinaturas HMAC |

### Frontend (via variáveis de ambiente / constantes hardcoded)

| Variável | Arquivo | Descrição |
|----------|---------|-----------|
| `SUPABASE_URL` | equipe/index.html, calendario/admin.html | URL do Supabase |
| `SUPABASE_ANON_KEY` | equipe/index.html, calendario/admin.html | Chave anon (pública) |
| `ZOOM_ATTENDANCE_URL` | equipe/index.html | URL da edge function zoom-attendance |

---

## 10. Segurança

### Webhook HMAC-SHA256
- Todo evento do Zoom é verificado com `ZOOM_WEBHOOK_SECRET`
- Rejeitados imediatamente se assinatura inválida
- Timestamp verificado para prevenir replay attacks

### OAuth State Anti-CSRF
- State UUID gerado por cada fluxo OAuth
- Armazenado server-side em `oauth_states` (TTL 10min)
- Validado no callback — qualquer state inválido/expirado rejeita o callback

### RLS em zoom_tokens
- Mentores só acessam próprio token (`mentor_id = jwt.mentor_id`)
- Edge functions usam `service_role` (bypass RLS para operações admin)

### Service Role vs Anon Key
- Edge functions sempre usam `SUPABASE_SERVICE_ROLE_KEY`
- Frontend usa `SUPABASE_ANON_KEY` + RLS para controle de acesso

---

## 11. Operações de Manutenção

### Importar participants de um meeting

```
POST zoom-attendance
{ "meeting_id": "12345678901" }
```

### Limpar duplicatas após importação

```
POST zoom-attendance
{ "action": "dedup_participants" }
```

### Propagar links confirmados

```
POST zoom-attendance
{ "action": "propagate_links" }
```

### Re-executar matching após adicionar aliases

```
POST zoom-attendance
{ "action": "rematch_all" }
```

### Transferir presença para student_attendance

```
POST zoom-attendance
{ "action": "transfer_to_attendance" }
```

### Verificar candidatos Zoom não identificados

```
POST zoom-attendance
{ "action": "zoom_mentor_candidates" }
```

### Verificar escopos da aplicação S2S

```
POST zoom-attendance
{ "action": "debug_scopes" }
```

### Deploy das edge functions

```bash
supabase functions deploy zoom-attendance
supabase functions deploy zoom-oauth
supabase functions deploy zoom-webhook
```

---

## 12. Limitações e Pontos de Atenção

### Escopo da API S2S
- A conta S2S precisa de escopos específicos: `dashboard_meetings:read:admin`, `report:read:admin`
- Se escopos estiverem faltando, usar `debug_scopes` para diagnóstico
- Escopos são configurados no portal Zoom Marketplace (app Server-to-Server)

### Zoom Dashboard API — Limite de Datas
- A API Metrics/Dashboard tem limite de 30 dias por request
- Para períodos maiores, múltiplas chamadas são necessárias

### Matching Ambíguo
- Participantes com nomes muito comuns (ex: "João") podem não ser matcheados (ambiguidade)
- Solução: adicionar alias mais específico ou fazer link manual
- O sistema nunca faz match quando há ambiguidade — prefere não matchear a matchear errado

### aliases[] vs zoom_alias
- `zoom_alias` (TEXT): campo legado para um único alias
- `aliases[]` (TEXT[]): novo campo array — suporta múltiplos aliases por mentor
- Ambos são usados em `mark_mentor_participants()` (compatibilidade retroativa)

### Sessões travadas no webhook
- Se o evento `meeting.ended` não chegar (falha de rede), a sessão fica ativa em `zoom_host_sessions`
- Mitigação: pg_cron libera automaticamente após 6 horas com `released_by='timeout'`

### Token OAuth expira em 1h
- `access_token` do Zoom tem TTL de 1 hora
- `zoom-oauth action: refresh` deve ser chamado antes de operações que usam OAuth por mentor
- O `refresh_token` tem validade de 90 dias

### Retroatividade do mark_mentor_participants()
- Ao adicionar um novo alias, `mark_mentor_participants()` pode ser chamado via RPC para propagar retroativamente
- Pode fazer matching incorreto se o alias for um nome muito comum
- O admin confirma explicitamente antes de vincular (Story 5.3)

---

*Documento gerado automaticamente a partir da análise do código-fonte. Para manter atualizado, re-gerar após mudanças significativas na integração Zoom.*
