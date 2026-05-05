# System Architecture — lesson-pages

> **Gerado por:** @architect (Aria) — Atualização pós EPIC-001 e EPIC-002
> **Data:** 2026-04-06
> **Projeto:** lesson-pages (Plataforma Educacional AIOS Avançado — Cohort 2026)
> **Revisão:** v2.0 (substitui system-architecture.md de 2026-04-01)

---

## 1. Visão Geral

**lesson-pages** é uma plataforma educacional para o cohort AIOS Avançado (Fevereiro–Maio 2026). Serve como portal central para mentores, alunos e administradores, com funcionalidades de calendário de aulas, controle de presença via Zoom, notificações automáticas via WhatsApp, agendamento com pg_cron e gestão de turmas (cohorts).

O projeto opera sem framework de frontend ou bundler — todo código é HTML/CSS/JS inline, servido de forma estática via Vercel e via container Docker+Nginx em VPS Contabo.

### Stack Tecnológico

| Camada | Tecnologia | Versão / Detalhes |
|---|---|---|
| **Frontend** | Vanilla HTML / CSS / JS | Sem framework, sem build system, sem bundler |
| **Estilização** | CSS inline por página | Design tokens definidos mas não aplicados universalmente |
| **Ícones** | Lucide Icons | CDN `unpkg.com/lucide@0.511.0` (pinado desde SYS-H4) |
| **Fontes** | Google Fonts (Inter) | `fonts.googleapis.com` |
| **Config central** | `js/config.js` | `window.SUPABASE_CONFIG` — URL + anon key |
| **Backend** | Supabase | PostgreSQL 15 + Auth + Edge Functions + Storage + RLS |
| **Edge Functions** | Deno (Supabase) | 4 functions deployadas |
| **Agendamento** | pg_cron (PostgreSQL) | Jobs na tabela `notification_schedules` |
| **Deploy VPS** | Docker + Nginx | `nginx:1.27-alpine`, VPS Contabo `194.163.179.68:3080` |
| **Deploy Static** | Vercel | CDN global, rewrites via `vercel.json` |
| **CI/CD** | GitHub Actions | Push `main` → SSH → docker build → compose up |
| **Integrações** | Zoom API (OAuth + S2S) | Tokens armazenados em `zoom_tokens` |
| **Integrações** | Evolution API (WhatsApp) | Envio via Edge Function `send-whatsapp` |
| **NPS** | Tally | Formulário embeddado, webhook para `student_nps` |

---

## 2. Arquitetura de Alto Nível

```
┌─────────────────────────────────────────────────────────────────────┐
│                        USUÁRIOS FINAIS                              │
│  Alunos (público)    Mentores (autenticado)    Admin (autenticado)  │
└──────────────┬────────────────────┬───────────────────┬────────────┘
               │                    │                   │
               ▼                    ▼                   ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       CAMADA DE ENTREGA                             │
│                                                                     │
│  ┌──────────────────────┐      ┌──────────────────────────────────┐ │
│  │   VERCEL (Static)    │      │  VPS Contabo (Docker + Nginx)    │ │
│  │  CDN Global          │      │  194.163.179.68:3080             │ │
│  │  vercel.json         │      │  calendario.igorrover.com.br     │ │
│  │  Rewrites + Headers  │      │  nginx.conf + security headers   │ │
│  └──────────────────────┘      └──────────────────────────────────┘ │
└─────────────────────────────┬───────────────────────────────────────┘
                              │  Static HTML/CSS/JS
                              ▼
┌─────────────────────────────────────────────────────────────────────┐
│                       SUPABASE (Backend)                            │
│  Project: gpufcipkajppykmnmdeh (calendario-aulas)                   │
│                                                                     │
│  ┌───────────────┐  ┌───────────────┐  ┌───────────────────────┐   │
│  │  PostgreSQL   │  │  Supabase     │  │  Edge Functions (Deno) │  │
│  │  15 + RLS     │  │  Auth         │  │  send-whatsapp        │   │
│  │  12+ tabelas  │  │  JWT + roles  │  │  zoom-oauth           │   │
│  │  pg_cron jobs │  │  user_metadata│  │  zoom-attendance      │   │
│  └───────────────┘  └───────────────┘  │  delivery-webhook     │   │
│                                        └───────────────────────┘   │
└──────────────────────────┬──────────────────────────────────────────┘
                           │
          ┌────────────────┼────────────────┐
          ▼                ▼                ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  Zoom API    │  │ Evolution    │  │   Tally      │
│  OAuth + S2S │  │ API          │  │   NPS Forms  │
│  Meetings    │  │ WhatsApp     │  │   Webhook    │
│  Participants│  │ Delivery ACK │  │              │
└──────────────┘  └──────────────┘  └──────────────┘
```

### Fluxo de Deploy (CI/CD)

```
git push main
     │
     ▼
GitHub Actions (.github/workflows/deploy.yml)
     │
     ├─► SSH → VPS → git pull → docker build → docker compose up -d
     │
     └─► Vercel (auto-deploy via GitHub integration)
```

---

## 3. Estrutura de Pastas

```
lesson-pages/
├── index.html                    # Hub central (239 linhas)
├── js/
│   └── config.js                 # window.SUPABASE_CONFIG (URL + anon key)
├── calendario/
│   ├── index.html                # Calendário público (811 linhas)
│   └── admin.html                # Painel admin (2.844 linhas) ⚠️
├── presenca/
│   └── index.html                # Controle de presença + Zoom (963 linhas)
├── alunos/
│   └── index.html                # Lista de alunos (616 linhas)
├── aulas/
│   └── index.html                # Lista de aulas (318 linhas)
├── escala/
│   └── index.html                # Escala de mentores (690 linhas)
├── abstracts/
│   └── index.html                # Conteúdo hardcoded (~4.973 linhas) ⚠️
├── avaliacao/                    # Formulário de avaliação
├── avaliacao-csat-nps/           # CSAT/NPS
├── equipe/                       # Página da equipe
├── relatorio/                    # Relatórios
├── aula-01/, aula-preparatorio/  # Páginas de aula individuais
├── ps-10-02-2026/, ps-pronto-socorro/  # Pronto-socorro (duplicados) ⚠️
├── aios-install/, aiox-install/  # Instalação (duplicados) ⚠️
├── interno/                      # Conteúdo interno de aulas
├── supabase/
│   ├── functions/
│   │   ├── send-whatsapp/index.ts
│   │   ├── zoom-oauth/index.ts
│   │   ├── zoom-attendance/index.ts
│   │   └── delivery-webhook/index.ts
│   └── migrations/               # 7 migrations (2026-04-02 em diante)
├── docs/
│   ├── architecture/             # system-architecture.md (este arquivo)
│   ├── frontend/                 # frontend-spec.md
│   └── stories/                  # Stories EPIC-001, EPIC-002
├── Dockerfile                    # nginx:1.27-alpine
├── vercel.json                   # Rewrites + security headers
└── .github/workflows/deploy.yml  # CI/CD SSH deploy
```

---

## 4. Dependências Externas (CDN)

Todas as dependências são carregadas via CDN, inline por página. Não existe `package.json` nem lock file no frontend.

| Biblioteca | CDN | Versão | Uso |
|---|---|---|---|
| **Supabase JS** | `cdn.jsdelivr.net/npm/@supabase/supabase-js@2` | @2 (latest minor) | Client Supabase em todas as páginas com auth |
| **Lucide Icons** | `unpkg.com/lucide@0.511.0` | 0.511.0 (pinada) | Ícones SVG em todas as páginas |
| **Google Fonts (Inter)** | `fonts.googleapis.com` | — | Tipografia base |

> ⚠️ A versão do Supabase JS (`@2`) não é pinada — atualiza automaticamente com minor/patch releases.

---

## 5. Padrões de Código

### Inicialização do Supabase

Padrão adotado após criação de `js/config.js`:

```html
<script src="/js/config.js"></script>
<script>
  const supabase = supabase.createClient(
    window.SUPABASE_CONFIG.url,
    window.SUPABASE_CONFIG.anonKey
  );
</script>
```

> ⚠️ SYS-C4 (parcial): `admin.html` ainda inicializa o cliente com a anon key inline. Páginas antigas que não incluem `js/config.js` também mantêm a key inline.

### Auth e Roles

- Autenticação via Supabase Auth (email/password)
- Roles propagadas via `user_metadata.role` no JWT (`'admin'`, `'mentor'`)
- RLS policies verificam `auth.jwt() -> 'user_metadata' ->> 'role'`
- Verificação de sessão em `onAuthStateChange` no carregamento de páginas protegidas

### CSS

- Sem framework CSS; sem CSS Modules; sem Tailwind
- Cada página possui `<style>` inline
- Design tokens definidos em `design-tokens-dark-premium.css` mas não importados universalmente
- Paleta: dark premium (`#0a0a0a`, `#111`, `#1a1a2e`, accent `#00d4ff`)

### JS

- Sem módulos ES (sem `import/export`)
- Async/await para queries Supabase
- Event listeners via `addEventListener` direto
- Sem state management; DOM manipulado diretamente

---

## 6. Edge Functions

Todas as Edge Functions são escritas em Deno (TypeScript) e deployadas no Supabase.

| Function | Trigger | Propósito |
|---|---|---|
| **send-whatsapp** | HTTP POST (admin.html + pg_cron) | Envia mensagem WhatsApp individual ou para grupo via Evolution API. Registra resultado em `notifications` (status, evolution_response, evolution_message_ids). |
| **zoom-oauth** | HTTP GET (callback OAuth) | Completa o fluxo OAuth do Zoom, troca code por tokens, armazena em `zoom_tokens`. |
| **zoom-attendance** | HTTP POST (presenca/index.html) | Busca lista de participantes de uma reunião Zoom via API S2S, faz match com `students`, registra em `zoom_participants`. |
| **delivery-webhook** | HTTP POST (Evolution API webhook) | Recebe callbacks de entrega/leitura da Evolution API, atualiza `notifications.status` para `delivered` ou `read`, popula `notifications.delivered_at`. |

### Variáveis de Ambiente das Edge Functions

> ⚠️ SYS-C2 e SYS-C3 — credenciais hardcoded detectadas nas Edge Functions.

| Variável | Function | Status |
|---|---|---|
| `EVOLUTION_API_URL` | send-whatsapp, delivery-webhook | Deve ser Supabase Secret |
| `EVOLUTION_API_KEY` | send-whatsapp, delivery-webhook | **HARDCODED** (SYS-C3) |
| `ZOOM_CLIENT_ID` | zoom-oauth, zoom-attendance | **HARDCODED** (SYS-C2) |
| `ZOOM_CLIENT_SECRET` | zoom-oauth, zoom-attendance | **HARDCODED** (SYS-C2) |
| `ZOOM_ACCOUNT_ID` | zoom-attendance (S2S) | **HARDCODED** (SYS-C2) |
| `SUPABASE_URL` | todas | Variável de runtime Supabase (OK) |
| `SUPABASE_SERVICE_ROLE_KEY` | todas | Variável de runtime Supabase (OK) |

---

## 7. Integrações

### Zoom API

| Aspecto | Detalhe |
|---|---|
| **Autenticação** | OAuth 2.0 (mentores) + Server-to-Server (admin/reports) |
| **Fluxo OAuth** | `zoom-oauth` Edge Function → callback `/api/zoom/callback.html` → tokens em `zoom_tokens` |
| **Dados consumidos** | Meeting list, participant reports (join/leave time, duration) |
| **Tabelas afetadas** | `zoom_tokens`, `zoom_meetings`, `zoom_participants` |

### WhatsApp via Evolution API

| Aspecto | Detalhe |
|---|---|
| **Envio** | `send-whatsapp` Edge Function (HTTP POST para Evolution API) |
| **Tipos de destino** | Número individual (`target_phone`) + Grupo JID (`target_group_jid`) |
| **Rastreamento de entrega** | `delivery-webhook` recebe ACK da Evolution API |
| **Status lifecycle** | `pending → processing → sent → delivered → read` (ou `failed`, `partial`, `cancelled`) |
| **Mensagens** | Templates renderizados em `notifications.message_rendered` |
| **Regra de teste** | Sempre enviar testes para `554399250490` (admin Igor) — nunca para mentores/alunos |

### pg_cron (Agendamento Automático)

| Aspecto | Detalhe |
|---|---|
| **Tabela de configuração** | `notification_schedules` |
| **Job** | `process_notification_schedules()` — função PostgreSQL chamada a cada minuto |
| **Lógica** | Verifica schedules com `trigger_at <= now()` e `status = 'pending'`, chama `send-whatsapp` |
| **UI** | Painel de agendamento em `admin.html` (EPIC-002) |

### Tally (NPS)

| Aspecto | Detalhe |
|---|---|
| **Formulário** | Embeddado via iframe/widget |
| **Webhook** | Recebe respostas, grava em `student_nps` |
| **Dados** | `score` (0–10), `feedback`, `tally_response_id`, `tally_form_id` |

---

## 8. Deploy e Infraestrutura

### Deploy Duplo

| Aspecto | VPS Contabo | Vercel |
|---|---|---|
| **URL** | `https://calendario.igorrover.com.br` | (mirrors / fallback) |
| **Container** | `lesson-pages` (nginx:1.27-alpine) | N/A |
| **Porta** | 3080 interno → 443 HTTPS via Nginx | CDN automático |
| **Trigger deploy** | Push `main` → GitHub Actions → SSH | Push `main` → Vercel auto |

### Dockerfile

```dockerfile
FROM nginx:1.27-alpine
COPY . /usr/share/nginx/html
COPY nginx.conf /etc/nginx/nginx.conf
```

### Nginx

- `nginx.conf`: security headers (CSP, HSTS, X-Frame-Options, X-Content-Type-Options)
- Clean URLs (rewrites para remover `.html`)
- Gzip habilitado

### Vercel

- `vercel.json`: rewrites + security headers espelhando Nginx
- Deploy automático via integração GitHub

### GitHub Actions

- Arquivo: `.github/workflows/deploy.yml`
- Segredos: `VPS_HOST`, `VPS_SSH_KEY`, `LESSON_PAGES_DOMAIN`
- Passos: SSH → `git pull` → `docker build` → `docker compose up -d`

### Supabase

- Projeto ID: `gpufcipkajppykmnmdeh`
- Região: (padrão Supabase)
- Migrations gerenciadas via Supabase CLI (`supabase db push`)
- Edge Functions deployadas via `supabase functions deploy`

---

## 9. Histórico de Epics

| Epic | Status | Período | Entregas |
|---|---|---|---|
| **EPIC-001** — Sistema de Notificações WhatsApp | ✅ Done | 2026-04-01 a 2026-04-02 | Tabelas `mentors`, `class_cohorts`, `class_mentors`, `notifications`; Edge Function `send-whatsapp`; webhook `delivery-webhook`; UI de notificações no `admin.html` |
| **EPIC-002** — Agendamento Automático | ✅ Done | 2026-04-02 a 2026-04-03 | Tabela `notification_schedules`; job pg_cron `process_notification_schedules()`; UI de agendamento no `admin.html` |

### Correções Avulsas (não-epic)

| ID | Correção | Data |
|---|---|---|
| SYS-C1 | `SERVICE_ROLE_KEY` removida de `presenca/index.html` | 2026-04-02 |
| SYS-H4 | CDN Lucide Icons pinada em `@0.511.0` | 2026-04-02 |
| SYS-H5 (parcial) | `js/config.js` criado para centralizar config Supabase | 2026-04-02 |
| SYS-H6 (parcial) | Baseline migration criada para `supabase/migrations/` | 2026-04-02 |

---

## 10. Inventário de Débitos Técnicos

### 🔴 CRÍTICO — Risco de segurança ou integridade de dados

| ID | Débito | Impacto | Status | Próximo passo |
|---|---|---|---|---|
| **SYS-NEW-C1** | Schema desync: `notifications.evolution_message_ids` (TEXT[]) e `notifications.delivered_at` (TIMESTAMPTZ) existem em produção (migration `20260402200000_delivery_status.sql`) mas faltavam no DDL documentado originalmente. O `delivery-webhook` depende dessas colunas. | `delivery-webhook` pode falhar silenciosamente se migration não for aplicada; dados de entrega perdidos. | ⚠️ Migration existe — verificar se foi aplicada via `supabase migration list` | Confirmar `supabase db push` e testar delivery-webhook end-to-end |
| **SYS-C2** | Credenciais Zoom (`ZOOM_CLIENT_ID`, `ZOOM_CLIENT_SECRET`, `ZOOM_ACCOUNT_ID`) hardcoded nas Edge Functions `zoom-oauth` e `zoom-attendance`. | Exposição de credenciais se código vazar; rotação de chaves exige redeploy. | ❌ Aberto | Migrar para `supabase secrets set` e `Deno.env.get()` |
| **SYS-C3** | `EVOLUTION_API_KEY` hardcoded nas Edge Functions `send-whatsapp` e `delivery-webhook`. | Mesmos riscos que SYS-C2; comprometimento do canal WhatsApp. | ❌ Aberto | Migrar para `supabase secrets set` |
| **SYS-C4** | `admin.html` ainda inicializa Supabase com anon key inline, não usando `js/config.js`. | Mudança de key exige editar múltiplos arquivos; inconsistência. | ⚠️ Parcial (config.js criado) | Refatorar `admin.html` para usar `window.SUPABASE_CONFIG` |
| **SYS-C5** | Edge Functions com `CORS: *` — qualquer origem pode chamar `send-whatsapp` e `delivery-webhook`. | Risco de abuso; qualquer URL pode disparar envios WhatsApp. | ❌ Aberto | Restringir CORS para domínios conhecidos + validar token caller |

### 🟠 ALTO — Débito estrutural que impede evolução saudável

| ID | Débito | Impacto | Status | Próximo passo |
|---|---|---|---|---|
| **SYS-H1** | Sem build system. Nenhum bundling, tree-shaking, minificação ou transpilação. | Performance degradada; impossível escalar código; sem imports nativos. | ❌ Aberto | Avaliar Vite ou esbuild como bundler mínimo |
| **SYS-H2** | Zero testes automatizados. Nenhum unit, integration ou E2E test. | Qualquer mudança pode quebrar sem detecção; risco alto em refatorações. | ❌ Aberto | Começar com Playwright E2E para fluxos críticos |
| **SYS-H3** | Sem linting nem formatação automatizada (ESLint, Prettier ou similar). | Inconsistência de código entre páginas; bugs silenciosos. | ❌ Aberto | Adicionar ESLint + Prettier com pre-commit hook |
| **SYS-H5** | JS ainda inline por página. `js/config.js` centraliza apenas a config Supabase. | Duplicação massiva de lógica; sem reuso de funções comuns. | ⚠️ Parcial | Criar `js/supabase-client.js`, `js/auth.js`, `js/notifications.js` |
| **SYS-H6** | `classes` table sem migration DDL própria. Baseline captura o estado mas sem histórico de alterações. | Alterações futuras na tabela `classes` sem rastreabilidade. | ⚠️ Parcial | Criar migration dedicada para `classes` com todas as colunas atuais |
| **SYS-H7** | `abstracts/index.html` com ~4.973 linhas de conteúdo 100% hardcoded. | Impossível atualizar conteúdo sem editar HTML; sem busca; sem versioning. | ❌ Aberto | Migrar conteúdo para tabela `abstracts` no Supabase |

### 🟡 MÉDIO — Qualidade e manutenibilidade

| ID | Débito | Impacto | Status | Próximo passo |
|---|---|---|---|---|
| **SYS-M1** | Supabase JS versão `@2` sem pin de minor/patch. | Uma atualização breaking do Supabase JS pode quebrar o site sem aviso. | ❌ Aberto | Pinar para `@supabase/supabase-js@2.X.Y` específico |
| **SYS-M2** | Sem ambiente de staging. Deploy vai direto para produção. | Bugs em produção sem triagem; impossível testar mudanças isoladas. | ❌ Aberto | Criar branch `staging` + deploy separado no Vercel |
| **SYS-M3** | Páginas duplicadas: `ps-10-02-2026/` e `ps-pronto-socorro/`; `aios-install/` e `aiox-install/`. | Confusão de manutenção; conteúdo pode divergir. | ❌ Aberto | Consolidar em uma URL canônica; redirecionar a outra |

---

## 11. Métricas do Projeto

| Métrica | Valor (2026-04-06) |
|---|---|
| Total de arquivos HTML | ~36 arquivos |
| Linhas totais estimadas | ~15.000+ linhas |
| Maior arquivo | `abstracts/index.html` (~4.973 linhas) |
| Segundo maior | `calendario/admin.html` (2.844 linhas) |
| Tabelas no banco | 17 tabelas (cohorts, students, student_cohorts, staff, classes, class_cohort_access, schedule_overrides, attendance, mentor_attendance, zoom_tokens, zoom_meetings, zoom_participants, student_nps, oauth_states, mentors, class_cohorts, class_mentors, notifications, notification_schedules) |
| Edge Functions | 4 (send-whatsapp, zoom-oauth, zoom-attendance, delivery-webhook) |
| Migrations | 7 arquivos (todas em 2026-04-02) |
| Epics concluídas | 2 (EPIC-001, EPIC-002) |
| Débitos críticos abertos | 4 (SYS-NEW-C1 parcial, SYS-C2, SYS-C3, SYS-C5) |
| Débitos totais | 13 |

---

## 12. EPIC-015 — Área CS Dedicada (em desenvolvimento)

**Status:** Wave 1 em implementação (2026-05-05)
**Refs:** `docs/stories/EPIC-015-cs-area/spec/spec.md`, `docs/architecture/ADR-015`, `docs/architecture/ADR-016`

### Schema EPIC-015 (Story 15.A)

7 tabelas novas + 1 audit log + 1 throttle:

| Tabela | Propósito | Story |
|---|---|---|
| `survey_versions` | Snapshots imutáveis de questionários (versionamento) | 15.A + 15.G |
| `ac_purchase_events` | Webhooks AC com workflow (received/processing/processed/failed/duplicate) | 15.A + 15.B |
| `pending_student_assignments` | Fila CS para alunos órfãos de cohort | 15.A + 15.F |
| `ac_product_mappings` | Regras N:1 produto AC → cohort + survey + template | 15.A + 15.D |
| `ac_dispatch_callbacks` | Confirmações outbound para AC com retry exp 3x | 15.A + 15.C |
| `meta_templates` | Registry templates Meta WhatsApp aprovados | 15.A + 15.8 |
| `student_audit_log` | Auditoria mudanças phone/email/cohort em students | 15.A + 15.3 |
| `alert_history` | Throttle de alerts Slack (1/h por chave) | 15.A + 15.E |

### Extensões em Tabelas Existentes

| Tabela | Coluna | Propósito |
|---|---|---|
| `students` | `ac_contact_id TEXT UNIQUE` | Mapping com ActiveCampaign contact |
| `survey_links` | `delivered_at`, `read_at` | Tracking 4 timestamps NFR-16 |
| `survey_links` | `version_id` | Aponta para survey_version usada no envio |
| `survey_links` | `meta_message_id TEXT UNIQUE sparse` | Correlação webhook Meta delivery |
| `survey_links` | `cohort_snapshot_name TEXT` | Histórico imutável (NFR-19) |
| `surveys` | `category` | nps/csat/onboarding/feedback/custom |
| `surveys` | `current_version_id` | Aponta para versão ativa |

### Helper SQL Functions

- `is_cs_or_admin()` — STABLE função para RLS policies
- `process_ac_purchase_events_batch()` — worker SECURITY DEFINER chamado por pg_cron 30s (ADR-016 §3)
- `recently_alerted(key, within)` — throttle helper Story 15.E
- `send_slack_alert(key, msg)` — placeholder Story 15.E
- `alert_slack_if_unhealthy()` — placeholder Story 15.E

### Views

- `ac_integration_health` — métricas agregadas eventos AC últimas 24h por hora/status
- `student_dispatch_timeline` — timeline aluno-centric com 4 timestamps + cohort_snapshot (FR-12/17)

### pg_cron Jobs (4)

| Job | Schedule | Função |
|---|---|---|
| `epic015-process-ac-events` | 30s | `process_ac_purchase_events_batch()` |
| `epic015-warmup-edge-functions` | `*/4 * * * *` | HTTP GET warmup 3 edge functions |
| `epic015-alert-ac-health` | `*/15 * * * *` | `alert_slack_if_unhealthy()` |
| `epic015-purge-old-ac-events` | `0 3 * * *` | DELETE ac_purchase_events > 90d (LGPD) |

### Edge Functions (Wave 3)

3 novas edge functions Deno:
- `ac-purchase-webhook` (15.B) — minimal-sync handler (HMAC + INSERT + 200)
- `ac-report-dispatch` (15.C) — callback outbound AC com retry exp
- `meta-delivery-webhook` (15.I) — receives messages.update do Meta

### RLS Pattern

Todas tabelas EPIC-015 usam `is_cs_or_admin()` helper. Service role bypass em `ac_purchase_events` (worker), `ac_dispatch_callbacks` (callback function), `student_audit_log` (DDL triggers).

---

*Documento gerado por @architect (Aria) — Synkra AIOX v2.0*
*Última atualização: 2026-05-05 — @data-engineer (Dara) Story 15.A*
*Próxima revisão recomendada: após conclusão Wave 3 EPIC-015*
