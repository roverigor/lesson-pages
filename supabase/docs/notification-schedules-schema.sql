-- ═══════════════════════════════════════
-- LESSON PAGES — Schema: notification_schedules
-- Gerado por DB-NEW-M1 — @data-engineer (Dara) — 06/04/2026
-- Este arquivo é documentação de referência, NÃO deve ser executado diretamente.
-- Migration canônica: supabase/migrations/20260402191455_notification_schedules_pgcron.sql
-- ═══════════════════════════════════════

-- ─── NOTIFICATION_SCHEDULES ────────────────────────────────────────────────
-- Define agendamentos recorrentes de notificações WhatsApp por turma/cohort.
-- O pg_cron job "process-notifications" executa process_notification_schedules()
-- a cada 15 minutos para disparar notificações cujo next_fire_at <= now().
--
-- Fluxo:
--   1. Admin cria/edita um schedule via UI (/calendario/admin.html)
--   2. calculate_next_fire_at() calcula o próximo horário de disparo baseado em
--      class.weekday, class.time_start e hours_before
--   3. pg_cron chama process_notification_schedules() a cada 15 min
--   4. Schedules ativos com next_fire_at <= now() geram um registro em notifications
--   5. O trigger notifications INSERT → send-whatsapp Edge Function envia a mensagem
--   6. last_fired_at e next_fire_at são atualizados após disparo
--
-- pg_cron job: SELECT cron.schedule('process-notifications', '*/15 * * * *',
--              'SELECT process_notification_schedules()');
--
-- RLS: apenas admin (user_metadata.role = 'admin') pode ler/escrever.

CREATE TABLE IF NOT EXISTS public.notification_schedules (
  id                UUID      DEFAULT gen_random_uuid() PRIMARY KEY,
  class_id          UUID      REFERENCES public.classes(id) ON DELETE CASCADE,
  cohort_id         UUID      REFERENCES public.cohorts(id) ON DELETE SET NULL,
  notification_type TEXT      NOT NULL
                    CHECK (notification_type IN ('class_reminder', 'group_announcement', 'custom')),
  target_type       TEXT      NOT NULL DEFAULT 'both'
                    CHECK (target_type IN ('group', 'individual', 'both')),
  message_template  TEXT      NOT NULL,  -- suporta {{class_name}}, {{cohort_name}}, {{zoom_link}}, {{class_time_start}}, {{class_professor}}
  hours_before      SMALLINT  NOT NULL DEFAULT 2 CHECK (hours_before > 0),  -- horas antes da aula para disparar
  active            BOOLEAN   DEFAULT true,
  last_fired_at     TIMESTAMPTZ,   -- quando foi disparado pela última vez
  next_fire_at      TIMESTAMPTZ,   -- quando será disparado novamente (calculado automaticamente)
  created_by        UUID      REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

-- Índices
-- CREATE INDEX idx_notification_schedules_active     ON public.notification_schedules(active);
-- CREATE INDEX idx_notification_schedules_class      ON public.notification_schedules(class_id);
-- CREATE INDEX idx_notification_schedules_next       ON public.notification_schedules(next_fire_at)
--   WHERE active = true;                             -- filtro eficiente para o pg_cron job
-- CREATE INDEX idx_notification_schedules_last_fired ON public.notification_schedules(last_fired_at);
--   (adicionado em 20260406140000_missing_indexes.sql)


-- ─── FUNÇÕES RELACIONADAS ───────────────────────────────────────────────────

-- calculate_next_fire_at(class_weekday, class_time_start, hours_before)
-- → Calcula o próximo TIMESTAMPTZ em que a notificação deve ser disparada.
--    Avança para a próxima ocorrência do dia da semana da aula.
--    Definida em: 20260402191455_notification_schedules_pgcron.sql

-- process_notification_schedules()
-- → Chamada pelo pg_cron a cada 15 min. Para cada schedule ativo com
--    next_fire_at <= now(), insere uma linha em notifications com status='pending'.
--    O trigger db→Edge Function cuida do envio.
--    Definida em: 20260402191455_notification_schedules_pgcron.sql


-- ─── RELAÇÕES ───────────────────────────────────────────────────────────────
--
--  notification_schedules (N) >── classes (1)
--  notification_schedules (N) >── cohorts (1)
--  notification_schedules (1) ──> notifications (N)  [via process_notification_schedules()]
--
-- ─── VARIÁVEIS DE TEMPLATE ──────────────────────────────────────────────────
--
--  {{class_name}}        — nome da turma (classes.name)
--  {{cohort_name}}       — nome da turma/grupo (cohorts.name)
--  {{zoom_link}}         — link Zoom (cohorts.zoom_link)
--  {{class_time_start}}  — horário de início (classes.time_start)
--  {{class_professor}}   — professor escalado (via class_mentors JOIN)
--  {{mentor_name}}       — nome do mentor (para notificações individuais)
