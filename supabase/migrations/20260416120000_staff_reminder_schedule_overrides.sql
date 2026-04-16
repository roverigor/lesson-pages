-- ═══════════════════════════════════════
-- Story 14.2: Incorporate schedule_overrides into staff reminder
-- Frontend buildEventsFromDB() applies overrides AFTER class_mentors filter.
-- This migration aligns the PL/pgSQL function to do the same:
--   1. Exclude mentors with override action='remove' for today
--   2. Include mentors with override action='add' for today
-- Override matching uses lesson_date (DD/MM text) + course name + teacher_name
-- ═══════════════════════════════════════

CREATE OR REPLACE FUNCTION public.process_daily_staff_reminders()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  today_dow INT;
  today_date DATE;
  today_key TEXT;
  rec RECORD;
  role_emoji TEXT;
  role_label TEXT;
  msg_template TEXT;
  companion_line TEXT;
  inserted_count INT := 0;
BEGIN
  today_dow  := EXTRACT(DOW FROM NOW() AT TIME ZONE 'America/Sao_Paulo')::int;
  today_date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
  today_key  := to_char(today_date, 'DD/MM');

  -- ─── PART 1: Regular class_mentors (minus overrides with action='remove') ───
  FOR rec IN
    SELECT DISTINCT
      c.id         AS class_id,
      c.name       AS class_name,
      c.time_start,
      c.time_end,
      c.zoom_link,
      cm.role      AS staff_role,
      m.id         AS mentor_id,
      m.name       AS mentor_name,
      m.phone      AS mentor_phone
    FROM classes c
    JOIN class_mentors cm ON c.id = cm.class_id
      AND cm.weekday = today_dow
      AND cm.valid_from <= today_date
      AND (cm.valid_until IS NULL OR cm.valid_until >= today_date)
    JOIN mentors m ON cm.mentor_id = m.id
      AND m.active = true
      AND m.phone IS NOT NULL
    WHERE c.active = true
      AND (c.start_date IS NULL OR c.start_date <= today_date)
      AND (c.end_date   IS NULL OR c.end_date   >= today_date)
      -- Exclude if override removes this mentor today
      AND NOT EXISTS (
        SELECT 1 FROM schedule_overrides so
        WHERE so.lesson_date  = today_key
          AND so.course       = c.name
          AND so.teacher_name = m.name
          AND so.action       = 'remove'
      )
      -- Anti-duplicate: skip if already sent today
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.type      = 'staff_reminder'
          AND n.mentor_id = m.id
          AND n.class_id  = c.id
          AND n.created_at >= today_date::timestamptz
      )
    ORDER BY c.time_start, m.name
  LOOP
    CASE rec.staff_role
      WHEN 'Professor' THEN role_emoji := '👨‍🏫'; role_label := 'Professor(a)';
      WHEN 'Host'      THEN role_emoji := '🎙️';  role_label := 'Host';
      WHEN 'Mentor'    THEN role_emoji := '🧑‍🤝‍🧑'; role_label := 'Mentor(a)';
      ELSE                   role_emoji := '📌';  role_label := rec.staff_role;
    END CASE;

    -- Companion info (Professor sees Host, Host sees Professor)
    -- Includes override adds, excludes override removes
    companion_line := '';
    IF rec.staff_role = 'Professor' THEN
      SELECT string_agg(host_name, ', ')
      INTO companion_line
      FROM (
        -- Regular hosts from class_mentors (minus removes)
        SELECT m2.name AS host_name
        FROM class_mentors cm2
        JOIN mentors m2 ON cm2.mentor_id = m2.id AND m2.active = true
        WHERE cm2.class_id = rec.class_id
          AND cm2.weekday = today_dow
          AND cm2.valid_from <= today_date
          AND (cm2.valid_until IS NULL OR cm2.valid_until >= today_date)
          AND cm2.role = 'Host'
          AND NOT EXISTS (
            SELECT 1 FROM schedule_overrides so
            WHERE so.lesson_date = today_key AND so.course = rec.class_name
              AND so.teacher_name = m2.name AND so.action = 'remove'
          )
        UNION
        -- Override-added hosts
        SELECT so.teacher_name AS host_name
        FROM schedule_overrides so
        WHERE so.lesson_date = today_key
          AND so.course = rec.class_name
          AND so.action = 'add'
          AND so.role = 'Host'
      ) sub;
      IF companion_line IS NOT NULL AND companion_line <> '' THEN
        companion_line := E'\n🎙️ Host: *' || companion_line || '*';
      ELSE
        companion_line := '';
      END IF;
    ELSIF rec.staff_role = 'Host' THEN
      SELECT string_agg(prof_name, ', ')
      INTO companion_line
      FROM (
        -- Regular professors from class_mentors (minus removes)
        SELECT m2.name AS prof_name
        FROM class_mentors cm2
        JOIN mentors m2 ON cm2.mentor_id = m2.id AND m2.active = true
        WHERE cm2.class_id = rec.class_id
          AND cm2.weekday = today_dow
          AND cm2.valid_from <= today_date
          AND (cm2.valid_until IS NULL OR cm2.valid_until >= today_date)
          AND cm2.role = 'Professor'
          AND NOT EXISTS (
            SELECT 1 FROM schedule_overrides so
            WHERE so.lesson_date = today_key AND so.course = rec.class_name
              AND so.teacher_name = m2.name AND so.action = 'remove'
          )
        UNION
        -- Override-added professors
        SELECT so.teacher_name AS prof_name
        FROM schedule_overrides so
        WHERE so.lesson_date = today_key
          AND so.course = rec.class_name
          AND so.action = 'add'
          AND so.role = 'Professor'
      ) sub;
      IF companion_line IS NOT NULL AND companion_line <> '' THEN
        companion_line := E'\n👨‍🏫 Professor: *' || companion_line || '*';
      ELSE
        companion_line := '';
      END IF;
    END IF;

    msg_template := format(
      E'Bom dia, *%s*! 👋\n\nVocê está escalado(a) hoje como %s *%s* na aula:\n\n📚 *%s* — %s às %s%s\n%s\n\nPosso confirmar sua presença?\n✅ Confirmado\n❌ Não vou conseguir',
      rec.mentor_name,
      role_emoji,
      role_label,
      rec.class_name,
      to_char(rec.time_start, 'HH24:MI'),
      to_char(rec.time_end, 'HH24:MI'),
      companion_line,
      CASE WHEN rec.zoom_link IS NOT NULL AND rec.zoom_link <> ''
        THEN '🔗 ' || rec.zoom_link
        ELSE ''
      END
    );

    INSERT INTO notifications (
      type, class_id, mentor_id, target_type, target_phone,
      message_template, message_rendered, metadata, status
    ) VALUES (
      'staff_reminder',
      rec.class_id,
      rec.mentor_id,
      'individual',
      rec.mentor_phone,
      msg_template,
      msg_template,
      jsonb_build_object(
        'staff_role', rec.staff_role,
        'role_emoji', role_emoji,
        'role_label', role_label,
        'automated',  true,
        'date_key',   today_key
      ),
      'pending'
    );

    inserted_count := inserted_count + 1;
  END LOOP;

  -- ─── PART 2: Override-added mentors (action='add' for today) ───
  -- These are mentors added via schedule_overrides who are NOT in class_mentors
  FOR rec IN
    SELECT DISTINCT
      c.id         AS class_id,
      c.name       AS class_name,
      c.time_start,
      c.time_end,
      c.zoom_link,
      so.role      AS staff_role,
      m.id         AS mentor_id,
      m.name       AS mentor_name,
      m.phone      AS mentor_phone
    FROM schedule_overrides so
    JOIN classes c ON c.name = so.course AND c.active = true
    JOIN mentors m ON m.name = so.teacher_name
      AND m.active = true
      AND m.phone IS NOT NULL
    WHERE so.lesson_date = today_key
      AND so.action = 'add'
      -- Only if NOT already covered by class_mentors (avoid double-send)
      AND NOT EXISTS (
        SELECT 1 FROM class_mentors cm
        WHERE cm.class_id = c.id
          AND cm.mentor_id = m.id
          AND cm.weekday = today_dow
          AND cm.valid_from <= today_date
          AND (cm.valid_until IS NULL OR cm.valid_until >= today_date)
      )
      -- Anti-duplicate
      AND NOT EXISTS (
        SELECT 1 FROM notifications n
        WHERE n.type      = 'staff_reminder'
          AND n.mentor_id = m.id
          AND n.class_id  = c.id
          AND n.created_at >= today_date::timestamptz
      )
    ORDER BY c.time_start, m.name
  LOOP
    CASE rec.staff_role
      WHEN 'Professor' THEN role_emoji := '👨‍🏫'; role_label := 'Professor(a)';
      WHEN 'Host'      THEN role_emoji := '🎙️';  role_label := 'Host';
      WHEN 'Mentor'    THEN role_emoji := '🧑‍🤝‍🧑'; role_label := 'Mentor(a)';
      ELSE                   role_emoji := '📌';  role_label := rec.staff_role;
    END CASE;

    -- Companion info for override-added mentors
    companion_line := '';
    IF rec.staff_role = 'Professor' THEN
      SELECT string_agg(host_name, ', ')
      INTO companion_line
      FROM (
        SELECT m2.name AS host_name
        FROM class_mentors cm2
        JOIN mentors m2 ON cm2.mentor_id = m2.id AND m2.active = true
        WHERE cm2.class_id = rec.class_id
          AND cm2.weekday = today_dow
          AND cm2.valid_from <= today_date
          AND (cm2.valid_until IS NULL OR cm2.valid_until >= today_date)
          AND cm2.role = 'Host'
          AND NOT EXISTS (
            SELECT 1 FROM schedule_overrides so2
            WHERE so2.lesson_date = today_key AND so2.course = rec.class_name
              AND so2.teacher_name = m2.name AND so2.action = 'remove'
          )
        UNION
        SELECT so2.teacher_name AS host_name
        FROM schedule_overrides so2
        WHERE so2.lesson_date = today_key
          AND so2.course = rec.class_name
          AND so2.action = 'add'
          AND so2.role = 'Host'
          AND so2.teacher_name <> rec.mentor_name
      ) sub;
      IF companion_line IS NOT NULL AND companion_line <> '' THEN
        companion_line := E'\n🎙️ Host: *' || companion_line || '*';
      ELSE
        companion_line := '';
      END IF;
    ELSIF rec.staff_role = 'Host' THEN
      SELECT string_agg(prof_name, ', ')
      INTO companion_line
      FROM (
        SELECT m2.name AS prof_name
        FROM class_mentors cm2
        JOIN mentors m2 ON cm2.mentor_id = m2.id AND m2.active = true
        WHERE cm2.class_id = rec.class_id
          AND cm2.weekday = today_dow
          AND cm2.valid_from <= today_date
          AND (cm2.valid_until IS NULL OR cm2.valid_until >= today_date)
          AND cm2.role = 'Professor'
          AND NOT EXISTS (
            SELECT 1 FROM schedule_overrides so2
            WHERE so2.lesson_date = today_key AND so2.course = rec.class_name
              AND so2.teacher_name = m2.name AND so2.action = 'remove'
          )
        UNION
        SELECT so2.teacher_name AS prof_name
        FROM schedule_overrides so2
        WHERE so2.lesson_date = today_key
          AND so2.course = rec.class_name
          AND so2.action = 'add'
          AND so2.role = 'Professor'
          AND so2.teacher_name <> rec.mentor_name
      ) sub;
      IF companion_line IS NOT NULL AND companion_line <> '' THEN
        companion_line := E'\n👨‍🏫 Professor: *' || companion_line || '*';
      ELSE
        companion_line := '';
      END IF;
    END IF;

    msg_template := format(
      E'Bom dia, *%s*! 👋\n\nVocê está escalado(a) hoje como %s *%s* na aula:\n\n📚 *%s* — %s às %s%s\n%s\n\nPosso confirmar sua presença?\n✅ Confirmado\n❌ Não vou conseguir',
      rec.mentor_name,
      role_emoji,
      role_label,
      rec.class_name,
      to_char(rec.time_start, 'HH24:MI'),
      to_char(rec.time_end, 'HH24:MI'),
      companion_line,
      CASE WHEN rec.zoom_link IS NOT NULL AND rec.zoom_link <> ''
        THEN '🔗 ' || rec.zoom_link
        ELSE ''
      END
    );

    INSERT INTO notifications (
      type, class_id, mentor_id, target_type, target_phone,
      message_template, message_rendered, metadata, status
    ) VALUES (
      'staff_reminder',
      rec.class_id,
      rec.mentor_id,
      'individual',
      rec.mentor_phone,
      msg_template,
      msg_template,
      jsonb_build_object(
        'staff_role', rec.staff_role,
        'role_emoji', role_emoji,
        'role_label', role_label,
        'automated',  true,
        'date_key',   today_key,
        'source',     'schedule_override'
      ),
      'pending'
    );

    inserted_count := inserted_count + 1;
  END LOOP;

  RAISE LOG 'process_daily_staff_reminders: inserted % reminders for %',
    inserted_count, today_date;
END;
$$;
