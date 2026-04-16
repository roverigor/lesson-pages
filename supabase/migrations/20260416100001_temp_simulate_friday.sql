CREATE OR REPLACE FUNCTION public.simulate_staff_reminder_friday()
RETURNS TABLE(class_name TEXT, mentor_name TEXT, staff_role TEXT, phone TEXT)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT DISTINCT
    c.name AS class_name,
    m.name AS mentor_name,
    cm.role AS staff_role,
    m.phone
  FROM classes c
  JOIN class_mentors cm ON c.id = cm.class_id
    AND cm.valid_until IS NULL
    AND cm.weekday = 5
  JOIN mentors m ON cm.mentor_id = m.id
    AND m.active = true
    AND m.phone IS NOT NULL
  WHERE c.active = true
    AND (c.start_date IS NULL OR c.start_date <= '2026-04-17'::date)
    AND (c.end_date   IS NULL OR c.end_date   >= '2026-04-17'::date)
  ORDER BY c.name, cm.role, m.name;
$$;
