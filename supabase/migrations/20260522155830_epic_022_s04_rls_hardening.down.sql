-- ============================================================
-- Story 22.4 — RLS Hardening ROLLBACK (EPIC-022 S.022.4)
-- ============================================================
-- Migration up: 20260522155830_epic_022_s04_rls_hardening.sql
-- ADR: docs/architecture/ADR-020-rls-policies.md
--
-- DECISÃO ROLLBACK (documentada em ADR-020):
--   - REPLACE de POLICY frouxa: down DROP da policy nova SEM recrear a frouxa.
--     Razão: re-criar policy permissiva = re-introduzir vulnerabilidade conhecida.
--     Tabela fica SEM POLICY restritiva, mas COM RLS — bloqueia tudo pra
--     authenticated, exceto service_role bypass. Estado seguro por padrão.
--   - CREATE em tabela sem ENABLE prévio (somente `staff`, A): rollback DISABLE RLS.
--   - Comentários COMMENT ON TABLE: restaurar pro estado pré-existente ('').
--   - Audit insert: NÃO desfazer (audit é append-only).
-- ============================================================
-- Autor: @dev (Dex) — 2026-05-22
-- ============================================================


-- ============================================================
-- AUDIT TRAIL — registrar rollback ANTES de mexer em audit_log
-- ============================================================
DO $audit_rb$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'rls_hardening_rollback',
        jsonb_build_object(
          'story_id', '22.4',
          'migration', '20260522155830_epic_022_s04_rls_hardening.down',
          'started_at', now()
        )
      )
    $insert$;
  END IF;
END
$audit_rb$;


-- ============================================================
-- TIER 3 — app_config (no-op se bloco up estava comentado)
-- ============================================================
-- Mantido comentado pareado ao up. Se up foi descomentado pré-apply,
-- descomentar aqui também antes de rollback.
-- BEGIN;
-- DROP POLICY IF EXISTS "app_config_select_auth" ON public.app_config;
-- DROP POLICY IF EXISTS "app_config_write_admin" ON public.app_config;
-- ALTER TABLE public.app_config DISABLE ROW LEVEL SECURITY;
-- COMMIT;


-- ============================================================
-- TIER 3 — DROP policies criadas
-- ============================================================

-- T3.3 — survey_templates
BEGIN;
DROP POLICY IF EXISTS "survey_templates_select_auth" ON public.survey_templates;
DROP POLICY IF EXISTS "survey_templates_write_admin" ON public.survey_templates;
-- Não recriamos "cs_admin_read_templates" (decisão honest rollback)
COMMIT;

-- T3.2 — lesson_abstracts
BEGIN;
DROP POLICY IF EXISTS "lesson_abstracts_select_auth" ON public.lesson_abstracts;
DROP POLICY IF EXISTS "lesson_abstracts_write_admin" ON public.lesson_abstracts;
COMMIT;

-- T3.1 — integration_sources
BEGIN;
DROP POLICY IF EXISTS "integration_sources_select_auth" ON public.integration_sources;
DROP POLICY IF EXISTS "integration_sources_write_admin" ON public.integration_sources;
COMMIT;


-- ============================================================
-- TIER 2 — DROP policies novas
-- ============================================================

-- T2.16 — audit_log (primeiro inverter, antes de remover outras dependências)
BEGIN;
DROP POLICY IF EXISTS "audit_log_service_all" ON public.audit_log;
-- admin_read_all + cs_read_own existentes preservadas (não criadas por esta migration)
COMMIT;

-- T2.15 — engagement_daily_ranking
BEGIN;
DROP POLICY IF EXISTS "engagement_daily_ranking_select_auth" ON public.engagement_daily_ranking;
DROP POLICY IF EXISTS "engagement_daily_ranking_service_all" ON public.engagement_daily_ranking;
COMMIT;

-- T2.14 — alert_history
BEGIN;
DROP POLICY IF EXISTS "alert_history_select_auth" ON public.alert_history;
DROP POLICY IF EXISTS "alert_history_service_all" ON public.alert_history;
COMMIT;

-- T2.13 — automation_runs
BEGIN;
DROP POLICY IF EXISTS "automation_runs_select_auth" ON public.automation_runs;
DROP POLICY IF EXISTS "automation_runs_service_all" ON public.automation_runs;
COMMIT;

-- T2.12 — automation_rules
BEGIN;
DROP POLICY IF EXISTS "automation_rules_select_auth" ON public.automation_rules;
DROP POLICY IF EXISTS "automation_rules_service_all" ON public.automation_rules;
COMMIT;

-- T2.11 — automation_executions
BEGIN;
DROP POLICY IF EXISTS "automation_executions_select_auth" ON public.automation_executions;
DROP POLICY IF EXISTS "automation_executions_service_all" ON public.automation_executions;
COMMIT;

-- T2.10 — zoom_import_queue
BEGIN;
DROP POLICY IF EXISTS "zoom_import_queue_select_auth" ON public.zoom_import_queue;
DROP POLICY IF EXISTS "zoom_import_queue_service_all" ON public.zoom_import_queue;
COMMIT;

-- T2.9 — zoom_chat_messages
BEGIN;
DROP POLICY IF EXISTS "zoom_chat_messages_select_auth" ON public.zoom_chat_messages;
DROP POLICY IF EXISTS "zoom_chat_messages_service_all" ON public.zoom_chat_messages;
COMMIT;

-- T2.8 — whatsapp_group_messages
BEGIN;
DROP POLICY IF EXISTS "whatsapp_group_messages_select_auth" ON public.whatsapp_group_messages;
DROP POLICY IF EXISTS "whatsapp_group_messages_service_all" ON public.whatsapp_group_messages;
COMMIT;

-- T2.7 — error_reports
BEGIN;
DROP POLICY IF EXISTS "error_reports_select_auth" ON public.error_reports;
DROP POLICY IF EXISTS "error_reports_service_all" ON public.error_reports;
COMMIT;

-- T2.6 — class_cohort_access
BEGIN;
DROP POLICY IF EXISTS "class_cohort_access_select_auth" ON public.class_cohort_access;
DROP POLICY IF EXISTS "class_cohort_access_service_all" ON public.class_cohort_access;
COMMIT;

-- T2.5 — zoom_absence_alerts
BEGIN;
DROP POLICY IF EXISTS "zoom_absence_alerts_select_auth" ON public.zoom_absence_alerts;
DROP POLICY IF EXISTS "zoom_absence_alerts_service_all" ON public.zoom_absence_alerts;
COMMIT;

-- T2.4 — schedule_overrides
BEGIN;
DROP POLICY IF EXISTS "schedule_overrides_select_auth" ON public.schedule_overrides;
DROP POLICY IF EXISTS "schedule_overrides_service_all" ON public.schedule_overrides;
COMMIT;

-- T2.3 — notification_queue
BEGIN;
DROP POLICY IF EXISTS "notification_queue_select_auth" ON public.notification_queue;
DROP POLICY IF EXISTS "notification_queue_service_all" ON public.notification_queue;
COMMIT;

-- T2.2 — class_reminder_sends
BEGIN;
DROP POLICY IF EXISTS "class_reminder_sends_select_auth" ON public.class_reminder_sends;
DROP POLICY IF EXISTS "class_reminder_sends_service_all" ON public.class_reminder_sends;
COMMIT;

-- T2.1 — class_reminder_batches
BEGIN;
DROP POLICY IF EXISTS "class_reminder_batches_select_auth" ON public.class_reminder_batches;
DROP POLICY IF EXISTS "class_reminder_batches_service_all" ON public.class_reminder_batches;
COMMIT;


-- ============================================================
-- TIER 1 — DROP policies novas
-- ============================================================
-- Decisão honest rollback: NÃO recriar policies frouxas originais.
-- Tabelas ficam com RLS habilitado MAS sem POLICY pra authenticated.
-- service_role continua escrevendo (bypass natural).
-- Admin perde acesso até reaplicar migration up.
-- ============================================================

-- T1.7 — staff (DISABLE RLS — única Tier 1 que era sem ENABLE)
BEGIN;
DROP POLICY IF EXISTS "staff_select_admin" ON public.staff;
DROP POLICY IF EXISTS "staff_write_admin"  ON public.staff;
ALTER TABLE public.staff DISABLE ROW LEVEL SECURITY;
COMMIT;

-- T1.6 — nps_class_links
BEGIN;
DROP POLICY IF EXISTS "nps_class_links_select_admin" ON public.nps_class_links;
DROP POLICY IF EXISTS "nps_class_links_write_admin"  ON public.nps_class_links;
-- "nps_links: full for service" preservada (não era criada por esta migration)
COMMIT;

-- T1.5 — response_metadata
BEGIN;
DROP POLICY IF EXISTS "response_metadata_select_admin" ON public.response_metadata;
DROP POLICY IF EXISTS "response_metadata_write_admin"  ON public.response_metadata;
COMMIT;

-- T1.4 — student_attendance
BEGIN;
DROP POLICY IF EXISTS "student_attendance_select_admin" ON public.student_attendance;
DROP POLICY IF EXISTS "student_attendance_write_admin"  ON public.student_attendance;
COMMIT;

-- T1.3 — class_nps_responses
BEGIN;
DROP POLICY IF EXISTS "class_nps_responses_select_admin" ON public.class_nps_responses;
DROP POLICY IF EXISTS "class_nps_responses_write_admin"  ON public.class_nps_responses;
-- "nps_responses: full for service" preservada (não era criada por esta migration)
COMMIT;

-- T1.2 — wa_group_members
BEGIN;
DROP POLICY IF EXISTS "wa_group_members_select_admin" ON public.wa_group_members;
DROP POLICY IF EXISTS "wa_group_members_write_admin"  ON public.wa_group_members;
COMMIT;

-- T1.1 — student_imports
BEGIN;
DROP POLICY IF EXISTS "student_imports_select_admin" ON public.student_imports;
DROP POLICY IF EXISTS "student_imports_write_admin"  ON public.student_imports;
COMMIT;


-- ============================================================
-- EXCEÇÕES — restaurar COMMENT pré-existente (vazio)
-- ============================================================
COMMENT ON TABLE public.ac_dispatch_callbacks IS NULL;
COMMENT ON TABLE public.oauth_states          IS NULL;
COMMENT ON TABLE public.ac_purchase_events    IS NULL;
COMMENT ON TABLE public.ac_product_mappings   IS NULL;


-- ============================================================
-- HEADER helper function: NÃO dropar is_dashboard_admin()
-- ============================================================
-- Função é load-bearing pra ~20 migrations subsequentes (NPS admin, dispatch).
-- CREATE OR REPLACE foi idempotente; rollback NÃO precisa desfazer.
-- ============================================================


-- ============================================================
-- AUDIT TRAIL final
-- ============================================================
DO $audit_rb_final$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'rls_hardening_rollback',
        jsonb_build_object(
          'story_id', '22.4',
          'migration', '20260522155830_epic_022_s04_rls_hardening.down',
          'completed_at', now(),
          'status', 'rollback_complete',
          'note', 'policies dropadas; RLS permanece habilitado exceto staff (DISABLE); decisão honest: não recriar policies frouxas'
        )
      )
    $insert$;
  END IF;
END
$audit_rb_final$;
