-- ═══════════════════════════════════════
-- CLASSES TABLE — Schema Documentation
-- Tabela central referenciada por class_cohorts, class_mentors,
-- zoom_meetings e notifications.
-- ═══════════════════════════════════════

-- Esta tabela é criada no Supabase Dashboard / via SQL Editor.
-- Campos inferidos do uso no código (notifications-schema.sql, send-whatsapp/index.ts).

CREATE TABLE IF NOT EXISTS classes (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL,
  weekday     INTEGER NOT NULL CHECK (weekday BETWEEN 0 AND 6), -- 0=Dom, 1=Seg, ..., 6=Sáb
  time_start  TIME NOT NULL,
  time_end    TIME NOT NULL,
  date        DATE,                    -- data específica da aula (quando não recorrente)
  professor   TEXT,                    -- nome do professor principal (denormalizado)
  host        TEXT,                    -- nome do host/anfitrião (denormalizado)
  color       TEXT,                    -- cor para exibição no calendário (hex)
  zoom_link   TEXT,                    -- link Zoom da aula
  active      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now(),
  updated_at  TIMESTAMPTZ DEFAULT now()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_classes_weekday  ON classes(weekday);
CREATE INDEX IF NOT EXISTS idx_classes_date     ON classes(date);
CREATE INDEX IF NOT EXISTS idx_classes_active   ON classes(active);

-- Trigger de updated_at
CREATE TRIGGER classes_updated_at
  BEFORE UPDATE ON classes
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- RLS
ALTER TABLE classes ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Authenticated read classes"
  ON classes FOR SELECT TO authenticated
  USING (true);

CREATE POLICY "Admin insert classes"
  ON classes FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

CREATE POLICY "Admin update classes"
  ON classes FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

CREATE POLICY "Admin delete classes"
  ON classes FOR DELETE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
