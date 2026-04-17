-- Notification queue for human-in-the-loop approval flow
-- Alerts are queued here, sent to Igor for approval via Slack,
-- then dispatched to individual staff DMs when approved.

CREATE TABLE IF NOT EXISTS notification_queue (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  type text NOT NULL CHECK (type IN ('attendance_alert', 'survey_dispatch', 'custom')),
  title text NOT NULL,
  payload jsonb NOT NULL DEFAULT '{}',
  recipients jsonb NOT NULL DEFAULT '[]',
  status text NOT NULL DEFAULT 'pending_approval'
    CHECK (status IN ('pending_approval', 'approved', 'rejected', 'sending', 'sent', 'failed')),
  slack_message_ts text,
  requested_at timestamptz NOT NULL DEFAULT now(),
  approved_at timestamptz,
  sent_at timestamptz,
  created_by text DEFAULT 'system'
);

CREATE INDEX idx_notification_queue_status ON notification_queue (status);
CREATE INDEX idx_notification_queue_type ON notification_queue (type);

COMMENT ON TABLE notification_queue IS 'Queue for staff notifications with human-in-the-loop approval via Slack';
COMMENT ON COLUMN notification_queue.slack_message_ts IS 'Slack message timestamp used to match approval button callbacks';
COMMENT ON COLUMN notification_queue.recipients IS 'Array of {staff_id, slack_user_id, name} objects';
COMMENT ON COLUMN notification_queue.payload IS 'Notification content: message text, template data, metadata';
