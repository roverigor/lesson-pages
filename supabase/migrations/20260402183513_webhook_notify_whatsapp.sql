-- ═══════════════════════════════════════
-- LESSON PAGES — Database Webhook: notify-whatsapp-on-pending
-- Story 1.3 — EPIC-001
-- Triggers send-whatsapp Edge Function on every INSERT in notifications table
-- Edge Function guards internally: only processes status='pending'
-- Uses pg_net (net schema) since supabase_functions schema is not available
-- ═══════════════════════════════════════

-- Drop trigger and function if they exist (idempotent)
DROP TRIGGER IF EXISTS "notify-whatsapp-on-pending" ON public.notifications;
DROP FUNCTION IF EXISTS public.notify_whatsapp_on_insert();

-- Trigger function: fires asynchronous HTTP POST via pg_net on every notification INSERT
CREATE OR REPLACE FUNCTION public.notify_whatsapp_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM net.http_post(
    url     := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/send-whatsapp',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdwdWZjaXBrYWpwcHlrbW5tZGVoIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc3NDM3MTU3OCwiZXhwIjoyMDg5OTQ3NTc4fQ.DCTw5wwbkA9A1QPbby3aGkoaGpHySqLDTwv-yyn13qE'
    ),
    body    := jsonb_build_object(
      'type',   TG_OP,
      'table',  TG_TABLE_NAME,
      'schema', TG_TABLE_SCHEMA,
      'record', row_to_json(NEW)::jsonb
    ),
    timeout_milliseconds := 5000
  );
  RETURN NEW;
END;
$$;

-- Trigger: fires AFTER INSERT on notifications
CREATE TRIGGER "notify-whatsapp-on-pending"
  AFTER INSERT
  ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_whatsapp_on_insert();
