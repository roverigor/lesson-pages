# Technical Debt Assessment — DRAFT

> **Status:** DRAFT — Aguardando revisao dos especialistas
> **Gerado por:** @data-engineer (Dara) — consolidacao System + Database
> **Data:** 2026-04-06
> **Projeto:** lesson-pages / calendario.igorrover.com.br
> **Supabase:** `gpufcipkajppykmnmdeh`

---

## Para Revisao dos Especialistas

Este documento consolida os debitos tecnicos identificados nas fases 1-3 do Brownfield Discovery.
As secoes de **Frontend/UX** e **Qualidade** estao pre-preenchidas com debitos inferidos do codigo — **@ux-design-expert deve validar e corrigir** os itens UX-* antes da finalizacao.

---

## Resumo Executivo

| Metrica | Valor |
|---------|-------|
| Total de debitos identificados | ~35 |
| Criticos | 7 |
| Altos | 9 |
| Medios | 13 |
| Baixos | 6 |
| Debitos resolvidos (desde 01/04) | 4 |

| Area | Quantidade |
|------|-----------|
| Seguranca | 6 |
| Schema / Database | 9 |
| Frontend / UX | 10 |
| Qualidade de Codigo | 5 |
| Performance | 3 |
| Manutencao / Infra | 3 |

---

## 1. Debitos de Seguranca

> Prioridade maxima — impactam dados de alunos, mentores e credenciais de terceiros.

### DB-E1 — Credenciais Zoom hardcoded (CRITICO)

- **Severidade:** CRITICO
- **Arquivos:** `supabase/functions/zoom-oauth/index.ts`, `supabase/functions/zoom-attendance/index.ts`
- **Problema:** `client_id`, `client_secret` e credenciais S2S do Zoom estao hardcoded como fallback no codigo. Expostos no historico git.
- **Risco:** Comprometimento da conta Zoom corporativa. Zoom pode revogar acesso.
- **Acao:** Mover para Supabase Vault / env secrets. Rodar git filter-branch ou BFG para remover do historico.

### DB-E2 — Evolution API credentials hardcoded (CRITICO)

- **Severidade:** CRITICO
- **Arquivo:** `supabase/functions/send-whatsapp/index.ts`
- **Problema:** URL da instancia, API key e nome da instancia Evolution hardcoded.
- **Risco:** Qualquer pessoa com acesso ao repo pode enviar mensagens WhatsApp pela instancia da empresa.
- **Acao:** Mover para env secrets. Auditar uso historico da API.

### DB-NEW-C2 — CHECK constraint de `notifications.status` incompleto (CRITICO)

- **Severidade:** CRITICO
- **Tabela:** `notifications`
- **Problema:** O `delivery-webhook` atualiza `status` para `'delivered'` e `'read'`, mas o CHECK constraint nao inclui esses valores (`pending`, `processing`, `sent`, `partial`, `failed`, `cancelled`).
- **Risco:** **Todas as atualizacoes do delivery-webhook falham silenciosamente em producao.** Nenhuma confirmacao de entrega e registrada.
- **Acao:** Migration urgente: `ALTER TABLE notifications DROP CONSTRAINT ...; ALTER TABLE notifications ADD CONSTRAINT ... CHECK (status IN ('pending','processing','sent','partial','failed','cancelled','delivered','read'));`

### SYS-C2 — Autenticacao sem MFA (ALTO)

- **Severidade:** ALTO
- **Area:** Supabase Auth
- **Problema:** Painel admin acessivel com apenas email/senha. Sem MFA configurado.
- **Risco:** Comprometimento de conta admin = acesso total a dados de alunos e mentores.
- **Acao:** Habilitar TOTP MFA no Supabase Auth para usuarios admin.

### SYS-C3 — Sem politica de senha forte (ALTO)

- **Severidade:** ALTO
- **Area:** Supabase Auth
- **Problema:** Sem requisito de complexidade de senha documentado ou configurado.
- **Acao:** Configurar password strength policy no Supabase Auth.

### DB-E3 — CORS wildcard em Edge Functions (ALTO)

- **Severidade:** ALTO
- **Arquivos:** Todas as 3 Edge Functions (`send-whatsapp`, `zoom-oauth`, `zoom-attendance`)
- **Problema:** `Access-Control-Allow-Origin: *` — qualquer origem pode chamar as funcoes.
- **Acao:** Restringir para `https://calendario.igorrover.com.br` e origens autorizadas.

### DB-R2 — Tabela `classes` sem RLS (ALTO)

- **Severidade:** ALTO
- **Tabela:** `classes`
- **Problema:** Nao ha DDL documentado para `classes`, portanto nao ha RLS configurado. Qualquer usuario autenticado pode ler e potencialmente escrever.
- **Acao:** Criar DDL e RLS para `classes` — bloquear writes para admin, reads para authenticated.

---

## 2. Debitos de Schema / Database

> Debitos que afetam integridade de dados, rastreabilidade e operacao do sistema.

### DB-NEW-C1 — `evolution_message_ids` e `delivered_at` sem DDL (CRITICO)

- **Severidade:** CRITICO
- **Tabela:** `notifications`
- **Problema:** O `delivery-webhook` usa `.contains("evolution_message_ids", [msgId])` e `update({delivered_at: ...})`, mas essas colunas nao existem em nenhum schema file ou migration documentada.
- **Estado atual:** Desconhecido — as colunas podem ou nao existir em producao.
- **Risco:** Se nao existem: queries falham, entrega nunca e confirmada. Se existem: sem documentacao, sem controle de schema.
- **Acao:** Verificar estado em producao. Criar migration documentando as colunas. Ver pergunta para @data-engineer na Secao 6.

### DB-C1 — Tabela `classes` sem schema file (CRITICO)

- **Severidade:** CRITICO
- **Tabela:** `classes`
- **Problema:** Tabela central referenciada por 5 outras tabelas (class_cohorts, class_mentors, zoom_meetings, notifications, notification_schedules) sem DDL documentado.
- **Schema inferido do codigo:** `id UUID, name TEXT, weekday INT, time_start TIME, time_end TIME, start_date DATE, end_date DATE, professor TEXT, host TEXT, color TEXT, active BOOLEAN`
- **Acao:** Criar `db/classes.sql` e migration correspondente.

### DB-NEW-M1 — `notification_schedules` sem schema file (MEDIO)

- **Severidade:** MEDIO
- **Tabela:** `notification_schedules`
- **Problema:** Tabela operacional (EPIC-002 Done) sem schema file de referencia em `db/`. DDL existe apenas na migration baseline.
- **Acao:** Criar `db/notification-schedules.sql` para consistencia com o restante do projeto.

### DB-M1 — Schema files nao sao migrations Supabase CLI (ALTO)

- **Severidade:** ALTO
- **Area:** `db/` vs `supabase/migrations/`
- **Problema:** Os arquivos em `db/` sao SQL manuais sem controle de versao. A unica migration real e a baseline. Qualquer alteracao de schema precisa ser aplicada manualmente.
- **Acao:** Converter schema files em migrations versionadas. Adotar fluxo `supabase migration new`.

### DB-S1 — `attendance.lesson_date` como TEXT (MEDIO)

- **Severidade:** MEDIO
- **Tabela:** `attendance`
- **Problema:** Campo de data armazenado como TEXT sem validacao de formato.
- **Risco:** Queries por intervalo, ordenacao e integridade referencial comprometidas.
- **Acao:** `ALTER TABLE attendance ALTER COLUMN lesson_date TYPE DATE USING lesson_date::DATE;`

### DB-S2 — `attendance.teacher_name` desnormalizado (MEDIO)

- **Severidade:** MEDIO
- **Tabela:** `attendance`
- **Problema:** Nome do mentor armazenado como TEXT livre, sem FK para `mentors`. Inconsistencia com renomeacoes.
- **Acao:** Adicionar coluna `mentor_id UUID REFERENCES mentors(id)` e migrar dados.

### DB-C3 + DB-C4 — Dados reais no seed da migration baseline (ALTO)

- **Severidade:** ALTO
- **Migration:** `20260402175137_notifications_schema.sql`
- **Problema:** 14 telefones reais de mentores e Group JIDs de WhatsApp hardcoded na migration que esta no historico git publico.
- **Acao:** Remover dados do arquivo. Usar `supabase/seed.sql` separado (gitignored) para dados sensiveis. Considerar BFG para historico.

---

## 3. Debitos de Frontend / UX

> **Nota:** Itens UX-* foram inferidos da analise de codigo. @ux-design-expert deve validar, corrigir severidades e adicionar itens faltantes antes da finalizacao deste documento.

### UX-C1 — `admin.html` monolito de ~2844 linhas (CRITICO / ALTO)

- **Severidade:** ALTO
- **Arquivo:** `admin.html`
- **Problema:** Toda a logica de administracao em um unico arquivo HTML com JS inline. Inclui gerenciamento de turmas, mentores, notificacoes e agendamentos misturados.
- **Impacto:** Qualquer alteracao tem risco alto de regressao. Impossivel testar isoladamente. Tempo de carregamento aumenta com o arquivo.
- **Acao:** Quebrar em modulos JS separados por dominio. Ver pergunta para @ux-design-expert na Secao 6.

### UX-H1 — Zero consistencia visual entre paginas (ALTO)

- **Severidade:** ALTO
- **Problema:** Cada pagina tem estilos proprios sem design system ou componentes compartilhados.
- **Acao:** Criar design tokens minimos (cores, tipografia, espacamento) em arquivo CSS compartilhado.

### UX-H2 — URLs e constantes hardcoded por pagina (ALTO)

- **Severidade:** ALTO
- **Problema:** Supabase URL, anon key e outras constantes repetidas em cada arquivo HTML/JS.
- **Acao:** Centralizar em `config.js` importado por todas as paginas.

### UX-H3 — Sem estados de loading (ALTO)

- **Severidade:** ALTO
- **Problema:** Operacoes assincronas (busca de dados, envio de formularios) sem feedback visual para o usuario.
- **Acao:** Adicionar spinners/skeletons nas operacoes criticas.

### UX-H4 — Sem estados de erro padronizados (ALTO)

- **Severidade:** ALTO
- **Problema:** Erros de API ou rede nao sao exibidos de forma consistente — alguns silenciosos, outros com `alert()`.
- **Acao:** Criar componente de toast/notification reutilizavel.

### UX-M1 — Sem validacao client-side nos formularios (MEDIO)

- **Severidade:** MEDIO
- **Problema:** Formularios enviados sem validacao previa — erros so aparecem apos request ao servidor.
- **Acao:** Adicionar validacao HTML5 e JS antes do submit.

### UX-M2 — Sem paginacao em listagens longas (MEDIO)

- **Severidade:** MEDIO
- **Problema:** Listagens de alunos e historico de notificacoes carregam todos os registros sem limite.
- **Acao:** Implementar paginacao ou infinite scroll com `.range()` do Supabase.

### UX-M3 — Sem confirmacao em acoes destrutivas (MEDIO)

- **Severidade:** MEDIO
- **Problema:** Exclusao de registros sem dialogo de confirmacao.
- **Acao:** Adicionar modal de confirmacao para deletes.

### UX-M4 — Responsividade inconsistente (MEDIO)

- **Severidade:** MEDIO
- **Problema:** Algumas paginas quebram em mobile. Painel admin nao foi projetado para telas pequenas.
- **Acao:** Auditar e corrigir breakpoints criticos.

### UX-L1 — Sem favicon e meta tags basicas (BAIXO)

- **Severidade:** BAIXO
- **Problema:** Paginas sem favicon, `og:title`, `og:description` ou `meta viewport` consistente.
- **Acao:** Adicionar head padrao a todas as paginas.

---

## 4. Debitos de Qualidade de Codigo

### SYS-H1 — Sem build / bundling (ALTO)

- **Severidade:** ALTO
- **Problema:** Assets JS/CSS servidos sem minificacao, sem tree-shaking, sem cache busting automatico.
- **Impacto:** Performance de carregamento; atualizacoes de codigo podem ficar em cache no browser.
- **Acao:** Introducao de Vite ou esbuild como bundler minimo.

### SYS-H2 — Zero testes automatizados (ALTO)

- **Severidade:** ALTO
- **Problema:** Nenhum teste unitario, de integracao ou E2E. Regressoes so sao detectadas em producao.
- **Acao:** Adicionar testes criticos para Edge Functions (send-whatsapp FSM, process_notification_schedules). Vitest para JS.

### SYS-H3 — Sem linter / formatter (ALTO)

- **Severidade:** ALTO
- **Problema:** Sem ESLint, Prettier ou equivalente. Codigo inconsistente entre arquivos.
- **Acao:** Adicionar ESLint + Prettier com pre-commit hook (lint-staged + husky).

### SYS-H5 — JS inline por pagina (MEDIO)

- **Severidade:** MEDIO
- **Problema:** Logica de negocio misturada com HTML em `<script>` tags. Impossivel reutilizar ou testar.
- **Acao:** Extrair para arquivos `.js` separados por modulo.

### SYS-C5 — Sem CSP (Content Security Policy) (ALTO)

- **Severidade:** ALTO
- **Problema:** Sem headers CSP configurados no Nginx. Vulneravel a XSS.
- **Acao:** Configurar CSP no Nginx para restringir origens de scripts e estilos.

---

## 5. Matriz de Priorizacao Preliminar

> Impacto e Esforco em escala 1-5. Prioridade = Impacto / Esforco (quanto maior, melhor ROI).
> Quick Win = alto impacto, baixo esforco (Impacto >= 4, Esforco <= 2).

| ID | Debito | Area | Impacto | Esforco | Prioridade | Quick Win? |
|----|--------|------|---------|---------|-----------|-----------|
| DB-NEW-C2 | CHECK constraint `notifications.status` incompleto | DB | 5 | 1 | 5.0 | SIM |
| DB-NEW-C1 | `evolution_message_ids`/`delivered_at` sem DDL | DB | 5 | 1 | 5.0 | SIM |
| DB-E3 | CORS wildcard em Edge Functions | Seguranca | 4 | 1 | 4.0 | SIM |
| SYS-C5 | Sem CSP no Nginx | Seguranca | 4 | 1 | 4.0 | SIM |
| DB-E1 | Credenciais Zoom hardcoded | Seguranca | 5 | 2 | 2.5 | SIM |
| DB-E2 | Evolution API credentials hardcoded | Seguranca | 5 | 2 | 2.5 | SIM |
| DB-C1 | Tabela `classes` sem DDL | DB | 5 | 2 | 2.5 | SIM |
| DB-R2 | Sem RLS para `classes` | Seguranca / DB | 4 | 2 | 2.0 | SIM |
| SYS-H3 | Sem linter/formatter | Qualidade | 3 | 1 | 3.0 | SIM |
| UX-H2 | Constantes hardcoded por pagina | Frontend | 4 | 2 | 2.0 | SIM |
| SYS-C2 | Sem MFA para admin | Seguranca | 5 | 2 | 2.5 | SIM |
| DB-M1 | Schema files sem migrations Supabase CLI | DB | 4 | 3 | 1.3 | NAO |
| DB-S1 | `lesson_date` como TEXT | DB | 3 | 2 | 1.5 | NAO |
| DB-S2 | `teacher_name` desnormalizado | DB | 3 | 3 | 1.0 | NAO |
| UX-C1 | `admin.html` monolito 2844 linhas | Frontend | 4 | 4 | 1.0 | NAO |
| UX-H1 | Zero consistencia visual | UX | 3 | 4 | 0.75 | NAO |
| UX-H3 | Sem loading states | UX | 4 | 3 | 1.3 | NAO |
| UX-H4 | Sem error states padronizados | UX | 4 | 3 | 1.3 | NAO |
| SYS-H1 | Sem build/bundling | Qualidade | 3 | 3 | 1.0 | NAO |
| SYS-H2 | Zero testes automatizados | Qualidade | 5 | 5 | 1.0 | NAO |
| DB-C3/C4 | Dados reais no seed | Seguranca / DB | 4 | 3 | 1.3 | NAO |
| DB-NEW-L1 | `last_triggered_at` sem index | Performance | 2 | 1 | 2.0 | SIM |
| DB-I1 | Sem index `notifications.processed_at` | Performance | 2 | 1 | 2.0 | SIM |
| DB-M2 | Sem `supabase/config.toml` | Infra | 2 | 1 | 2.0 | SIM |
| DB-NEW-M1 | `notification_schedules` sem schema file | DB | 2 | 1 | 2.0 | SIM |
| UX-M1 | Sem validacao client-side | UX | 3 | 2 | 1.5 | NAO |
| UX-M2 | Sem paginacao em listagens | UX | 3 | 2 | 1.5 | NAO |
| UX-M3 | Sem confirmacao em acoes destrutivas | UX | 3 | 2 | 1.5 | NAO |
| UX-M4 | Responsividade inconsistente | UX | 3 | 3 | 1.0 | NAO |
| SYS-H5 | JS inline por pagina | Qualidade | 3 | 3 | 1.0 | NAO |
| SYS-C3 | Sem politica de senha forte | Seguranca | 3 | 1 | 3.0 | SIM |
| DB-S3 | `professor`/`host` como TEXT em `classes` | DB | 2 | 2 | 1.0 | NAO |
| DB-R3 | `zoom_tokens` acessivel a qualquer admin | DB / Seguranca | 3 | 2 | 1.5 | NAO |
| UX-L1 | Sem favicon/meta tags basicas | UX | 1 | 1 | 1.0 | SIM |
| DB-S4 | `students.name DEFAULT ''` | DB | 1 | 1 | 1.0 | SIM |

**Quick Wins identificados (14):** DB-NEW-C2, DB-NEW-C1, DB-E3, SYS-C5, DB-E1, DB-E2, DB-C1, DB-R2, SYS-H3, UX-H2, SYS-C2, SYS-C3, DB-NEW-L1, DB-I1, DB-M2, DB-NEW-M1, UX-L1, DB-S4

---

## 6. Perguntas para Especialistas

### Para @data-engineer (Dara)

> Estas perguntas requerem verificacao direta no projeto Supabase (`gpufcipkajppykmnmdeh`).

- **[URGENTE] DB-NEW-C1:** As colunas `evolution_message_ids` (TEXT[]) e `delivered_at` (TIMESTAMPTZ) existem na tabela `notifications` em producao? Verificar via Supabase Dashboard > Table Editor > notifications > columns.
- **[URGENTE] DB-NEW-C2:** O CHECK constraint de `notifications.status` em producao inclui os valores `'delivered'` e `'read'`? Se nao, o delivery-webhook esta falhando silenciosamente desde o deploy. Migration corretiva deve ser criada com prioridade maxima.
- **DB-M2:** Ha planos para adicionar `supabase/config.toml` para possibilitar reproducao local do ambiente?
- **DB-C3/C4:** Os dados de telefone e JIDs na migration baseline sao os dados reais de producao ou foram substituidos? O historico git ja foi limpo?

### Para @ux-design-expert (Uma)

> Itens UX-* foram inferidos — necessitam validacao.

- **[DECISAO CRITICA] UX-C1:** O `admin.html` deveria ser refatorado em componentes separados agora (como parte do proximo epic) ou numa fase futura apos estabilizacao do backend? Qual e o threshold de dor atual com o monolito?
- **UX-H1:** Ha um design system ou guia de estilos existente (mesmo que informal) que deveria ser aplicado ao projeto?
- **UX-H3/H4:** Quais fluxos tem mais reclamacoes de usuarios sobre falta de feedback? (loading, erros, confirmacoes)
- **UX-M4:** Quais paginas sao acessadas via mobile com frequencia? (para priorizar responsividade)
- **Itens faltantes:** Ha debitos de UX/Frontend que nao foram capturados neste draft?

### Para @qa (Quinn)

- **Cobertura atual:** Ha testes manuais documentados que cobrem os fluxos criticos (envio WhatsApp, Zoom sync, presenca)?
- **Regressoes temidas:** Quais fluxos causam mais medo de quebrar a cada deploy?
- **DB-NEW-C2:** O delivery-webhook foi testado em producao? Ha logs de erro no Supabase Functions que confirmam falhas nas atualizacoes de status?
- **Prioridade de testes:** Se fosse implementar apenas 3 testes automatizados agora, quais seriam?

---

## 7. Proximos Passos Recomendados

> Sugestao preliminar — sujeita a validacao dos especialistas.

### Imediato (antes do proximo deploy)

1. **Verificar estado das colunas `evolution_message_ids`/`delivered_at`** — confirmar com @data-engineer
2. **Criar migration corretiva para `notifications.status` CHECK constraint** — DB-NEW-C2 critico
3. **Mover credenciais hardcoded para env secrets** — DB-E1, DB-E2

### Proximo Epic (sugestao: EPIC-003 — Database Hardening)

1. DDL completo para `classes` com RLS — DB-C1, DB-R2
2. Migrations versionadas para todos os schemas — DB-M1
3. Adicionar `supabase/config.toml` — DB-M2
4. Indexes faltantes — DB-I1, DB-I2, DB-NEW-L1
5. MFA para admin — SYS-C2

### Epic Futuro (sugestao: EPIC-004 — Frontend Modularization)

1. Extrair JS inline do `admin.html` para modulos
2. Centralizar constantes (UX-H2)
3. Adicionar loading e error states (UX-H3, UX-H4)
4. Linter e formatter (SYS-H3)

---

*Draft gerado por @data-engineer (Dara) — aguardando revisao de @ux-design-expert e @qa*
*Apos revisao, @architect finaliza em `technical-debt-assessment.md`*
