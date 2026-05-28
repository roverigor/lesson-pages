-- ═══════════════════════════════════════════════════════════════════════════
-- Fix 3A (Story 22.10) — Alerta enqueue zero: trigger detecta meetings que
-- terminam SEM gerar jobs apesar de haver alunos esperados.
--
-- Caso real T5 27/05: trigger pegou class DUP-DESATIVADA sem cohorts →
-- 0 enqueues silenciosos. Esta versão adiciona Slack alert quando:
--   - meeting.processed flip true
--   - class resolvida ativa OK
--   - mas v_jobs_enqueued = 0 (cohorts vazios)
--
-- Combina com migration anterior (20260528120000) que já filtra active=true.
--
-- Rollback: re-apply migration 20260528120000 versão sem alerta.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_enqueue_nps_after_zoom_processed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_class_id      UUID;
  v_class_name    TEXT;
  v_session_date  DATE;
  v_cohort_rec    RECORD;
  v_enqueue_result JSONB;
  v_jobs_enqueued INT := 0;
  v_min_duration  INT;
  v_duration      INT;
  v_cohorts_count INT := 0;
BEGIN
  -- Only fire when processed flips false → true
  IF NOT (NEW.processed = true AND COALESCE(OLD.processed, false) = false) THEN
    RETURN NEW;
  END IF;

  -- Anti test-meeting gate (>=60min default)
  v_min_duration := public.nps_config_int('nps_dispatch_min_duration_minutes', 60);
  v_duration := NEW.duration_minutes;
  IF v_duration IS NULL AND NEW.start_time IS NOT NULL AND NEW.end_time IS NOT NULL THEN
    v_duration := EXTRACT(EPOCH FROM (NEW.end_time - NEW.start_time))::int / 60;
  END IF;

  IF v_min_duration > 0 AND v_duration IS NOT NULL AND v_duration < v_min_duration THEN
    RAISE NOTICE 'nps-hook: SKIPPED meeting % — duration % min < threshold % min',
      NEW.id, v_duration, v_min_duration;
    RETURN NEW;
  END IF;

  v_session_date := (NEW.start_time AT TIME ZONE 'America/Sao_Paulo')::date;

  -- HARDENED resolve: filter active=true + determinístico
  SELECT c.id, c.name INTO v_class_id, v_class_name
  FROM public.classes c
  WHERE c.zoom_meeting_id = NEW.zoom_meeting_id
    AND c.active = true
  ORDER BY c.created_at DESC
  LIMIT 1;

  IF v_class_id IS NULL THEN
    RAISE WARNING 'nps-hook: no active class found for zoom_meeting_id=%', NEW.zoom_meeting_id;
    -- Fix 3 Alerta A — meeting sem class ativa (provável DUP cleanup needed)
    BEGIN
      PERFORM public.send_slack_alert(
        'nps_enqueue_no_class:' || NEW.zoom_meeting_id,
        format('🚨 [nps-hook] meeting=%s terminou (%smin) mas NENHUMA classe ativa encontrada com zoom_meeting_id=%s. Provável DUP-DESATIVADA. Auditar classes table.',
               NEW.id, v_duration, NEW.zoom_meeting_id)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'nps-hook: slack alert failed (non-fatal): %', SQLERRM;
    END;
    RETURN NEW;
  END IF;

  -- Backfill zoom_meetings.class_id se ainda null
  IF NEW.class_id IS NULL THEN
    UPDATE public.zoom_meetings SET class_id = v_class_id WHERE id = NEW.id;
  END IF;

  -- Count cohorts vinculadas (pra detectar enqueue zero quando class OK)
  SELECT count(*) INTO v_cohorts_count
  FROM public.class_cohort_access cca
  WHERE cca.class_id = v_class_id;

  -- Multi-cohort loop via class_cohort_access
  FOR v_cohort_rec IN
    SELECT cca.cohort_id
      FROM public.class_cohort_access cca
     WHERE cca.class_id = v_class_id
  LOOP
    BEGIN
      SELECT public.enqueue_nps_class_dispatch(
        v_class_id, v_cohort_rec.cohort_id, v_session_date, NEW.zoom_meeting_id
      ) INTO v_enqueue_result;

      IF (v_enqueue_result->>'enqueued')::boolean THEN
        v_jobs_enqueued := v_jobs_enqueued + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'nps-hook: enqueue failed meeting=% cohort=% err=%',
        NEW.id, v_cohort_rec.cohort_id, SQLERRM;
    END;
  END LOOP;

  -- Fix 3 Alerta A — enqueue zero: class OK + cohorts existem mas 0 jobs criados.
  -- Cobre casos: cooldown bloqueou, dedup bloqueou, flag desligada, RPC falhou silent.
  IF v_jobs_enqueued = 0 AND v_cohorts_count > 0 THEN
    BEGIN
      PERFORM public.send_slack_alert(
        'nps_enqueue_zero:' || v_class_id::text || ':' || v_session_date::text,
        format('⚠️ [nps-hook] meeting=%s class=%s (%s) terminou mas 0 jobs criados apesar de %s cohorts vinculadas. Verificar nps_dispatch_enabled flag + cooldown + dedup.',
               NEW.id, v_class_id, COALESCE(v_class_name, '?'), v_cohorts_count)
      );
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'nps-hook: slack alert A failed (non-fatal): %', SQLERRM;
    END;
  END IF;

  RAISE NOTICE 'nps-hook: meeting=% class=% cohorts=% enqueued=%',
    NEW.id, v_class_id, v_cohorts_count, v_jobs_enqueued;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_enqueue_nps_after_zoom_processed IS
  'Story 22.10 Fix 3: enfileira jobs NPS quando zoom_meetings.processed=true. Filtra c.active=true (Fix migration 20260528120000). Dispara Slack alert quando: (a) zero classes ativas com matching zoom_meeting_id; (b) class OK + cohorts existem mas 0 enqueues.';
