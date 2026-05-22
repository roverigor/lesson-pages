# ADR-026 — Orphan Tables Cleanup (3 tabelas suspeitas)

- **Status:** Draft (skeleton — aguarda audit data + classificação)
- **Date:** 2026-05-22
- **Story:** [22.8 — Orphan Tables Cleanup](../stories/22.8.story.md)
- **Epic:** [EPIC-022 — Painel Refactor](../epics/EPIC-022-painel-refactor.md) §S.022.8
- **Authors:** @architect (Aria), @aiox-master (Orion)
- **Supersedes:** Nenhuma

---

## Context

Discovery `02-db-audit.md §5` listou 3 tabelas suspeitas órfãs:

| Tabela | Última escrita observada | Status investigação |
|--------|--------------------------|---------------------|
| `pending_student_assignments` | ? | Nunca mencionada em migrations recentes — ÓRFÃ? |
| `notification_queue` | 20260417110000 criação | Nenhuma query visível — ÓRFÃ? |
| `alert_history` | ? | Não aparece em migrations recentes — ÓRFÃ? |

**Risco diagnóstico:** tabelas dormentes confundem investigação futura (devs assumem que são usadas, perdem tempo investigando).

**Audit tool:** `scripts/audit-orphan-tables.sh` gera:
- `docs/22.8-orphan-audit.md` — grep refs + DB stats + schema + triggers

---

## Decision (skeleton — preencher pós-audit)

### Princípios

1. **Keep** se: rows recentes (< 30d) OR ref ativa em edge function OR feature documentada não-deprecated
2. **Deprecate** se: 0 writes recentes (>90d) AND refs ambíguas — rename + trigger Slack alert pra detect any write pós-deprecate
3. **Drop** se: 0 writes recentes (>90d) AND zero refs codebase AND tabela vazia OU dados sem valor histórico — snapshot antes drop

### Por tabela (preencher após review)

#### `pending_student_assignments`

- **Decisão:** TBD
- **Razão:** TBD (referenciar refs grep + DB stats)
- **Action:**
  - Se Keep: `COMMENT ON TABLE pending_student_assignments IS 'Active. Used by [consumer]. Ref ADR-026.';`
  - Se Deprecate: rename + trigger
  - Se Drop: snapshot + DROP

#### `notification_queue`

- **Decisão:** TBD
- **Razão:** TBD
- **Action:** TBD

#### `alert_history`

- **Decisão:** TBD
- **Razão:** TBD
- **Action:** TBD

---

## Patterns aplicáveis

### Pattern 1 — Keep (Active)

```sql
COMMENT ON TABLE public.<table> IS
  'Active. Used by <consumer>. Ref ADR-026.';
```

### Pattern 2 — Deprecate (rename + alert)

```sql
ALTER TABLE public.<table> RENAME TO <table>_deprecated_20260522;

CREATE OR REPLACE FUNCTION public.alert_deprecated_table_write()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.audit_log (event_type, payload)
  VALUES (
    'deprecated_table_write_attempt',
    jsonb_build_object(
      'table', TG_TABLE_NAME,
      'operation', TG_OP,
      'attempted_at', now(),
      'caller', current_user
    )
  );
  -- Não bloqueia write (apenas alerta) — drop final após 1 sprint
  RETURN COALESCE(NEW, OLD);
END;
$$;

CREATE TRIGGER trg_alert_<table>_deprecated
  AFTER INSERT OR UPDATE OR DELETE
  ON public.<table>_deprecated_20260522
  FOR EACH ROW
  EXECUTE FUNCTION public.alert_deprecated_table_write();
```

### Pattern 3 — Drop (snapshot + DROP)

```sql
-- 1. Snapshot (cópia completa pra rollback emergency)
CREATE TABLE public.<table>_snapshot_20260522 AS
SELECT * FROM public.<table>;

-- snapshot table sem RLS (admin-only via service_role)
ALTER TABLE public.<table>_snapshot_20260522 DISABLE ROW LEVEL SECURITY;
COMMENT ON TABLE public.<table>_snapshot_20260522 IS
  'Backup snapshot pre-drop. Created 20260522 ref ADR-026. Drop after 90 days if no rollback needed.';

-- 2. DROP original
DROP TABLE public.<table> CASCADE;

-- 3. Audit
INSERT INTO public.audit_log (event_type, payload)
VALUES (
  'orphan_table_dropped',
  jsonb_build_object(
    'table', '<table>',
    'snapshot_table', '<table>_snapshot_20260522',
    'rows_dropped', (SELECT count(*) FROM public.<table>_snapshot_20260522),
    'adr', 'ADR-026',
    'dropped_at', now()
  )
);
```

---

## Schema.md update

Atualizar `docs/architecture/schema.md` (criar se não existir) com:

```markdown
## Active Tables

| Table | Purpose | Last write | RLS Tier |
|-------|---------|------------|----------|
| ... | ... | ... | ... |

## Deprecated Tables (rename + trigger alert)

| Table (renamed) | Original | Deprecated date | Drop scheduled |
|-----------------|----------|----------------|----------------|
| ... | ... | ... | ... |

## Dropped Tables (snapshot kept 90d)

| Table | Dropped | Snapshot | Drop snapshot scheduled |
|-------|---------|----------|------------------------|
| ... | ... | ... | ... |
```

---

## Consequences

### Curto prazo (imediato pós-audit + decisões)

- ✅ Cada tabela com decisão documentada (keep/deprecate/drop)
- ✅ Snapshot antes drop preserva rollback emergency
- ✅ Trigger Slack alert detecta writes inesperados em deprecated
- ⚠️ Drop final apenas após 1 sprint deprecation buffer

### Longo prazo

- Cleanup arquitetural (3 tabelas removidas/clarificadas)
- Diagnósticos futuros: schema.md como source-of-truth
- Pattern reusável pra outras tabelas suspeitas (futuras)

### Custos

- **Storage temporário:** snapshot tables custam espaço por 90d
- **Trigger overhead:** AFTER INSERT trigger negligible (apenas log)
- **Lock:** RENAME TABLE adquire ACCESS EXCLUSIVE momentâneo

---

## Alternatives considered

### Alternativa 1 — DROP imediato sem snapshot

**Rejeitada:** se decisão errada, dados perdidos. Snapshot custa pouco e garante rollback.

### Alternativa 2 — Manter "as is" sem deprecation

**Rejeitada:** confunde diagnósticos futuros. Better explicit Keep/Deprecate/Drop documentation.

### Alternativa 3 — Auto-drop via cron se 30d sem writes

**Rejeitada:** muito automático pra ação destrutiva. Human review required.

---

## Validation

### Audit script outputs

`bash scripts/audit-orphan-tables.sh` gera `docs/22.8-orphan-audit.md`.

### Pós-decisão validators

```sql
-- Confirmar deprecated tables têm trigger alert
SELECT trigger_name FROM information_schema.triggers
WHERE event_object_table LIKE '%_deprecated_%';

-- Confirmar dropped tables têm snapshot
SELECT relname FROM pg_class
WHERE relname LIKE '%_snapshot_%';

-- Audit log entries
SELECT event_type, count(*) FROM public.audit_log
WHERE event_type IN ('orphan_table_dropped', 'deprecated_table_write_attempt')
GROUP BY 1;
```

---

## Known limitations

1. **Audit script depends PG connection:** sem token cofre prod, audit é grep-only (sem stats reais).

2. **"Used by" inference frágil:** grep pode missar refs em dynamic SQL ou via RPC names. Aceito — conservador (default Keep se ambíguo).

3. **Snapshot 90d retention:** após 90d, snapshot pode ser dropado (separate story). Calendar reminder necessário.

---

## References

- Story 22.8: `docs/stories/22.8.story.md`
- Story 22.8 PO validation: `docs/stories/22.8.validation.md` (GO 8/10)
- Discovery 02-db-audit: `docs/discovery/2026-05-22/02-db-audit.md` §5
- Audit script: `scripts/audit-orphan-tables.sh`
- ADR-020 (RLS Hardening): Tier classification

---

## Change Log

- 2026-05-22 @aiox-master — ADR-026 skeleton criado durante drafting code story 22.8
- TBD @architect — Preencher decisões por tabela após `bash scripts/audit-orphan-tables.sh`
- TBD — Atualizar status Draft → Accepted pós-classificação
