-- ═══════════════════════════════════════════════════════════════════════════
-- P2 — Class NPS responses (anonymous + attributable)
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.class_nps_responses (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  link_id        uuid NOT NULL REFERENCES public.nps_class_links(id) ON DELETE CASCADE,
  class_id       uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  cohort_id      uuid NOT NULL REFERENCES public.cohorts(id) ON DELETE CASCADE,
  mode           text NOT NULL CHECK (mode IN ('group','dm')),
  student_id     uuid REFERENCES public.students(id) ON DELETE SET NULL,
  nps_score      smallint NOT NULL CHECK (nps_score BETWEEN 0 AND 10),
  comment        text,
  name_provided  text,
  ip_hash        text,
  user_agent     text,
  submitted_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_class_nps_responses_class
  ON public.class_nps_responses (class_id, cohort_id, submitted_at DESC);

CREATE INDEX IF NOT EXISTS idx_class_nps_responses_link
  ON public.class_nps_responses (link_id);

CREATE INDEX IF NOT EXISTS idx_class_nps_responses_student
  ON public.class_nps_responses (student_id)
  WHERE student_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_class_nps_responses_ip_window
  ON public.class_nps_responses (ip_hash, submitted_at DESC)
  WHERE ip_hash IS NOT NULL;

ALTER TABLE public.class_nps_responses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "nps_responses: read for auth"
  ON public.class_nps_responses FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "nps_responses: full for service"
  ON public.class_nps_responses FOR ALL
  TO service_role USING (true) WITH CHECK (true);

COMMIT;
