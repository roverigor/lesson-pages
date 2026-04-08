-- ═══════════════════════════════════════
-- EPIC-011 Story 11.7: zoom_chat_messages
-- Captures in-meeting Zoom chat per student
-- ═══════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.zoom_chat_messages (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  zoom_meeting_id TEXT NOT NULL,
  sender_name     TEXT NOT NULL,
  student_id      UUID REFERENCES public.students(id) ON DELETE SET NULL,
  cohort_id       UUID REFERENCES public.cohorts(id) ON DELETE SET NULL,
  sent_at         TIMESTAMPTZ NOT NULL,
  message         TEXT,
  message_id      TEXT UNIQUE NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_zoom_chat_messages_meeting
  ON public.zoom_chat_messages (zoom_meeting_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_zoom_chat_messages_student
  ON public.zoom_chat_messages (student_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_zoom_chat_messages_cohort_date
  ON public.zoom_chat_messages (cohort_id, sent_at DESC);

-- Track whether chat has been imported for each meeting
ALTER TABLE public.zoom_meetings
  ADD COLUMN IF NOT EXISTS chat_imported BOOLEAN NOT NULL DEFAULT false;

-- RLS
ALTER TABLE public.zoom_chat_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role_all_zoom_chat_messages"
  ON public.zoom_chat_messages
  FOR ALL
  USING (true)
  WITH CHECK (true);

GRANT ALL ON public.zoom_chat_messages TO service_role;
GRANT SELECT ON public.zoom_chat_messages TO authenticated;
