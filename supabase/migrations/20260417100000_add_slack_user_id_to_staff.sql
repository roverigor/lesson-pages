-- Add slack_user_id to staff table for Slack DM integration
-- Human-in-the-loop: alerts go to Igor first, then DM to individual staff

ALTER TABLE staff
ADD COLUMN IF NOT EXISTS slack_user_id text,
ADD COLUMN IF NOT EXISTS notification_channel text DEFAULT 'whatsapp'
  CHECK (notification_channel IN ('whatsapp', 'slack', 'both'));

-- Index for quick lookup by slack_user_id
CREATE INDEX IF NOT EXISTS idx_staff_slack_user_id ON staff (slack_user_id) WHERE slack_user_id IS NOT NULL;

COMMENT ON COLUMN staff.slack_user_id IS 'Slack user ID (e.g., U08H381HY66) for DM notifications';
COMMENT ON COLUMN staff.notification_channel IS 'Preferred notification channel: whatsapp, slack, or both';
