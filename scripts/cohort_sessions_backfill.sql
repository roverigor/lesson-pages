-- ═══════════════════════════════════════════════════════════════════════════
-- Backfill cohort_sessions (Story 22.0 / ADR-019)
--
-- USO:
--   1. DRY-RUN: SET dry_run=true (default) → gera report SEM apply
--   2. Review per-cohort no output
--   3. APPLY: SET dry_run=false → executa INSERT
--
-- NÃO É MIGRATION — script manual, run via psql / Management API após review.
-- ═══════════════════════════════════════════════════════════════════════════

-- ─── Configuração ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_dry_run BOOLEAN := true;   -- ← TROCAR PRA false PRA APPLY
  v_cohort  RECORD;
  v_session RECORD;
  v_inserted INT := 0;
  v_skipped  INT := 0;
BEGIN
  -- ─── Iterar cohorts ativos ─────────────────────────────────────────────
  FOR v_cohort IN
    SELECT c.id, c.name
    FROM public.cohorts c
    WHERE c.name NOT ILIKE '%[merged]%'  -- skip merged cohorts
    ORDER BY c.name
  LOOP
    RAISE NOTICE '─── COHORT: % (%) ───', v_cohort.name, v_cohort.id;

    -- Pra cada zoom_meeting filtrado (heurística atual), propor session_number
    FOR v_session IN
      WITH ranked AS (
        SELECT
          zm.class_id,
          (zm.start_time AT TIME ZONE 'America/Sao_Paulo')::date AS session_date,
          (array_agg(zm.id ORDER BY zm.start_time))[1] AS zoom_meeting_id,  -- primeiro do dia (caso multi-meeting)
          MAX(zm.participants_count) AS max_participants,
          SUM(zm.duration_minutes) AS total_duration
        FROM public.zoom_meetings zm
        WHERE zm.cohort_id = v_cohort.id
          AND zm.start_time IS NOT NULL
          AND zm.class_id IS NOT NULL
          AND COALESCE(zm.participants_count, 0) >= 10
          AND COALESCE(zm.duration_minutes,   0) >= 60
        GROUP BY zm.class_id, (zm.start_time AT TIME ZONE 'America/Sao_Paulo')::date
      )
      SELECT
        ROW_NUMBER() OVER (ORDER BY session_date) AS session_number,
        class_id, session_date, zoom_meeting_id,
        max_participants, total_duration
      FROM ranked
      ORDER BY session_date
    LOOP
      -- Check conflict
      IF EXISTS (
        SELECT 1 FROM public.cohort_sessions
        WHERE cohort_id = v_cohort.id AND session_number = v_session.session_number
      ) THEN
        RAISE NOTICE '  [SKIP] Sessão #% já existe pra cohort %', v_session.session_number, v_cohort.name;
        v_skipped := v_skipped + 1;
        CONTINUE;
      END IF;

      -- Report
      RAISE NOTICE '  Aula %  date=%  class=%  zoom=%  parts=%  dur=%min',
        lpad(v_session.session_number::text, 2, '0'),
        v_session.session_date,
        v_session.class_id,
        v_session.zoom_meeting_id,
        v_session.max_participants,
        v_session.total_duration;

      -- Apply
      IF NOT v_dry_run THEN
        INSERT INTO public.cohort_sessions (
          cohort_id, session_number, class_id, planned_date,
          actual_zoom_meeting_id, status
        ) VALUES (
          v_cohort.id,
          v_session.session_number,
          v_session.class_id,
          v_session.session_date,
          v_session.zoom_meeting_id,
          'done'  -- já aconteceu (zoom_meeting existe)
        );
        v_inserted := v_inserted + 1;
      END IF;
    END LOOP;
  END LOOP;

  RAISE NOTICE '';
  RAISE NOTICE '═══════════════════════════════════════════';
  IF v_dry_run THEN
    RAISE NOTICE 'DRY-RUN — nenhum INSERT executado.';
    RAISE NOTICE 'Pra apply: troque dry_run := false no script.';
  ELSE
    RAISE NOTICE 'APPLIED — % rows inseridas, % skipped.', v_inserted, v_skipped;
  END IF;
  RAISE NOTICE '═══════════════════════════════════════════';
END;
$$;

-- ─── Validação pós-backfill ────────────────────────────────────────────────
-- Rodar manual após apply pra checar consistency:

-- 1. Cobertura: cohorts sem cohort_sessions
-- SELECT c.id, c.name
-- FROM cohorts c
-- LEFT JOIN cohort_sessions cs ON cs.cohort_id = c.id
-- WHERE cs.id IS NULL
--   AND c.name NOT ILIKE '%merged%'
-- ORDER BY c.name;

-- 2. Conflito: session_number duplicado por cohort (UNIQUE deveria prevenir, mas check)
-- SELECT cohort_id, session_number, COUNT(*)
-- FROM cohort_sessions
-- GROUP BY cohort_id, session_number
-- HAVING COUNT(*) > 1;

-- 3. Orphan zoom_meeting (zoom_meeting_id em cohort_sessions mas not in zoom_meetings)
-- SELECT cs.id, cs.cohort_id, cs.actual_zoom_meeting_id
-- FROM cohort_sessions cs
-- LEFT JOIN zoom_meetings zm ON zm.id = cs.actual_zoom_meeting_id
-- WHERE cs.actual_zoom_meeting_id IS NOT NULL AND zm.id IS NULL;
