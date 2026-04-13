-- Fix: Remove hardcoded service_role key from trigger function
-- Reads from app_config instead (key already stored there)

CREATE OR REPLACE FUNCTION public.notify_whatsapp_on_insert()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  _service_key text;
BEGIN
  SELECT value INTO _service_key FROM app_config WHERE key = 'supabase_service_key';

  PERFORM net.http_post(
    url     := 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/send-whatsapp',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || _service_key
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
