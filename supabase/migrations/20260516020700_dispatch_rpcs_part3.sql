-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Dashboard RPCs part 3: render_message_preview (JIT message rendering)
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.render_message_preview(
  p_source       text,
  p_dispatch_id  uuid
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT is_dashboard_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  IF p_source = 'survey_link' THEN
    SELECT jsonb_build_object(
      'message', 'Link da pesquisa: https://painel.academialendaria.ai/r/' || sl.token::text,
      'template_name', sv.meta_template_name,
      'recipient_phone', s.phone,
      'recipient_name', s.name,
      'survey_title', sv.title
    ) INTO v_result
    FROM survey_links sl
    LEFT JOIN students s ON s.id = sl.student_id
    LEFT JOIN surveys  sv ON sv.id = sl.survey_id
    WHERE sl.id = p_dispatch_id;

  ELSIF p_source = 'notification' THEN
    SELECT jsonb_build_object(
      'message', n.message_rendered,
      'recipient_phone', n.target_phone,
      'recipient_group', n.target_group_jid,
      'type', n.type,
      'metadata', n.metadata
    ) INTO v_result
    FROM notifications n WHERE n.id = p_dispatch_id;

  ELSIF p_source = 'class_reminder' THEN
    SELECT jsonb_build_object(
      'message', s.message_preview,
      'recipient_group', s.group_jid,
      'group_name', s.group_name,
      'zoom_link', s.zoom_link_snapshot,
      'reminder_type', s.reminder_type
    ) INTO v_result
    FROM class_reminder_sends s WHERE s.id = p_dispatch_id;

  ELSIF p_source = 'nps_class_link' THEN
    SELECT jsonb_build_object(
      'message',
        'Link NPS: https://painel.academialendaria.ai/survey/' ||
        CASE WHEN l.mode = 'group' THEN 'grupo' ELSE 'aluno' END ||
        '/' || l.token,
      'mode', l.mode,
      'expires_at', l.expires_at,
      'response_count', l.response_count,
      'recipient_name', CASE WHEN l.mode = 'dm' THEN (SELECT name FROM students WHERE id = l.student_id) END
    ) INTO v_result
    FROM nps_class_links l WHERE l.id = p_dispatch_id;
  END IF;

  RETURN COALESCE(v_result, jsonb_build_object('error', 'dispatch_not_found'));
END;
$$;
GRANT EXECUTE ON FUNCTION public.render_message_preview(text, uuid) TO authenticated;

COMMIT;
