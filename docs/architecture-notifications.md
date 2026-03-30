# Arquitetura: Sistema de Notificacoes WhatsApp

**Projeto:** lesson-pages (lesson-pages.vercel.app)
**Data:** 2026-03-30
**Autor:** Aria (Architect Agent)
**Status:** Draft - Aguardando implementacao

---

## 1. Visao Geral

Sistema event-driven de notificacoes WhatsApp para a plataforma educacional Academia Lendaria. O admin insere um registro na tabela `notifications` com status `pending`; um Database Webhook dispara a Edge Function `send-whatsapp`, que processa o envio via Evolution API e atualiza o status para `sent`, `partial` ou `failed`.

### Principio Arquitetural

```
INSERT notification (pending)
    |
    v
[Database Webhook]
    |
    v
[Edge Function: send-whatsapp]
    |
    +---> Evolution API (grupo WhatsApp)
    +---> Evolution API (mentores individuais)
    |
    v
UPDATE notification (sent | partial | failed)
```

**Nenhuma mensagem e enviada sem registro previo na tabela** (auditoria completa).

---

## 2. Diagrama de Componentes

```
+------------------+     +------------------+     +--------------------+
|  Painel Admin    |     |    Supabase      |     |    VPS Contabo     |
|  (Vercel)        |     |    (Cloud)       |     |  194.163.179.68    |
|                  |     |                  |     |                    |
|  calendario/     |---->| notifications    |     |  Evolution API     |
|  admin.html      |     | table            |     |  :8084             |
|                  |     |      |           |     |  instancia: igor   |
|  "Enviar Aviso"  |     |      | webhook   |     |                    |
|  button          |     |      v           |     |                    |
|                  |     | Edge Function    |---->|  /message/sendText |
|                  |     | send-whatsapp    |     |                    |
+------------------+     +------------------+     +--------------------+
```

### Fluxo de Dados Detalhado

```
1. Admin clica "Enviar Aviso" no painel
   |
2. Frontend faz INSERT na tabela notifications via Supabase JS
   (status: 'pending', type: 'class_reminder', class_id, metadata)
   |
3. Database Webhook detecta INSERT e invoca Edge Function
   |
4. Edge Function:
   a. Valida status = 'pending'
   b. Marca status = 'processing'
   c. Busca dados da class, cohort (JID do grupo), mentores
   d. Renderiza template da mensagem com variaveis
   e. Envia para grupo WhatsApp via Evolution API
   f. Envia para cada mentor individualmente via Evolution API
   g. Atualiza status para 'sent' | 'partial' | 'failed'
   |
5. Admin ve status atualizado no painel
```

---

## 3. Modelo de Dados

### 3.1 Novas Tabelas

#### `mentors`
Tabela dedicada para mentores, separada de `students`. Justificativa: mentores tem telefone verificado, papeis diferentes (Professor/Host/Both) e sao alvo de notificacoes individuais.

| Coluna | Tipo | Descricao |
|--------|------|-----------|
| id | UUID PK | Identificador |
| name | TEXT | Nome do mentor |
| phone | TEXT UNIQUE | Telefone no formato internacional (5511...) |
| role | TEXT | 'Professor', 'Host' ou 'Both' |
| active | BOOLEAN | Se esta ativo |
| created_at | TIMESTAMPTZ | Criacao |
| updated_at | TIMESTAMPTZ | Ultima atualizacao |

#### `class_cohorts` (bridge N:N)
Vincula classes a cohorts. Uma classe pode pertencer a multiplos cohorts (ex: PS Advanced T1+T2).

| Coluna | Tipo | Descricao |
|--------|------|-----------|
| id | UUID PK | Identificador |
| class_id | UUID FK | Referencia classes(id) |
| cohort_id | UUID FK | Referencia cohorts(id) |

#### `class_mentors` (bridge N:N)
Vincula mentores a classes com papel especifico.

| Coluna | Tipo | Descricao |
|--------|------|-----------|
| id | UUID PK | Identificador |
| class_id | UUID FK | Referencia classes(id) |
| mentor_id | UUID FK | Referencia mentors(id) |
| role | TEXT | 'Professor' ou 'Host' |

#### `notifications`
Registro central de todas as notificacoes. Fonte unica de verdade para auditoria.

| Coluna | Tipo | Descricao |
|--------|------|-----------|
| id | UUID PK | Identificador |
| type | TEXT | Tipo da notificacao (ver enum abaixo) |
| class_id | UUID FK | Aula referenciada (nullable) |
| cohort_id | UUID FK | Cohort referenciado (nullable) |
| mentor_id | UUID FK | Mentor especifico (nullable) |
| target_type | TEXT | 'group', 'individual' ou 'both' |
| target_phone | TEXT | Telefone para individual |
| target_group_jid | TEXT | JID do grupo para grupo |
| message_template | TEXT | Template com {{placeholders}} |
| message_rendered | TEXT | Mensagem final apos renderizacao |
| metadata | JSONB | Dados extras |
| status | TEXT | Estado da notificacao (ver state machine) |
| error_message | TEXT | Mensagem de erro se falhou |
| evolution_response | JSONB | Response da Evolution API |
| sent_at | TIMESTAMPTZ | Quando foi enviado |
| retry_count | INT | Tentativas realizadas |
| max_retries | INT | Maximo de tentativas (default: 3) |
| created_by | UUID FK | Admin que criou |
| created_at | TIMESTAMPTZ | Criacao |
| processed_at | TIMESTAMPTZ | Quando a Edge Function processou |

### 3.2 Tipos de Notificacao

| Tipo | Descricao | Target |
|------|-----------|--------|
| `class_reminder` | Lembrete de aula | both (grupo + mentores) |
| `mentor_individual` | Mensagem direta para mentor | individual |
| `group_announcement` | Aviso geral para grupo | group |
| `schedule_change` | Mudanca de escala/substituicao | both |
| `custom` | Mensagem livre do admin | group, individual ou both |

### 3.3 State Machine

```
pending --> processing --> sent
                      --> partial (grupo OK, individual falhou ou vice-versa)
                      --> failed  --> (retry se count < max_retries)
pending --> cancelled (admin cancela antes do processamento)
```

### 3.4 Diagrama ER (relacoes novas)

```
classes ──< class_cohorts >── cohorts
   |                             |
   +──< class_mentors >── mentors
   |
   +──< notifications
              |
              +── cohorts (FK direto opcional)
              +── mentors (FK direto opcional)
```

---

## 4. Edge Function: send-whatsapp

### 4.1 Trigger

- **Mecanismo:** Supabase Database Webhook
- **Tabela:** `notifications`
- **Evento:** INSERT
- **Funcao:** `send-whatsapp`

### 4.2 Ambiente

| Variavel | Valor | Fonte |
|----------|-------|-------|
| SUPABASE_URL | https://gpufcipkajppykmnmdeh.supabase.co | Auto (Supabase) |
| SUPABASE_SERVICE_ROLE_KEY | eyJ... | Supabase Secrets |
| EVOLUTION_API_URL | http://194.163.179.68:8084 | Supabase Secrets |
| EVOLUTION_API_KEY | evo_acadlendaria_2026_secure_key | Supabase Secrets |
| EVOLUTION_INSTANCE | igor | Supabase Secrets |

### 4.3 Fluxo Interno

```
1. Recebe payload do webhook { type, table, record, schema }
2. Extrai record (notification)
3. Valida status === 'pending'
4. UPDATE status = 'processing'
5. Busca dados relacionados:
   - classes (nome, horario)
   - class_cohorts -> cohorts (JID, zoom_link)
   - class_mentors -> mentors (phone, nome)
6. Renderiza template com variaveis
7. Se target_type = 'group' ou 'both':
   - POST /message/sendText/{instance} com JID do grupo
8. Se target_type = 'individual' ou 'both':
   - Para cada mentor: POST /message/sendText/{instance} com phone
9. UPDATE notification com status final, response, erro
```

### 4.4 Evolution API Integration

**Endpoint:** `POST /message/sendText/{instance}`

**Headers:**
```json
{
  "Content-Type": "application/json",
  "apikey": "evo_acadlendaria_2026_secure_key"
}
```

**Body (grupo):**
```json
{
  "number": "120363407322736559@g.us",
  "text": "Mensagem renderizada aqui"
}
```

**Body (individual):**
```json
{
  "number": "556499425822",
  "text": "Mensagem renderizada aqui"
}
```

### 4.5 Template Engine

Templates usam sintaxe `{{variavel}}`. Variaveis disponiveis:

| Variavel | Fonte | Exemplo |
|----------|-------|---------|
| `{{class_name}}` | classes.name | "PS Advanced T1" |
| `{{class_time_start}}` | classes.time_start | "18:00" |
| `{{class_time_end}}` | classes.time_end | "20:00" |
| `{{class_weekday}}` | classes.weekday (traduzido) | "Terca" |
| `{{class_professor}}` | classes.professor | "Talles" |
| `{{class_host}}` | classes.host | "Bruno Gentil" |
| `{{cohort_name}}` | cohorts.name | "Advanced T1" |
| `{{zoom_link}}` | cohorts.zoom_link | "https://zoom.us/..." |
| `{{mentor_name}}` | mentors.name | "Klaus" |
| `{{mentors_list}}` | class_mentors joined | "Talles, Klaus, Day" |

**Exemplo de template (class_reminder):**
```
Lembrete de Aula

Turma: {{cohort_name}}
Aula: {{class_name}}
Horario: {{class_weekday}}, {{class_time_start}} - {{class_time_end}}
Professor: {{class_professor}}
Host: {{class_host}}

Link Zoom: {{zoom_link}}

Ate la!
```

---

## 5. Seguranca

### 5.1 RLS Policies

| Tabela | SELECT | INSERT/UPDATE/DELETE |
|--------|--------|---------------------|
| mentors | Authenticated | Admin only |
| class_cohorts | Authenticated | Admin only |
| class_mentors | Authenticated | Admin only |
| notifications | **Admin only** | Admin only |

**Decisao:** Notifications tem SELECT restrito a admin porque contem telefones e JIDs (dados sensiveis).

### 5.2 Service Role Key

A Edge Function usa `service_role` key que bypassa RLS. Isso e necessario porque:
1. O webhook invoca a function sem contexto de usuario autenticado
2. A function precisa ler/escrever em todas as tabelas sem restricao

**Mitigacao:** A `service_role` key nunca e exposta no frontend. Fica apenas nos Supabase Secrets da Edge Function.

### 5.3 Evolution API Key

- Armazenada como Supabase Secret, nunca no codigo-fonte
- A VPS esta em rede publica (necessario para Edge Function acessar)
- Recomendacao futura: configurar firewall na VPS para aceitar requests apenas dos IPs do Supabase Edge Functions

### 5.4 Auditoria

- Toda notificacao tem `created_by` (UUID do admin que criou)
- Toda notificacao tem `created_at`, `processed_at`, `sent_at`
- Evolution API response e armazenado em `evolution_response` (JSONB)
- Erros sao registrados em `error_message`

---

## 6. Decisoes Arquiteturais

### ADR-1: Tabela mentors separada de students

**Contexto:** Mentores estavam como flag `is_mentor` na tabela `students`.

**Decisao:** Criar tabela `mentors` dedicada.

**Razoes:**
- Mentores precisam de telefone verificado (UNIQUE) para WhatsApp
- Campo `role` (Professor/Host/Both) nao faz sentido para students
- Relacao N:N com classes via `class_mentors` e mais limpa
- Evita queries com filtro `WHERE is_mentor = true` em toda operacao

**Trade-off:** Duplicacao de dados se alguem for mentor E aluno. Aceitavel porque sao dominios diferentes com ciclos de vida diferentes.

### ADR-2: Event-driven via Database Webhook (nao cron)

**Contexto:** Poderia usar pg_cron para polling ou chamar a Edge Function diretamente do frontend.

**Decisao:** Database Webhook no INSERT da tabela notifications.

**Razoes:**
- Processamento imediato (sem delay de polling)
- Desacoplamento: frontend so faz INSERT, nao precisa conhecer a Edge Function
- Auditoria nativa: toda mensagem tem registro antes do envio
- Retry facil: basta atualizar status para 'pending' novamente

**Trade-off:** Database Webhooks tem limite de timeout (2s para trigger, mas Edge Function pode rodar mais). Se o envio para muitos mentores demorar, pode haver timeout. Mitigacao: a function ja marca 'processing' antes de enviar, entao um timeout nao causa reenvio duplicado.

### ADR-3: Bridge tables (N:N) em vez de FK direto

**Contexto:** Classes poderiam ter `cohort_id` direto.

**Decisao:** Usar `class_cohorts` como bridge table.

**Razoes:**
- "PS Advanced T1+T2" atende DOIS cohorts (T1 e T2) simultaneamente
- Um mentor pode estar em multiplas classes com papeis diferentes
- Flexibilidade para reorganizar turmas sem alterar schema

**Trade-off:** Mais JOINs nas queries. Aceitavel dado o volume baixo (dezenas de classes, nao milhares).

### ADR-4: Template engine simples ({{var}})

**Contexto:** Poderia usar Handlebars, Mustache ou Liquid.

**Decisao:** Substituicao simples de `{{variavel}}` com `replaceAll`.

**Razoes:**
- Zero dependencias extras na Edge Function
- Templates sao criados pelo admin no painel, nao por desenvolvedores
- Nao ha necessidade de condicionais ou loops nos templates
- Se precisar de logica, o admin monta a mensagem completa em `message_rendered`

### ADR-5: Nao usar Supabase Realtime para status updates

**Contexto:** O painel poderia se inscrever em `notifications` via Realtime para mostrar status em tempo real.

**Decisao:** Polling simples no painel admin (ou refresh manual).

**Razoes:**
- Volume baixo de notificacoes (dezenas por semana)
- Complexidade desnecessaria para o caso de uso atual
- Realtime adiciona custo no plano Supabase
- Se necessario futuramente, basta adicionar `supabase.channel('notifications')` no frontend

---

## 7. Plano de Implementacao

### Fase 1: Schema e Dados (SQL)
1. Executar `db/notifications-schema.sql` no Supabase SQL Editor
2. Verificar tabelas criadas e seed de mentores
3. Popular `class_cohorts` com mapeamento classes -> cohorts existentes
4. Popular `class_mentors` com mapeamento classes -> mentores existentes

### Fase 2: Edge Function
1. Deploy `supabase/functions/send-whatsapp/index.ts` via Supabase CLI
2. Configurar secrets:
   ```bash
   supabase secrets set EVOLUTION_API_URL=http://194.163.179.68:8084
   supabase secrets set EVOLUTION_API_KEY=evo_acadlendaria_2026_secure_key
   supabase secrets set EVOLUTION_INSTANCE=igor
   ```
3. Testar com INSERT manual na tabela notifications

### Fase 3: Database Webhook
1. Supabase Dashboard > Database > Webhooks
2. Criar webhook `notify-whatsapp-on-pending`
3. Tabela: `notifications`, Evento: INSERT
4. Target: Edge Function `send-whatsapp`
5. Testar fluxo completo

### Fase 4: Painel Admin
1. Adicionar secao "Notificacoes" no `calendario/admin.html`
2. Botao "Enviar Aviso" que abre modal com:
   - Selecao de tipo (class_reminder, announcement, custom)
   - Selecao de classe/cohort
   - Template pre-preenchido ou mensagem livre
   - Preview da mensagem renderizada
3. Historico de notificacoes com status (sent/failed/pending)

### Fase 5: Testes
1. Enviar para grupo de teste (criar cohort de teste com JID de grupo proprio)
2. Enviar individual para numero do admin
3. Testar cenarios de falha (Evolution API offline, JID invalido)
4. Validar retry logic

---

## 8. Riscos e Mitigacoes

| Risco | Severidade | Mitigacao |
|-------|-----------|-----------|
| Evolution API fora do ar | Alta | Retry com max_retries=3; status 'failed' com erro detalhado |
| Timeout da Edge Function (>60s) | Media | Processar em batch se muitos mentores; marcar 'processing' antes |
| Rate limit da Evolution API | Media | Adicionar delay entre envios individuais (500ms) se necessario |
| JID de grupo incorreto | Baixa | Validacao no INSERT; log do erro no evolution_response |
| Service role key comprometida | Alta | Armazenada apenas em Supabase Secrets; rotacionar periodicamente |
| Mensagem duplicada (webhook retry) | Media | Guard: so processar status='pending'; marcar 'processing' atomicamente |

---

## 9. Monitoramento

### Queries uteis

```sql
-- Notificacoes com falha nas ultimas 24h
SELECT * FROM notifications
WHERE status = 'failed'
  AND created_at > now() - interval '24 hours'
ORDER BY created_at DESC;

-- Taxa de sucesso por tipo
SELECT type,
  count(*) FILTER (WHERE status = 'sent') as sent,
  count(*) FILTER (WHERE status = 'failed') as failed,
  count(*) FILTER (WHERE status = 'partial') as partial,
  count(*) as total
FROM notifications
GROUP BY type;

-- Mentores que mais receberam notificacoes
SELECT m.name, count(n.id) as total_notifications
FROM notifications n
JOIN class_mentors cm ON cm.class_id = n.class_id
JOIN mentors m ON m.id = cm.mentor_id
GROUP BY m.name
ORDER BY total_notifications DESC;
```

---

## 10. Evolucoes Futuras

1. **Agendamento:** Tabela `notification_schedules` com pg_cron para envio automatico X horas antes da aula
2. **Templates pre-definidos:** Tabela `notification_templates` para o admin escolher templates salvos
3. **Supabase Realtime:** Status updates em tempo real no painel
4. **Webhook de confirmacao:** Evolution API webhook de delivery para atualizar status de entrega
5. **Rate limiting:** Controle de volume para evitar bloqueio pelo WhatsApp
6. **Mensagens ricas:** Suporte a media (imagens, PDFs) via Evolution API `/message/sendMedia`

---

*Documento gerado por Aria (Architect Agent) -- arquitetando o futuro*
