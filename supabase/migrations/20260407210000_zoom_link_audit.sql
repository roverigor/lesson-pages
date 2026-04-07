CREATE TABLE IF NOT EXISTS public.zoom_link_audit (
  id             UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  participant_id TEXT NOT NULL,
  student_id     UUID REFERENCES public.students(id),
  action         TEXT NOT NULL CHECK (action IN ('linked', 'unlinked')),
  performed_by   TEXT NOT NULL DEFAULT 'admin',
  performed_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_zoom_link_audit_participant
  ON public.zoom_link_audit (participant_id, performed_at DESC);

GRANT ALL ON public.zoom_link_audit TO service_role;
ALTER TABLE public.zoom_link_audit DISABLE ROW LEVEL SECURITY;
