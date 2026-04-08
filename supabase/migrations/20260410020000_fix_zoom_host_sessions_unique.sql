-- Fix: add UNIQUE constraint on zoom_host_sessions.meeting_id
-- Required for the meeting.started upsert (onConflict: "meeting_id") to work correctly.
-- Without this constraint, PostgREST returns an error on every upsert attempt.

ALTER TABLE public.zoom_host_sessions
  ADD CONSTRAINT zoom_host_sessions_meeting_id_key UNIQUE (meeting_id);
