# EPIC-002 — Agendamento Automático de Notificações WhatsApp

## Metadata

```yaml
epic_id: EPIC-002
title: Agendamento Automático de Notificações WhatsApp
status: Ready for Story Creation
created_by: "@pm (Morgan)"
created_at: 2026-04-02
priority: High
depends_on: EPIC-001 (Done)
```

---

## Epic Goal

Permitir que o coordenador configure envios automáticos de lembretes de aula (e outros tipos) com antecedência definida — sem precisar acessar o painel no momento exato do envio. O sistema agenda, verifica e dispara via pg_cron + Edge Function existente.

---

## Problem

Atualmente o envio de avisos WhatsApp é 100% manual: o admin precisa acessar o painel, selecionar cohort/classe e clicar "Enviar" no momento correto. Isso cria dependência humana e risco de esquecimento, especialmente para lembretes recorrentes de aula.

---

## Solution Overview

Adicionar uma tabela `notification_schedules` que define regras de envio recorrente (ex: "enviar lembrete 2h antes de cada aula da classe X"). Um job pg_cron executa a cada 15 minutos, verifica quais schedules devem ser disparados, e insere o registro correspondente em `notifications` — o webhook existente cuida do resto.

```
pg_cron (15min) → verifica notification_schedules → INSERT notifications → webhook → Edge Function → WhatsApp
```

---

## Existing System Context

- **EPIC-001 completo:** tabelas `notifications`, `mentors`, `class_cohorts`, `class_mentors` existem
- **Webhook ativo:** trigger `notify-whatsapp-on-pending` dispara em qualquer INSERT `pending`
- **Edge Function deployada:** `send-whatsapp` com template engine e state machine
- **pg_cron:** extensão não instalada ainda — precisa ser ativada no Dashboard
- **classes:** tabela com `weekday`, `time_start` — base para calcular próxima ocorrência

---

## Stories

### Story 2.1 — Schema de Agendamentos + pg_cron
- Criar tabela `notification_schedules`
- Habilitar extensão `pg_cron`
- Criar função SQL `process_notification_schedules()` que gera INSERTs em `notifications`
- Registrar job pg_cron a cada 15 minutos
- Status: Draft

### Story 2.2 — UI de Agendamentos no Painel Admin
- Nova aba "Agendamentos" em `calendario/admin.html`
- CRUD de schedules (criar, pausar, deletar)
- Visualização de próximos disparos previstos
- Status: Draft

---

## Dependency Order

```
EPIC-001 (Done) → Story 2.1 → Story 2.2
```

---

## Key Design Decisions

### Schema: notification_schedules
```sql
CREATE TABLE notification_schedules (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  class_id         UUID REFERENCES classes(id),
  cohort_id        UUID REFERENCES cohorts(id),
  notification_type TEXT NOT NULL,          -- 'class_reminder' | 'group_announcement'
  target_type      TEXT NOT NULL DEFAULT 'both',
  message_template TEXT NOT NULL,
  hours_before     SMALLINT NOT NULL DEFAULT 2, -- enviar X horas antes da aula
  active           BOOLEAN DEFAULT true,
  last_fired_at    TIMESTAMPTZ,
  next_fire_at     TIMESTAMPTZ,              -- calculado pelo cron
  created_by       UUID REFERENCES auth.users(id),
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);
```

### Lógica do pg_cron
A função `process_notification_schedules()` para cada schedule ativo:
1. Calcula próxima ocorrência da aula (baseado em `classes.weekday` + `classes.time_start`)
2. Verifica se `now() >= next_fire_at` E `next_fire_at > last_fired_at`
3. Se sim: INSERT em `notifications` com status='pending', atualiza `last_fired_at`
4. Recalcula `next_fire_at` para a próxima ocorrência

### Prevenção de duplicatas
Guard no INSERT:
```sql
WHERE NOT EXISTS (
  SELECT 1 FROM notifications
  WHERE class_id = s.class_id
    AND created_at > now() - interval '1 hour'
    AND type = s.notification_type
)
```

---

## Compatibility Requirements

- Zero impacto no sistema de notificações manual (EPIC-001)
- O webhook existente não precisa de modificação
- pg_cron requer ativação no Supabase Dashboard (Extensions)

---

## Definition of Done

- [ ] pg_cron ativo no projeto Supabase
- [ ] Tabela `notification_schedules` criada com RLS
- [ ] Job pg_cron a cada 15min executando `process_notification_schedules()`
- [ ] Teste: criar schedule → aguardar disparo → verificar notification gerada → WhatsApp recebido
- [ ] UI: admin consegue criar/pausar/deletar schedules sem tocar no banco
- [ ] Regressão: envio manual (EPIC-001) continua funcionando

---

## Risks

| Risco | Probabilidade | Impacto | Mitigação |
|-------|-------------|---------|-----------|
| pg_cron não disponível no plano Supabase | Baixa | Alto | Verificar plano antes de iniciar Story 2.1; alternativa: Edge Function via Vercel Cron |
| Duplicatas de envio (race condition no cron) | Baixa | Médio | Guard EXISTS no INSERT + UNIQUE em notifications por class+hora |
| Cálculo errado de next_fire_at | Média | Médio | Testar com classes em dias diferentes da semana |

---

## Change Log

| Data | Agente | Ação |
|------|--------|------|
| 2026-04-02 | @pm (Morgan) | Epic criado com base no EPIC-001 Done e architecture-notifications.md §10 |
