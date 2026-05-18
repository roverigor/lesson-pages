-- ═══════════════════════════════════════════════════════════════════════════
-- Opção B — Unified NPS results VIEW (old surveys + new auto-class system)
--
-- Combines:
--   - class_nps_responses (new auto post-class system: group + DM)
--   - student_nps (legacy manual surveys via /admin/?view=surveys + Tally)
--
-- Dashboard /admin/nps-results/ now sees BOTH origins in one consolidated
-- view. Source column lets filter by origin if needed.
--
-- Schemas stay separate; only this read-only VIEW unifies for analytics.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE VIEW public.nps_results_unified AS
SELECT
  'auto_class'::text         AS source,
  r.id                       AS response_id,
  r.cohort_id,
  r.class_id,
  r.student_id,
  r.mode,                    -- 'group' or 'dm'
  r.nps_score                AS score,
  r.comment,
  r.name_provided,
  r.submitted_at,
  r.link_id                  AS legacy_link_id,
  NULL::uuid                 AS survey_id
FROM public.class_nps_responses r

UNION ALL

SELECT
  'manual_survey'::text      AS source,
  sn.id                      AS response_id,
  sn.cohort_id,
  NULL::uuid                 AS class_id,           -- student_nps doesn't track class_id directly
  sn.student_id,
  'dm'::text                 AS mode,               -- legacy was always individual DM via Tally / dispatch-survey
  sn.score,
  sn.feedback                AS comment,
  NULL::text                 AS name_provided,
  COALESCE(sn.responded_at, sn.created_at) AS submitted_at,
  NULL::uuid                 AS legacy_link_id,
  sn.survey_id
FROM public.student_nps sn
WHERE sn.score IS NOT NULL;

GRANT SELECT ON public.nps_results_unified TO authenticated, service_role;

COMMENT ON VIEW public.nps_results_unified IS
  'Unifies new auto-class NPS responses with legacy survey/Tally student_nps. Read-only — admin dashboards filter via source column.';

COMMIT;
