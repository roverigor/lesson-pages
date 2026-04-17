-- Fix class_schedule_view to filter by valid_from/valid_until
-- Previously showed ALL class_mentors records (including expired),
-- causing duplicates. Now only shows currently valid assignments.

CREATE OR REPLACE VIEW class_schedule_view AS
SELECT
  c.id AS class_id,
  c.name AS class_name,
  c.type AS class_type,
  c.start_date,
  c.end_date,
  c.time_start,
  c.time_end,
  c.color,
  c.active,
  cm.weekday,
  cm.role AS mentor_role,
  m.id AS mentor_id,
  m.name AS mentor_name,
  m.phone AS mentor_phone
FROM classes c
LEFT JOIN class_mentors cm ON cm.class_id = c.id
  AND cm.valid_from <= CURRENT_DATE
  AND (cm.valid_until IS NULL OR cm.valid_until >= CURRENT_DATE)
LEFT JOIN mentors m ON m.id = cm.mentor_id
ORDER BY c.name, cm.weekday, cm.role;
