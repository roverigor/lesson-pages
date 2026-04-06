-- ═══════════════════════════════════════
-- EPIC-005 Story 5.1 — Form Builder Schema
-- ═══════════════════════════════════════

-- Extend surveys with intro text and remove hard type constraint
ALTER TABLE surveys ADD COLUMN IF NOT EXISTS intro_text TEXT;

-- Allow 'mixed' type for multi-question surveys
ALTER TABLE surveys DROP CONSTRAINT IF EXISTS surveys_type_check;
ALTER TABLE surveys ADD CONSTRAINT surveys_type_check
  CHECK (type IN ('nps', 'csat', 'mixed'));

-- ─── SURVEY_QUESTIONS ───
CREATE TABLE IF NOT EXISTS survey_questions (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  survey_id   UUID NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
  position    INT NOT NULL DEFAULT 0,
  type        TEXT NOT NULL CHECK (type IN ('nps','csat','text','choice','multi','scale')),
  label       TEXT NOT NULL,
  required    BOOLEAN DEFAULT true,
  options     JSONB,       -- for choice/multi: ["Opção A","Opção B"]
  scale_max   INT,         -- for scale type
  placeholder TEXT,        -- for text type
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_survey_questions_survey   ON survey_questions(survey_id);
CREATE INDEX IF NOT EXISTS idx_survey_questions_position ON survey_questions(survey_id, position);

-- ─── SURVEY_RESPONSES ───
CREATE TABLE IF NOT EXISTS survey_responses (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  survey_id   UUID NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
  link_id     UUID REFERENCES survey_links(id) ON DELETE SET NULL,
  student_id  UUID REFERENCES students(id) ON DELETE SET NULL,
  submitted_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_survey_responses_survey  ON survey_responses(survey_id);
CREATE INDEX IF NOT EXISTS idx_survey_responses_student ON survey_responses(student_id);

-- ─── SURVEY_ANSWERS ───
CREATE TABLE IF NOT EXISTS survey_answers (
  id           UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  response_id  UUID NOT NULL REFERENCES survey_responses(id) ON DELETE CASCADE,
  question_id  UUID NOT NULL REFERENCES survey_questions(id) ON DELETE CASCADE,
  value_text   TEXT,
  value_number INT,
  value_options JSONB,
  created_at   TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_survey_answers_response  ON survey_answers(response_id);
CREATE INDEX IF NOT EXISTS idx_survey_answers_question  ON survey_answers(question_id);

-- ─── RLS ───
ALTER TABLE survey_questions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin all survey_questions" ON survey_questions;
CREATE POLICY "Admin all survey_questions" ON survey_questions FOR ALL TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- Anon pode ler perguntas (para exibir na página pública via join com survey_links)
DROP POLICY IF EXISTS "Anon read survey_questions" ON survey_questions;
CREATE POLICY "Anon read survey_questions" ON survey_questions FOR SELECT TO anon USING (true);

ALTER TABLE survey_responses ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin all survey_responses" ON survey_responses;
CREATE POLICY "Admin all survey_responses" ON survey_responses FOR ALL TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

ALTER TABLE survey_answers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin all survey_answers" ON survey_answers;
CREATE POLICY "Admin all survey_answers" ON survey_answers FOR ALL TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
