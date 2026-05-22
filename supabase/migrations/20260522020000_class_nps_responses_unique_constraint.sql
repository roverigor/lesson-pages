-- ═══════════════════════════════════════════════════════════════════════════
-- Defense-in-depth: bloqueia double-submit do form NPS no nível DB.
-- Frontend já tem guard state.submitting (survey/index.html) mas race
-- conditions ou bypass via curl ainda possíveis. Constraint só aplica
-- quando ip_hash existe (NULL = inserts via backend sem hash).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE UNIQUE INDEX IF NOT EXISTS idx_class_nps_responses_link_ip_unique
  ON public.class_nps_responses (link_id, ip_hash)
  WHERE ip_hash IS NOT NULL;

COMMIT;
