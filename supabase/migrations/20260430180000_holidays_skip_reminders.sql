-- ═══════════════════════════════════════════════════════════════════════
-- HOLIDAYS — Suprimir disparos staff/professor/mentor/host em feriados
-- ═══════════════════════════════════════════════════════════════════════
-- Cria tabela holidays + função is_holiday(date)
-- Aplica skip em:
--   1. process_daily_staff_reminders()  (cron 08:00 BRT)
--   2. slack-class-reminder cron        (Mon-Fri 10:00 BRT)
--   3. whatsapp-class-reminder cron     (Mon-Fri 10:00 BRT)
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. holidays table ───
CREATE TABLE IF NOT EXISTS public.holidays (
  date        DATE PRIMARY KEY,
  name        TEXT NOT NULL,
  scope       TEXT NOT NULL DEFAULT 'national' CHECK (scope IN ('national', 'regional', 'custom')),
  active      BOOLEAN NOT NULL DEFAULT true,
  created_at  TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_holidays_active ON public.holidays(date) WHERE active = true;

ALTER TABLE public.holidays ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin manage holidays" ON public.holidays;
CREATE POLICY "Admin manage holidays" ON public.holidays
  FOR ALL TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Authenticated read holidays" ON public.holidays;
CREATE POLICY "Authenticated read holidays" ON public.holidays
  FOR SELECT TO authenticated USING (true);

-- ─── 2. is_holiday() helper ───
CREATE OR REPLACE FUNCTION public.is_holiday(p_date DATE DEFAULT NULL)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.holidays
    WHERE date = COALESCE(p_date, (now() AT TIME ZONE 'America/Sao_Paulo')::date)
      AND active = true
  );
$$;

-- ─── 3. Seed feriados nacionais 2026 + 2027 ───
INSERT INTO public.holidays (date, name, scope) VALUES
  -- 2026
  ('2026-01-01', 'Confraternização Universal', 'national'),
  ('2026-02-16', 'Carnaval (segunda)',         'national'),
  ('2026-02-17', 'Carnaval (terça)',           'national'),
  ('2026-04-03', 'Sexta-feira Santa',          'national'),
  ('2026-04-21', 'Tiradentes',                 'national'),
  ('2026-05-01', 'Dia do Trabalho',            'national'),
  ('2026-06-04', 'Corpus Christi',             'national'),
  ('2026-09-07', 'Independência do Brasil',    'national'),
  ('2026-10-12', 'Nossa Senhora Aparecida',    'national'),
  ('2026-11-02', 'Finados',                    'national'),
  ('2026-11-15', 'Proclamação da República',   'national'),
  ('2026-11-20', 'Consciência Negra',          'national'),
  ('2026-12-25', 'Natal',                      'national'),
  -- 2027
  ('2027-01-01', 'Confraternização Universal', 'national'),
  ('2027-02-08', 'Carnaval (segunda)',         'national'),
  ('2027-02-09', 'Carnaval (terça)',           'national'),
  ('2027-03-26', 'Sexta-feira Santa',          'national'),
  ('2027-04-21', 'Tiradentes',                 'national'),
  ('2027-05-01', 'Dia do Trabalho',            'national'),
  ('2027-05-27', 'Corpus Christi',             'national'),
  ('2027-09-07', 'Independência do Brasil',    'national'),
  ('2027-10-12', 'Nossa Senhora Aparecida',    'national'),
  ('2027-11-02', 'Finados',                    'national'),
  ('2027-11-15', 'Proclamação da República',   'national'),
  ('2027-11-20', 'Consciência Negra',          'national'),
  ('2027-12-25', 'Natal',                      'national')
ON CONFLICT (date) DO NOTHING;

-- ─── 4. Modificar process_daily_staff_reminders() — early return em feriado ───
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
  v_holiday_name TEXT;
BEGIN
  today_dow  := EXTRACT(DOW FROM NOW() AT TIME ZONE 'America/Sao_Paulo')::int;
  today_date := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;

  -- Skip if today is a holiday
  SELECT name INTO v_holiday_name
  FROM public.holidays
  WHERE date = today_date AND active = true
  LIMIT 1;

  IF v_holiday_name IS NOT NULL THEN
    RAISE LOG 'process_daily_staff_reminders: SKIPPED (holiday: %)', v_holiday_name;
    RETURN;
  END IF;

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
      AND cm.valid_until IS NULL
    JOIN mentors m ON cm.mentor_id = m.id
      AND m.active = true
      AND m.phone IS NOT NULL
    WHERE c.active = true
      AND c.weekday = today_dow
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

    companion_line := '';
    IF rec.staff_role = 'Professor' THEN
      SELECT string_agg(m2.name, ', ')
      INTO companion_line
      FROM class_mentors cm2
      JOIN mentors m2 ON cm2.mentor_id = m2.id AND m2.active = true
      WHERE cm2.class_id = rec.class_id
        AND cm2.valid_until IS NULL
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
        AND cm2.valid_until IS NULL
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
      'staff_reminder', rec.class_id, rec.mentor_id, 'individual', rec.mentor_phone,
      msg_template, msg_template,
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

  RAISE LOG 'process_daily_staff_reminders: inserted % reminders for %', inserted_count, today_date;
END;
$$;

-- ─── 5. Modificar process_notification_schedules() — skip em feriado ───
CREATE OR REPLACE FUNCTION public.process_notification_schedules()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_schedule         RECORD;
  v_class_weekday    INTEGER;
  v_class_time_start TIME;
  v_today            DATE := (NOW() AT TIME ZONE 'America/Sao_Paulo')::date;
BEGIN
  -- Skip all schedule processing on holidays
  IF public.is_holiday(v_today) THEN
    RAISE LOG 'process_notification_schedules: SKIPPED (holiday)';
    RETURN;
  END IF;

  FOR v_schedule IN
    SELECT s.*
    FROM notification_schedules s
    WHERE s.active = true
      AND s.next_fire_at IS NOT NULL
      AND s.next_fire_at <= now()
      AND (s.last_fired_at IS NULL OR s.next_fire_at > s.last_fired_at)
  LOOP
    SELECT c.weekday, c.time_start INTO v_class_weekday, v_class_time_start
    FROM classes c WHERE c.id = v_schedule.class_id;

    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE class_id = v_schedule.class_id
        AND type = v_schedule.notification_type
        AND created_at > now() - INTERVAL '2 hours'
    ) THEN
      INSERT INTO notifications (
        type, class_id, cohort_id, target_type, target_group_jid,
        message_template, status, metadata
      ) VALUES (
        v_schedule.notification_type,
        v_schedule.class_id,
        v_schedule.cohort_id,
        v_schedule.target_type,
        (SELECT whatsapp_group_jid FROM cohorts WHERE id = v_schedule.cohort_id),
        v_schedule.message_template,
        'pending',
        jsonb_build_object('schedule_id', v_schedule.id, 'automated', true)
      );

      UPDATE notification_schedules
      SET last_fired_at = now(),
          next_fire_at  = calculate_next_fire_at(v_class_weekday, v_class_time_start, v_schedule.hours_before)
      WHERE id = v_schedule.id;
    END IF;
  END LOOP;
END;
$$;

-- ─── 6. Reagendar slack-class-reminder cron com check de feriado ───
SELECT cron.unschedule('slack-class-reminder')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'slack-class-reminder');

SELECT cron.schedule(
  'slack-class-reminder',
  '0 13 * * 1-5',
  $$
  DO $inner$
  DECLARE
    fn_url  TEXT;
    svc_key TEXT;
  BEGIN
    IF public.is_holiday() THEN
      RAISE LOG 'slack-class-reminder: SKIPPED (holiday)';
      RETURN;
    END IF;

    SELECT value INTO fn_url  FROM public.app_config WHERE key = 'slack_reminder_url';
    SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';
    IF fn_url IS NOT NULL THEN
      PERFORM net.http_post(
        url     := fn_url,
        body    := '{"dry_run": false}'::jsonb,
        headers := json_build_object(
          'Authorization', 'Bearer ' || COALESCE(svc_key,''),
          'Content-Type',  'application/json'
        )::jsonb
      );
    END IF;
  END;
  $inner$;
  $$
);

-- ─── 7. Reagendar whatsapp-class-reminder cron com check de feriado ───
SELECT cron.unschedule('whatsapp-class-reminder')
WHERE EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'whatsapp-class-reminder');

SELECT cron.schedule(
  'whatsapp-class-reminder',
  '0 13 * * 1-5',
  $$
  DO $inner$
  DECLARE
    fn_url  TEXT;
    svc_key TEXT;
  BEGIN
    IF public.is_holiday() THEN
      RAISE LOG 'whatsapp-class-reminder: SKIPPED (holiday)';
      RETURN;
    END IF;

    SELECT value INTO fn_url  FROM public.app_config WHERE key = 'whatsapp_reminder_url';
    SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';
    IF fn_url IS NOT NULL THEN
      PERFORM net.http_post(
        url     := fn_url,
        body    := '{"dry_run": false}'::jsonb,
        headers := json_build_object(
          'Authorization', 'Bearer ' || COALESCE(svc_key,''),
          'Content-Type',  'application/json'
        )::jsonb
      );
    END IF;
  END;
  $inner$;
  $$
);

-- ─── 8. Comments ───
COMMENT ON TABLE  public.holidays    IS 'Feriados que suprimem disparos automáticos. Admin via UI ou INSERT direto.';
COMMENT ON FUNCTION public.is_holiday IS 'Retorna true se data (default hoje BRT) é feriado ativo.';
