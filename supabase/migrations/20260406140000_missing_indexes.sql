-- ═══════════════════════════════════════
-- LESSON PAGES — DB-NEW-L1 + DB-I1: índices ausentes
-- notification_schedules.last_triggered_at — consultado para verificar
-- quando um agendamento foi disparado pela última vez pelo pg_cron.
-- notifications.processed_at — consultado para auditoria e relatórios.
-- ═══════════════════════════════════════

-- DB-NEW-L1: last_fired_at (coluna real — não last_triggered_at)
CREATE INDEX IF NOT EXISTS idx_notification_schedules_last_fired
  ON public.notification_schedules(last_fired_at);

-- DB-I1
CREATE INDEX IF NOT EXISTS idx_notifications_processed_at
  ON public.notifications(processed_at);
