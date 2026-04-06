-- ═══════════════════════════════════════
-- EPIC-004 Story 4.1 — surveys schema
-- ═══════════════════════════════════════

-- ─── SURVEYS ───
CREATE TABLE IF NOT EXISTS surveys (
  id             UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name           TEXT NOT NULL,
  type           TEXT NOT NULL CHECK (type IN ('nps', 'csat')),
  cohort_id      UUID REFERENCES cohorts(id) ON DELETE SET NULL,
  class_id       UUID REFERENCES classes(id) ON DELETE SET NULL,
  question       TEXT NOT NULL,
  follow_up      TEXT,
  status         TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'active', 'closed')),
  dispatched_at  TIMESTAMPTZ,
  created_by     TEXT,
  created_at     TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_surveys_cohort ON surveys(cohort_id);
CREATE INDEX IF NOT EXISTS idx_surveys_status ON surveys(status);
CREATE INDEX IF NOT EXISTS idx_surveys_class  ON surveys(class_id);

-- ─── SURVEY_LINKS ───
CREATE TABLE IF NOT EXISTS survey_links (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  survey_id   UUID NOT NULL REFERENCES surveys(id) ON DELETE CASCADE,
  student_id  UUID NOT NULL REFERENCES students(id) ON DELETE CASCADE,
  token       UUID DEFAULT gen_random_uuid() NOT NULL,
  used_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE(survey_id, student_id),
  UNIQUE(token)
);

CREATE INDEX IF NOT EXISTS idx_survey_links_token      ON survey_links(token);
CREATE INDEX IF NOT EXISTS idx_survey_links_survey_id  ON survey_links(survey_id);
CREATE INDEX IF NOT EXISTS idx_survey_links_student_id ON survey_links(student_id);

-- ─── EXTEND student_nps ───
ALTER TABLE student_nps ADD COLUMN IF NOT EXISTS survey_id   UUID REFERENCES surveys(id) ON DELETE SET NULL;
ALTER TABLE student_nps ADD COLUMN IF NOT EXISTS survey_type TEXT DEFAULT 'nps';

CREATE INDEX IF NOT EXISTS idx_student_nps_survey ON student_nps(survey_id);
