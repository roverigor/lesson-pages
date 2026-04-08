-- ═══════════════════════════════════════
-- EPIC-011 Story 11.6: whatsapp_group_messages
-- Captures student messages in WhatsApp class groups
-- ═══════════════════════════════════════

-- Add whatsapp_group_jid to cohorts if not exists
ALTER TABLE public.cohorts
  ADD COLUMN IF NOT EXISTS whatsapp_group_jid TEXT;

CREATE INDEX IF NOT EXISTS idx_cohorts_wa_group_jid
  ON public.cohorts (whatsapp_group_jid)
  WHERE whatsapp_group_jid IS NOT NULL;

-- Main table
CREATE TABLE IF NOT EXISTS public.whatsapp_group_messages (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  group_jid             TEXT NOT NULL,
  sender_phone          TEXT NOT NULL,
  student_id            UUID REFERENCES public.students(id) ON DELETE SET NULL,
  cohort_id             UUID REFERENCES public.cohorts(id) ON DELETE SET NULL,
  sent_at               TIMESTAMPTZ NOT NULL DEFAULT now(),
  message_type          TEXT NOT NULL DEFAULT 'text'
                          CHECK (message_type IN ('text', 'image', 'audio', 'video', 'other')),
  evolution_message_id  TEXT UNIQUE NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_wa_group_messages_cohort_date
  ON public.whatsapp_group_messages (cohort_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_wa_group_messages_student
  ON public.whatsapp_group_messages (student_id, sent_at DESC);

CREATE INDEX IF NOT EXISTS idx_wa_group_messages_group_jid
  ON public.whatsapp_group_messages (group_jid, sent_at DESC);

-- RLS
ALTER TABLE public.whatsapp_group_messages ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role_all_wa_group_messages"
  ON public.whatsapp_group_messages
  FOR ALL
  USING (true)
  WITH CHECK (true);

GRANT ALL ON public.whatsapp_group_messages TO service_role;
GRANT SELECT ON public.whatsapp_group_messages TO authenticated;
