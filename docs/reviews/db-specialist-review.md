## Database Specialist Review — lesson-pages

> **Revisado por:** @data-engineer (Dara)
> **Data:** 2026-04-06
> **Base:** technical-debt-DRAFT.md + commits recentes (feat: add WhatsApp delivery confirmation tracking)

---

### Parecer Geral

O banco de dados do lesson-pages apresenta uma estrutura funcional para o volume atual de dados, mas sofre de débitos críticos de integridade e rastreabilidade. A ausência de migrations versionadas é o problema estrutural mais grave: sem elas, é impossível garantir que o schema em produção corresponde ao que está documentado, e qualquer tentativa de rollback ou replicação do ambiente será manual e propensa a erros.

O segundo ponto crítico é o estado da tabela `notifications`: há evidência direta de que o sistema de delivery tracking (adicionado em commit recente) opera sobre colunas (`evolution_message_ids`, `delivered_at`) e valores de status (`delivered`, `read`) que **não existem no DDL documentado**. Isso significa que ou as alterações foram feitas manualmente no Dashboard do Supabase — sem migration — ou as operações do delivery-webhook estão falhando silenciosamente. Ambos os cenários representam risco crítico de dados corrompidos ou perdidos sem qualquer alerta.

---

### Débitos Validados

| ID | Débito | Severidade Confirmada | Horas | Prioridade | Notas |
|---|---|---|---|---|---|
| DB-NEW-C1 | `notifications.evolution_message_ids` e `delivered_at` sem DDL/migration documentada | CRÍTICO | 2h | P0 — resolver esta semana | Evidência: commit de delivery tracking merged sem migration correspondente |
| DB-NEW-C2 | `notifications.status` CHECK constraint não inclui `delivered` e `read` | CRÍTICO | 1h | P0 — bloqueia funcionalidade de entrega | Updates do delivery-webhook provavelmente falham silenciosamente |
| DB-C1 | `classes` sem schema file (tabela central referenciada por tudo) | ALTO | 3h | P1 | Sem DDL, RLS ou índices documentados para a tabela mais crítica do sistema |
| DB-M1 | Sem migrations versionadas (arquivos SQL avulsos, não Supabase CLI) | ALTO | 4h | P1 | Impede reprodução do ambiente, rollback e auditoria de mudanças |
| DB-NEW-M1 | `notification_schedules` sem schema file documentado | MÉDIO | 1h | P2 | Tabela funcional mas sem referência formal |
| DB-S1 | `attendance.lesson_date` como TEXT em vez de DATE | MÉDIO | 2h | P2 | Impede queries de range, ordenação e validação nativa |
| DB-S2 | `attendance.teacher_name` desnormalizado (nome em vez de FK) | MÉDIO | 4h | P2 | Risco de inconsistência se mentor mudar nome; impede joins eficientes |
| DB-S3 | `classes.professor`/`host` como TEXT legados | MÉDIO | incluído em DB-C1 | P3 | `class_mentors` já resolve via FK; colunas legadas geram confusão |
| DB-R1 | RLS sem roles intermediários (apenas admin write, sem mentor-scoped) | MÉDIO | 3h | P3 | Mentores não podem gerenciar apenas suas próprias turmas |
| DB-R2 | `classes` sem RLS documentada | ALTO | 1h | P1 | Tabela central exposta; sem evidência de política de acesso |
| DB-R3 | `zoom_tokens` acessível a qualquer admin | MÉDIO | 2h | P3 | Deveria ser scoped por mentor para isolamento de credenciais |
| DB-NEW-L1 | `notification_schedules.last_triggered_at` sem índice | BAIXO | 0.5h | P4 | pg_cron consulta essa coluna; índice melhora performance |
| DB-I1 | Sem índice em `notifications.processed_at` | BAIXO | 0.5h | P4 | Relevante se volume de notificações crescer significativamente |

---

### Débitos Adicionados

| ID | Débito | Severidade | Horas | Notas |
|---|---|---|---|---|
| DB-NEW-A1 | Ausência de constraints `NOT NULL` e `DEFAULT` explícitos nas colunas de notificações novas | MÉDIO | 0.5h | `evolution_message_ids` deveria ser `JSONB DEFAULT '[]'`; `delivered_at` deveria ser `TIMESTAMPTZ NULL` — sem isso, inserções parciais geram NULLs inesperados |
| DB-NEW-A2 | Sem auditoria de alterações manuais no Dashboard vs. schema documentado | ALTO | 1h (investigação) | Necessário rodar `supabase db diff` contra produção para mapear divergências antes de qualquer migration |

---

### Respostas ao Architect

**Q: As colunas `evolution_message_ids` e `delivered_at` existem em produção?**

A: Com base na evidência disponível — o commit `feat: add WhatsApp delivery confirmation tracking` foi merged na `main` e o GitHub Actions faz deploy automático — é **provável que o código do delivery-webhook esteja em produção**. Porém, não há migration correspondente no repositório. Conclusão: as colunas foram adicionadas manualmente via Dashboard do Supabase (sem versionamento) OU o delivery-webhook está em produção mas falhando silenciosamente ao tentar referenciar colunas inexistentes. É necessário rodar `supabase db diff` imediatamente para confirmar o estado real do schema em produção. **Este é o débito DB-NEW-C1.**

**Q: O CHECK constraint de status foi atualizado?**

A: A migration existente define `CHECK (status IN ('pending', 'processing', 'sent', 'partial', 'failed', 'cancelled'))`. O código do delivery-webhook tenta executar `UPDATE notifications SET status = 'delivered'` e `status = 'read'`. Existem dois cenários possíveis: **(a)** a constraint foi relaxada manualmente no Dashboard — sem migration — o que é tecnicamente funcional mas cria divergência de schema não rastreada; **(b)** a constraint está intacta e os UPDATEs estão falhando com erro de constraint violation, que o webhook provavelmente engole silenciosamente via `try/catch` genérico. **Risco crítico: confirmações de entrega WhatsApp podem estar sendo descartadas sem registro.** A resolução requer uma migration `ALTER TABLE notifications DROP CONSTRAINT ... ADD CONSTRAINT ... CHECK (status IN (..., 'delivered', 'read'))`.

---

### Recomendações (ordem de resolução)

1. **Imediato — Diagnóstico de divergência:** Executar `supabase db diff` contra produção para mapear toda divergência entre schema documentado e estado real. Sem isso, qualquer migration nova pode colidar com alterações manuais existentes.
2. **Dia 1-2 — DB-NEW-C2:** Escrever e aplicar migration que adiciona `delivered` e `read` ao CHECK constraint de `notifications.status`. Verificar se delivery-webhook começa a registrar confirmações de entrega.
3. **Dia 2-3 — DB-NEW-C1:** Escrever migration formal para `evolution_message_ids JSONB DEFAULT '[]'` e `delivered_at TIMESTAMPTZ NULL` em `notifications`. Se colunas já existem em produção, usar `ALTER TABLE ... ADD COLUMN IF NOT EXISTS`.
4. **Semana 1 — DB-C1 + DB-R2:** Documentar DDL completo da tabela `classes` (a tabela mais crítica do sistema não tem schema file). Incluir políticas RLS, índices e constraints.
5. **Semana 2 — DB-M1:** Migrar todos os arquivos SQL avulsos para migrations versionadas do Supabase CLI. Adotar convenção `YYYYMMDDHHMMSS_descricao.sql`.
6. **Semana 2-3 — DB-NEW-M1 + DB-S1:** Documentar schema de `notification_schedules` e criar migration para converter `attendance.lesson_date` de TEXT para DATE (com backfill dos dados existentes).
7. **Fase 2 — DB-S2, DB-R1, DB-R3:** Normalizar `teacher_name` para FK e implementar RLS com roles scoped por mentor.
8. **Backlog — DB-NEW-L1, DB-I1, DB-NEW-A1, DB-NEW-A2:** Índices e ajustes menores após estabilização do schema crítico.

---

### Estimativa Total DB

| Categoria | Débitos | Horas | Custo (R$150/h) |
|---|---|---|---|
| Críticos (P0) | DB-NEW-C1, DB-NEW-C2 | 3h | R$ 450 |
| Altos (P1) | DB-C1, DB-M1, DB-R2, DB-NEW-A2 | 9h | R$ 1.350 |
| Médios (P2/P3) | DB-NEW-M1, DB-S1, DB-S2, DB-S3, DB-R1, DB-R3, DB-NEW-A1 | 12.5h | R$ 1.875 |
| Baixos (P4) | DB-NEW-L1, DB-I1 | 1h | R$ 150 |
| **Total** | **14 débitos** | **25.5h** | **R$ 3.825** |

> **Nota:** A investigação inicial com `supabase db diff` (DB-NEW-A2) pode revelar débitos adicionais não mapeados. Recomendo reservar 20% de buffer no planejamento da Fase 1.
