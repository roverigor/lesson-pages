-- ═══════════════════════════════════════════════════════════
-- Story 12.3 — WhatsApp Group Members Auto-Sync
-- pg_cron at 04:00 AM UTC-3 (07:00 UTC) + unique constraint
-- ═══════════════════════════════════════════════════════════

-- Ensure idempotent inserts in student_cohorts
CREATE UNIQUE INDEX IF NOT EXISTS idx_student_cohorts_unique
  ON student_cohorts (student_id, cohort_id);

-- Wrapper function: reads URL/key from app_config, calls edge function
CREATE OR REPLACE FUNCTION public.trigger_wa_group_sync()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  fn_url   TEXT;
  svc_key  TEXT;
BEGIN
  SELECT value INTO fn_url  FROM public.app_config WHERE key = 'sync_wa_group_url';
  SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';

  IF fn_url IS NULL OR fn_url = '' THEN
    RAISE WARNING 'wa_group_sync: sync_wa_group_url not set in app_config';
    RETURN;
  END IF;

  IF svc_key IS NULL OR svc_key = '' THEN
    RAISE WARNING 'wa_group_sync: supabase_service_key not set in app_config';
    RETURN;
  END IF;

  PERFORM net.http_post(
    url     := fn_url,
    body    := '{"action":"auto_sync"}'::jsonb,
    headers := json_build_object(
      'Authorization', 'Bearer ' || svc_key,
      'Content-Type',  'application/json'
    )::jsonb
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.trigger_wa_group_sync() TO service_role;

-- Schedule: 04:00 AM BRT = 07:00 UTC
SELECT cron.schedule(
  'wa-group-sync',
  '0 7 * * *',
  $$ SELECT public.trigger_wa_group_sync(); $$
);
