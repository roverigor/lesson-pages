-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: trigger trg_enqueue_nps_after_zoom_processed pega DUP-DESATIVADA
-- Caso real: aula T5 27/05 → 2 classes com mesmo zoom_meeting_id (uma DUP
-- desativada). Trigger fazia LIMIT 1 sem filtro → pegou classe inativa →
-- 0 jobs criados → 0 DMs enviadas.
--
-- Fix: filtrar c.active = true + ORDER BY determinístico (created_at DESC).
--
-- Refs: docs/sessions/2026-05-28-nps-t5-root-cause.md (em criação)
--       commit cleanup paralelo: classes.zoom_meeting_id=null em DUP
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_enqueue_nps_after_zoom_processed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_class_id      UUID;
  v_session_date  DATE;
  v_cohort_rec    RECORD;
  v_enqueue_result JSONB;
  v_jobs_enqueued INT := 0;
  v_min_duration  INT;
  v_duration      INT;
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

  -- ─── HARDENED resolve: filter active=true + determinístico ───────────────
  -- Previne match contra classes [DUP-DESATIVADA] que ainda têm
  -- zoom_meeting_id setado mas active=false. Priorização: classes mais
  -- recentes (created_at DESC) primeiro pra cobrir caso de re-criação.
  SELECT c.id INTO v_class_id
  FROM public.classes c
  WHERE c.zoom_meeting_id = NEW.zoom_meeting_id
    AND c.active = true
  ORDER BY c.created_at DESC
  LIMIT 1;

  -- Fallback: se nenhuma class ativa, log warning + retorna (não enqueue)
  IF v_class_id IS NULL THEN
    RAISE WARNING 'nps-hook: no active class found for zoom_meeting_id=%', NEW.zoom_meeting_id;
    RETURN NEW;
  END IF;

  -- Backfill zoom_meetings.class_id se ainda null (session_index correto)
  IF NEW.class_id IS NULL THEN
    UPDATE public.zoom_meetings SET class_id = v_class_id WHERE id = NEW.id;
  END IF;

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

  RAISE NOTICE 'nps-hook: meeting=% class=% enqueued=% jobs',
    NEW.id, v_class_id, v_jobs_enqueued;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_enqueue_nps_after_zoom_processed IS
  'Enfileira jobs NPS quando zoom_meetings.processed=true. Filtra c.active=true pra ignorar classes DUP-DESATIVADA com zoom_meeting_id ainda setado. Hardened 2026-05-28 após incidente T5 sem envio.';
