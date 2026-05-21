-- ═══════════════════════════════════════════════════════════════════════════
-- trg_enqueue_nps_after_zoom_processed: agora seta zoom_meetings.class_id
-- automaticamente ao processar.
--
-- Bug: label "Aula NN" em /admin/nps-results/ dependia de
--   zoom_meetings.class_id populated mas trigger nunca setava.
--   Resultado: session_index sempre 1 → "Aula 01" mesmo na N-ésima aula.
--
-- Fix: trigger agora UPDATE zoom_meetings.class_id após match.
-- Plus backfill rotina pra registros legados (rodada uma vez no apply).
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

  -- Anti test-meeting gate (>=60min)
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

  -- Resolve class_id via classes.zoom_meeting_id direct match
  SELECT c.id INTO v_class_id
  FROM public.classes c
  WHERE c.zoom_meeting_id = NEW.zoom_meeting_id
  LIMIT 1;

  -- ─── NEW: backfill zoom_meetings.class_id se ainda null ──────────────
  -- Garante session_index correto em nps_results_by_survey
  IF v_class_id IS NOT NULL AND NEW.class_id IS NULL THEN
    UPDATE public.zoom_meetings SET class_id = v_class_id WHERE id = NEW.id;
  END IF;

  -- Multi-cohort loop via class_cohort_access
  IF v_class_id IS NOT NULL THEN
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
  END IF;

  -- Legacy fallback (single cohort no NEW)
  IF v_class_id IS NULL AND NEW.cohort_id IS NOT NULL THEN
    BEGIN
      SELECT public.enqueue_nps_class_dispatch(
        NULL, NEW.cohort_id, v_session_date, NEW.zoom_meeting_id
      ) INTO v_enqueue_result;
      IF (v_enqueue_result->>'enqueued')::boolean THEN
        v_jobs_enqueued := v_jobs_enqueued + 1;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'nps-hook: legacy enqueue failed meeting=% err=%', NEW.id, SQLERRM;
    END;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_enqueue_nps_after_zoom_processed() IS
  'On zoom_meetings.processed=true: gate duration >=60min, backfill class_id, enqueue NPS dispatch per linked cohort. Session_index agora funciona porque class_id é setado.';

-- ─── BACKFILL ÚNICA: zoom_meetings antigas sem class_id ─────────────────
UPDATE public.zoom_meetings zm
SET class_id = c.id
FROM public.classes c
WHERE zm.class_id IS NULL
  AND c.zoom_meeting_id IS NOT NULL
  AND c.zoom_meeting_id = zm.zoom_meeting_id;
