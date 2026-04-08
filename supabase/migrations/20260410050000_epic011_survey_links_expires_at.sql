-- ═══════════════════════════════════════
-- EPIC-011 Story 11.3: survey_links expires_at
-- Adds 7-day expiry to NPS tokens
-- ═══════════════════════════════════════

ALTER TABLE public.survey_links
  ADD COLUMN IF NOT EXISTS expires_at TIMESTAMPTZ;

-- Index for fast expiry checks
CREATE INDEX IF NOT EXISTS idx_survey_links_expires_at
  ON public.survey_links (expires_at)
  WHERE expires_at IS NOT NULL;

-- NOTE: existing rows keep expires_at = NULL (no expiry — backward compatible)
-- New rows set by dispatch-survey will have expires_at = NOW() + 7 days
