-- ═══════════════════════════════════════
-- LESSON PAGES — student_attendance table
-- Stores student presence derived from Zoom participant data.
-- Source of truth after zoom_participants are matched to students.
-- ═══════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.student_attendance (
  id                  UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id          UUID NOT NULL REFERENCES public.students(id) ON DELETE CASCADE,
  class_date          DATE NOT NULL,
  cohort_id           UUID REFERENCES public.cohorts(id) ON DELETE SET NULL,
  zoom_meeting_id     UUID REFERENCES public.zoom_meetings(id) ON DELETE SET NULL,
  zoom_participant_id UUID REFERENCES public.zoom_participants(id) ON DELETE SET NULL,
  source              TEXT NOT NULL DEFAULT 'zoom' CHECK (source IN ('zoom', 'manual')),
  duration_minutes    INT,
  created_at          TIMESTAMPTZ DEFAULT now(),
  UNIQUE (student_id, class_date, zoom_meeting_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_student_attendance_student  ON public.student_attendance(student_id);
CREATE INDEX IF NOT EXISTS idx_student_attendance_date     ON public.student_attendance(class_date);
CREATE INDEX IF NOT EXISTS idx_student_attendance_cohort   ON public.student_attendance(cohort_id);
CREATE INDEX IF NOT EXISTS idx_student_attendance_meeting  ON public.student_attendance(zoom_meeting_id);

-- RLS
ALTER TABLE public.student_attendance ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read student_attendance" ON public.student_attendance;
CREATE POLICY "Authenticated read student_attendance"
  ON public.student_attendance FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admin write student_attendance" ON public.student_attendance;
CREATE POLICY "Admin write student_attendance"
  ON public.student_attendance FOR ALL TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- Service role bypass (used by edge functions)
DROP POLICY IF EXISTS "Service role bypass student_attendance" ON public.student_attendance;
CREATE POLICY "Service role bypass student_attendance"
  ON public.student_attendance FOR ALL TO service_role USING (true) WITH CHECK (true);
