# ADR-021 — Student Identity Unification (EPIC-022 S.022.1)

- **Status:** Proposed (awaiting prod apply post-22.4)
- **Date:** 2026-05-22
- **Story:** [22.1 — Identity Unification](../stories/22.1.story.md)
- **Epic:** [EPIC-022 — Painel Refactor](../epics/EPIC-022-painel-refactor.md) §S.022.1
- **Authors:** @architect (Aria), @data-engineer (Dara), @dev (Dex)
- **Supersedes:** Nenhuma (primeira decisão formal sobre identidade canônica de aluno)
- **Migration:** `supabase/migrations/20260522220000_epic_022_s01_identity_unification.sql`
- **Depends on:** ADR-020 (RLS Hardening) — VIEW herda RLS Tier 1

---

## Context

Discovery `02-db-audit.md` §3.1 identificou **triple-identity** crítico de aluno em produção:

| Tabela | Origem | Phone format | Constraint |
|--------|--------|--------------|------------|
| `students` | CSV manual + admin entries | Heterogêneo (varia por origem) | UNIQUE(phone, cohort_id) — mas phone raw |
| `student_imports` | AC webhook `payload->>'phone'` | JSONB bruto, pode ter "+55", espaços, hífens | Sem constraint |
| `wa_group_members` | Cron sync grupos WhatsApp | Format WA API (5511987654321) | UNIQUE(cohort_id, phone) |

**Vazamentos observados (Discovery §3.2):**
- `dispatch_link_opens` e `nps_class_links` não sabem qual `student_id` usar
- JOINs por phone falham silenciosamente (`+5511987654321` ≠ `11987654321` ≠ `5511987654321`)
- Campanhas perdem alunos (impact: receita NPS + retenção)
- `find_duplicate_students()` RPC detecta, mas merge é manual

**Estado atual da normalização:**
- Migração `20260409050000_normalize_student_phones.sql` definiu `normalize_student_phones()` RPC
- Aplicada via UPDATE one-off — sem trigger automático
- Novos rows via AC webhook ou WA sync entram com phone raw
- Source-of-truth de identidade nunca formalizada

Sistema EM PRODUÇÃO com 1k+ alunos ativos + envios diários — phone format inconsistente afeta campanhas em tempo real.

---

## Decision

### 1. Identidade canônica: `(normalized_phone, cohort_id)` em E.164 BR

Phone E.164 BR (`+55DDD9XXXXXXXX` ou `+55DDD8XXXXXXX` pra fixo) é a **chave única** de identidade de aluno por turma. Combinação `(normalized_phone, cohort_id)` resolve identidade independente de origem (CSV, AC, WA).

**Por que phone, não email/CPF/UUID?**
- Email é opcional em `student_imports`, missing em `wa_group_members`
- CPF não existe em nenhuma das 3 tabelas
- Phone é universal (Brasil WhatsApp-first market) e está em 100% dos canais
- UUID interno (`students.id`) é correto pra FK, mas falha cross-source matching

### 2. Hierarquia de fontes

| Tabela | Role | Responsabilidade |
|--------|------|------------------|
| `students` | **Source-of-truth** | Identidade canônica admin-curated. UNIQUE(normalized_phone, cohort_id) — pós-validation T7 |
| `student_imports` | **Audit log AC** | Append-only. Auditoria de compras AC. Nunca dropa. Pode ter duplicates legítimos (mesmo aluno comprou 2 produtos) |
| `wa_group_members` | **Mirror WhatsApp** | Sync automático via cron. UNIQUE(cohort_id, normalized_phone) — espelho do estado WA atual |

### 3. Coluna `normalized_phone` + trigger BEFORE INSERT/UPDATE

Adicionar `normalized_phone text` nas 3 tabelas. Trigger function `trigger_normalize_phone()` popula automaticamente via `normalize_phone_e164(NEW.phone)`. Origem do phone nunca importa pro consumer — `normalized_phone` é fonte única.

**Função `normalize_phone_e164(text) returns text`:**
- IMMUTABLE (mesmo input → mesmo output sempre)
- Strip non-digits, prepend `+55` se BR raw, validate pattern E.164
- Returns NULL se inválido (deixa caller decidir tratamento)
- Inline unit tests no DO block da migration (8 cenários AC7)

### 4. VIEW canônica `v_students_unified`

```sql
SELECT
  s.id, s.normalized_phone, s.cohort_id,
  COALESCE(s.name, wgm.wa_name, si.name) AS canonical_name,
  s.is_mentor, s.active,
  si.product, si.source, si.created_at AS ac_imported_at,
  wgm.group_id AS wa_group_id, wgm.synced_at AS wa_synced_at,
  s.phone AS student_phone_raw, si.phone AS import_phone_raw, wgm.phone AS wa_phone_raw
FROM students s
LEFT JOIN student_imports si ON (s.normalized_phone = si.normalized_phone AND s.cohort_id = si.cohort_id)
LEFT JOIN wa_group_members wgm ON (s.normalized_phone = wgm.normalized_phone AND s.cohort_id = wgm.cohort_id)
WHERE s.normalized_phone IS NOT NULL;
```

Consumers (edge functions, dashboards, RPCs) usam VIEW em vez de JOINs manuais. Schema mudanças nas base tables podem ser absorvidas pela VIEW sem quebrar consumers.

**Herda RLS via tabelas base** — Tier 1 admin-only via ADR-020. Aluno comum não vê VIEW (sem login).

### 5. UNIQUE constraint deferred

`ALTER TABLE students ADD CONSTRAINT students_normalized_phone_cohort_unique UNIQUE (normalized_phone, cohort_id)` fica em **migration follow-up separada**, gate pre-apply:

```sql
SELECT COUNT(*) FROM find_duplicate_students();
-- expected: 0 — se > 0, RESOLVER via merge_students() antes adicionar UNIQUE
```

**Razão:** se prod tiver duplicates não-detectados antes, ALTER falha → migration trava. Separar minimiza blast radius.

### 6. Coluna `phone` legacy preservada (30 dias)

`students.phone`, `student_imports.phone`, `wa_group_members.phone` (raw) **NÃO são dropadas** na migration 22.1. Razão:

- Queries legacy que SELECT phone continuam OK
- Rollback é mais simples (revert column add, não recompute drop)
- Deprecation timeline: drop em 2026-06-22 via story 22.x.cleanup (separada)

A VIEW expõe ambos `normalized_phone` E `*_phone_raw` pra facilitar debug/migration de consumers.

### 7. Backfill via RPC service_role only

`backfill_normalized_phones()`:
- SECURITY DEFINER
- GRANT EXECUTE TO service_role only (REVOKE authenticated/anon)
- Idempotente: UPDATE WHERE normalized_phone IS NULL — segundo run retorna 0
- RETURNS TABLE(table_name, rows_updated) pra observability
- Audit log entry pós-execução

### 8. Indexes em `normalized_phone` (perf)

```sql
CREATE INDEX idx_<tbl>_normalized_phone ON <tbl> (normalized_phone) WHERE normalized_phone IS NOT NULL;
```

Partial index (WHERE NOT NULL) economiza espaço + acelera LEFT JOIN da VIEW.

---

## Consequences

### Curto prazo (imediato pós-apply)

- ✅ JOINs cross-table por `normalized_phone` ficam confiáveis
- ✅ AC webhook continua escrevendo phone raw — trigger normaliza automaticamente
- ✅ WA cron continua escrevendo phone raw — trigger normaliza automaticamente
- ✅ Dashboards admin podem usar `v_students_unified` em vez de JOINs manuais
- ✅ Vazamentos passados (alunos perdidos por phone format) param de acumular
- ⚠️ Edge functions usando `students.phone` continuam OK (legacy preservado 30d)
- ⚠️ Backfill em 1k+ rows × 3 tabelas pode levar 5-15s (dry-run T11 valida)

### Longo prazo

- **Single point of truth:** consumers usam VIEW canônica em vez de JOINs manuais
- **Migração futura:** drop coluna phone legacy (post 2026-06-22) sem quebrar nada
- **Extensão:** se aparecer phone internacional (EU/US), expandir `normalize_phone_e164` (mas avaliar custo vs benefício — AL é BR-only hoje)
- **Reconciliação:** `find_duplicate_students()` agora confiável pra detectar duplicates (chave normalizada)

### Custos

- **Latência INSERT/UPDATE:** trigger add ~µs por row (função IMMUTABLE — cache-friendly)
- **Storage:** 3 colunas TEXT (~14 chars cada) × N rows = pequeno (1k * 3 * 14 = 42KB)
- **Manutenção:** mais 1 função + 1 RPC + 1 VIEW + 3 triggers + 3 indexes
- **Rollback parcial:** se VIEW for usada em queries críticas, rollback derruba consumers (mitigação: preservar phone legacy 30d)

---

## Alternatives considered

### Alternativa 1 — UUID-based identity service (Auth0/Clerk)

Migrar pra identity service externo gerar UUID estável por aluno.

**Rejeitada:** over-engineering pra cenário atual. AL é admin-only — alunos não logam. Adicionar dependency externa pra solucionar JOIN problem é desproporcional.

### Alternativa 2 — Dedupe automático cross-table via merge trigger

Trigger BEFORE INSERT em student_imports que automaticamente upserta em students.

**Rejeitada:** semântica de "duplicate" é nuançada (mesmo aluno compra 2 produtos = 2 imports legítimos, não 1 student duplicado). Manter merge manual via admin RPC preserva controle.

### Alternativa 3 — Coluna virtual GENERATED ALWAYS AS

`ALTER TABLE students ADD COLUMN normalized_phone text GENERATED ALWAYS AS (normalize_phone_e164(phone)) STORED`.

**Rejeitada:** PG 15 suporta GENERATED, mas:
- Reaplica função em todo UPDATE de qualquer coluna (não só phone)
- Não pode ser modificada manualmente em caso de bug raro
- Trigger BEFORE oferece controle equivalente sem essa rigidez

### Alternativa 4 — Phone E.164 internacional (libphonenumber)

Usar lib pra E.164 universal (não só BR).

**Rejeitada:** AL é BR-only hoje. Pattern simples é mais maintainable que dependency externa. Documentar como story futura se aparecer demanda internacional.

### Alternativa 5 — Tabela separada `student_identities` resolver cross-source

Tabela com `(phone, cohort_id, students_id, student_imports_id, wa_group_member_id)` que age como chave.

**Rejeitada:** introduz 4ª tabela. VIEW resolve igualmente sem custo de manutenção adicional. Princípio: prefer view over table when read-only aggregation.

---

## Validation

### SQL validators (AC11)

```sql
-- AC11.1: students com phone tem normalized_phone E.164 válido
SELECT count(*) FROM public.students
WHERE phone IS NOT NULL
  AND (normalized_phone IS NULL OR normalized_phone !~ '^\+55[1-9][0-9][0-9]{8,9}$');
-- expected: 0

-- AC11.2: VIEW retorna 1 linha por (normalized_phone, cohort_id)
SELECT normalized_phone, cohort_id, count(*) FROM public.v_students_unified
GROUP BY 1,2 HAVING count(*) > 1;
-- expected: 0 rows

-- AC11.3: backfill idempotência
SELECT SUM(rows_updated) FROM public.backfill_normalized_phones();
-- expected pós-primeiro run: 0
```

### Smoke script (AC7)

`scripts/smoke-identity-test.sh` — 14 cenários:
- 10 inputs de `normalize_phone_e164`
- Trigger BEFORE INSERT em temp table
- Backfill idempotência
- VIEW queryable
- AC11 validator

### Pre-flight (T1)

```sql
-- Audit heterogeneidade pré-apply
SELECT count(*), substring(phone from 1 for 4) AS prefix
FROM public.students
GROUP BY 2 ORDER BY 1 DESC;

-- Gate UNIQUE constraint (T7)
SELECT COUNT(*) FROM public.find_duplicate_students();
-- expected: 0 pre-apply migration follow-up
```

---

## Known limitations

1. **Phone fixo 8 dígitos legacy:** AC2 pattern `[1-9][0-9][0-9]{8,9}` cobre 8 OR 9 dígitos pós-DDD. Mas se DDD começa com 1 ou 2 e número começa com 0/1 → reject. Trade-off aceito: phones modernos celular dominam base.

2. **Phones internacionais:** normalize_phone_e164 retorna NULL pra phones não-BR. Story futura se necessário.

3. **JSONB raw em `student_imports.phone`:** se AC webhook escrever `payload->>'phone'` com format JSON literal (`"+5511..."`) em vez de extract, trigger pode receber lixo. T1 audit valida + edge function de AC pode precisar refactor (out-of-scope desta story).

4. **VIEW performance em cohorts grandes (>10k alunos):** indexes parciais ajudam, mas LEFT JOIN × 3 pode lentar. Se observado, migrar pra MATERIALIZED VIEW + refresh via cron (story futura).

---

## References

- Story 22.1: `docs/stories/22.1.story.md`
- Story 22.1 PO validation: `docs/stories/22.1.validation.md` (GO 10/10)
- Discovery 02-db-audit: `docs/discovery/2026-05-22/02-db-audit.md` §3.1 §3.2 §4
- Helper existente: `supabase/migrations/20260409050000_normalize_student_phones.sql`
- ADR-020 (RLS Hardening): `docs/architecture/ADR-020-rls-policies.md` — VIEW herda RLS Tier 1
- Migration up: `supabase/migrations/20260522220000_epic_022_s01_identity_unification.sql`
- Migration down: `supabase/migrations/20260522220000_epic_022_s01_identity_unification.down.sql`
- Smoke script: `scripts/smoke-identity-test.sh`
- Constitution Article IV (No Invention): `.aiox-core/constitution.md`
- CLAUDE.md "Comunicação Externa — NON-NEGOTIABLE" (apply prod requer aprovação humana)

---

## Change Log

- 2026-05-22 @aiox-master — ADR-021 criado durante drafting story 22.1 (workflow @dev T10)
- 2026-05-22 @architect/@data-engineer/@dev — Status: Proposed; aguarda apply prod pós-22.4 OK
