-- ══════════════════════════════════════════════════════════════
-- Migration: Unify staff table into mentors
-- Problem: Two tables (mentors + staff) for the same people,
--          with different IDs, causing Slack notifications to fail.
-- Solution: Add slack columns to mentors, migrate data, drop staff.
-- ══════════════════════════════════════════════════════════════

-- Step 1: Add columns to mentors (if not exists)
ALTER TABLE mentors ADD COLUMN IF NOT EXISTS slack_user_id text;
ALTER TABLE mentors ADD COLUMN IF NOT EXISTS notification_channel text DEFAULT 'whatsapp';

-- Add check constraint (same as staff had)
DO $$ BEGIN
  ALTER TABLE mentors ADD CONSTRAINT mentors_notification_channel_check
    CHECK (notification_channel IN ('whatsapp', 'slack', 'both'));
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

-- Step 2: Migrate slack_user_id from staff to mentors (match by name)
UPDATE mentors m
SET
  slack_user_id = s.slack_user_id,
  notification_channel = COALESCE(s.notification_channel, 'whatsapp'),
  email = COALESCE(m.email, s.email)
FROM staff s
WHERE m.name = s.name;

-- Step 3: Handle Klaus (different name in staff vs mentors)
-- staff has "Klaus Deor" with email klausdraeger@academialendaria.ai
-- mentors has "Klaus Draeger"
UPDATE mentors
SET
  slack_user_id = (SELECT slack_user_id FROM staff WHERE name = 'Klaus Deor'),
  notification_channel = (SELECT notification_channel FROM staff WHERE name = 'Klaus Deor'),
  email = COALESCE(email, (SELECT email FROM staff WHERE name = 'Klaus Deor'))
WHERE name = 'Klaus Draeger'
  AND slack_user_id IS NULL;

-- Step 4: Create index on slack_user_id
CREATE INDEX IF NOT EXISTS idx_mentors_slack_user_id ON mentors (slack_user_id) WHERE slack_user_id IS NOT NULL;

-- Step 5: Drop staff table
DROP TABLE IF EXISTS staff CASCADE;

-- Step 6: Verify migration
DO $$
DECLARE
  cnt_with_slack integer;
  cnt_total integer;
BEGIN
  SELECT count(*) INTO cnt_total FROM mentors;
  SELECT count(*) INTO cnt_with_slack FROM mentors WHERE slack_user_id IS NOT NULL;
  RAISE NOTICE 'Migration complete: % mentors total, % with slack_user_id', cnt_total, cnt_with_slack;
END $$;
