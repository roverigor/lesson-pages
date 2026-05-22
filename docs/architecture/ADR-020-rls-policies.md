# ADR-020 — RLS Policies Hardening (EPIC-022 S.022.4)

- **Status:** Accepted
- **Date:** 2026-05-22
- **Story:** [22.4 — RLS Hardening](../stories/22.4.story.md)
- **Epic:** [EPIC-022 — Painel Refactor](../epics/EPIC-022-painel-refactor.md) §S.022.4
- **Authors:** @architect (Aria), @data-engineer (Dara), @dev (Dex)
- **Supersedes:** Nenhuma (primeira decisão formal sobre baseline RLS no calendario-aulas)
- **Migration:** `supabase/migrations/20260522155830_epic_022_s04_rls_hardening.sql`

---

## Context

A discovery `02-db-audit.md` §6 (2026-05-22) identificou um cenário misto de cobertura RLS em produção:

- **6 das 7 tabelas Tier 1** já tinham RLS habilitado, mas com policies frouxas:
  - `class_nps_responses` — `USING (true)` (comments NPS expostos pra qualquer authenticated)
  - `wa_group_members` — `USING (auth.uid() IS NOT NULL)` (phones de toda base expostos)
  - `nps_class_links` — `USING (true)` (tokens magic-link expostos — risco spoofing)
  - `student_attendance` — authenticated read all (presença individual vazada)
  - `student_imports` + `response_metadata` — inline role checks (heterogêneos cross-tabela)
- **1 das 7** (`staff`) sem RLS habilitado
- **Tier 2/3** com cobertura mista — algumas com POLICY OK, outras sem ENABLE, outras sem POLICY
- `app_config` explicitamente com `DISABLE ROW LEVEL SECURITY` porque pg_cron (superuser) precisa
  ler/escrever via admin user connection (migration `20260407202000_app_config.sql:15`)

A audit @data-engineer (`22.4.data-engineer-notes.md` Q1) também confirmou achado estrutural:
**não existe link `students.id` ↔ `auth.users.id`** em nenhuma migration. O painel é admin-only;
alunos NÃO logam no Supabase Auth, apenas acessam forms NPS via token opaco em `nps_class_links`.
Isso descarta o pattern "self read" (`USING (student_id = auth.uid())`) pra todas as 7 tabelas Tier 1.

Sistema EM PRODUÇÃO com 1k+ alunos ativos e envios diários — vazamento é ATIVO, não teórico.

---

## Decision

### 1. Pattern por Tier

**Tier 1 — PII / Tokens / Financeiro (7 tabelas):**
- POLICY: `is_dashboard_admin()` only (Opção B confirmada — sem link auth.users)
- `service_role`: bypass natural (sem POLICY explícita)
- Tabelas: `staff`, `student_imports`, `wa_group_members`, `class_nps_responses`,
  `student_attendance`, `response_metadata`, `nps_class_links`
- Comentário SQL `-- Future: adicionar OR <ownership_clause> when self-service NPS view ships`
  em todos os `CREATE POLICY` pra extensão futura sem mudança arquitetural

**Tier 2 — Operacional (16 tabelas):**
- POLICY: `authenticated` read all + `service_role` full write
- Tabelas: `audit_log`, `class_reminder_batches`, `class_reminder_sends`, `notification_queue`,
  `schedule_overrides`, `zoom_absence_alerts`, `class_cohort_access`, `error_reports`,
  `whatsapp_group_messages`, `zoom_chat_messages`, `zoom_import_queue`,
  `automation_executions`, `automation_rules`, `automation_runs`, `alert_history`,
  `engagement_daily_ranking`

**Tier 3 — Referência / Config (4 tabelas):**
- POLICY: `authenticated` read all + `is_dashboard_admin()` write
- Tabelas: `app_config` (pós-T11), `integration_sources`, `lesson_abstracts`, `survey_templates`
- `service_role`: bypass natural

**Exceções (4 tabelas):**
- Sem POLICY; apenas `COMMENT ON TABLE` justificativa SQL-side
- Tabelas: `ac_dispatch_callbacks`, `oauth_states`, `ac_purchase_events`, `ac_product_mappings`
- Razão: webhooks/callbacks escritos/lidos APENAS por edge functions com `service_role`,
  nunca queriados por usuário

### 2. Por que `is_dashboard_admin()` only para Tier 1 (Opção B)

Alternativas consideradas:

| Opção | Pattern | Veredito |
|-------|---------|----------|
| A | `student_id = auth.uid() OR is_dashboard_admin()` | **REJEITADA** — `students.id` ≠ `auth.users.id` (sem FK) |
| B | `is_dashboard_admin()` only | **ACEITA** — única semântica válida hoje |
| C | JOIN custom via `phone`/`email` | **REJEITADA** — frágil, performance ruim, complexidade alta |

**Razão da aceitação:**
- Painel é admin-only por design (decisão Caminho A EPIC-015, login compartilhado)
- Aluno acessa forms NPS via token em URL, não via login Supabase Auth
- Adicionar self-read seria over-engineering pra cenário que não existe

### 3. `is_dashboard_admin()` defensivo no header da migration

Incluímos `CREATE OR REPLACE FUNCTION public.is_dashboard_admin()` no topo da migration RLS
hardening (custo: 6 linhas SQL, performance: zero — STABLE function). Razões:

1. **Idempotência:** se função for dropada acidentalmente em refactor futuro, rerun da migration
   restaura estado consistente
2. **Documentação inline:** quem lê a migration entende o gate central sem ir a outra migration
3. **Audit trail:** garante linha do tempo coerente (função criada/atualizada exatamente quando
   policies que dependem dela)

### 4. `app_config` requer refactor pg_cron antes de ENABLE RLS (T11)

Sequência obrigatória:

1. T11 — refactor pg_cron jobs (`process_zoom_import_queue()`, `zoom-absence-alert`) pra
   conexão `service_role` (não admin user)
2. Smoke pré-RLS: rodar job manualmente — sucesso
3. Aplicar `ENABLE ROW LEVEL SECURITY` + POLICY Tier 3 em `app_config` (bloco comentado
   na migration original — descomentar quando T11 estiver pronto)
4. Smoke pós-RLS: rodar job manualmente — sucesso (service_role bypassa)

Risco mitigado: cron quebrar em prod entre RLS apply e job próximo trigger.

### 5. Rollback honest (não-vulnerable rollback)

**Decisão:** REPLACE de policies frouxas (Tier 1) **não recria** policies vulneráveis no
`.down.sql`. Em vez disso:

- Down dropa policy restritiva nova
- Tabela permanece com RLS habilitado MAS sem POLICY pra authenticated
- `service_role` continua escrevendo (bypass natural)
- Admin perde acesso até reaplicar `.up.sql`

**Razão:** re-criar policy frouxa = re-introduzir vulnerabilidade conhecida (vazamento ATIVO).
Aceita-se trade-off: rollback rompe acesso admin temporariamente, mas mantém estado seguro
por padrão.

Exceção: `staff` (Tier 1, única sem ENABLE prévio) — down faz `DISABLE ROW LEVEL SECURITY`
restaurando estado original.

### 6. Idempotência via `DROP IF EXISTS + CREATE POLICY`

PostgreSQL 15 (versão atual do Supabase managed) **NÃO suporta** `CREATE POLICY IF NOT EXISTS`
(introduzido em PG 16). Padrão único na migration:

```sql
DROP POLICY IF EXISTS "<name>" ON public.<table>;
CREATE POLICY "<name>" ON public.<table>
  FOR <cmd> TO <role> USING (<qual>) [WITH CHECK (<qual>)];
```

Wrapping `BEGIN/COMMIT` por tabela:
- Isola falha (uma tabela falha não bloqueia próximas)
- Sem window de 401 entre ENABLE RLS e CREATE POLICY (ambos no mesmo transação)

### 7. Audit trail ordering

`audit_log` é Tier 2 e recebe `ALTER ENABLE RLS` na migration. Inserts de audit registrando a
própria migration ocorrem **ANTES** de qualquer ALTER em `audit_log` (header da migration up
+ início do down). Razão: evitar paradoxo self-protection bloquear insert.

---

## Consequences

### Curto prazo (imediato pós-apply)

- **Vazamentos fechados:** `class_nps_responses`, `wa_group_members`, `nps_class_links`,
  `student_attendance` deixam de expor dados pra qualquer authenticated
- **Edge functions:** continuam OK via `service_role` bypass natural (validar grep pré-apply
  conforme T1 da story)
- **Dashboards admin:** continuam OK (admin tem `is_dashboard_admin()=true` via JWT)
- **Mentor/CS sem role admin:** perdem acesso temporário até decisão final sobre expand
  `is_dashboard_admin()` ou inline check em `response_metadata` (caveat documentado)
- **Pg_cron `app_config`:** bloco RLS comentado até T11 — sem mudança comportamental

### Longo prazo

- **Self-service NPS view (futura story):** comment SQL `-- Future: adicionar OR ...` em todos
  Tier 1 facilita extensão. Quando self-service ships, adicionar OR clause condicional sem
  re-arquitetar policies
- **Single point of change:** `is_dashboard_admin()` centraliza gate admin. Mudar critério de
  "admin" = mudar 1 função vs N inline checks
- **Auditoria:** `audit_log` event_type `rls_hardening_migration` permite trace forense da
  mudança

### Custos

- **Acesso CS (caveat `response_metadata`):** se existir user com role `cs` ativo,
  padronização atual quebra. Pre-apply validação T1:
  ```sql
  SELECT raw_user_meta_data->>'role' AS r, count(*) FROM auth.users GROUP BY 1;
  ```
- **Janela manutenção:** ALTER TABLE adquire `ACCESS EXCLUSIVE` lock por tabela (ms em
  prática, mas 27 tabelas × write traffic pode causar lock storm em horário ativo)
- **Rollback parcial:** admin perde acesso temporariamente em caso de down (decisão honest)

---

## Alternatives considered

### Alternativa 1 — Expand `is_dashboard_admin()` pra incluir role `cs`

Adicionar `OR (auth.jwt()->'user_metadata'->>'role') = 'cs'` na função helper.

**Rejeitada (escopo):** muda comportamento de ~20 migrations que dependem da função.
Out-of-scope S.022.4 — flag pra @architect em story futura. Decisão local em
`response_metadata` documentada inline (caveat).

### Alternativa 2 — RLS via SECURITY DEFINER functions

Em vez de POLICY direto, usar functions com `SECURITY DEFINER` pra controle granular.

**Rejeitada:** complexidade desnecessária pra hardening defensivo. POLICY direto é o pattern
canônico Postgres + Supabase recommended.

### Alternativa 3 — Branch DB Supabase (paid feature) pra staging

Em vez de pg_dump + Docker local.

**Rejeitada:** custo recorrente desproporcional ao uso (1 migration crítica/trimestre).
Dry-run via pg_dump + Docker PG 15 cobre cenário validation (decisão B do user — `22.4.story.md`
Dependencies).

---

## Validation

### SQL validators (AC1, AC9)

```sql
-- AC1: todas as 27 tabelas têm RLS habilitado
SELECT count(*) FROM pg_tables t
WHERE schemaname='public'
  AND tablename = ANY(ARRAY[
    'staff','student_imports','wa_group_members','class_nps_responses',
    'student_attendance','response_metadata','nps_class_links',
    'audit_log','class_reminder_batches','class_reminder_sends',
    'notification_queue','schedule_overrides','zoom_absence_alerts',
    'class_cohort_access','error_reports','whatsapp_group_messages',
    'zoom_chat_messages','zoom_import_queue','automation_executions',
    'automation_rules','automation_runs','alert_history',
    'engagement_daily_ranking','integration_sources','lesson_abstracts',
    'survey_templates','app_config'
  ])
  AND NOT EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON c.relnamespace=n.oid
    WHERE n.nspname='public' AND c.relname=t.tablename AND c.relrowsecurity
  );
-- expected: 0 (todas têm RLS habilitado — exceto app_config até T11)
```

### Smoke script (AC7)

10 cenários cobrindo admin / user comum / anon × Tier 1/2/3 + edge function + dashboards.
Ver `scripts/smoke-rls-test.sh`.

### Pre-flight (AC10)

3 validators SQL pra `is_dashboard_admin()` (definição existe, retorna boolean, CREATE OR
REPLACE no header da migration). Output em `qa/22.4-admin-fn-check.log`.

---

## References

- Story 22.4: `docs/stories/22.4.story.md`
- Story 22.4 PO validation: `docs/stories/22.4.validation.md` (GO 9/10 post-reconciliation)
- Story 22.4 Data engineer notes: `docs/stories/22.4.data-engineer-notes.md`
- Discovery 02-db-audit: `docs/discovery/2026-05-22/02-db-audit.md` §6
- Helper function source: `supabase/migrations/20260516020300_helper_functions.sql`
- Pattern reference: `supabase/migrations/20260522010000_ps_rsvp_rls_authenticated_select.sql`
- Migration up: `supabase/migrations/20260522155830_epic_022_s04_rls_hardening.sql`
- Migration down: `supabase/migrations/20260522155830_epic_022_s04_rls_hardening.down.sql`
- Smoke script: `scripts/smoke-rls-test.sh`
- Slack wrapper: `scripts/apply-with-slack-alert.sh`
- T11 cron refactor: `scripts/refactor-pg-cron-service-role.sql`
- Dry-run: `scripts/dry-run-rls.sh`
- Constitution Article IV (No Invention): `.aiox-core/constitution.md`
- CLAUDE.md "Comunicação Externa — NON-NEGOTIABLE" (apply prod requer aprovação humana)
