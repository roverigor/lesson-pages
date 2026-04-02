-- ═══════════════════════════════════════
-- LESSON PAGES — Baseline Migration
-- Captures all tables created manually before Supabase CLI migrations were adopted.
-- This migration is marked as applied without re-running (repair --status applied).
-- DO NOT modify: represents the state as of 2026-04-02.
-- ═══════════════════════════════════════

-- ─── update_updated_at() trigger function ───
CREATE OR REPLACE FUNCTION update_updated_at()
RETURNS TRIGGER AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END;
$$ LANGUAGE plpgsql;

-- ─── COHORTS ───
CREATE TABLE IF NOT EXISTS cohorts (
  id                   UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name                 TEXT NOT NULL UNIQUE,
  whatsapp_group_jid   TEXT,
  whatsapp_group_name  TEXT,
  zoom_link            TEXT,
  start_date           DATE,
  end_date             DATE,
  active               BOOLEAN DEFAULT true,
  created_at           TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_cohorts_active ON cohorts(active);
ALTER TABLE cohorts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated read cohorts" ON cohorts;
CREATE POLICY "Authenticated read cohorts" ON cohorts FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admin insert cohorts" ON cohorts;
CREATE POLICY "Admin insert cohorts" ON cohorts FOR INSERT TO authenticated WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin update cohorts" ON cohorts;
CREATE POLICY "Admin update cohorts" ON cohorts FOR UPDATE TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin delete cohorts" ON cohorts;
CREATE POLICY "Admin delete cohorts" ON cohorts FOR DELETE TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── STUDENTS ───
CREATE TABLE IF NOT EXISTS students (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL DEFAULT '',
  phone      TEXT NOT NULL,
  cohort_id  UUID REFERENCES cohorts(id) ON DELETE SET NULL,
  is_mentor  BOOLEAN DEFAULT false,
  active     BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(phone, cohort_id)
);
CREATE INDEX IF NOT EXISTS idx_students_phone  ON students(phone);
CREATE INDEX IF NOT EXISTS idx_students_cohort ON students(cohort_id);
ALTER TABLE students ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated read students" ON students;
CREATE POLICY "Authenticated read students" ON students FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admin insert students" ON students;
CREATE POLICY "Admin insert students" ON students FOR INSERT TO authenticated WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin update students" ON students;
CREATE POLICY "Admin update students" ON students FOR UPDATE TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin delete students" ON students;
CREATE POLICY "Admin delete students" ON students FOR DELETE TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── STUDENT_COHORTS ───
CREATE TABLE IF NOT EXISTS student_cohorts (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id  UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  cohort_id   UUID NOT NULL REFERENCES cohorts(id) ON DELETE CASCADE,
  enrolled_at TIMESTAMPTZ DEFAULT now()
);

-- ─── STAFF ───
CREATE TABLE IF NOT EXISTS staff (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  email      TEXT,
  phone      TEXT,
  category   TEXT NOT NULL,
  active     BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

-- ─── CLASSES ───
CREATE TABLE IF NOT EXISTS classes (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  weekday    INTEGER NOT NULL CHECK (weekday BETWEEN 0 AND 6),
  time_start TIME NOT NULL,
  time_end   TIME NOT NULL,
  date       DATE,
  professor  TEXT,
  host       TEXT,
  color      TEXT,
  zoom_link  TEXT,
  active     BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_classes_weekday ON classes(weekday);
CREATE INDEX IF NOT EXISTS idx_classes_date    ON classes(date);
CREATE INDEX IF NOT EXISTS idx_classes_active  ON classes(active);
DROP TRIGGER IF EXISTS classes_updated_at ON classes;
CREATE TRIGGER classes_updated_at BEFORE UPDATE ON classes FOR EACH ROW EXECUTE FUNCTION update_updated_at();
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated read classes" ON classes;
CREATE POLICY "Authenticated read classes" ON classes FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admin insert classes" ON classes;
CREATE POLICY "Admin insert classes" ON classes FOR INSERT TO authenticated WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin update classes" ON classes;
CREATE POLICY "Admin update classes" ON classes FOR UPDATE TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin delete classes" ON classes;
CREATE POLICY "Admin delete classes" ON classes FOR DELETE TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── CLASS_COHORT_ACCESS ───
CREATE TABLE IF NOT EXISTS class_cohort_access (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  class_id     UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  cohort_id    UUID NOT NULL REFERENCES cohorts(id) ON DELETE CASCADE,
  access_until DATE NOT NULL,
  notes        TEXT,
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- ─── SCHEDULE_OVERRIDES ───
CREATE TABLE IF NOT EXISTS schedule_overrides (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  lesson_date  TEXT NOT NULL,
  course       TEXT NOT NULL,
  teacher_name TEXT NOT NULL,
  action       TEXT NOT NULL,
  role         TEXT NOT NULL DEFAULT 'Professor',
  recorded_by  UUID REFERENCES auth.users(id),
  created_at   TIMESTAMPTZ DEFAULT now()
);

-- ─── ATTENDANCE ───
CREATE TABLE IF NOT EXISTS attendance (
  id              UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  lesson_date     DATE NOT NULL,
  course          TEXT NOT NULL,
  teacher_name    TEXT NOT NULL,
  role            TEXT NOT NULL DEFAULT 'Professor',
  status          TEXT NOT NULL CHECK (status IN ('present', 'absent')),
  substitute_name TEXT,
  substitute_role TEXT DEFAULT 'Professor',
  notes           TEXT,
  recorded_by     UUID REFERENCES auth.users(id),
  recorded_at     TIMESTAMPTZ DEFAULT now(),
  updated_at      TIMESTAMPTZ DEFAULT now(),
  UNIQUE(lesson_date, course, teacher_name)
);
CREATE INDEX IF NOT EXISTS idx_attendance_date    ON attendance(lesson_date);
CREATE INDEX IF NOT EXISTS idx_attendance_status  ON attendance(status);
CREATE INDEX IF NOT EXISTS idx_attendance_teacher ON attendance(teacher_name);
DROP TRIGGER IF EXISTS attendance_updated_at ON attendance;
CREATE TRIGGER attendance_updated_at BEFORE UPDATE ON attendance FOR EACH ROW EXECUTE FUNCTION update_updated_at();
ALTER TABLE attendance ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated read" ON attendance;
CREATE POLICY "Authenticated read" ON attendance FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Admin insert" ON attendance;
CREATE POLICY "Admin insert" ON attendance FOR INSERT TO authenticated WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin update" ON attendance;
CREATE POLICY "Admin update" ON attendance FOR UPDATE TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin delete" ON attendance;
CREATE POLICY "Admin delete" ON attendance FOR DELETE TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── MENTOR_ATTENDANCE ───
CREATE TABLE IF NOT EXISTS mentor_attendance (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  mentor_id    UUID NOT NULL REFERENCES mentors(id) ON DELETE CASCADE,
  class_id     UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  session_date DATE NOT NULL,
  status       TEXT NOT NULL DEFAULT 'present' CHECK (status IN ('present', 'absent')),
  comment      TEXT,
  created_at   TIMESTAMPTZ DEFAULT now(),
  updated_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE(mentor_id, class_id, session_date)
);
CREATE INDEX IF NOT EXISTS idx_mentor_attendance_mentor ON mentor_attendance(mentor_id);
CREATE INDEX IF NOT EXISTS idx_mentor_attendance_class  ON mentor_attendance(class_id);
CREATE INDEX IF NOT EXISTS idx_mentor_attendance_date   ON mentor_attendance(session_date);
ALTER TABLE mentor_attendance ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Authenticated read mentor_attendance" ON mentor_attendance;
CREATE POLICY "Authenticated read mentor_attendance" ON mentor_attendance FOR SELECT TO authenticated USING (true);
DROP POLICY IF EXISTS "Mentor insert own attendance" ON mentor_attendance;
CREATE POLICY "Mentor insert own attendance" ON mentor_attendance FOR INSERT TO authenticated
  WITH CHECK (mentor_id IN (SELECT id FROM mentors WHERE (auth.jwt() -> 'user_metadata' ->> 'mentor_id')::uuid = id OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'));
DROP POLICY IF EXISTS "Mentor update own attendance" ON mentor_attendance;
CREATE POLICY "Mentor update own attendance" ON mentor_attendance FOR UPDATE TO authenticated
  USING (mentor_id IN (SELECT id FROM mentors WHERE (auth.jwt() -> 'user_metadata' ->> 'mentor_id')::uuid = id OR (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'));
DROP POLICY IF EXISTS "Admin delete mentor_attendance" ON mentor_attendance;
CREATE POLICY "Admin delete mentor_attendance" ON mentor_attendance FOR DELETE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── ZOOM TOKENS ───
CREATE TABLE IF NOT EXISTS zoom_tokens (
  id               UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  mentor_id        UUID REFERENCES mentors(id) ON DELETE SET NULL,
  zoom_email       TEXT NOT NULL UNIQUE,
  zoom_account_id  TEXT,
  access_token     TEXT NOT NULL,
  refresh_token    TEXT NOT NULL,
  token_type       TEXT DEFAULT 'Bearer',
  expires_at       TIMESTAMPTZ NOT NULL,
  scope            TEXT,
  active           BOOLEAN DEFAULT true,
  created_at       TIMESTAMPTZ DEFAULT now(),
  updated_at       TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_zoom_tokens_mentor ON zoom_tokens(mentor_id);
CREATE INDEX IF NOT EXISTS idx_zoom_tokens_email  ON zoom_tokens(zoom_email);
DROP TRIGGER IF EXISTS zoom_tokens_updated_at ON zoom_tokens;
CREATE TRIGGER zoom_tokens_updated_at BEFORE UPDATE ON zoom_tokens FOR EACH ROW EXECUTE FUNCTION update_updated_at();
ALTER TABLE zoom_tokens ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin all zoom_tokens" ON zoom_tokens;
CREATE POLICY "Admin all zoom_tokens" ON zoom_tokens FOR ALL TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── ZOOM MEETINGS ───
CREATE TABLE IF NOT EXISTS zoom_meetings (
  id                 UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  zoom_meeting_id    TEXT NOT NULL,
  zoom_uuid          TEXT UNIQUE,
  host_email         TEXT,
  host_name          TEXT,
  topic              TEXT,
  start_time         TIMESTAMPTZ,
  end_time           TIMESTAMPTZ,
  duration_minutes   INT,
  participants_count INT DEFAULT 0,
  class_id           UUID REFERENCES classes(id) ON DELETE SET NULL,
  cohort_id          UUID REFERENCES cohorts(id) ON DELETE SET NULL,
  processed          BOOLEAN DEFAULT false,
  created_at         TIMESTAMPTZ DEFAULT now(),
  updated_at         TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_zoom_meetings_meeting_id ON zoom_meetings(zoom_meeting_id);
CREATE INDEX IF NOT EXISTS idx_zoom_meetings_host       ON zoom_meetings(host_email);
CREATE INDEX IF NOT EXISTS idx_zoom_meetings_class      ON zoom_meetings(class_id);
CREATE INDEX IF NOT EXISTS idx_zoom_meetings_cohort     ON zoom_meetings(cohort_id);
CREATE INDEX IF NOT EXISTS idx_zoom_meetings_start      ON zoom_meetings(start_time DESC);
CREATE INDEX IF NOT EXISTS idx_zoom_meetings_processed  ON zoom_meetings(processed) WHERE processed = false;
DROP TRIGGER IF EXISTS zoom_meetings_updated_at ON zoom_meetings;
CREATE TRIGGER zoom_meetings_updated_at BEFORE UPDATE ON zoom_meetings FOR EACH ROW EXECUTE FUNCTION update_updated_at();
ALTER TABLE zoom_meetings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin read zoom_meetings" ON zoom_meetings;
CREATE POLICY "Admin read zoom_meetings"  ON zoom_meetings FOR SELECT TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin write zoom_meetings" ON zoom_meetings;
CREATE POLICY "Admin write zoom_meetings" ON zoom_meetings FOR INSERT TO authenticated WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin update zoom_meetings" ON zoom_meetings;
CREATE POLICY "Admin update zoom_meetings" ON zoom_meetings FOR UPDATE TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── ZOOM PARTICIPANTS ───
CREATE TABLE IF NOT EXISTS zoom_participants (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  meeting_id        UUID NOT NULL REFERENCES zoom_meetings(id) ON DELETE CASCADE,
  participant_name  TEXT,
  participant_email TEXT,
  join_time         TIMESTAMPTZ,
  leave_time        TIMESTAMPTZ,
  duration_minutes  INT,
  student_id        UUID REFERENCES students(id) ON DELETE SET NULL,
  matched           BOOLEAN DEFAULT false,
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_zoom_participants_meeting ON zoom_participants(meeting_id);
CREATE INDEX IF NOT EXISTS idx_zoom_participants_student ON zoom_participants(student_id);
CREATE INDEX IF NOT EXISTS idx_zoom_participants_email   ON zoom_participants(participant_email);
ALTER TABLE zoom_participants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin read zoom_participants" ON zoom_participants;
CREATE POLICY "Admin read zoom_participants"  ON zoom_participants FOR SELECT TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin write zoom_participants" ON zoom_participants;
CREATE POLICY "Admin write zoom_participants" ON zoom_participants FOR INSERT TO authenticated WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── STUDENT NPS ───
CREATE TABLE IF NOT EXISTS student_nps (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id        UUID REFERENCES students(id) ON DELETE SET NULL,
  meeting_id        UUID REFERENCES zoom_meetings(id) ON DELETE SET NULL,
  cohort_id         UUID REFERENCES cohorts(id) ON DELETE SET NULL,
  score             INT NOT NULL CHECK (score >= 0 AND score <= 10),
  feedback          TEXT,
  tally_response_id TEXT,
  tally_form_id     TEXT,
  responded_at      TIMESTAMPTZ DEFAULT now(),
  created_at        TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_student_nps_student ON student_nps(student_id);
CREATE INDEX IF NOT EXISTS idx_student_nps_meeting ON student_nps(meeting_id);
CREATE INDEX IF NOT EXISTS idx_student_nps_cohort  ON student_nps(cohort_id);
CREATE INDEX IF NOT EXISTS idx_student_nps_score   ON student_nps(score);
ALTER TABLE student_nps ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admin read student_nps" ON student_nps;
CREATE POLICY "Admin read student_nps"  ON student_nps FOR SELECT TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin write student_nps" ON student_nps;
CREATE POLICY "Admin write student_nps" ON student_nps FOR INSERT TO authenticated WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
DROP POLICY IF EXISTS "Admin update student_nps" ON student_nps;
CREATE POLICY "Admin update student_nps" ON student_nps FOR UPDATE TO authenticated USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── OAUTH STATES ───
CREATE TABLE IF NOT EXISTS oauth_states (
  state      TEXT PRIMARY KEY,
  mentor_id  TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now()
);
