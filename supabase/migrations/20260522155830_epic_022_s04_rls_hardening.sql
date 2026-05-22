-- ============================================================
-- Story 22.4 — RLS Hardening (EPIC-022 S.022.4)
-- ============================================================
-- ESCOPO: 27 tabelas (Tier 1+2+3) + 4 exceções com COMMENT
-- ROLLBACK: ver migration .down.sql pareada
-- ADR: docs/architecture/ADR-020-rls-policies.md
-- DRY-RUN: pg_dump prod + Docker PG 15 (ver scripts/dry-run-rls.sh)
-- GATE PROD: NON-NEGOTIABLE — autorização literal do user antes apply
-- ============================================================
-- Autor: @dev (Dex) — 2026-05-22
-- Pattern reference: 20260522010000_ps_rsvp_rls_authenticated_select.sql
-- Helper: 20260516020300_helper_functions.sql (is_dashboard_admin)
-- Data-engineer notes: docs/stories/22.4.data-engineer-notes.md
-- PG version: 15 (Supabase managed) — CREATE POLICY IF NOT EXISTS NÃO disponível
-- Idempotência: DROP POLICY IF EXISTS + CREATE POLICY (rerun-safe)
-- ============================================================


-- ============================================================
-- HEADER: helper function defensivo (AC10)
-- ============================================================
-- Custo zero, STABLE — não invalida planos. Garante função existe
-- pré-policies que dependem dela.
-- Body idêntico a 20260516020300_helper_functions.sql:25-30.
-- ============================================================

CREATE OR REPLACE FUNCTION public.is_dashboard_admin()
RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT COALESCE((auth.jwt()->'user_metadata'->>'role') = 'admin', false);
$$;
GRANT EXECUTE ON FUNCTION public.is_dashboard_admin() TO authenticated, anon, service_role;


-- ============================================================
-- AUDIT TRAIL — INSERT ANTES de qualquer ALTER em audit_log (ordering AC8)
-- ============================================================
-- Insere row identificando esta migration ANTES de proteger audit_log.
-- Se inserir DEPOIS de ENABLE RLS audit_log + POLICY, pode falhar self-write.
-- ============================================================

DO $audit$
BEGIN
  -- Não falha se audit_log não existir (defesa runtime)
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'rls_hardening_migration',
        jsonb_build_object(
          'story_id', '22.4',
          'epic_id',  'EPIC-022',
          'migration', '20260522155830_epic_022_s04_rls_hardening',
          'started_at', now(),
          'tables_in_scope', 27,
          'exceptions', 4
        )
      )
    $insert$;
  END IF;
END
$audit$;


-- ============================================================
-- TIER 1 — PII / Tokens / Financeiro (7 tabelas — admin only)
-- ============================================================
-- Pattern: is_dashboard_admin() only (Opção B confirmada @data-engineer Q1)
-- Razão: NÃO existe link students.id ↔ auth.users.id. Painel é admin-only.
-- service_role: bypass natural — sem POLICY explícita necessária.
-- Future: comment SQL `-- Future: adicionar OR ...` quando self-service ships
-- ============================================================


-- T1.1 — student_imports (REPLACE inline check pra is_dashboard_admin)
BEGIN;
ALTER TABLE public.student_imports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin full access on student_imports" ON public.student_imports;
DROP POLICY IF EXISTS "student_imports_select_admin" ON public.student_imports;
DROP POLICY IF EXISTS "student_imports_write_admin"  ON public.student_imports;
CREATE POLICY "student_imports_select_admin" ON public.student_imports
  FOR SELECT TO authenticated
  USING (public.is_dashboard_admin());
  -- Future: adicionar OR imported_by = auth.uid() if admin self-ownership view ships
CREATE POLICY "student_imports_write_admin" ON public.student_imports
  FOR ALL TO authenticated
  USING (public.is_dashboard_admin())
  WITH CHECK (public.is_dashboard_admin());
COMMIT;


-- T1.2 — wa_group_members (REPLACE auth.uid() IS NOT NULL — vazamento ativo)
BEGIN;
ALTER TABLE public.wa_group_members ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated full access on wa_group_members" ON public.wa_group_members;
DROP POLICY IF EXISTS "wa_group_members_select_admin" ON public.wa_group_members;
DROP POLICY IF EXISTS "wa_group_members_write_admin"  ON public.wa_group_members;
CREATE POLICY "wa_group_members_select_admin" ON public.wa_group_members
  FOR SELECT TO authenticated
  USING (public.is_dashboard_admin());
  -- Future: adicionar OR <ownership_clause> when self-service NPS view ships
CREATE POLICY "wa_group_members_write_admin" ON public.wa_group_members
  FOR ALL TO authenticated
  USING (public.is_dashboard_admin())
  WITH CHECK (public.is_dashboard_admin());
COMMIT;


-- T1.3 — class_nps_responses (REPLACE USING (true) — vazamento ativo)
BEGIN;
ALTER TABLE public.class_nps_responses ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "nps_responses: read for auth"     ON public.class_nps_responses;
DROP POLICY IF EXISTS "class_nps_responses_select_admin" ON public.class_nps_responses;
DROP POLICY IF EXISTS "class_nps_responses_write_admin"  ON public.class_nps_responses;
CREATE POLICY "class_nps_responses_select_admin" ON public.class_nps_responses
  FOR SELECT TO authenticated
  USING (public.is_dashboard_admin());
  -- Future: adicionar OR student_id IN (SELECT ... ) when self-service NPS view ships
CREATE POLICY "class_nps_responses_write_admin" ON public.class_nps_responses
  FOR ALL TO authenticated
  USING (public.is_dashboard_admin())
  WITH CHECK (public.is_dashboard_admin());
-- service_role: "nps_responses: full for service" preservada (não dropada)
COMMIT;


-- T1.4 — student_attendance (REPLACE authenticated read all — vazamento ativo)
BEGIN;
ALTER TABLE public.student_attendance ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated read student_attendance" ON public.student_attendance;
DROP POLICY IF EXISTS "Admin write student_attendance"        ON public.student_attendance;
DROP POLICY IF EXISTS "student_attendance_select_admin"       ON public.student_attendance;
DROP POLICY IF EXISTS "student_attendance_write_admin"        ON public.student_attendance;
CREATE POLICY "student_attendance_select_admin" ON public.student_attendance
  FOR SELECT TO authenticated
  USING (public.is_dashboard_admin());
  -- Future: adicionar OR student_id IN (SELECT ...) when self-service attendance view ships
CREATE POLICY "student_attendance_write_admin" ON public.student_attendance
  FOR ALL TO authenticated
  USING (public.is_dashboard_admin())
  WITH CHECK (public.is_dashboard_admin());
-- service_role policy preservada (não dropada)
COMMIT;


-- T1.5 — response_metadata (REPLACE inline IN ('admin','cs') — caveat CS role)
-- TODO T1: confirmar role 'cs' ativo antes de standardize pra is_dashboard_admin().
-- Se houver user CS ativo em prod, REVERTER esta seção pra inline check
-- ANTES de apply em T9. Comando validação T1:
--   SELECT raw_user_meta_data->>'role' AS r, count(*) FROM auth.users GROUP BY 1;
BEGIN;
ALTER TABLE public.response_metadata ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cs_admin_read_response_metadata"  ON public.response_metadata;
DROP POLICY IF EXISTS "cs_admin_write_response_metadata" ON public.response_metadata;
DROP POLICY IF EXISTS "response_metadata_select_admin"   ON public.response_metadata;
DROP POLICY IF EXISTS "response_metadata_write_admin"    ON public.response_metadata;
CREATE POLICY "response_metadata_select_admin" ON public.response_metadata
  FOR SELECT TO authenticated
  USING (public.is_dashboard_admin());
  -- Future: expand is_dashboard_admin() to include role='cs' OR keep inline here
CREATE POLICY "response_metadata_write_admin" ON public.response_metadata
  FOR ALL TO authenticated
  USING (public.is_dashboard_admin())
  WITH CHECK (public.is_dashboard_admin());
COMMIT;


-- T1.6 — nps_class_links (REPLACE USING (true) — tokens magic-link expostos)
BEGIN;
ALTER TABLE public.nps_class_links ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "nps_links: read for auth"   ON public.nps_class_links;
DROP POLICY IF EXISTS "nps_class_links_select_admin" ON public.nps_class_links;
DROP POLICY IF EXISTS "nps_class_links_write_admin"  ON public.nps_class_links;
CREATE POLICY "nps_class_links_select_admin" ON public.nps_class_links
  FOR SELECT TO authenticated
  USING (public.is_dashboard_admin());
  -- Future: adicionar OR <ownership_clause> when self-service NPS view ships
CREATE POLICY "nps_class_links_write_admin" ON public.nps_class_links
  FOR ALL TO authenticated
  USING (public.is_dashboard_admin())
  WITH CHECK (public.is_dashboard_admin());
-- "nps_links: full for service" preservada (não dropada)
COMMIT;


-- T1.7 — staff (CREATE — única Tier 1 sem ENABLE RLS)
BEGIN;
ALTER TABLE public.staff ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "staff_select_admin" ON public.staff;
DROP POLICY IF EXISTS "staff_write_admin"  ON public.staff;
CREATE POLICY "staff_select_admin" ON public.staff
  FOR SELECT TO authenticated
  USING (public.is_dashboard_admin());
  -- Future: adicionar OR email = (auth.jwt()->>'email') if staff self-service ships
CREATE POLICY "staff_write_admin" ON public.staff
  FOR ALL TO authenticated
  USING (public.is_dashboard_admin())
  WITH CHECK (public.is_dashboard_admin());
COMMIT;


-- ============================================================
-- TIER 2 — Operacional (16 tabelas — authenticated read + service_role write)
-- ============================================================
-- Pattern: authenticated lê tudo (UI admin), service_role full write
-- audit_log: tabela protegida POR ÚLTIMO via ordering AC8
-- ============================================================


-- T2.1 — class_reminder_batches (padronizado select_auth + service_role)
BEGIN;
ALTER TABLE public.class_reminder_batches ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "class_reminder_batches_select_auth" ON public.class_reminder_batches;
DROP POLICY IF EXISTS "class_reminder_batches_service_all" ON public.class_reminder_batches;
CREATE POLICY "class_reminder_batches_select_auth" ON public.class_reminder_batches
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "class_reminder_batches_service_all" ON public.class_reminder_batches
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.2 — class_reminder_sends (padronizado select_auth + service_role)
BEGIN;
ALTER TABLE public.class_reminder_sends ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "class_reminder_sends_select_auth" ON public.class_reminder_sends;
DROP POLICY IF EXISTS "class_reminder_sends_service_all" ON public.class_reminder_sends;
CREATE POLICY "class_reminder_sends_select_auth" ON public.class_reminder_sends
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "class_reminder_sends_service_all" ON public.class_reminder_sends
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.3 — notification_queue (CREATE — fila legacy sem ENABLE)
BEGIN;
ALTER TABLE public.notification_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "notification_queue_select_auth"  ON public.notification_queue;
DROP POLICY IF EXISTS "notification_queue_service_all"  ON public.notification_queue;
CREATE POLICY "notification_queue_select_auth" ON public.notification_queue
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "notification_queue_service_all" ON public.notification_queue
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.4 — schedule_overrides
BEGIN;
ALTER TABLE public.schedule_overrides ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "schedule_overrides_select_auth"  ON public.schedule_overrides;
DROP POLICY IF EXISTS "schedule_overrides_service_all"  ON public.schedule_overrides;
CREATE POLICY "schedule_overrides_select_auth" ON public.schedule_overrides
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "schedule_overrides_service_all" ON public.schedule_overrides
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.5 — zoom_absence_alerts
BEGIN;
ALTER TABLE public.zoom_absence_alerts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "zoom_absence_alerts_select_auth"  ON public.zoom_absence_alerts;
DROP POLICY IF EXISTS "zoom_absence_alerts_service_all"  ON public.zoom_absence_alerts;
CREATE POLICY "zoom_absence_alerts_select_auth" ON public.zoom_absence_alerts
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "zoom_absence_alerts_service_all" ON public.zoom_absence_alerts
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.6 — class_cohort_access
BEGIN;
ALTER TABLE public.class_cohort_access ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "class_cohort_access_select_auth"  ON public.class_cohort_access;
DROP POLICY IF EXISTS "class_cohort_access_service_all"  ON public.class_cohort_access;
CREATE POLICY "class_cohort_access_select_auth" ON public.class_cohort_access
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "class_cohort_access_service_all" ON public.class_cohort_access
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.7 — error_reports
BEGIN;
ALTER TABLE public.error_reports ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "error_reports_select_auth"  ON public.error_reports;
DROP POLICY IF EXISTS "error_reports_service_all"  ON public.error_reports;
CREATE POLICY "error_reports_select_auth" ON public.error_reports
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "error_reports_service_all" ON public.error_reports
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.8 — whatsapp_group_messages
BEGIN;
ALTER TABLE public.whatsapp_group_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "whatsapp_group_messages_select_auth"  ON public.whatsapp_group_messages;
DROP POLICY IF EXISTS "whatsapp_group_messages_service_all"  ON public.whatsapp_group_messages;
CREATE POLICY "whatsapp_group_messages_select_auth" ON public.whatsapp_group_messages
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "whatsapp_group_messages_service_all" ON public.whatsapp_group_messages
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.9 — zoom_chat_messages
BEGIN;
ALTER TABLE public.zoom_chat_messages ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "zoom_chat_messages_select_auth"  ON public.zoom_chat_messages;
DROP POLICY IF EXISTS "zoom_chat_messages_service_all"  ON public.zoom_chat_messages;
CREATE POLICY "zoom_chat_messages_select_auth" ON public.zoom_chat_messages
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "zoom_chat_messages_service_all" ON public.zoom_chat_messages
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.10 — zoom_import_queue
BEGIN;
ALTER TABLE public.zoom_import_queue ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "zoom_import_queue_select_auth"  ON public.zoom_import_queue;
DROP POLICY IF EXISTS "zoom_import_queue_service_all"  ON public.zoom_import_queue;
CREATE POLICY "zoom_import_queue_select_auth" ON public.zoom_import_queue
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "zoom_import_queue_service_all" ON public.zoom_import_queue
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.11 — automation_executions
BEGIN;
ALTER TABLE public.automation_executions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "automation_executions_select_auth"  ON public.automation_executions;
DROP POLICY IF EXISTS "automation_executions_service_all"  ON public.automation_executions;
CREATE POLICY "automation_executions_select_auth" ON public.automation_executions
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "automation_executions_service_all" ON public.automation_executions
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.12 — automation_rules
BEGIN;
ALTER TABLE public.automation_rules ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "automation_rules_select_auth"  ON public.automation_rules;
DROP POLICY IF EXISTS "automation_rules_service_all"  ON public.automation_rules;
CREATE POLICY "automation_rules_select_auth" ON public.automation_rules
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "automation_rules_service_all" ON public.automation_rules
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.13 — automation_runs
BEGIN;
ALTER TABLE public.automation_runs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "automation_runs_select_auth"  ON public.automation_runs;
DROP POLICY IF EXISTS "automation_runs_service_all"  ON public.automation_runs;
CREATE POLICY "automation_runs_select_auth" ON public.automation_runs
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "automation_runs_service_all" ON public.automation_runs
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.14 — alert_history
BEGIN;
ALTER TABLE public.alert_history ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "alert_history_select_auth"  ON public.alert_history;
DROP POLICY IF EXISTS "alert_history_service_all"  ON public.alert_history;
CREATE POLICY "alert_history_select_auth" ON public.alert_history
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "alert_history_service_all" ON public.alert_history
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.15 — engagement_daily_ranking
BEGIN;
ALTER TABLE public.engagement_daily_ranking ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "engagement_daily_ranking_select_auth"  ON public.engagement_daily_ranking;
DROP POLICY IF EXISTS "engagement_daily_ranking_service_all"  ON public.engagement_daily_ranking;
CREATE POLICY "engagement_daily_ranking_select_auth" ON public.engagement_daily_ranking
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "engagement_daily_ranking_service_all" ON public.engagement_daily_ranking
  FOR ALL TO service_role USING (true) WITH CHECK (true);
COMMIT;


-- T2.16 — audit_log (POR ÚLTIMO — ordering crítico AC8 + R11)
-- audit insert acima JÁ rodou ANTES de qualquer ALTER em audit_log.
-- Adicionar service_role policy explícita. Preservar admin_read_all + cs_read_own
-- existentes (não DROP genérico — apenas o nome específico que vamos criar).
BEGIN;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "audit_log_service_all" ON public.audit_log;
CREATE POLICY "audit_log_service_all" ON public.audit_log
  FOR ALL TO service_role USING (true) WITH CHECK (true);
-- "admin_read_all" + "cs_read_own" existentes preservadas
COMMIT;


-- ============================================================
-- TIER 3 — Referência / Config (4 tabelas — authenticated read + admin write)
-- ============================================================
-- Pattern: authenticated read (feature flags, lookups), admin write
-- service_role: bypass natural
-- ============================================================


-- T3.1 — integration_sources
BEGIN;
ALTER TABLE public.integration_sources ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "integration_sources_select_auth" ON public.integration_sources;
DROP POLICY IF EXISTS "integration_sources_write_admin" ON public.integration_sources;
CREATE POLICY "integration_sources_select_auth" ON public.integration_sources
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "integration_sources_write_admin" ON public.integration_sources
  FOR ALL TO authenticated
  USING (public.is_dashboard_admin())
  WITH CHECK (public.is_dashboard_admin());
COMMIT;


-- T3.2 — lesson_abstracts
BEGIN;
ALTER TABLE public.lesson_abstracts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "lesson_abstracts_select_auth" ON public.lesson_abstracts;
DROP POLICY IF EXISTS "lesson_abstracts_write_admin" ON public.lesson_abstracts;
CREATE POLICY "lesson_abstracts_select_auth" ON public.lesson_abstracts
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "lesson_abstracts_write_admin" ON public.lesson_abstracts
  FOR ALL TO authenticated
  USING (public.is_dashboard_admin())
  WITH CHECK (public.is_dashboard_admin());
COMMIT;


-- T3.3 — survey_templates (preserve cs_admin_read_templates se houver, padronizar)
BEGIN;
ALTER TABLE public.survey_templates ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "cs_admin_read_templates"        ON public.survey_templates;
DROP POLICY IF EXISTS "survey_templates_select_auth"   ON public.survey_templates;
DROP POLICY IF EXISTS "survey_templates_write_admin"   ON public.survey_templates;
CREATE POLICY "survey_templates_select_auth" ON public.survey_templates
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "survey_templates_write_admin" ON public.survey_templates
  FOR ALL TO authenticated
  USING (public.is_dashboard_admin())
  WITH CHECK (public.is_dashboard_admin());
COMMIT;


-- ============================================================
-- TIER 3 — app_config (T11 PREREQ — só ENABLE se pg_cron refactor pronto)
-- ============================================================
-- T11 PREREQ: refactor pg_cron pra service_role DEVE rodar ANTES desta seção.
-- Migration 20260407202000_app_config.sql:15 explicita DISABLE RLS porque
-- pg_cron (superuser) precisa ler/escrever via admin user connection.
-- Sequência obrigatória:
--   1. scripts/refactor-pg-cron-service-role.sql aplicado (T11)
--   2. Smoke pré-RLS: cron roda manualmente — sucesso
--   3. Este bloco aplicado
--   4. Smoke pós-RLS: cron roda manualmente — sucesso (service_role bypassa)
--
-- Se T11 não rodou ainda, COMENTAR este bloco e re-apply migration com
-- bloco ativo após T11 completo.
-- ============================================================

-- T3.4 — app_config (DESCOMENTAR só após T11 completo)
-- BEGIN;
-- ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;
-- DROP POLICY IF EXISTS "app_config_select_auth" ON public.app_config;
-- DROP POLICY IF EXISTS "app_config_write_admin" ON public.app_config;
-- CREATE POLICY "app_config_select_auth" ON public.app_config
--   FOR SELECT TO authenticated USING (true);
-- CREATE POLICY "app_config_write_admin" ON public.app_config
--   FOR ALL TO authenticated
--   USING (public.is_dashboard_admin())
--   WITH CHECK (public.is_dashboard_admin());
-- COMMIT;


-- ============================================================
-- EXCEÇÕES — Sem POLICY, service_role only (4 tabelas)
-- ============================================================
-- Razão por tabela documentada em ADR-020.
-- service_role bypass natural cobre 100% dos acessos.
-- ============================================================

COMMENT ON TABLE public.ac_dispatch_callbacks IS
  'RLS_DISABLED_REASON: webhook callbacks written/read only by edge functions with service_role. Ref: ADR-020';

COMMENT ON TABLE public.oauth_states IS
  'RLS_DISABLED_REASON: used only by OAuth callback flow with service_role, never queried by users. Ref: ADR-020';

COMMENT ON TABLE public.ac_purchase_events IS
  'RLS_DISABLED_REASON: webhook events written/read only by edge functions with service_role. Ref: ADR-020';

COMMENT ON TABLE public.ac_product_mappings IS
  'RLS_DISABLED_REASON: lookup table written/read only by edge functions with service_role. Ref: ADR-020';


-- ============================================================
-- AUDIT TRAIL — final entry (status complete)
-- ============================================================
DO $audit_final$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'rls_hardening_migration',
        jsonb_build_object(
          'story_id', '22.4',
          'migration', '20260522155830_epic_022_s04_rls_hardening',
          'completed_at', now(),
          'status', 'tier_1_2_3_minus_app_config_applied',
          'app_config_pending', true,
          'note', 'app_config bloco comentado — aguarda T11 pg_cron refactor'
        )
      )
    $insert$;
  END IF;
END
$audit_final$;
