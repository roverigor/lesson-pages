## QA Review — Technical Debt Assessment

> **Revisado por:** @qa (Quinn)
> **Data:** 2026-04-06
> **Base:** technical-debt-DRAFT.md + db-specialist-review.md + ux-specialist-review.md

---

### Gate Status: APPROVED COM RESSALVAS CRÍTICAS

O assessment está aprovado para seguir para planejamento de resolução, com uma ressalva crítica que deve ser tratada antes de qualquer merge de nova feature: **a divergência de schema entre código e produção (DB-NEW-C1 + DB-NEW-C2) não foi confirmada empiricamente**. O delivery tracking do WhatsApp pode estar silenciosamente descartando confirmações de entrega. Esta condição deve ser verificada e documentada antes da próxima sprint.

Justificativa para aprovação parcial: os débitos estão bem catalogados, as severidades são coerentes com a evidência disponível, as dependências entre itens foram mapeadas, e o plano de fases é tecnicamente viável. O assessment não omite problemas conhecidos e não subestima esforços críticos.

---

### Gaps Identificados

#### Gap 1 — Ausência de verificação empírica do estado em produção
O assessment identifica corretamente que há divergência provável entre schema documentado e schema em produção. Porém, **nenhum diagnóstico foi executado** (`supabase db diff`). O risco é que a Fase 1 planeje migrations que colidam com alterações manuais já aplicadas no Dashboard. **Ação requerida antes do planejamento de Fase 1:** executar `supabase db diff` e documentar saída.

#### Gap 2 — Monitoramento de erros das Edge Functions não coberto
O assessment cobre as credenciais hardcoded nas Edge Functions (SYS-C2, SYS-C3), mas não aborda se existe **algum sistema de monitoramento de erros** para essas funções. Se o delivery-webhook está falhando silenciosamente, não há alerta. **Débito implícito:** ausência de observabilidade.

#### Gap 3 — Impacto de DB-S1 em dados existentes não estimado
A conversão de `attendance.lesson_date` de TEXT para DATE requer backfill. O assessment não estima o volume de registros existentes nem o risco de falha de conversão para entradas com formato inválido (e.g., datas em formato DD/MM/YYYY em vez de YYYY-MM-DD). Pode ser maior que 2h se houver dados mal-formatados.

#### Gap 4 — Sem critérios de rollback para as migrations
O plano de Fase 1 propõe alterações em tabelas com dados em produção. Nenhuma das migrations tem estratégia de rollback documentada. Para `ALTER TABLE notifications`, especificamente, um rollback após dados com `status = 'delivered'` terem sido inseridos pode corromper o histórico.

#### Gap 5 — CORS (SYS-C5) não tem testes de validação propostos
A resolução do CORS é listada como 1h, mas não há critério de aceitação claro. "Remover `*`" sem validar quais origens são legítimas pode quebrar integrações existentes (Evolution API callback, frontend de terceiros). Requer mapeamento de origens antes da mudança.

---

### Riscos Cruzados

| Risco | Áreas Afetadas | Probabilidade | Impacto | Mitigação |
|---|---|---|---|---|
| Migration DB-NEW-C2 colidindo com estado manual em produção | DB + Sistema de notificações | ALTA | ALTO | Executar `db diff` antes; usar `IF NOT EXISTS` e `ALTER TABLE ... DROP CONSTRAINT IF EXISTS` |
| Refactor do `admin.html` introduzindo regressão em fluxo de presença | UX + DB (escrita de attendance) | MÉDIA | ALTO | Criar smoke tests de presença antes do refactor; testar fluxo completo após |
| Correção de CORS quebrando callback da Evolution API | Segurança + Sistema WhatsApp | MÉDIA | CRÍTICO | Mapear todas as origens que chamam as Edge Functions antes de restringir `*` |
| Conversão `lesson_date` TEXT→DATE com dados mal-formatados | DB + Frontend de presença | MÉDIA | MÉDIO | Auditoria dos dados existentes com `SELECT DISTINCT lesson_date FROM attendance` antes da migration |
| Normalização de `teacher_name` (DB-S2) quebrando queries existentes | DB + Frontend | BAIXA | ALTO | Manter coluna legada com `GENERATED ALWAYS AS` ou view de compatibilidade durante transição |
| Credenciais Zoom/Evolution em logs de erro (mesmo após mover para env vars) | Segurança | BAIXA | ALTO | Garantir que mensagens de erro não interpolam variáveis de ambiente |

---

### Dependências Validadas

A ordem de resolução proposta faz sentido técnico, com os seguintes ajustes recomendados:

**Deve preceder tudo:**
- `supabase db diff` em produção (DB-NEW-A2) → mapeia estado real antes de qualquer migration

**Fase 1 (segurança + schema crítico) — ordem interna correta:**
- SYS-C2 + SYS-C3 (credenciais) podem ser resolvidos em paralelo com DB-NEW-C2
- DB-NEW-C1 deve vir **após** DB-NEW-C2 (CHECK constraint primeiro, depois adicionar colunas com novos valores)
- SYS-C5 (CORS) deve ser o **último** item da Fase 1, após mapear origens legítimas

**Dependência cruzada não documentada:**
- UX-H2 (abstracts DB-driven) depende de DB-C1 estar resolvido (tabela `classes` documentada com schema estável)
- UX-C1 (refactor admin) deve vir **após** DB-M1 (migrations versionadas), pois o refactor provavelmente exporá queries implícitas que precisam de schema estável

---

### Testes Requeridos (pós-resolução)

#### Após Fase 1 — Segurança + Schema

**SYS-C2/C3 (credenciais):**
- [ ] Edge Functions ainda funcionam após mover credenciais para env vars
- [ ] Nenhuma credencial aparece em logs de erro ou responses da API
- [ ] Variáveis de ambiente estão definidas no Supabase Dashboard (prod)

**DB-NEW-C2 (CHECK constraint):**
- [ ] `UPDATE notifications SET status = 'delivered'` executa sem erro
- [ ] `UPDATE notifications SET status = 'read'` executa sem erro
- [ ] Delivery webhook registra confirmações de entrega visíveis na tabela

**DB-NEW-C1 (colunas novas):**
- [ ] `evolution_message_ids` aceita array JSON
- [ ] `delivered_at` aceita TIMESTAMPTZ e persiste corretamente
- [ ] Webhook de confirmação de entrega popula ambas as colunas

#### Após Fase 2 — Migrations e DB

**DB-M1 (migrations versionadas):**
- [ ] `supabase db push` em ambiente de staging executa sem erros
- [ ] `supabase migration list` mostra histórico completo e consistente
- [ ] `supabase db diff` retorna diff vazio após aplicar todas as migrations

**DB-S1 (lesson_date DATE):**
- [ ] Todos os registros existentes foram convertidos sem perda de dados
- [ ] Queries de range por data funcionam (e.g., aulas desta semana)
- [ ] Frontend exibe datas corretamente após conversão de tipo

#### Após Fase 3 — Frontend

**UX-C1 (admin refactor):**
- [ ] Fluxo de marcação de presença funciona end-to-end
- [ ] Envio de notificação WhatsApp funciona end-to-end
- [ ] Agendamento pg_cron visível e editável no admin
- [ ] Nenhuma regressão em funcionalidades existentes (smoke test completo)

**UX-H2 (abstracts DB-driven):**
- [ ] Conteúdo renderizado a partir do banco é idêntico ao hardcoded anterior
- [ ] Admin consegue atualizar conteúdo sem editar código
- [ ] Página carrega em menos de 2s (evitar N+1 queries)

---

### Parecer Final

O assessment está **APROVADO para seguir para planejamento**, com três condições que devem ser atendidas antes do início da Fase 1:

1. **Executar `supabase db diff` em produção** e documentar todas as divergências encontradas. Resultado deve ser adicionado como seção no `technical-debt-assessment.md` final.
2. **Verificar empiricamente se o delivery-webhook está falhando** (inspecionar logs do Supabase Edge Functions para erros de constraint violation nos últimos 7 dias).
3. **Mapear origens legítimas** que chamam as Edge Functions antes de planejar a correção de CORS.

Sem essas três ações, a Fase 1 corre risco de introduzir migrations em conflito com o estado atual de produção.
