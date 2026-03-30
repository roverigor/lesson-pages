-- ═══════════════════════════════════════
-- LESSON PAGES — Zoom Integration & NPS Schema
-- Run in Supabase SQL Editor
-- ═══════════════════════════════════════

-- ─── 1. ZOOM TOKENS ───
-- OAuth tokens por conta Zoom (cada mentor autoriza 1 vez)
CREATE TABLE IF NOT EXISTS zoom_tokens (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  mentor_id UUID REFERENCES mentors(id) ON DELETE SET NULL,
  zoom_email TEXT NOT NULL,
  zoom_account_id TEXT,
  access_token TEXT NOT NULL,
  refresh_token TEXT NOT NULL,
  token_type TEXT DEFAULT 'Bearer',
  expires_at TIMESTAMPTZ NOT NULL,
  scope TEXT,
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(zoom_email)
);

CREATE INDEX IF NOT EXISTS idx_zoom_tokens_mentor ON zoom_tokens(mentor_id);
CREATE INDEX IF NOT EXISTS idx_zoom_tokens_email ON zoom_tokens(zoom_email);

-- ─── 2. ZOOM MEETINGS ───
-- Reunioes realizadas (fonte da verdade de aulas)
CREATE TABLE IF NOT EXISTS zoom_meetings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  zoom_meeting_id TEXT NOT NULL,
  zoom_uuid TEXT UNIQUE,
  host_email TEXT,
  host_name TEXT,
  topic TEXT,
  start_time TIMESTAMPTZ,
  end_time TIMESTAMPTZ,
  duration_minutes INT,
  participants_count INT DEFAULT 0,
  class_id UUID REFERENCES classes(id) ON DELETE SET NULL,
  cohort_id UUID REFERENCES cohorts(id) ON DELETE SET NULL,
  processed BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_zoom_meetings_meeting_id ON zoom_meetings(zoom_meeting_id);
CREATE INDEX IF NOT EXISTS idx_zoom_meetings_host ON zoom_meetings(host_email);
CREATE INDEX IF NOT EXISTS idx_zoom_meetings_class ON zoom_meetings(class_id);
CREATE INDEX IF NOT EXISTS idx_zoom_meetings_cohort ON zoom_meetings(cohort_id);
CREATE INDEX IF NOT EXISTS idx_zoom_meetings_start ON zoom_meetings(start_time DESC);
CREATE INDEX IF NOT EXISTS idx_zoom_meetings_processed ON zoom_meetings(processed) WHERE processed = false;

-- ─── 3. ZOOM PARTICIPANTS ───
-- Participantes de cada reuniao (base para presenca de alunos)
CREATE TABLE IF NOT EXISTS zoom_participants (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  meeting_id UUID NOT NULL REFERENCES zoom_meetings(id) ON DELETE CASCADE,
  participant_name TEXT,
  participant_email TEXT,
  join_time TIMESTAMPTZ,
  leave_time TIMESTAMPTZ,
  duration_minutes INT,
  student_id UUID REFERENCES students(id) ON DELETE SET NULL,
  matched BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_zoom_participants_meeting ON zoom_participants(meeting_id);
CREATE INDEX IF NOT EXISTS idx_zoom_participants_student ON zoom_participants(student_id);
CREATE INDEX IF NOT EXISTS idx_zoom_participants_email ON zoom_participants(participant_email);

-- ─── 4. STUDENT NPS/CSAT ───
-- Respostas NPS por aluno por aula (vindas do Tally)
CREATE TABLE IF NOT EXISTS student_nps (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  student_id UUID REFERENCES students(id) ON DELETE SET NULL,
  meeting_id UUID REFERENCES zoom_meetings(id) ON DELETE SET NULL,
  cohort_id UUID REFERENCES cohorts(id) ON DELETE SET NULL,
  score INT NOT NULL CHECK (score >= 0 AND score <= 10),
  feedback TEXT,
  tally_response_id TEXT,
  tally_form_id TEXT,
  responded_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_student_nps_student ON student_nps(student_id);
CREATE INDEX IF NOT EXISTS idx_student_nps_meeting ON student_nps(meeting_id);
CREATE INDEX IF NOT EXISTS idx_student_nps_cohort ON student_nps(cohort_id);
CREATE INDEX IF NOT EXISTS idx_student_nps_score ON student_nps(score);

-- ─── 5. RLS ───
ALTER TABLE zoom_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE zoom_meetings ENABLE ROW LEVEL SECURITY;
ALTER TABLE zoom_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE student_nps ENABLE ROW LEVEL SECURITY;

-- Admin read/write for all
CREATE POLICY "Admin all zoom_tokens" ON zoom_tokens FOR ALL TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

CREATE POLICY "Admin read zoom_meetings" ON zoom_meetings FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin write zoom_meetings" ON zoom_meetings FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin update zoom_meetings" ON zoom_meetings FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

CREATE POLICY "Admin read zoom_participants" ON zoom_participants FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin write zoom_participants" ON zoom_participants FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

CREATE POLICY "Admin read student_nps" ON student_nps FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin write student_nps" ON student_nps FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin update student_nps" ON student_nps FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── 6. TRIGGERS ───
CREATE TRIGGER zoom_tokens_updated_at
  BEFORE UPDATE ON zoom_tokens FOR EACH ROW EXECUTE FUNCTION update_updated_at();
CREATE TRIGGER zoom_meetings_updated_at
  BEFORE UPDATE ON zoom_meetings FOR EACH ROW EXECUTE FUNCTION update_updated_at();
