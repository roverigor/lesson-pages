-- ═══════════════════════════════════════════════════════════════════════════
-- P2 — NPS class links (tokens that authorize anonymous form access)
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.nps_class_links (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token          text UNIQUE NOT NULL,
  class_id       uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  cohort_id      uuid NOT NULL REFERENCES public.cohorts(id) ON DELETE CASCADE,
  trigger_date   date NOT NULL,
  mode           text NOT NULL CHECK (mode IN ('group','dm')),
  student_id     uuid REFERENCES public.students(id) ON DELETE CASCADE,
  expires_at     timestamptz NOT NULL,
  response_count integer NOT NULL DEFAULT 0,
  created_by     text NOT NULL DEFAULT 'system',
  created_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT nps_class_links_mode_student_consistency
    CHECK (
      (mode = 'dm' AND student_id IS NOT NULL) OR
      (mode = 'group' AND student_id IS NULL)
    )
);

-- One group link per (class, cohort, date)
CREATE UNIQUE INDEX IF NOT EXISTS idx_nps_class_links_group_unique
  ON public.nps_class_links (class_id, cohort_id, trigger_date)
  WHERE mode = 'group';

-- One DM link per (class, cohort, date, student)
CREATE UNIQUE INDEX IF NOT EXISTS idx_nps_class_links_dm_unique
  ON public.nps_class_links (class_id, cohort_id, trigger_date, student_id)
  WHERE mode = 'dm';

CREATE INDEX IF NOT EXISTS idx_nps_class_links_token
  ON public.nps_class_links (token);

CREATE INDEX IF NOT EXISTS idx_nps_class_links_expires
  ON public.nps_class_links (expires_at)
  WHERE expires_at > now();

ALTER TABLE public.nps_class_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY "nps_links: read for auth"
  ON public.nps_class_links FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "nps_links: full for service"
  ON public.nps_class_links FOR ALL
  TO service_role USING (true) WITH CHECK (true);

COMMIT;
