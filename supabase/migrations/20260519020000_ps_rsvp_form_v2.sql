-- ═══════════════════════════════════════════════════════════════════════════
-- PS RSVP form v2:
--   • Drop "maybe" option (will_attend = yes | no only)
--   • Add confirmed_name (yes path)
--   • Add no_reason + team_message (no path)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE ps_rsvp_responses
  DROP CONSTRAINT IF EXISTS ps_rsvp_responses_will_attend_check;

ALTER TABLE ps_rsvp_responses
  ADD CONSTRAINT ps_rsvp_responses_will_attend_check
  CHECK (will_attend IN ('yes', 'no'));

ALTER TABLE ps_rsvp_responses
  ADD COLUMN IF NOT EXISTS confirmed_name text,
  ADD COLUMN IF NOT EXISTS no_reason     text,
  ADD COLUMN IF NOT EXISTS team_message  text;

COMMENT ON COLUMN ps_rsvp_responses.confirmed_name IS
  'Nome confirmado pelo aluno quando will_attend=yes (pode diferir do students.name).';
COMMENT ON COLUMN ps_rsvp_responses.no_reason IS
  'Motivo específico que aluno escolheu compartilhar quando will_attend=no.';
COMMENT ON COLUMN ps_rsvp_responses.team_message IS
  'Recado opcional pra equipe quando will_attend=no (e aluno não compartilhou motivo).';

-- Update ps_rsvp_today view to expose new fields
DROP VIEW IF EXISTS ps_rsvp_today;
CREATE OR REPLACE VIEW ps_rsvp_today AS
SELECT
  r.id, r.class_id, c.name AS class_name, r.session_date,
  r.student_id, s.name AS student_name, s.phone AS student_phone,
  r.will_attend, r.doubts_text, r.project_phase,
  r.confirmed_name, r.no_reason, r.team_message,
  r.submitted_at
FROM ps_rsvp_responses r
LEFT JOIN classes c ON c.id = r.class_id
LEFT JOIN students s ON s.id = r.student_id
WHERE r.session_date >= CURRENT_DATE
ORDER BY r.session_date DESC, r.will_attend, s.name;

GRANT SELECT ON ps_rsvp_today TO authenticated;
