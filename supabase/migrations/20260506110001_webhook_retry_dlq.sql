-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-016 Story 16.10 — Webhook retry + Dead-Letter Queue
-- Adiciona retry policy automática pra ac_purchase_events que falham.
-- Backoff exponencial: 5min / 30min / 2h. Após 3 retries, vai pra DLQ.
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE public.ac_purchase_events
  ADD COLUMN IF NOT EXISTS retry_count integer DEFAULT 0,
  ADD COLUMN IF NOT EXISTS next_retry_at timestamptz,
  ADD COLUMN IF NOT EXISTS last_error text,
  ADD COLUMN IF NOT EXISTS dlq boolean DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_ac_events_retry_pending
  ON public.ac_purchase_events (next_retry_at)
  WHERE status = 'failed' AND dlq = false AND retry_count < 3;

CREATE INDEX IF NOT EXISTS idx_ac_events_dlq
  ON public.ac_purchase_events (created_at DESC)
  WHERE dlq = true;

-- ─── Function: marca event como failed + agenda retry com backoff ──────
CREATE OR REPLACE FUNCTION public.mark_ac_event_failed(p_event_id uuid, p_error text)
RETURNS void LANGUAGE plpgsql AS $$
DECLARE
  v_retry_count integer;
  v_backoff_minutes integer;
BEGIN
  SELECT retry_count INTO v_retry_count FROM public.ac_purchase_events WHERE id = p_event_id;

  -- Backoff exponencial: 5min, 30min, 2h
  v_backoff_minutes := CASE
    WHEN v_retry_count = 0 THEN 5
    WHEN v_retry_count = 1 THEN 30
    WHEN v_retry_count = 2 THEN 120
    ELSE NULL
  END;

  IF v_backoff_minutes IS NULL THEN
    -- Esgotou retries → DLQ
    UPDATE public.ac_purchase_events
       SET status = 'failed', dlq = true, last_error = p_error, retry_count = retry_count + 1
     WHERE id = p_event_id;
  ELSE
    UPDATE public.ac_purchase_events
       SET status = 'failed',
           last_error = p_error,
           retry_count = retry_count + 1,
           next_retry_at = now() + (v_backoff_minutes || ' minutes')::interval
     WHERE id = p_event_id;
  END IF;
END $$;

-- ─── Function: process_ac_retries() — chamada por pg_cron ──────────────
-- Pega eventos failed elegíveis pra retry, marca como pending, deixa worker reprocessar.
CREATE OR REPLACE FUNCTION public.process_ac_retries()
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  v_count integer := 0;
BEGIN
  WITH eligible AS (
    SELECT id FROM public.ac_purchase_events
    WHERE status = 'failed'
      AND dlq = false
      AND retry_count < 3
      AND next_retry_at <= now()
    LIMIT 50
    FOR UPDATE SKIP LOCKED
  )
  UPDATE public.ac_purchase_events SET status = 'pending', next_retry_at = NULL
  WHERE id IN (SELECT id FROM eligible);

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN jsonb_build_object('reprocessed', v_count, 'at', now());
END $$;

GRANT EXECUTE ON FUNCTION public.process_ac_retries() TO service_role;
GRANT EXECUTE ON FUNCTION public.mark_ac_event_failed(uuid, text) TO service_role;

-- ─── pg_cron: roda retry processor a cada 5 min ────────────────────────
SELECT cron.schedule(
  'epic016-ac-retries',
  '*/5 * * * *',
  $$ SELECT public.process_ac_retries(); $$
) WHERE NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'epic016-ac-retries');

COMMENT ON COLUMN public.ac_purchase_events.retry_count IS
  'EPIC-016 Story 16.10: incrementado a cada failed. Após 3 → dlq=true.';

COMMENT ON FUNCTION public.process_ac_retries() IS
  'Worker pg_cron 5min: marca eventos failed elegíveis como pending pra reprocessamento.';
