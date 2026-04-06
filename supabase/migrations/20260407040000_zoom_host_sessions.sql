-- ═══════════════════════════════════════════════════════
-- ZOOM HOST SESSIONS — Pool de hosts para sessões simultâneas
-- ═══════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS zoom_host_sessions (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  host_email   TEXT NOT NULL,
  meeting_id   TEXT,
  zoom_uuid    TEXT,
  topic        TEXT,
  started_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  released_at  TIMESTAMPTZ,                          -- NULL = sessão ativa
  released_by  TEXT CHECK (released_by IN ('webhook','timeout','manual')),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_zoom_host_sessions_host    ON zoom_host_sessions(host_email);
CREATE INDEX idx_zoom_host_sessions_active  ON zoom_host_sessions(host_email) WHERE released_at IS NULL;
CREATE INDEX idx_zoom_host_sessions_meeting ON zoom_host_sessions(meeting_id);

-- RLS
ALTER TABLE zoom_host_sessions ENABLE ROW LEVEL SECURITY;
CREATE POLICY "admin_all" ON zoom_host_sessions FOR ALL
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ═══════════════════════════════════════════════════════
-- SAFETY NET: libera hosts presos há mais de 6h sem webhook
-- Roda a cada hora via pg_cron
-- ═══════════════════════════════════════════════════════
SELECT cron.schedule(
  'zoom-ghost-session-cleanup',
  '0 * * * *',
  $$
    UPDATE zoom_host_sessions
    SET
      released_at = now(),
      released_by = 'timeout'
    WHERE
      released_at IS NULL
      AND started_at < now() - INTERVAL '6 hours';
  $$
);
