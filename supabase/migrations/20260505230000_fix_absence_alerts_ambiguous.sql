-- ═══════════════════════════════════════════════════════════════════════════
-- Fix: get_consecutive_absences_needing_alert() — ambiguous cohort_id
--
-- Bug: variável de retorno `cohort_id` colidia com coluna em FROM clause.
-- Função NUNCA executou — explica zero records em zoom_absence_alerts.
--
-- Fix: #variable_conflict use_column directive resolve ambiguidade.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.get_consecutive_absences_needing_alert()
RETURNS TABLE (
  student_id        UUID,
  student_name      TEXT,
  phone             TEXT,
  cohort_id         UUID,
  cohort_name       TEXT,
  consecutive_count INT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
#variable_conflict use_column
BEGIN
  RETURN QUERY
  WITH cohort_list AS (
    SELECT DISTINCT zm.cohort_id AS cl_cohort_id
    FROM public.zoom_meetings zm
    WHERE zm.cohort_id IS NOT NULL
  ),
  summaries AS (
    SELECT
      s.student_id    AS s_student_id,
      s.student_name  AS s_student_name,
      s.phone         AS s_phone,
      cl.cl_cohort_id AS s_cohort_id,
      COALESCE(co.name, 'Turma') AS s_cohort_name,
      s.consecutive_abs AS s_consecutive_abs
    FROM cohort_list cl
    CROSS JOIN LATERAL public.get_attendance_summary(cl.cl_cohort_id) s
    LEFT JOIN public.cohorts co ON co.id = cl.cl_cohort_id
    WHERE s.consecutive_abs >= 2
      AND s.phone IS NOT NULL
      AND s.phone != ''
  )
  SELECT
    su.s_student_id,
    su.s_student_name,
    su.s_phone,
    su.s_cohort_id,
    su.s_cohort_name,
    su.s_consecutive_abs
  FROM summaries su
  WHERE NOT EXISTS (
    SELECT 1 FROM public.zoom_absence_alerts a
    WHERE a.student_id = su.s_student_id
      AND a.cohort_id  = su.s_cohort_id
      AND a.sent_at    > now() - INTERVAL '7 days'
  )
  AND EXISTS (
    SELECT 1 FROM public.students st
    WHERE st.id = su.s_student_id
      AND st.whatsapp_alerts_enabled = true
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_consecutive_absences_needing_alert() TO service_role;

COMMENT ON FUNCTION public.get_consecutive_absences_needing_alert() IS
  'Retorna alunos com 2+ faltas consecutivas elegíveis pra alert WhatsApp. Fix 2026-05-05: ambiguous cohort_id resolvido via use_column directive + alias prefixos.';
