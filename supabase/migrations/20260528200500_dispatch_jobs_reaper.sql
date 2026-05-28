-- ═══════════════════════════════════════════════════════════════════════════
-- Fix 2 (Story 22.10) — Reaper jobs travados + last_progress_at + RPC
--
-- Incidente 27/05: dispatch-class-nps abortou time budget 130s sem unlock,
-- deixou job in_progress órfão. Cron */5min skip pq WHERE status='pending'.
-- Resultado: 78 DMs T2 nunca saíram.
--
-- Fix v18 (edge fn): graceful abort marca status=pending no caminho
-- time-budget. Mas crash em outros pontos (RPC fail, network, deploy
-- mid-flight) ainda deixa stuck.
--
-- Esta migration:
--   1. ADD COLUMN last_progress_at em nps_class_dispatch_jobs (+ outras
--      tables com lock job-level)
--   2. RPC reaper reclaim_stuck_dispatch_jobs() — recupera jobs cuja
--      última progresso > N minutos. SECURITY DEFINER + admin gated.
--   3. RPC pode ser chamada manualmente da UI /admin/nps-monitor OU
--      automaticamente pelo dispatcher inline antes do lock.
--
-- Rollback:
--   DROP FUNCTION reclaim_stuck_dispatch_jobs;
--   ALTER TABLE nps_class_dispatch_jobs DROP COLUMN last_progress_at;
--   ALTER TABLE class_reminder_batches DROP COLUMN last_progress_at;
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. ADD COLUMN last_progress_at (NULL ok — default backfill)
ALTER TABLE public.nps_class_dispatch_jobs
  ADD COLUMN IF NOT EXISTS last_progress_at TIMESTAMPTZ;

COMMENT ON COLUMN public.nps_class_dispatch_jobs.last_progress_at IS
  'Story 22.10 Fix 2: timestamp último checkpoint do dispatcher. Reaper usa pra detectar jobs travados.';

-- Defesa em profundidade: class_reminder_batches
ALTER TABLE public.class_reminder_batches
  ADD COLUMN IF NOT EXISTS last_progress_at TIMESTAMPTZ;

COMMENT ON COLUMN public.class_reminder_batches.last_progress_at IS
  'Story 22.10 Fix 2: checkpoint dispatcher class-reminders. Defesa preventiva (batch usa link-level lock granular).';

-- 2. RPC reaper — recupera jobs stuck > N minutos
CREATE OR REPLACE FUNCTION public.reclaim_stuck_dispatch_jobs(
  p_minutes INT DEFAULT 10
)
RETURNS TABLE (
  table_name TEXT,
  job_id UUID,
  previous_status TEXT,
  previous_started_at TIMESTAMPTZ,
  recovered_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_threshold TIMESTAMPTZ;
  v_count_nps INT := 0;
  v_count_reminders INT := 0;
BEGIN
  -- Admin gate (relax pra cron service_role + admin user)
  IF NOT (
    auth.role() = 'service_role'
    OR (auth.jwt() ->> 'role') IN ('admin', 'cs')
  ) THEN
    RAISE EXCEPTION 'unauthorized: requires admin/cs or service_role';
  END IF;

  v_threshold := now() - (p_minutes || ' minutes')::interval;

  -- nps_class_dispatch_jobs
  RETURN QUERY
  WITH recovered AS (
    UPDATE public.nps_class_dispatch_jobs
       SET status = 'pending',
           started_at = NULL,
           error_detail = COALESCE(error_detail, '') ||
             '|reaper_recovered_at_' || now()::text,
           scheduled_at = now()
     WHERE status = 'in_progress'
       AND COALESCE(last_progress_at, started_at) < v_threshold
     RETURNING id, started_at
  )
  SELECT 'nps_class_dispatch_jobs'::TEXT,
         r.id,
         'in_progress'::TEXT,
         r.started_at,
         now()
    FROM recovered r;

  GET DIAGNOSTICS v_count_nps = ROW_COUNT;

  -- Slack alert via existing helper (best-effort; fail-safe)
  IF v_count_nps > 0 THEN
    BEGIN
      PERFORM public.send_slack_alert(
        'reaper_recovered_jobs',
        format('[reaper] %s nps_class_dispatch_jobs recuperados (> %s min stuck)',
               v_count_nps, p_minutes)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'reaper: slack alert failed (non-fatal): %', SQLERRM;
    END;
  END IF;

  -- Log audit
  INSERT INTO public.audit_log (event_type, details, created_at)
  VALUES (
    'reaper_dispatch_jobs',
    jsonb_build_object(
      'nps_recovered', v_count_nps,
      'threshold_minutes', p_minutes,
      'caller', current_user
    ),
    now()
  );

  RETURN;
END;
$$;

REVOKE ALL ON FUNCTION public.reclaim_stuck_dispatch_jobs(INT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.reclaim_stuck_dispatch_jobs(INT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reclaim_stuck_dispatch_jobs(INT) TO service_role;

COMMENT ON FUNCTION public.reclaim_stuck_dispatch_jobs IS
  'Story 22.10 Fix 2: recupera jobs dispatch stuck status=in_progress > N min. Admin-gated. Chamável manualmente da UI nps-monitor OU automaticamente inline pelo dispatcher.';
