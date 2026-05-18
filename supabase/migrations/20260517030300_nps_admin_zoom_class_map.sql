-- ═══════════════════════════════════════════════════════════════════════════
-- NPS admin — Zoom × Aula × Cohort resolution map.
-- Goal: surface to admin which Zoom meeting binds to which class, which
-- cohorts attend that class, and whether the trigger chain is ready end-to-end.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public.nps_admin_zoom_class_map()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_rows JSONB;
BEGIN
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'unauthorized' USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(jsonb_agg(row ORDER BY row->>'class_name'), '[]'::jsonb) INTO v_rows
  FROM (
    SELECT jsonb_build_object(
      'class_id', cl.id,
      'class_name', cl.name,
      'class_active', COALESCE(cl.active, true),
      'zoom_meeting_id', cl.zoom_meeting_id,
      'has_zoom_binding', cl.zoom_meeting_id IS NOT NULL AND cl.zoom_meeting_id <> '',
      'cohorts', (
        SELECT COALESCE(jsonb_agg(jsonb_build_object(
          'cohort_id', co.id,
          'cohort_name', co.name,
          'has_group_jid', co.whatsapp_group_jid IS NOT NULL,
          'group_jid_valid', public.nps_is_valid_group_jid(co.whatsapp_group_jid),
          'group_verified', COALESCE(co.whatsapp_group_verified, false),
          'group_link', co.whatsapp_group_link,
          'active_students', (
            SELECT COUNT(*) FROM public.students s
            WHERE s.cohort_id = co.id AND s.active = true AND COALESCE(s.is_mentor, false) = false
          )
        ) ORDER BY co.name), '[]'::jsonb)
        FROM public.cohorts co
        JOIN public.class_cohort_access cca ON cca.cohort_id = co.id
        WHERE cca.class_id = cl.id
      ),
      'last_zoom_session', (
        SELECT jsonb_build_object(
          'start_time', zm.start_time,
          'processed', zm.processed,
          'zoom_meeting_id', zm.zoom_meeting_id
        )
        FROM public.zoom_meetings zm
        WHERE zm.zoom_meeting_id = cl.zoom_meeting_id
        ORDER BY zm.start_time DESC NULLS LAST
        LIMIT 1
      )
    ) AS row
    FROM public.classes cl
    WHERE COALESCE(cl.active, true) = true
  ) sub;

  RETURN v_rows;
END;
$$;

REVOKE ALL ON FUNCTION public.nps_admin_zoom_class_map() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.nps_admin_zoom_class_map() TO authenticated;

COMMENT ON FUNCTION public.nps_admin_zoom_class_map IS
  'Returns full Zoom × Class × Cohort resolution map for nps-monitor UI.';
