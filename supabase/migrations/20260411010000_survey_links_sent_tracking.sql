-- Track which survey links have been sent via WhatsApp
-- Prevents duplicate sends on resume after interruption
ALTER TABLE public.survey_links
  ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS send_status TEXT DEFAULT 'pending';

-- Index for filtering unsent links
CREATE INDEX IF NOT EXISTS idx_survey_links_send_status
  ON public.survey_links(survey_id, send_status)
  WHERE send_status = 'pending';
