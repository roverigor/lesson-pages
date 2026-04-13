# System Architecture — lesson-pages (Brownfield Discovery Fase 1)

> **Data:** 2026-04-13
> **Agente:** @architect (Aria)
> **Projeto:** lesson-pages — Painel Educacional Academia Lendaria
> **Dominio:** https://painel.igorrover.com.br

---

## 1. Visao Geral

**Stack:** HTML/CSS/JS vanilla + Supabase (Postgres + Edge Functions + Auth) + Nginx + Docker
**Deploy:** GitHub Actions → SSH → VPS Contabo (194.163.179.68) → Container Docker porta 3080
**Supabase Project:** `gpufcipkajppykmnmdeh` (AWS us-east-2, Postgres 17.6)

Nao ha framework frontend (React/Vue/Next.js). Cada pagina e um HTML standalone com CSS inline e JS vanilla que consome Supabase via PostgREST (client SDK).

---

## 2. Mapa de Paginas (22 HTML files)

### 2.1 Paginas Administrativas (auth Supabase)

| Pagina | LOC | Funcao |
|--------|-----|--------|
| `admin/index.html` | 1.024 | SPA admin com 14 views (dashboard, calendar, turmas, staff, classes, notify, schedules, zoom, abstracts, surveys) |
| `turma/detalhe.html` | **2.358** | Detalhe turma: 9 tabs (alunos, presenca, WA, equipe, zoom, resumos, avisos, avaliacoes, fontes) |
| `turma/index.html` | 210 | Listagem de turmas |
| `presenca/index.html` | 1.370 | Controle de presenca (standalone + iframe no admin) |
| `alunos/index.html` | 812 | Gestao de alunos CSV + enrichment |
| `relatorio/index.html` | 910 | Relatorio de presencas da equipe |
| `equipe/index.html` | 842 | Equipe pedagogica por turma |
| `calendario/admin.html` | 926 | Calendario admin |

### 2.2 Paginas Semi-publicas

| Pagina | LOC | Auth | Funcao |
|--------|-----|------|--------|
| `calendario/index.html` | 1.081 | Senha localStorage | Calendario publico |
| `perfil/index.html` | 639 | Nenhuma | Perfil de presenca por aluno |
| `avaliacao/responder.html` | 691 | Token JWT query string | Responder survey |
| `avaliacao/index.html` | 517 | Nenhuma | Overview avaliacoes |

### 2.3 Paginas de Conteudo (publicas)

| Pagina | LOC | Funcao |
|--------|-----|--------|
| `abstracts/index.html` | 1.312 | Resumos de aulas |
| `analise-interna/index.html` | 9.075 | Analise GPS/ML (maior arquivo) |
| `cohort-fundamentals-c3/index.html` | 1.909 | Cohort especifico |
| `manual-aios/index.html` | 1.718 | Manual AIOS |
| `squad-creator/index.html` | 1.677 | Criador de squads |
| Paginas de aula (6 arquivos) | ~200-500 cada | Conteudo de aulas individuais |

---

## 3. Modulos JS do Admin (14 arquivos, ~4.325 LOC total)

| Arquivo | LOC | Responsabilidade |
|---------|-----|-----------------|
| `js/config.js` | 12 | SUPABASE_URL + anon key |
| `js/admin/supabase-client.js` | 4 | Cria cliente `sb` |
| `js/admin/config.js` | 108 | Dados estaticos (TEACHERS, COURSES, feriados) |
| `js/admin/state.js` | 25 | Variaveis globais mutaveis compartilhadas |
| `js/admin/utils.js` | 83 | showToast, showDeleteConfirm, generateDates |
| `js/admin/auth.js` | 58 | Login/logout Supabase |
| `js/admin/attendance.js` | 513 | CRUD presencas |
| `js/admin/staff.js` | 121 | CRUD staff |
| `js/admin/classes.js` | 547 | CRUD turmas/cohorts/class_mentors |
| `js/admin/notifications.js` | 428 | Envio WA + agendamento |
| `js/admin/schedules.js` | 167 | Notification schedules |
| `js/admin/zoom.js` | **967** | Matching Zoom (Jaro-Winkler, dedup, vinculos) |
| `js/admin/abstracts.js` | 160 | CRUD resumos |
| `js/admin/surveys.js` | **964** | Form builder + gestao surveys |
| `js/admin/views.js` | 172 | switchView + renderReport |
| `js/admin/init.js` | 8 | Bootstrap |

---

## 4. Banco de Dados (36 tabelas + 1 view)

### 4.1 Tabelas Core

| Tabela | Rows | Funcao | FK Principal |
|--------|------|--------|-------------|
| `cohorts` | 7 | Turmas | — |
| `classes` | 10 | Aulas (tipo PS/Aula) | — |
| `class_cohorts` | 14 | Vinculo N:N aula↔turma | classes, cohorts |
| `class_mentors` | 90 | Escala equipe por aula | classes, mentors |
| `mentors` | 15 | Equipe (professores, hosts) | — |
| `staff` | 15 | Equipe (espelho de mentors + email/category) | — |

### 4.2 Tabelas de Alunos

| Tabela | Rows | Funcao | Obs |
|--------|------|--------|-----|
| `student_imports` | **490** | CSV importado — fonte da verdade | cohort_id FK |
| `students` | **777** | **LEGADO** — FK target de zoom_participants | Duplicatas, mentores misturados |
| `student_cohorts` | 869 | Vinculo N:N aluno↔turma | students FK |
| `wa_group_members` | 137 | Membros do grupo WA por turma | cohorts FK |

### 4.3 Tabelas Zoom

| Tabela | Rows | Funcao |
|--------|------|--------|
| `zoom_meetings` | 18 | Reunioes importadas |
| `zoom_participants` | **1.074** | Registros brutos de conexao |
| `zoom_tokens` | 1 | OAuth tokens por mentor |
| `zoom_host_sessions` | 2 | Sessoes ativas de host |
| `zoom_import_queue` | 8 | Fila de importacao |
| `zoom_link_audit` | 2 | Auditoria de vinculos |
| `zoom_chat_messages` | 0 | Mensagens do chat (schema pronto, nao populado) |
| `zoom_absence_alerts` | 0 | Alertas de ausencia |

### 4.4 Tabelas de Notificacao

| Tabela | Rows | Funcao |
|--------|------|--------|
| `notifications` | 76 | Fila de envio WA |
| `notification_schedules` | 0 | Agendamentos periodicos |

### 4.5 Tabelas de Survey

| Tabela | Rows | Funcao |
|--------|------|--------|
| `surveys` | 2 | Pesquisas criadas |
| `survey_questions` | 7 | Perguntas |
| `survey_links` | 137 | Links individuais por aluno |
| `survey_responses` | 11 | Respostas |
| `survey_answers` | 35 | Respostas por pergunta |
| `student_nps` | 0 | NPS (migrando para surveys) |

### 4.6 Tabelas de Engajamento (schema pronto, sem dados)

| Tabela | Rows | Funcao |
|--------|------|--------|
| `engagement_daily_ranking` | 0 | Ranking diario |
| `whatsapp_group_messages` | 0 | Mensagens WA capturadas |

### 4.7 Outras

| Tabela | Rows | Funcao |
|--------|------|--------|
| `attendance` | 213 | Presenca manual da equipe |
| `schedule_overrides` | 70 | Substituicoes de escala |
| `class_recordings` | 3 | Gravacoes + transcricoes |
| `class_materials` | 0 | Materiais de aula |
| `lesson_abstracts` | 9 | Resumos publicados |
| `app_config` | 2 | Configuracoes KV |
| `oauth_states` | 0 | OAuth state temporario |

---

## 5. Integracoes Externas

### 5.1 Supabase (Backend Principal)

| Recurso | Uso |
|---------|-----|
| **Auth** | Email/senha para admin (anon key publica + RLS) |
| **PostgREST** | CRUD de todas as tabelas via JS SDK |
| **Edge Functions** | 7 funcoes Deno (ver abaixo) |
| **pg_cron** | 4 jobs agendados |
| **pg_net** | Trigger async para envio WA |
| **Realtime** | Habilitado mas nao utilizado |
| **Storage** | Habilitado mas nao utilizado |

### 5.2 Edge Functions (7)

| Funcao | Trigger | Funcao |
|--------|---------|--------|
| `send-whatsapp` | pg_net trigger + chamada direta | Envia msg WA via Evolution API |
| `zoom-oauth` | Redirect do Zoom | Fluxo OAuth por mentor |
| `zoom-attendance` | pg_cron (2min) | Processa fila de importacao Zoom |
| `zoom-webhook` | Webhook Zoom | Recebe meeting.ended, recording.completed |
| `sync-wa-group` | Chamada manual | Sincroniza membros do grupo WA |
| `dispatch-survey` | Chamada manual | Envia links de survey em chunks via WA |
| `delivery-webhook` | Webhook Evolution | Tracking de entrega/leitura WA |

### 5.3 APIs Externas

| Servico | Uso | Credenciais |
|---------|-----|-------------|
| **Zoom API** | OAuth (por mentor) + S2S (admin) + Webhooks | env vars Supabase |
| **Evolution API (WhatsApp)** | Envio de msgs + sync grupo + webhooks | env vars Supabase |
| **OpenAI** | Resumo de transcricoes (gpt-4o-mini) | env var Supabase |

### 5.4 Deploy Pipeline

```
git push main → GitHub Actions → SSH VPS → git pull → docker build → docker compose up
```

- VPS: Contabo 194.163.179.68
- Container: lesson-pages:latest (Nginx 1.27 Alpine)
- Build: Node 20 (minify JS) → Nginx (serve estaticos)
- Dominio: painel.igorrover.com.br (Nginx reverse proxy)

---

## 6. Padrao de Auth

| Metodo | Paginas | Seguranca |
|--------|---------|-----------|
| Supabase email/senha + RLS | 8 paginas admin | Adequado |
| Senha local + localStorage | calendario publico | Fraco (senha no client) |
| Token JWT via query string | avaliacao/responder | Adequado (single-use) |
| Sem auth | 10+ paginas de conteudo | Intencional |

---

## 7. Problemas Arquiteturais Identificados

### CRITICO

| # | Problema | Impacto |
|---|---------|---------|
| A1 | **Tabela `students` legada (777 rows) coexiste com `student_imports` (490 rows)** | Dados duplicados, FKs apontam para tabela errada, contagens inconsistentes |
| A2 | **`student_cohorts` (N:N) coexiste com `students.cohort_id` (FK direta)** | Migracao incompleta para modelo multi-turma |
| A3 | **Service role key commitada em migration SQL** | Bypass total de RLS exposto no repositorio |
| A4 | **Supabase URL+key hardcoded em 6+ paginas** em vez de usar `/js/config.js` | Manutencao fragil — mudar key exige editar 6 arquivos |

### ALTO

| # | Problema | Impacto |
|---|---------|---------|
| A5 | **`showToast` duplicado em 10 lugares** diferentes | Manutencao impossivel — corrigir bug exige 10 edits |
| A6 | **Login overlay CSS inline em 8+ paginas** (template existe mas ninguem importa) | Idem |
| A7 | **Admin usa iframes para 4 views** (alunos, presenca, aulas, relatorio) | Sessao desconectada entre parent e frame, UX inconsistente |
| A8 | **`turma/detalhe.html` monolito de 2.358 linhas** | CSS + HTML + JS em 1 arquivo — impossivel testar, dificil manter |
| A9 | **MENTOR_COLORS com arrays diferentes** em config vs utils | Mesma pessoa pode ter cores diferentes em paginas diferentes |
| A10 | **Tabelas com schema pronto mas sem dados** (6 tabelas) | Features anunciadas mas nao operacionais |
| A11 | **Indexes duplicados** em class_mentors e lesson_abstracts | Overhead de storage desnecessario |

### MEDIO

| # | Problema | Impacto |
|---|---------|---------|
| A12 | **RLS de student_imports e wa_group_members** e "authenticated full access" | Menos restritivo que o padrao admin-only do restante |
| A13 | **`js/admin/config.js` hardcoda 12 professores com datas** | Qualquer mudanca de calendario exige deploy |
| A14 | **Nenhuma pagina importa `templates/login-overlay.css`** | Arquivo morto |
| A15 | **Realtime e Storage habilitados mas nao utilizados** | Custo desnecessario no plano Supabase |
| A16 | **`generateDates`/`fmtDate` duplicados em 6+ lugares** | Versoes divergentes causam bugs sutis |

---

## 8. Metricas

| Metrica | Valor |
|---------|-------|
| Total HTML files | 22 |
| Total JS files (projeto) | 18 |
| Total SQL migrations | 50 |
| Total tabelas DB | 36 + 1 view |
| Total Edge Functions | 7 |
| Maior arquivo | analise-interna (9.075 LOC) |
| Maior arquivo funcional | turma/detalhe.html (2.358 LOC) |
| Total LOC estimado (HTML+JS) | ~25.000 |
| Total rows no DB | ~5.000 |

---

*Documento gerado por @architect (Aria) — Brownfield Discovery Fase 1*
