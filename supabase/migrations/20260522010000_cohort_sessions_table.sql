-- ═══════════════════════════════════════════════════════════════════════════
-- Story 22.0 / ADR-019: cohort_sessions — Source of truth pra ordem das aulas
--
-- Cria tabela cohort_sessions que substitui inferência via COUNT(zoom_meetings).
-- RPC nps_results_by_survey será refatorada em migration 20260522010300 pra
-- consumir essa tabela (com fallback graceful pra heurística legacy).
--
-- DOWN: 20260522010000_cohort_sessions_table.down.sql
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── Table ─────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.cohort_sessions (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cohort_id              UUID NOT NULL REFERENCES public.cohorts(id) ON DELETE CASCADE,
  session_number         INT  NOT NULL CHECK (session_number > 0),
  class_id               UUID REFERENCES public.classes(id) ON DELETE SET NULL,
  planned_date           DATE,
  actual_zoom_meeting_id UUID REFERENCES public.zoom_meetings(id) ON DELETE SET NULL,
  status                 TEXT NOT NULL DEFAULT 'planned'
                              CHECK (status IN ('planned','live','done','cancelled')),
  notes                  TEXT,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT now(),
  deleted_at             TIMESTAMPTZ,
  CONSTRAINT cohort_sessions_unique UNIQUE (cohort_id, session_number)
);

COMMENT ON TABLE  public.cohort_sessions IS 'Source of truth pra ordem das aulas por cohort. Substitui inferência via COUNT(zoom_meetings). Story 22.0 / ADR-019.';
COMMENT ON COLUMN public.cohort_sessions.session_number IS 'Ordem da aula no cohort. UNIQUE per cohort.';
COMMENT ON COLUMN public.cohort_sessions.planned_date IS 'Data planejada da aula. Pode diferir de actual_zoom_meeting.start_time.';
COMMENT ON COLUMN public.cohort_sessions.actual_zoom_meeting_id IS 'FK zoom_meetings quando aula acontece. NULL pra planned/cancelled.';
COMMENT ON COLUMN public.cohort_sessions.status IS 'planned > live > done OR cancelled.';
COMMENT ON COLUMN public.cohort_sessions.deleted_at IS 'Soft delete pra audit trail. NULL = ativo.';

-- ─── Indexes ───────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_cohort_sessions_lookup
  ON public.cohort_sessions(cohort_id, class_id)
  WHERE deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_cohort_sessions_planned
  ON public.cohort_sessions(planned_date)
  WHERE status='planned' AND deleted_at IS NULL;

CREATE INDEX IF NOT EXISTS idx_cohort_sessions_zoom
  ON public.cohort_sessions(actual_zoom_meeting_id)
  WHERE actual_zoom_meeting_id IS NOT NULL;

-- ─── updated_at trigger ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.cohort_sessions_set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_cohort_sessions_updated_at ON public.cohort_sessions;
CREATE TRIGGER trg_cohort_sessions_updated_at
  BEFORE UPDATE ON public.cohort_sessions
  FOR EACH ROW EXECUTE FUNCTION public.cohort_sessions_set_updated_at();

-- ─── RLS ───────────────────────────────────────────────────────────────────

ALTER TABLE public.cohort_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS cohort_sessions_read_admin  ON public.cohort_sessions;
DROP POLICY IF EXISTS cohort_sessions_write_admin ON public.cohort_sessions;

CREATE POLICY cohort_sessions_read_admin ON public.cohort_sessions
  FOR SELECT TO authenticated
  USING (public.is_dashboard_admin());

CREATE POLICY cohort_sessions_write_admin ON public.cohort_sessions
  FOR ALL TO authenticated
  USING (public.is_dashboard_admin())
  WITH CHECK (public.is_dashboard_admin());

-- service_role bypass RLS naturalmente; no explicit grant needed

-- ─── Helper: resolver session_number ──────────────────────────────────────
-- Função utilitária usada por outras RPCs/edge functions.
-- Resolução: snapshot > cohort_sessions > heurística legacy (zoom_meetings).

CREATE OR REPLACE FUNCTION public.resolve_session_number(
  p_class_id       UUID,
  p_cohort_id      UUID,
  p_session_date   DATE,
  p_snapshot       INT DEFAULT NULL  -- nps_class_links.session_number_snapshot quando disponível
) RETURNS INT
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_result INT;
BEGIN
  -- 1. Snapshot do dispatch (imutável)
  IF p_snapshot IS NOT NULL THEN
    RETURN p_snapshot;
  END IF;

  -- 2a. Match exato (session_date == planned_date)
  SELECT cs.session_number INTO v_result
  FROM public.cohort_sessions cs
  WHERE cs.cohort_id = p_cohort_id
    AND cs.class_id  = p_class_id
    AND cs.deleted_at IS NULL
    AND cs.planned_date = p_session_date
  LIMIT 1;

  IF v_result IS NOT NULL THEN
    RETURN v_result;
  END IF;

  -- 2b. Próxima sessão: MAX(session_number) + 1 (quando session_date > todas planned_dates)
  SELECT MAX(cs.session_number) + 1 INTO v_result
  FROM public.cohort_sessions cs
  WHERE cs.cohort_id = p_cohort_id
    AND cs.class_id  = p_class_id
    AND cs.deleted_at IS NULL
    AND cs.planned_date IS NOT NULL
    AND cs.planned_date < p_session_date;

  IF v_result IS NOT NULL THEN
    RETURN v_result;
  END IF;

  -- 3. Heurística legacy (fallback graceful pra dados antigos)
  SELECT COUNT(DISTINCT (zm.start_time AT TIME ZONE 'America/Sao_Paulo')::date)::int + 1
  INTO v_result
  FROM public.zoom_meetings zm
  WHERE zm.class_id  = p_class_id
    AND zm.cohort_id = p_cohort_id
    AND zm.start_time IS NOT NULL
    AND COALESCE(zm.participants_count, 0) >= 10
    AND COALESCE(zm.duration_minutes,   0) >= 60
    AND (zm.start_time AT TIME ZONE 'America/Sao_Paulo')::date < p_session_date;

  RETURN v_result;
END;
$$;

COMMENT ON FUNCTION public.resolve_session_number(UUID,UUID,DATE,INT) IS
  'Story 22.0 / ADR-019 — Resolve session_number via cadeia: snapshot > cohort_sessions > heurística legacy zoom_meetings.';

GRANT EXECUTE ON FUNCTION public.resolve_session_number(UUID,UUID,DATE,INT) TO authenticated, service_role;

COMMIT;
