-- PS RSVP — 8h morning DM with attendance check + doubts collection

CREATE TABLE IF NOT EXISTS ps_rsvp_links (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token uuid UNIQUE NOT NULL DEFAULT gen_random_uuid(),
  class_id uuid NOT NULL REFERENCES classes(id),
  student_id uuid NOT NULL REFERENCES students(id),
  session_date date NOT NULL,
  expires_at timestamptz NOT NULL DEFAULT (now() + interval '24 hours'),
  sent_at timestamptz,
  send_status text DEFAULT 'pending' CHECK (send_status IN ('pending','sent','failed','skipped')),
  error_detail text,
  evolution_message_id text,
  responded_at timestamptz,
  created_at timestamptz DEFAULT now(),
  CONSTRAINT ps_rsvp_unique UNIQUE (class_id, student_id, session_date)
);

CREATE INDEX IF NOT EXISTS idx_ps_rsvp_links_token ON ps_rsvp_links(token);
CREATE INDEX IF NOT EXISTS idx_ps_rsvp_links_class_date ON ps_rsvp_links(class_id, session_date);
CREATE INDEX IF NOT EXISTS idx_ps_rsvp_links_student ON ps_rsvp_links(student_id);

CREATE TABLE IF NOT EXISTS ps_rsvp_responses (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  link_id uuid REFERENCES ps_rsvp_links(id) ON DELETE CASCADE,
  class_id uuid NOT NULL,
  student_id uuid NOT NULL,
  session_date date NOT NULL,
  will_attend text NOT NULL CHECK (will_attend IN ('yes','no','maybe')),
  doubts_text text,
  project_phase text,
  submitted_at timestamptz DEFAULT now(),
  ip_hash text,
  user_agent text,
  metadata jsonb DEFAULT '{}'
);

CREATE INDEX IF NOT EXISTS idx_ps_rsvp_responses_class_date ON ps_rsvp_responses(class_id, session_date);
CREATE INDEX IF NOT EXISTS idx_ps_rsvp_responses_student ON ps_rsvp_responses(student_id);

ALTER TABLE ps_rsvp_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE ps_rsvp_responses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "ps_rsvp_links_service" ON ps_rsvp_links FOR ALL TO service_role USING (true) WITH CHECK (true);
CREATE POLICY "ps_rsvp_responses_service" ON ps_rsvp_responses FOR ALL TO service_role USING (true) WITH CHECK (true);

GRANT ALL ON ps_rsvp_links TO service_role;
GRANT ALL ON ps_rsvp_responses TO service_role;
GRANT SELECT ON ps_rsvp_links TO authenticated;
GRANT SELECT ON ps_rsvp_responses TO authenticated;

-- RPC: token metadata
CREATE OR REPLACE FUNCTION get_ps_rsvp_metadata(p_token uuid)
RETURNS TABLE(valid boolean, expired boolean, already_answered boolean, class_name text, session_date date, student_name text)
LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
DECLARE
  v_link ps_rsvp_links%ROWTYPE;
  v_answered boolean;
BEGIN
  SELECT * INTO v_link FROM ps_rsvp_links WHERE token = p_token;
  IF NOT FOUND THEN
    RETURN QUERY SELECT false, false, false, NULL::text, NULL::date, NULL::text;
    RETURN;
  END IF;
  IF v_link.expires_at < now() THEN
    RETURN QUERY SELECT false, true, false, NULL::text, NULL::date, NULL::text;
    RETURN;
  END IF;
  SELECT EXISTS(SELECT 1 FROM ps_rsvp_responses WHERE link_id = v_link.id) INTO v_answered;
  RETURN QUERY
    SELECT true, false, v_answered, c.name, v_link.session_date, s.name
    FROM classes c, students s
    WHERE c.id = v_link.class_id AND s.id = v_link.student_id;
END;
$$;

GRANT EXECUTE ON FUNCTION get_ps_rsvp_metadata(uuid) TO anon, authenticated;

-- Admin view: mentors see today's RSVPs by class
CREATE OR REPLACE VIEW ps_rsvp_today AS
SELECT
  r.id, r.class_id, c.name AS class_name, r.session_date,
  r.student_id, s.name AS student_name, s.phone AS student_phone,
  r.will_attend, r.doubts_text, r.project_phase, r.submitted_at
FROM ps_rsvp_responses r
LEFT JOIN classes c ON c.id = r.class_id
LEFT JOIN students s ON s.id = r.student_id
WHERE r.session_date >= CURRENT_DATE
ORDER BY r.session_date DESC, r.will_attend, s.name;

GRANT SELECT ON ps_rsvp_today TO authenticated;
