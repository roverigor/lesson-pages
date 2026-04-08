-- ═══════════════════════════════════════════════════════
-- LESSON PAGES — Scheduled Notifications
-- Adds scheduled_at column + scheduled status + pg_cron job
-- ═══════════════════════════════════════════════════════

-- 1. Add scheduled_at column
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ;

-- 2. Extend status CHECK to include 'scheduled'
ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_status_check;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_status_check CHECK (status IN (
    'scheduled',   -- Agendado para envio futuro
    'pending',     -- Aguardando processamento
    'processing',  -- Edge Function processando
    'sent',        -- Enviado com sucesso
    'partial',     -- Envio parcial
    'failed',      -- Falhou
    'cancelled'    -- Cancelado
  ));

-- 3. Index for scheduled lookup
CREATE INDEX IF NOT EXISTS idx_notifications_scheduled
  ON public.notifications(scheduled_at)
  WHERE status = 'scheduled';

-- 4. Modify trigger to also fire on UPDATE when status changes to 'pending'
CREATE OR REPLACE FUNCTION public.notify_whatsapp_on_insert()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_url  TEXT := current_setting('app.supabase_url', true) || '/functions/v1/send-whatsapp';
  v_key  TEXT := current_setting('app.supabase_service_role_key', true);
BEGIN
  -- Fire on INSERT or when status transitions to pending via UPDATE
  IF (TG_OP = 'INSERT' AND NEW.status = 'pending') OR
     (TG_OP = 'UPDATE' AND NEW.status = 'pending' AND OLD.status = 'scheduled') THEN
    PERFORM net.http_post(
      url     := v_url,
      body    := jsonb_build_object('notification_id', NEW.id),
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_key,
        'apikey', v_key
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

-- Drop old INSERT-only trigger and recreate for INSERT + UPDATE
DROP TRIGGER IF EXISTS "notify-whatsapp-on-pending" ON public.notifications;

CREATE TRIGGER "notify-whatsapp-on-pending"
  AFTER INSERT OR UPDATE OF status
  ON public.notifications
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_whatsapp_on_insert();

-- 5. Function to process scheduled notifications (called by pg_cron at 8am BRT = 11:00 UTC)
CREATE OR REPLACE FUNCTION public.process_scheduled_notifications()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER AS $$
BEGIN
  UPDATE public.notifications
  SET status = 'pending'
  WHERE status = 'scheduled'
    AND scheduled_at <= now();
END;
$$;

-- 6. pg_cron job: run at 11:00 UTC (08:00 BRT) every day
SELECT cron.schedule(
  'process-scheduled-notifications',
  '0 11 * * *',
  $$SELECT public.process_scheduled_notifications();$$
);
