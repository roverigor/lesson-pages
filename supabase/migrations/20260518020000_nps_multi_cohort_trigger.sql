-- ═══════════════════════════════════════════════════════════════════════════
-- NPS.E.2 — Multi-cohort enqueue on Zoom-end
--
-- Architect concern #9: previous trigger used LIMIT 1 from class_cohort_access,
-- meaning PS Advanced with T3+T4+T5 cohorts attending same Zoom = only ONE
-- cohort got NPS dispatched.
--
-- Fix: loop over ALL cohort rows linked to the resolved class, enqueue one
-- job per cohort. Idempotency preserved by UNIQUE constraint on
-- (cohort_id, class_id, session_date).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_enqueue_nps_after_zoom_processed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_class_id     UUID;
  v_session_date DATE;
  v_cohort_rec   RECORD;
  v_enqueue_result JSONB;
  v_jobs_enqueued INT := 0;
BEGIN
  -- Only fire when processed flips false → true
  IF NOT (NEW.processed = true AND COALESCE(OLD.processed, false) = false) THEN
    RETURN NEW;
  END IF;

  v_session_date := (NEW.start_time AT TIME ZONE 'America/Sao_Paulo')::date;

  -- 1. Resolve class_id via classes.zoom_meeting_id direct match
  SELECT c.id INTO v_class_id
  FROM public.classes c
  WHERE c.zoom_meeting_id = NEW.zoom_meeting_id
  LIMIT 1;

  -- 2. NPS.E.2 — loop over ALL cohorts linked to the class (multi-cohort fix)
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

  -- 3. Fallback — if no class resolved via classes.zoom_meeting_id,
  --    try zoom_meetings.cohort_id (single cohort legacy case)
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

  IF v_jobs_enqueued = 0 THEN
    RAISE NOTICE 'nps-hook: meeting % yielded zero jobs (no class binding + no cohort)', NEW.id;
  ELSE
    RAISE NOTICE 'nps-hook: meeting % enqueued % job(s)', NEW.id, v_jobs_enqueued;
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.trg_enqueue_nps_after_zoom_processed IS
  'NPS.E.2: enqueues one dispatch job per cohort linked to the resolved class. Multi-cohort PS classes now covered.';
