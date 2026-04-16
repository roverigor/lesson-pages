-- ═══════════════════════════════════════
-- Fix: align staff reminder date filtering with frontend buildEventsFromDB()
-- Frontend checks: valid_from <= date AND (valid_until IS NULL OR valid_until >= date)
-- Previous version only checked valid_until IS NULL (missed temporal ranges)
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
  rec RECORD;
  role_emoji TEXT;
  role_label TEXT;
  msg_template TEXT;
  companion_line TEXT;
  inserted_count INT := 0;
BEGIN
  today_dow  := EXTRACT(DOW FROM NOW() AT TIME ZONE 'America/Sao_Paulo')::int;
  today_date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;

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
    companion_line := '';
    IF rec.staff_role = 'Professor' THEN
      SELECT string_agg(m2.name, ', ')
      INTO companion_line
      FROM class_mentors cm2
      JOIN mentors m2 ON cm2.mentor_id = m2.id AND m2.active = true
      WHERE cm2.class_id = rec.class_id
        AND cm2.weekday = today_dow
        AND cm2.valid_from <= today_date
        AND (cm2.valid_until IS NULL OR cm2.valid_until >= today_date)
        AND cm2.role = 'Host';
      IF companion_line IS NOT NULL AND companion_line <> '' THEN
        companion_line := E'\n🎙️ Host: *' || companion_line || '*';
      ELSE
        companion_line := '';
      END IF;
    ELSIF rec.staff_role = 'Host' THEN
      SELECT string_agg(m2.name, ', ')
      INTO companion_line
      FROM class_mentors cm2
      JOIN mentors m2 ON cm2.mentor_id = m2.id AND m2.active = true
      WHERE cm2.class_id = rec.class_id
        AND cm2.weekday = today_dow
        AND cm2.valid_from <= today_date
        AND (cm2.valid_until IS NULL OR cm2.valid_until >= today_date)
        AND cm2.role = 'Professor';
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
        'date_key',   to_char(today_date, 'DD/MM')
      ),
      'pending'
    );

    inserted_count := inserted_count + 1;
  END LOOP;

  RAISE LOG 'process_daily_staff_reminders: inserted % reminders for %',
    inserted_count, today_date;
END;
$$;
