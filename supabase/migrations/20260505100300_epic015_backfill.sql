-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-015 Story 15.A — Backfill (Migration 4/4)
-- Popula colunas novas em rows existentes + seed inicial meta_templates.
-- IDEMPOTENTE: rodar 2x = mesmo resultado.
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- 1. BACKFILL survey_versions v1 + survey_links.version_id
-- ═══════════════════════════════════════════════════════════════════════════
-- Para cada survey existente (EPIC-004), cria v1 representando o estado atual.
-- survey_links existentes ficam apontando para v1.

INSERT INTO survey_versions (survey_id, version_number, created_at)
SELECT
  s.id,
  1,
  COALESCE(s.created_at, now())
FROM surveys s
WHERE NOT EXISTS (
  SELECT 1 FROM survey_versions sv WHERE sv.survey_id = s.id
);

-- Atualiza surveys.current_version_id para v1
UPDATE surveys s
   SET current_version_id = sv.id
  FROM survey_versions sv
 WHERE sv.survey_id = s.id
   AND sv.version_number = 1
   AND s.current_version_id IS NULL;

-- Atualiza survey_links.version_id existentes para v1
UPDATE survey_links sl
   SET version_id = sv.id
  FROM survey_versions sv
 WHERE sv.survey_id = sl.survey_id
   AND sv.version_number = 1
   AND sl.version_id IS NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- 2. BACKFILL survey_links.cohort_snapshot_name
-- Preserva nome da cohort no momento do envio (NFR-19 timeline imutável)
-- ═══════════════════════════════════════════════════════════════════════════
-- Para survey_links existentes, deriva nome via surveys.cohort_id → cohorts.name

UPDATE survey_links sl
   SET cohort_snapshot_name = c.name
  FROM surveys s
  LEFT JOIN cohorts c ON c.id = s.cohort_id
 WHERE sl.survey_id = s.id
   AND sl.cohort_snapshot_name IS NULL
   AND c.name IS NOT NULL;

-- ═══════════════════════════════════════════════════════════════════════════
-- 3. SEED INICIAL meta_templates
-- Templates já em uso em produção (extraídos de dispatch-survey/index.ts L388)
-- ═══════════════════════════════════════════════════════════════════════════

INSERT INTO meta_templates (name, language, category, body_params_count, button_count, status, approved_at)
VALUES
  ('pesquisa_csat_painel', 'pt_BR', 'MARKETING', 2, 1, 'active', now())
ON CONFLICT (name) DO NOTHING;

-- Story 15.0/15.8 popula demais templates via Graph API sync.

-- ═══════════════════════════════════════════════════════════════════════════
-- 4. VALIDATION QUERIES (smoke tests embedded — informativo)
-- Comentado para evitar output em prod. Descomentar para validar manualmente:
--
-- SELECT 'survey_links sem version_id' AS check, COUNT(*)
--   FROM survey_links WHERE version_id IS NULL;
--
-- SELECT 'surveys sem current_version_id' AS check, COUNT(*)
--   FROM surveys WHERE current_version_id IS NULL;
--
-- SELECT 'survey_links sem cohort_snapshot' AS check, COUNT(*)
--   FROM survey_links sl
--   JOIN surveys s ON s.id = sl.survey_id
--   WHERE sl.cohort_snapshot_name IS NULL AND s.cohort_id IS NOT NULL;
-- ═══════════════════════════════════════════════════════════════════════════

-- ═══════════════════════════════════════════════════════════════════════════
-- Fim Migration 4/4 — Backfill
-- Story 15.A schema 100% aplicado.
-- ═══════════════════════════════════════════════════════════════════════════
