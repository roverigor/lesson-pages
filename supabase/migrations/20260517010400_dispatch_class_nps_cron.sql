-- ═══════════════════════════════════════════════════════════════════════════
-- P3 — Register dispatch-class-nps endpoint URL in app_config
--
-- ⚠️ Cron schedule INTENTIONALLY NOT created here (NPS.D.5 — architect review
-- 2026-05-17). Per CLAUDE.md NON-NEGOTIABLE, scheduling a worker of envio
-- externo requires explicit human approval — see runbook step 6 in
-- docs/runbooks/nps-post-class-activation.md to register cron AFTER flag flip.
--
-- This migration is safe to apply at any time — only writes a config row.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- Register endpoint URL (idempotent override)
INSERT INTO public.app_config (key, value)
VALUES ('dispatch_class_nps_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/dispatch-class-nps')
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

-- Defensive cleanup: if any previous version of this migration installed a
-- premature cron schedule (e.g. earlier draft), remove it.
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'dispatch-class-nps-tick') THEN
    PERFORM cron.unschedule('dispatch-class-nps-tick');
    RAISE NOTICE 'Removed premature cron job dispatch-class-nps-tick; reschedule via runbook.';
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'cron.unschedule skipped: %', SQLERRM;
END $$;

COMMIT;

-- ─── How to enable the worker AFTER human-approved activation ────────────
-- (Copy/paste into Supabase SQL editor; do NOT include in migrations.)
--
-- SELECT cron.schedule(
--   'dispatch-class-nps-tick',
--   '*/5 * * * *',
--   $cron$
--   DO $inner$
--   DECLARE
--     fn_url  TEXT;
--     svc_key TEXT;
--   BEGIN
--     SELECT value INTO fn_url  FROM public.app_config WHERE key = 'dispatch_class_nps_url';
--     SELECT value INTO svc_key FROM public.app_config WHERE key = 'supabase_service_key';
--     IF fn_url IS NOT NULL AND svc_key IS NOT NULL THEN
--       PERFORM net.http_post(
--         url     := fn_url,
--         body    := '{}'::jsonb,
--         headers := json_build_object(
--           'Authorization', 'Bearer ' || svc_key,
--           'Content-Type',  'application/json'
--         )::jsonb
--       );
--     END IF;
--   END;
--   $inner$;
--   $cron$
-- );
--
-- ─── Rollback (disable worker) ────────────────────────────────────────────
-- SELECT cron.unschedule('dispatch-class-nps-tick');
