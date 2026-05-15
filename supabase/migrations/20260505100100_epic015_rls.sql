-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-015 Story 15.A — RLS Policies (Migration 2/4)
-- Estende role 'cs' às policies + cria policies para 8 tabelas novas.
--
-- Pattern: usa is_cs_or_admin() helper criado em migration 1/4.
-- Service role bypass mantido em todas (worker pg_cron usa).
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. EXTEND RLS em tabelas existentes — aceitar role IN ('admin','cs')
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── cohorts ──────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "CS or Admin insert cohorts" ON cohorts;
CREATE POLICY "CS or Admin insert cohorts" ON cohorts FOR INSERT TO authenticated
  WITH CHECK (is_cs_or_admin());

DROP POLICY IF EXISTS "CS or Admin update cohorts" ON cohorts;
CREATE POLICY "CS or Admin update cohorts" ON cohorts FOR UPDATE TO authenticated
  USING (is_cs_or_admin());

DROP POLICY IF EXISTS "CS or Admin delete cohorts" ON cohorts;
CREATE POLICY "CS or Admin delete cohorts" ON cohorts FOR DELETE TO authenticated
  USING (is_cs_or_admin());

-- ─── students ─────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "CS or Admin insert students" ON students;
CREATE POLICY "CS or Admin insert students" ON students FOR INSERT TO authenticated
  WITH CHECK (is_cs_or_admin());

DROP POLICY IF EXISTS "CS or Admin update students" ON students;
CREATE POLICY "CS or Admin update students" ON students FOR UPDATE TO authenticated
  USING (is_cs_or_admin());

DROP POLICY IF EXISTS "CS or Admin delete students" ON students;
CREATE POLICY "CS or Admin delete students" ON students FOR DELETE TO authenticated
  USING (is_cs_or_admin());

-- ─── student_cohorts ──────────────────────────────────────────────────────

ALTER TABLE student_cohorts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read student_cohorts" ON student_cohorts;
CREATE POLICY "Authenticated read student_cohorts" ON student_cohorts FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "CS or Admin write student_cohorts" ON student_cohorts;
CREATE POLICY "CS or Admin write student_cohorts" ON student_cohorts FOR ALL TO authenticated
  USING (is_cs_or_admin())
  WITH CHECK (is_cs_or_admin());

-- ─── surveys ──────────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Admin read surveys"   ON surveys;
DROP POLICY IF EXISTS "Admin insert surveys" ON surveys;
DROP POLICY IF EXISTS "Admin update surveys" ON surveys;
DROP POLICY IF EXISTS "Admin delete surveys" ON surveys;

DROP POLICY IF EXISTS "CS or Admin all surveys" ON surveys;
CREATE POLICY "CS or Admin all surveys" ON surveys FOR ALL TO authenticated
  USING (is_cs_or_admin())
  WITH CHECK (is_cs_or_admin());

-- ─── survey_links ─────────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Admin read survey_links"   ON survey_links;
DROP POLICY IF EXISTS "Admin insert survey_links" ON survey_links;
DROP POLICY IF EXISTS "Admin update survey_links" ON survey_links;

DROP POLICY IF EXISTS "CS or Admin all survey_links" ON survey_links;
CREATE POLICY "CS or Admin all survey_links" ON survey_links FOR ALL TO authenticated
  USING (is_cs_or_admin())
  WITH CHECK (is_cs_or_admin());

-- Mantém policy anon (validação token aluno responder)
-- "Anon read survey_links by token" já existe em migration anterior.

-- ─── survey_questions (se existe — extends Article 5.1 EPIC-005) ──────────

DROP POLICY IF EXISTS "Admin all survey_questions" ON survey_questions;

DROP POLICY IF EXISTS "CS or Admin all survey_questions" ON survey_questions;
CREATE POLICY "CS or Admin all survey_questions" ON survey_questions FOR ALL TO authenticated
  USING (is_cs_or_admin())
  WITH CHECK (is_cs_or_admin());

-- Anon SELECT mantido (responder.html via token)
-- "Anon read survey_questions" já existe.

-- ─── survey_responses ─────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Admin all survey_responses" ON survey_responses;

DROP POLICY IF EXISTS "CS or Admin read survey_responses" ON survey_responses;
CREATE POLICY "CS or Admin read survey_responses" ON survey_responses FOR SELECT TO authenticated
  USING (is_cs_or_admin());

-- INSERT permanece via service_role (edge function submit-survey)

-- ─── survey_answers ───────────────────────────────────────────────────────

DROP POLICY IF EXISTS "Admin all survey_answers" ON survey_answers;

DROP POLICY IF EXISTS "CS or Admin read survey_answers" ON survey_answers;
CREATE POLICY "CS or Admin read survey_answers" ON survey_answers FOR SELECT TO authenticated
  USING (is_cs_or_admin());

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. RLS em tabelas NOVAS (8 tabelas)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── survey_versions ──────────────────────────────────────────────────────

ALTER TABLE survey_versions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "CS or Admin all survey_versions" ON survey_versions;
CREATE POLICY "CS or Admin all survey_versions" ON survey_versions FOR ALL TO authenticated
  USING (is_cs_or_admin())
  WITH CHECK (is_cs_or_admin());

-- Anon SELECT (aluno responde via token; submit-survey usa service_role mas client-side preview pode acessar)
DROP POLICY IF EXISTS "Anon read survey_versions" ON survey_versions;
CREATE POLICY "Anon read survey_versions" ON survey_versions FOR SELECT TO anon USING (true);

-- ─── ac_purchase_events ───────────────────────────────────────────────────

ALTER TABLE ac_purchase_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "CS or Admin read ac_purchase_events" ON ac_purchase_events;
CREATE POLICY "CS or Admin read ac_purchase_events" ON ac_purchase_events FOR SELECT TO authenticated
  USING (is_cs_or_admin());

-- INSERT/UPDATE/DELETE: APENAS service_role (worker pg_cron + edge function ac-purchase-webhook)
-- Não criamos policy para INSERT/UPDATE — service_role bypassa RLS automaticamente.

-- ─── pending_student_assignments ──────────────────────────────────────────

ALTER TABLE pending_student_assignments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "CS or Admin all pending_assignments" ON pending_student_assignments;
CREATE POLICY "CS or Admin all pending_assignments" ON pending_student_assignments FOR ALL TO authenticated
  USING (is_cs_or_admin())
  WITH CHECK (is_cs_or_admin());

-- ─── ac_product_mappings ──────────────────────────────────────────────────

ALTER TABLE ac_product_mappings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "CS or Admin all ac_mappings" ON ac_product_mappings;
CREATE POLICY "CS or Admin all ac_mappings" ON ac_product_mappings FOR ALL TO authenticated
  USING (is_cs_or_admin())
  WITH CHECK (is_cs_or_admin());

-- ─── ac_dispatch_callbacks ────────────────────────────────────────────────

ALTER TABLE ac_dispatch_callbacks ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "CS or Admin read ac_callbacks" ON ac_dispatch_callbacks;
CREATE POLICY "CS or Admin read ac_callbacks" ON ac_dispatch_callbacks FOR SELECT TO authenticated
  USING (is_cs_or_admin());

-- INSERT/UPDATE: apenas service_role (edge function ac-report-dispatch)

-- ─── meta_templates ───────────────────────────────────────────────────────

ALTER TABLE meta_templates ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "CS or Admin all meta_templates" ON meta_templates;
CREATE POLICY "CS or Admin all meta_templates" ON meta_templates FOR ALL TO authenticated
  USING (is_cs_or_admin())
  WITH CHECK (is_cs_or_admin());

-- ─── student_audit_log ────────────────────────────────────────────────────

ALTER TABLE student_audit_log ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "CS or Admin read student_audit" ON student_audit_log;
CREATE POLICY "CS or Admin read student_audit" ON student_audit_log FOR SELECT TO authenticated
  USING (is_cs_or_admin());

-- INSERT: apenas service_role OR CS/admin direto via UI
DROP POLICY IF EXISTS "CS or Admin insert student_audit" ON student_audit_log;
CREATE POLICY "CS or Admin insert student_audit" ON student_audit_log FOR INSERT TO authenticated
  WITH CHECK (is_cs_or_admin());

-- ─── alert_history ────────────────────────────────────────────────────────
-- Acesso apenas via service_role (cron functions). Sem policies authenticated.

ALTER TABLE alert_history ENABLE ROW LEVEL SECURITY;

-- ═══════════════════════════════════════════════════════════════════════════
-- Fim Migration 2/4 — RLS
-- Próxima: 20260505100200_epic015_worker.sql (worker function + crons + views)
-- ═══════════════════════════════════════════════════════════════════════════
