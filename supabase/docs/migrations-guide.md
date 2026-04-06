# Migrations Guide — lesson-pages

## Visão geral

Este projeto usa o **Supabase CLI** para gerenciar todas as mudanças de schema do banco de dados. Cada mudança é representada por um arquivo `.sql` numerado em `supabase/migrations/`.

> **Regra:** nenhuma mudança de schema deve ser feita diretamente no SQL Editor do Supabase Dashboard. Toda alteração passa por uma migration versionada.

---

## Pré-requisitos

```bash
# Instalar Supabase CLI (se não tiver)
npm install -g supabase

# Verificar versão
supabase --version

# Login (primeira vez)
supabase login
```

---

## Como aplicar uma nova migration

### 1. Criar o arquivo de migration

```bash
# Formato do nome: YYYYMMDDHHMMSS_descricao_curta.sql
# Exemplo:
supabase migration new add_campo_x_na_tabela_y
```

Isso cria `supabase/migrations/20260406XXXXXX_add_campo_x_na_tabela_y.sql`.

Abra o arquivo e escreva o SQL:

```sql
-- Sempre use IF NOT EXISTS / IF EXISTS para tornar idempotente
ALTER TABLE public.minha_tabela
  ADD COLUMN IF NOT EXISTS novo_campo TEXT;

-- Para constraints, use DO block:
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'minha_constraint' AND conrelid = 'public.minha_tabela'::regclass
  ) THEN
    ALTER TABLE public.minha_tabela ADD CONSTRAINT minha_constraint CHECK (...);
  END IF;
END $$;

-- Para policies: sempre DROP IF EXISTS antes de CREATE
DROP POLICY IF EXISTS "Nome da policy" ON public.minha_tabela;
CREATE POLICY "Nome da policy" ON public.minha_tabela FOR SELECT TO authenticated USING (true);
```

### 2. Testar localmente (opcional)

```bash
# Subir instância local do Supabase
supabase start

# Verificar status das migrations locais
supabase migration list

# Aplicar localmente para testar
supabase db reset  # ⚠️ reseta o banco local, não afeta produção
```

### 3. Verificar estado antes de aplicar

```bash
supabase migration list
```

A saída mostra `Local` vs `Remote`. Migrations sem coluna `Remote` ainda não foram aplicadas.

### 4. Aplicar em produção

```bash
# Na raiz do projeto lesson-pages:
supabase db push
```

O CLI pede confirmação antes de aplicar. Confirme com `Y`.

### 5. Verificar após aplicação

```bash
supabase migration list
# Todas as migrations devem ter Local e Remote preenchidos com o mesmo timestamp
```

---

## Convenções de nomenclatura

| Prefixo | Uso |
|---------|-----|
| `YYYYMMDDHHMMSS_add_` | Adicionar coluna, tabela, index |
| `YYYYMMDDHHMMSS_fix_` | Corrigir constraint, policy, tipo |
| `YYYYMMDDHHMMSS_seed_` | Dados iniciais (seeds) |
| `YYYYMMDDHHMMSS_drop_` | Remover coluna ou tabela |

---

## Regras de qualidade para migrations

1. **Idempotência obrigatória** — toda migration deve poder ser executada múltiplas vezes sem erro
   - Use `ADD COLUMN IF NOT EXISTS`
   - Use `CREATE INDEX IF NOT EXISTS`
   - Use `DROP CONSTRAINT IF EXISTS` antes de `ADD CONSTRAINT`
   - Use `DROP POLICY IF EXISTS` antes de `CREATE POLICY`

2. **Não modifique migrations já aplicadas** — se uma migration chegou ao `Remote`, ela é imutável. Crie uma nova migration para corrigir.

3. **Inclua RLS** — toda nova tabela deve ter:
   - `ALTER TABLE ... ENABLE ROW LEVEL SECURITY;`
   - Ao menos uma policy de SELECT
   - Policies de INSERT/UPDATE/DELETE

4. **Documente intenção** — inclua comentários explicando o porquê da mudança, não apenas o quê.

5. **Nunca use `DROP TABLE` sem backup** — migrações destrutivas exigem aprovação explícita.

---

## Histórico de migrations

| Arquivo | Descrição |
|---------|-----------|
| `20260402175137_notifications_schema.sql` | Mentors, class_cohorts, class_mentors, notifications |
| `20260402175310_seed_mentors.sql` | Seed da equipe pedagógica (14 mentores) |
| `20260402180000_seed_class_cohorts.sql` | Seed das turmas iniciais |
| `20260402183513_webhook_notify_whatsapp.sql` | Trigger DB → Edge Function send-whatsapp |
| `20260402190833_baseline_existing_schema.sql` | Baseline (cohorts, students, classes, attendance, zoom_*) — marcada como aplicada via repair, não re-executada |
| `20260402191455_notification_schedules_pgcron.sql` | Tabela notification_schedules + pg_cron job |
| `20260402200000_delivery_status.sql` | evolution_message_ids, delivered_at, status check update |
| `20260406120000_classes_schema_rls.sql` | Schema formal classes: type/start_date/end_date, valid_from/valid_until, RLS pública para calendário |

---

## Scripts legados em `db/`

O diretório `db/` contém scripts SQL avulsos criados antes da adoção do Supabase CLI. Eles **não devem ser executados diretamente** em produção — seu conteúdo foi incorporado às migrations formais ou representa estado já aplicado manualmente.

| Script | Status |
|--------|--------|
| `schema.sql` | Incorporado ao baseline (`20260402190833`) |
| `students-schema.sql` | Incorporado ao baseline |
| `notifications-schema.sql` | Incorporado a `20260402175137` |
| `zoom-schema.sql` | Incorporado ao baseline |
| `classes-schema.sql` | Documentação de referência → ver `supabase/docs/classes-schema.sql` |
| `migration-class-mentors-fix.sql` | Incorporado a `20260406120000` |
| `migration-fix-rls-and-types.sql` | Incorporado a `20260406120000` |
| `migration-mentor-attendance.sql` | Incorporado ao baseline |
| `seed-notifications-setup.sql` | Incorporado a `20260402175310` e `20260402180000` |
| `set-mentor-passwords.sql` | Script operacional (não é migration) |
| `seed-students.js` | Script de seed (não é migration) |
| `enrich-from-groups.js` | Script de enriquecimento (não é migration) |
| `enrich-names.js` | Script de enriquecimento (não é migration) |

---

## Troubleshooting

### Erro: "already exists, skipping" (NOTICE)

Normal — a migration é idempotente e ignorou o que já existia. Não é um erro.

### Erro: constraint X already exists

A migration tentou adicionar uma constraint sem checar se ela existe. Corrija com DO block condicional (ver seção "Regras de qualidade").

### Migration lista como Local mas não Remote após push

Verifique se o `supabase db push` foi confirmado com `Y`. Rode novamente.

### Projeto não linkado

```bash
supabase link --project-ref gpufcipkajppykmnmdeh
```
