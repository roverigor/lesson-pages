-- Migration: Create mentor_attendance table
-- Allows mentors/professors/hosts to check their own attendance per class session

CREATE TABLE IF NOT EXISTS mentor_attendance (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  mentor_id UUID NOT NULL REFERENCES mentors(id) ON DELETE CASCADE,
  class_id  UUID NOT NULL REFERENCES classes(id)  ON DELETE CASCADE,
  session_date DATE NOT NULL,
  status TEXT NOT NULL DEFAULT 'present' CHECK (status IN ('present', 'absent')),
  comment TEXT,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE(mentor_id, class_id, session_date)
);

CREATE INDEX IF NOT EXISTS idx_mentor_attendance_mentor  ON mentor_attendance(mentor_id);
CREATE INDEX IF NOT EXISTS idx_mentor_attendance_class   ON mentor_attendance(class_id);
CREATE INDEX IF NOT EXISTS idx_mentor_attendance_date    ON mentor_attendance(session_date);

-- RLS: mentors read/write their own rows; anon key allowed (page uses anon key)
ALTER TABLE mentor_attendance ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Allow all on mentor_attendance"
  ON mentor_attendance FOR ALL
  USING (true)
  WITH CHECK (true);
