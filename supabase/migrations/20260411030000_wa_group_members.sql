-- Persistent storage for WhatsApp group members per cohort
-- Populated by sync-wa-group edge function via frontend

CREATE TABLE IF NOT EXISTS public.wa_group_members (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  cohort_id UUID NOT NULL REFERENCES public.cohorts(id),
  phone TEXT NOT NULL,
  wa_name TEXT,
  synced_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(cohort_id, phone)
);

CREATE INDEX IF NOT EXISTS idx_wa_group_members_cohort ON public.wa_group_members(cohort_id);
CREATE INDEX IF NOT EXISTS idx_wa_group_members_phone ON public.wa_group_members(phone);

ALTER TABLE public.wa_group_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated full access on wa_group_members"
  ON public.wa_group_members
  FOR ALL
  USING (auth.uid() IS NOT NULL)
  WITH CHECK (auth.uid() IS NOT NULL);
