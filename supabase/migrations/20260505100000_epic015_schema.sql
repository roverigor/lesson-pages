-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-015 Story 15.A — Schema Migrations (Migration 1/4)
-- Área CS Dedicada: NPS/Onboarding/Forms + Integração ActiveCampaign
--
-- Refs:
--   - docs/stories/15.A.story.md
--   - docs/architecture/ADR-016-async-dispatch-strategy.md
--   - docs/stories/EPIC-015-cs-area/spec/spec.md §4.2
--
-- Strategy: additive only (NULLABLE columns + new tables).
-- Backward compat EPIC-004 preservada — surveys legacy continuam funcionando.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 0. EXTENSIONS (idempotente) ───────────────────────────────────────────

CREATE EXTENSION IF NOT EXISTS pg_cron;
CREATE EXTENSION IF NOT EXISTS pg_net;
GRANT USAGE ON SCHEMA cron TO postgres;

-- ─── 1. HELPER FUNCTION — is_cs_or_admin() ─────────────────────────────────
-- Reusável em RLS policies (Story 15.A AC-15)

CREATE OR REPLACE FUNCTION is_cs_or_admin()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT (auth.jwt() -> 'user_metadata' ->> 'role') IN ('admin', 'cs');
$$;

COMMENT ON FUNCTION is_cs_or_admin() IS
  'EPIC-015: helper para RLS policies — true se JWT tem role=admin OR role=cs';

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. NEW TABLES (7 tabelas novas)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 2.1. survey_versions — snapshots imutáveis de questionários ──────────

CREATE TABLE IF NOT EXISTS survey_versions (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  survey_id       UUID NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
  version_number  INTEGER NOT NULL,
  created_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(survey_id, version_number)
);

CREATE INDEX IF NOT EXISTS idx_survey_versions_survey ON survey_versions(survey_id);

COMMENT ON TABLE survey_versions IS
  'EPIC-015 FR-13: versionamento de forms — snapshot imutável quando survey é editada após disparos.';

-- ─── 2.2. ac_purchase_events — webhooks AC inbound (audit + idempotência) ──

CREATE TABLE IF NOT EXISTS ac_purchase_events (
  id                       UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ac_event_id              TEXT NOT NULL UNIQUE,
  payload                  JSONB NOT NULL,
  status                   TEXT NOT NULL DEFAULT 'received'
                             CHECK (status IN ('received','processing','processed','failed','duplicate')),
  processing_started_at    TIMESTAMPTZ,
  processed_at             TIMESTAMPTZ,
  retry_count              INTEGER NOT NULL DEFAULT 0,
  last_error               TEXT,
  created_at               TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ac_events_pending
  ON ac_purchase_events (created_at)
  WHERE status = 'received';

CREATE INDEX IF NOT EXISTS idx_ac_events_status_created
  ON ac_purchase_events (status, created_at DESC);

COMMENT ON TABLE ac_purchase_events IS
  'EPIC-015 FR-7/NFR-4: eventos webhook AC com workflow de processamento. UNIQUE ac_event_id garante idempotência (ON CONFLICT DO NOTHING).';

-- ─── 2.3. pending_student_assignments — fila CS resolução manual ───────────

CREATE TABLE IF NOT EXISTS pending_student_assignments (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id          UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  ac_event_id         UUID REFERENCES ac_purchase_events(id) ON DELETE SET NULL,
  reason              TEXT NOT NULL,
  ac_payload          JSONB,
  suggested_cohort_id UUID REFERENCES cohorts(id) ON DELETE SET NULL,
  resolved_at         TIMESTAMPTZ,
  resolved_by         TEXT,
  resolved_cohort_id  UUID REFERENCES cohorts(id) ON DELETE SET NULL,
  created_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_pending_unresolved
  ON pending_student_assignments(created_at)
  WHERE resolved_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_pending_student
  ON pending_student_assignments(student_id);

COMMENT ON TABLE pending_student_assignments IS
  'EPIC-015 FR-9/FR-10: fila de alunos órfãos de cohort criados via webhook AC sem mapping. CS resolve manualmente em /cs/pending.';

-- ─── 2.4. ac_product_mappings — regras produto AC → cohort + survey ────────
-- N:1 cardinalidade (ASM-19): UNIQUE em ac_product_id; cohort_id pode repetir

CREATE TABLE IF NOT EXISTS ac_product_mappings (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  ac_product_id   TEXT NOT NULL UNIQUE,
  cohort_id       UUID NOT NULL REFERENCES cohorts(id) ON DELETE RESTRICT,
  survey_id       UUID NOT NULL REFERENCES surveys(id) ON DELETE RESTRICT,
  template_name   TEXT NOT NULL,
  active          BOOLEAN NOT NULL DEFAULT true,
  created_at      TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ac_mappings_active
  ON ac_product_mappings(active)
  WHERE active = true;

CREATE INDEX IF NOT EXISTS idx_ac_mappings_cohort
  ON ac_product_mappings(cohort_id);

COMMENT ON TABLE ac_product_mappings IS
  'EPIC-015 FR-15 (ASM-19 N:1): mapeia ac_product_id → cohort + survey + template Meta. N:1 = múltiplos produtos podem apontar para mesma cohort/survey, mas cada ac_product_id é único.';

-- ─── 2.5. ac_dispatch_callbacks — confirmações outbound para AC ────────────

CREATE TABLE IF NOT EXISTS ac_dispatch_callbacks (
  id                   UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  link_id              UUID NOT NULL REFERENCES survey_links(id) ON DELETE CASCADE,
  ac_contact_id        TEXT NOT NULL,
  status               TEXT NOT NULL DEFAULT 'pending'
                         CHECK (status IN ('pending','ok','failed')),
  retries              INTEGER NOT NULL DEFAULT 0,
  last_attempt_at      TIMESTAMPTZ,
  error_message        TEXT,
  acknowledged_by_ac   BOOLEAN NOT NULL DEFAULT false,
  created_at           TIMESTAMPTZ DEFAULT now(),
  UNIQUE(link_id, ac_contact_id)
);

CREATE INDEX IF NOT EXISTS idx_callbacks_pending
  ON ac_dispatch_callbacks(last_attempt_at)
  WHERE status IN ('pending','failed');

COMMENT ON TABLE ac_dispatch_callbacks IS
  'EPIC-015 FR-11/NFR-5: rastreia callbacks outbound para AC API após dispatch. Retry exponencial 3x (1s/4s/16s).';

-- ─── 2.6. meta_templates — registry de templates Meta WhatsApp ────────────

CREATE TABLE IF NOT EXISTS meta_templates (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name                TEXT NOT NULL UNIQUE,
  language            TEXT NOT NULL DEFAULT 'pt_BR',
  category            TEXT CHECK (category IN ('marketing','utility','authentication','MARKETING','UTILITY','AUTHENTICATION')),
  body_params_count   INTEGER NOT NULL DEFAULT 0,
  button_count        INTEGER NOT NULL DEFAULT 0,
  status              TEXT NOT NULL DEFAULT 'active'
                        CHECK (status IN ('active','paused','rejected','pending')),
  approved_at         TIMESTAMPTZ,
  created_at          TIMESTAMPTZ DEFAULT now(),
  updated_at          TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_meta_templates_status
  ON meta_templates(status)
  WHERE status = 'active';

COMMENT ON TABLE meta_templates IS
  'EPIC-015 FR-15/Story 15.8: registry de templates Meta aprovados. CS edita sem deploy. Sync via Graph API GET /{WABA_ID}/message_templates.';

-- ─── 2.7. student_audit_log — auditoria mudanças em students ───────────────
-- Decisão: incluir aqui (centralizado) — Story 15.3 EC-19 phone update audit

CREATE TABLE IF NOT EXISTS student_audit_log (
  id            UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id    UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  changed_field TEXT NOT NULL,
  old_value     TEXT,
  new_value     TEXT,
  changed_by    TEXT,
  changed_at    TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_audit_student
  ON student_audit_log(student_id, changed_at DESC);

COMMENT ON TABLE student_audit_log IS
  'EPIC-015 EC-19: rastreia mudanças em campos sensíveis de students (phone, email) com old/new value e ator.';

-- ─── 2.8. alert_history — throttle de alerts Slack ─────────────────────────
-- Necessário para Story 15.E (observabilidade) — incluído aqui para schema-completeness

CREATE TABLE IF NOT EXISTS alert_history (
  alert_key     TEXT PRIMARY KEY,
  last_sent_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE alert_history IS
  'EPIC-015 Story 15.E: throttle de alerts (1 por hora por alert_key) para evitar spam Slack.';

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. ALTER EXISTING TABLES (additive — NULLABLE para zero regressão)
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── 3.1. students ─── ac_contact_id (FR-7 mapping AC contact)

ALTER TABLE students ADD COLUMN IF NOT EXISTS ac_contact_id TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_students_ac_contact
  ON students(ac_contact_id)
  WHERE ac_contact_id IS NOT NULL;

COMMENT ON COLUMN students.ac_contact_id IS
  'EPIC-015 FR-7: identificador do contato no ActiveCampaign (NULLABLE — students legacy não têm). UNIQUE sparse index.';

-- ─── 3.2. survey_links ─── extensions tracking + versioning + cohort snapshot

ALTER TABLE survey_links ADD COLUMN IF NOT EXISTS delivered_at         TIMESTAMPTZ;
ALTER TABLE survey_links ADD COLUMN IF NOT EXISTS read_at              TIMESTAMPTZ;
ALTER TABLE survey_links ADD COLUMN IF NOT EXISTS version_id           UUID REFERENCES survey_versions(id) ON DELETE SET NULL;
ALTER TABLE survey_links ADD COLUMN IF NOT EXISTS meta_message_id      TEXT;
ALTER TABLE survey_links ADD COLUMN IF NOT EXISTS cohort_snapshot_name TEXT;

-- Sparse UNIQUE em meta_message_id (correlação webhook delivery 15.I)
CREATE UNIQUE INDEX IF NOT EXISTS idx_survey_links_meta_message
  ON survey_links(meta_message_id)
  WHERE meta_message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_survey_links_version  ON survey_links(version_id);
CREATE INDEX IF NOT EXISTS idx_survey_links_student  ON survey_links(student_id);
CREATE INDEX IF NOT EXISTS idx_survey_links_status   ON survey_links(send_status);

COMMENT ON COLUMN survey_links.delivered_at IS
  'EPIC-015 FR-16/NFR-17: timestamp Meta delivery callback (Story 15.I)';
COMMENT ON COLUMN survey_links.read_at IS
  'EPIC-015 FR-16/NFR-17: timestamp Meta read receipt (Story 15.I)';
COMMENT ON COLUMN survey_links.version_id IS
  'EPIC-015 FR-13: link aponta para survey_version usada no momento do envio (imutável após sent)';
COMMENT ON COLUMN survey_links.meta_message_id IS
  'EPIC-015 NFR-17: ID retornado pela Meta API; correlaciona com webhook messages.update';
COMMENT ON COLUMN survey_links.cohort_snapshot_name IS
  'EPIC-015 FR-17/NFR-19: nome da cohort no momento do envio. Preserva histórico mesmo se cohort renomeada/deletada.';

-- ─── 3.3. surveys ─── category + current_version_id

ALTER TABLE surveys ADD COLUMN IF NOT EXISTS category           TEXT
  CHECK (category IS NULL OR category IN ('nps','csat','onboarding','feedback','custom'));

ALTER TABLE surveys ADD COLUMN IF NOT EXISTS current_version_id UUID
  REFERENCES survey_versions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_surveys_category ON surveys(category);

COMMENT ON COLUMN surveys.category IS
  'EPIC-015 FR-4: categoria do form criado pelo CS. NULL para surveys EPIC-004 legacy.';
COMMENT ON COLUMN surveys.current_version_id IS
  'EPIC-015 FR-13: aponta para a versão ativa em survey_versions. Novos disparos usam esta.';

-- ═══════════════════════════════════════════════════════════════════════════
-- Fim Migration 1/4 — Schema
-- Próxima: 20260505100100_epic015_rls.sql (RLS policies)
-- ═══════════════════════════════════════════════════════════════════════════
