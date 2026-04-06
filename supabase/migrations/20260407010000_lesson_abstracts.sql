-- ============================================================
-- LESSON_ABSTRACTS: Dynamic lesson summaries table
-- Migrated from abstracts/index.html static content
-- ============================================================

CREATE TABLE IF NOT EXISTS lesson_abstracts (
  id           UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  slug         TEXT        UNIQUE NOT NULL,
  title        TEXT        NOT NULL,
  lesson_date  DATE        NOT NULL,
  badge_class  TEXT        NOT NULL DEFAULT 'green',
  badge_label  TEXT        NOT NULL DEFAULT 'Aula',
  body_html    TEXT        NOT NULL DEFAULT '',
  section_type TEXT        NOT NULL DEFAULT 'lesson' CHECK (section_type IN ('lesson', 'kb')),
  sort_order   INTEGER     NOT NULL DEFAULT 0,
  published    BOOLEAN     NOT NULL DEFAULT true,
  cohort_tag   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for ordered listing
CREATE INDEX IF NOT EXISTS idx_lesson_abstracts_sort ON lesson_abstracts (section_type, sort_order);
CREATE INDEX IF NOT EXISTS idx_lesson_abstracts_slug ON lesson_abstracts (slug);

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION update_lesson_abstracts_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_lesson_abstracts_updated_at ON lesson_abstracts;
CREATE TRIGGER trg_lesson_abstracts_updated_at
  BEFORE UPDATE ON lesson_abstracts
  FOR EACH ROW EXECUTE FUNCTION update_lesson_abstracts_updated_at();

-- RLS: public read, authenticated admin write
ALTER TABLE lesson_abstracts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "lesson_abstracts_public_read" ON lesson_abstracts;
CREATE POLICY "lesson_abstracts_public_read"
  ON lesson_abstracts FOR SELECT
  USING (published = true);

DROP POLICY IF EXISTS "lesson_abstracts_admin_all" ON lesson_abstracts;
CREATE POLICY "lesson_abstracts_admin_all"
  ON lesson_abstracts FOR ALL
  TO authenticated
  USING (true)
  WITH CHECK (true);
