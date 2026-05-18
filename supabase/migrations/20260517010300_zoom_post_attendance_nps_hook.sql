-- ═══════════════════════════════════════════════════════════════════════════
-- P3 — Hook: after zoom_meetings.processed flips to true, enqueue NPS dispatch
-- Resolves class_id + cohort_id from meeting + session_date, then calls
-- enqueue_nps_class_dispatch (which is gated by feature flag — safe when OFF).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.trg_enqueue_nps_after_zoom_processed()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_class_id    UUID;
  v_cohort_id   UUID;
  v_session_date DATE;
  v_enqueue_result JSONB;
BEGIN
  -- Only fire when processed flips false → true
  IF NOT (NEW.processed = true AND COALESCE(OLD.processed, false) = false) THEN
    RETURN NEW;
  END IF;

  v_session_date := (NEW.start_time AT TIME ZONE 'America/Sao_Paulo')::date;

  -- 1. Try classes.zoom_meeting_id direct match (PS Advanced/Fundamentals)
  SELECT c.id INTO v_class_id
  FROM public.classes c
  WHERE c.zoom_meeting_id = NEW.zoom_meeting_id
  LIMIT 1;

  -- 2. cohort resolution
  v_cohort_id := NEW.cohort_id;

  -- 3. If still missing class_id, try class_cohort_access via cohort
  IF v_class_id IS NULL AND v_cohort_id IS NOT NULL THEN
    SELECT cca.class_id INTO v_class_id
    FROM public.class_cohort_access cca
    WHERE cca.cohort_id = v_cohort_id
    LIMIT 1;
  END IF;

  -- 4. If cohort still null, try resolving via class
  IF v_cohort_id IS NULL AND v_class_id IS NOT NULL THEN
    SELECT cca.cohort_id INTO v_cohort_id
    FROM public.class_cohort_access cca
    WHERE cca.class_id = v_class_id
    LIMIT 1;
  END IF;

  IF v_cohort_id IS NULL THEN
    -- Cannot enqueue without cohort; log via meeting metadata
    RAISE NOTICE 'nps-hook: skipped meeting % — no cohort resolvable', NEW.id;
    RETURN NEW;
  END IF;

  -- Fire-and-forget enqueue (function is gate-protected internally)
  BEGIN
    SELECT public.enqueue_nps_class_dispatch(
      v_class_id, v_cohort_id, v_session_date, NEW.zoom_meeting_id
    ) INTO v_enqueue_result;
    RAISE NOTICE 'nps-hook: meeting=% result=%', NEW.id, v_enqueue_result;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'nps-hook: enqueue failed meeting=% err=%', NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS zoom_meetings_nps_enqueue ON public.zoom_meetings;
CREATE TRIGGER zoom_meetings_nps_enqueue
  AFTER UPDATE OF processed ON public.zoom_meetings
  FOR EACH ROW
  EXECUTE FUNCTION public.trg_enqueue_nps_after_zoom_processed();

COMMENT ON TRIGGER zoom_meetings_nps_enqueue ON public.zoom_meetings IS
  'P3: fires NPS dispatch enqueue when zoom meeting marked processed. Gated by nps_dispatch_enabled flag.';
