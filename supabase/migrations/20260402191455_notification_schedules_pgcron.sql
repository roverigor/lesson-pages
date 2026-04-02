-- ═══════════════════════════════════════
-- LESSON PAGES — Story 2.1: notification_schedules + pg_cron
-- EPIC-002 — Agendamento Automático de Notificações WhatsApp
-- ═══════════════════════════════════════

-- ─── 1. ENABLE pg_cron ───
CREATE EXTENSION IF NOT EXISTS pg_cron;
GRANT USAGE ON SCHEMA cron TO postgres;

-- ─── 2. NOTIFICATION_SCHEDULES TABLE ───
CREATE TABLE IF NOT EXISTS notification_schedules (
  id                UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  class_id          UUID REFERENCES classes(id) ON DELETE CASCADE,
  cohort_id         UUID REFERENCES cohorts(id) ON DELETE SET NULL,
  notification_type TEXT NOT NULL CHECK (notification_type IN (
    'class_reminder', 'group_announcement', 'custom'
  )),
  target_type       TEXT NOT NULL DEFAULT 'both' CHECK (target_type IN (
    'group', 'individual', 'both'
  )),
  message_template  TEXT NOT NULL,
  hours_before      SMALLINT NOT NULL DEFAULT 2 CHECK (hours_before > 0),
  active            BOOLEAN DEFAULT true,
  last_fired_at     TIMESTAMPTZ,
  next_fire_at      TIMESTAMPTZ,
  created_by        UUID REFERENCES auth.users(id),
  created_at        TIMESTAMPTZ DEFAULT now(),
  updated_at        TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_notification_schedules_active   ON notification_schedules(active);
CREATE INDEX IF NOT EXISTS idx_notification_schedules_class    ON notification_schedules(class_id);
CREATE INDEX IF NOT EXISTS idx_notification_schedules_next     ON notification_schedules(next_fire_at) WHERE active = true;

DROP TRIGGER IF EXISTS notification_schedules_updated_at ON notification_schedules;
CREATE TRIGGER notification_schedules_updated_at
  BEFORE UPDATE ON notification_schedules
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── 3. RLS ───
ALTER TABLE notification_schedules ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin read notification_schedules" ON notification_schedules;
CREATE POLICY "Admin read notification_schedules" ON notification_schedules
  FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin insert notification_schedules" ON notification_schedules;
CREATE POLICY "Admin insert notification_schedules" ON notification_schedules
  FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin update notification_schedules" ON notification_schedules;
CREATE POLICY "Admin update notification_schedules" ON notification_schedules
  FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin delete notification_schedules" ON notification_schedules;
CREATE POLICY "Admin delete notification_schedules" ON notification_schedules
  FOR DELETE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── 4. FUNCTION: calculate next_fire_at ───
-- Returns the next UTC datetime when weekday+time_start occurs, minus hours_before.
-- Uses America/Sao_Paulo timezone (UTC-3).
CREATE OR REPLACE FUNCTION calculate_next_fire_at(
  p_weekday     INTEGER,  -- 0=Sun,1=Mon,...,6=Sat (matches classes.weekday)
  p_time_start  TIME,     -- local class start time
  p_hours_before SMALLINT
) RETURNS TIMESTAMPTZ AS $$
DECLARE
  v_now_local   TIMESTAMPTZ := now() AT TIME ZONE 'America/Sao_Paulo';
  v_today_dow   INTEGER     := EXTRACT(DOW FROM v_now_local)::INTEGER;
  v_days_ahead  INTEGER     := (p_weekday - v_today_dow + 7) % 7;
  v_next_date   DATE        := (v_now_local::DATE) + v_days_ahead;
  v_fire_local  TIMESTAMPTZ := (v_next_date + p_time_start - (p_hours_before || ' hours')::INTERVAL)
                                 AT TIME ZONE 'America/Sao_Paulo';
BEGIN
  -- If calculated time is in the past (same weekday, already passed), advance 7 days
  IF v_fire_local <= now() THEN
    v_fire_local := v_fire_local + INTERVAL '7 days';
  END IF;
  RETURN v_fire_local;
END;
$$ LANGUAGE plpgsql STABLE;

-- ─── 5. FUNCTION: process_notification_schedules ───
-- Called by pg_cron every 15 minutes.
-- For each active schedule due to fire: insert notification + update timestamps.
CREATE OR REPLACE FUNCTION process_notification_schedules() RETURNS void AS $$
DECLARE
  v_schedule  RECORD;
  v_class     RECORD;
  v_cohort    RECORD;
BEGIN
  FOR v_schedule IN
    SELECT s.*
    FROM notification_schedules s
    WHERE s.active = true
      AND s.next_fire_at IS NOT NULL
      AND s.next_fire_at <= now()
      AND (s.last_fired_at IS NULL OR s.next_fire_at > s.last_fired_at)
  LOOP
    -- Fetch class data
    SELECT id, weekday, time_start, whatsapp_group_jid AS group_jid
    INTO v_class
    FROM classes c
    LEFT JOIN class_cohorts cc ON cc.class_id = c.id AND cc.cohort_id = v_schedule.cohort_id
    WHERE c.id = v_schedule.class_id;

    -- Fetch cohort group JID if needed
    SELECT whatsapp_group_jid INTO v_cohort
    FROM cohorts WHERE id = v_schedule.cohort_id;

    -- Duplicate guard: skip if notification already created in last 2 hours for same class+type
    IF NOT EXISTS (
      SELECT 1 FROM notifications
      WHERE class_id = v_schedule.class_id
        AND type = v_schedule.notification_type
        AND created_at > now() - INTERVAL '2 hours'
    ) THEN
      -- Insert notification (webhook fires automatically via pg_net trigger)
      INSERT INTO notifications (
        type,
        class_id,
        cohort_id,
        target_type,
        target_group_jid,
        message_template,
        status,
        metadata
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

      -- Mark as fired
      UPDATE notification_schedules
      SET last_fired_at = now(),
          next_fire_at  = calculate_next_fire_at(
            (SELECT weekday FROM classes WHERE id = v_schedule.class_id),
            (SELECT time_start FROM classes WHERE id = v_schedule.class_id),
            v_schedule.hours_before
          )
      WHERE id = v_schedule.id;
    END IF;
  END LOOP;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ─── 6. REGISTER pg_cron JOB ───
-- Runs every 15 minutes to check and fire scheduled notifications
SELECT cron.schedule(
  'notify-schedules',
  '*/15 * * * *',
  'SELECT process_notification_schedules()'
);
