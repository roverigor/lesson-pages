-- ═══════════════════════════════════════
-- LESSON PAGES — Daily Staff Reminder (8h BRT)
-- Sends individual WhatsApp to each staff member
-- with their role for today's classes
-- ═══════════════════════════════════════

-- ─── 1. Add 'staff_reminder' to notifications.type CHECK constraint ───
ALTER TABLE notifications DROP CONSTRAINT IF EXISTS notifications_type_check;
ALTER TABLE notifications ADD CONSTRAINT notifications_type_check CHECK (type IN (
  'class_reminder',
  'mentor_individual',
  'group_announcement',
  'schedule_change',
  'staff_reminder',
  'custom'
));

-- ─── 2. PL/pgSQL function: process_daily_staff_reminders ───
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
  inserted_count INT := 0;
BEGIN
  -- Current day-of-week and date in BRT
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
      AND cm.valid_until IS NULL                -- active cycle only
    JOIN mentors m ON cm.mentor_id = m.id
      AND m.active = true
      AND m.phone IS NOT NULL
    WHERE c.active = true
      AND c.weekday = today_dow
      AND (c.start_date IS NULL OR c.start_date <= today_date)
      AND (c.end_date   IS NULL OR c.end_date   >= today_date)
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
    -- Map role → emoji + label
    CASE rec.staff_role
      WHEN 'Professor' THEN role_emoji := '👨‍🏫'; role_label := 'Professor(a)';
      WHEN 'Host'      THEN role_emoji := '🎙️';  role_label := 'Host';
      WHEN 'Mentor'    THEN role_emoji := '🧑‍🤝‍🧑'; role_label := 'Mentor(a)';
      ELSE                   role_emoji := '📌';  role_label := rec.staff_role;
    END CASE;

    -- Build message template with placeholders already resolved
    msg_template := format(
      E'Bom dia, *%s*! 👋\n\nVocê está escalado(a) hoje como %s *%s* na aula:\n\n📚 *%s* — %s às %s\n%s\n\nPosso confirmar sua presença?\n✅ Confirmado\n❌ Não vou conseguir',
      rec.mentor_name,
      role_emoji,
      role_label,
      rec.class_name,
      to_char(rec.time_start, 'HH24:MI'),
      to_char(rec.time_end, 'HH24:MI'),
      CASE WHEN rec.zoom_link IS NOT NULL AND rec.zoom_link <> ''
        THEN '🔗 ' || rec.zoom_link
        ELSE ''
      END
    );

    -- Insert notification → triggers webhook → send-whatsapp
    INSERT INTO notifications (
      type,
      class_id,
      mentor_id,
      target_type,
      target_phone,
      message_template,
      message_rendered,
      metadata,
      status
    ) VALUES (
      'staff_reminder',
      rec.class_id,
      rec.mentor_id,
      'individual',
      rec.mentor_phone,
      msg_template,
      msg_template,  -- already fully rendered
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

-- ─── 3. pg_cron job: daily at 08:00 BRT (11:00 UTC) ───
SELECT cron.unschedule('daily-staff-reminder')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'daily-staff-reminder'
);

SELECT cron.schedule(
  'daily-staff-reminder',
  '0 11 * * *',
  $$SELECT process_daily_staff_reminders()$$
);
