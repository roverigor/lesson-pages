-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Unified dispatch history VIEW (read-only UNION across 4 sources)
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE VIEW public.dispatch_history_unified AS

-- 1. notifications
SELECT
  'notification'::text     AS source,
  n.id                     AS dispatch_id,
  CASE WHEN n.target_type = 'group' THEN 'evolution_group' ELSE 'meta_dm' END AS channel,
  n.created_at             AS sent_at,
  n.delivered_at           AS delivered_at,
  NULL::timestamptz        AS read_at,
  n.status                 AS status,
  NULL::text               AS error_detail,
  NULL::uuid               AS student_id,
  n.mentor_id              AS mentor_id,
  COALESCE(n.target_phone, n.target_group_jid) AS recipient_identifier,
  n.target_type            AS recipient_type,
  n.class_id, n.cohort_id,
  n.type::text             AS dispatch_type,
  NULL::text               AS template_name,
  'utility'::text          AS template_category,
  n.message_rendered       AS rendered_message,
  CASE WHEN n.evolution_message_ids IS NOT NULL
       AND array_length(n.evolution_message_ids, 1) > 0
       THEN n.evolution_message_ids[1] END AS provider_message_id,
  n.metadata               AS metadata,
  (SELECT COUNT(*) FROM dispatch_link_opens o WHERE o.source = 'notification' AND o.dispatch_id = n.id)::int AS open_count,
  (SELECT MAX(opened_at) FROM dispatch_link_opens o WHERE o.source = 'notification' AND o.dispatch_id = n.id) AS last_opened_at,
  0::int                   AS response_count,
  n.created_at
FROM public.notifications n

UNION ALL

-- 2. survey_links
SELECT
  'survey_link', sl.id, 'meta_dm',
  sl.sent_at,
  sl.delivered_at,
  sl.read_at,
  CASE
    WHEN sl.used_at IS NOT NULL THEN 'responded'
    WHEN sl.read_at IS NOT NULL THEN 'read'
    WHEN sl.delivered_at IS NOT NULL THEN 'delivered'
    WHEN sl.sent_at IS NOT NULL THEN 'sent'
    ELSE 'pending'
  END,
  NULL::text, sl.student_id, NULL::uuid,
  NULL::text, 'individual'::text, NULL::uuid, NULL::uuid,
  'survey'::text, NULL::text, 'utility'::text, NULL::text, NULL::text,
  jsonb_build_object('survey_id', sl.survey_id, 'token', sl.token::text),
  (SELECT COUNT(*) FROM dispatch_link_opens o WHERE o.source = 'survey_link' AND o.dispatch_id = sl.id)::int,
  (SELECT MAX(opened_at) FROM dispatch_link_opens o WHERE o.source = 'survey_link' AND o.dispatch_id = sl.id),
  CASE WHEN sl.used_at IS NOT NULL THEN 1 ELSE 0 END,
  sl.created_at
FROM public.survey_links sl

UNION ALL

-- 3. class_reminder_sends
SELECT
  'class_reminder', s.id, 'evolution_group',
  s.scheduled_at, s.sent_at, NULL::timestamptz,
  s.send_status, s.error_detail,
  NULL::uuid, NULL::uuid, s.group_jid, 'group'::text,
  s.class_id, s.cohort_id, 'class_reminder'::text,
  NULL::text, 'utility'::text, s.message_preview, s.evolution_message_id,
  jsonb_build_object(
    'batch_id', s.batch_id,
    'reminder_type', s.reminder_type,
    'zoom_link', s.zoom_link_snapshot,
    'group_name', s.group_name
  ),
  0::int, NULL::timestamptz, 0::int,
  s.created_at
FROM public.class_reminder_sends s

UNION ALL

-- 4. nps_class_links
SELECT
  'nps_class_link', l.id,
  CASE WHEN l.mode = 'group' THEN 'evolution_group' ELSE 'meta_dm' END,
  l.created_at, NULL::timestamptz, NULL::timestamptz,
  CASE WHEN l.response_count > 0 THEN 'responded' ELSE 'sent' END,
  NULL::text, l.student_id, NULL::uuid, NULL::text,
  CASE WHEN l.mode = 'group' THEN 'group' ELSE 'individual' END,
  l.class_id, l.cohort_id, 'nps'::text,
  NULL::text, 'utility'::text, NULL::text, NULL::text,
  jsonb_build_object(
    'mode', l.mode,
    'token', l.token,
    'trigger_date', l.trigger_date,
    'expires_at', l.expires_at,
    'response_count', l.response_count
  ),
  (SELECT COUNT(*) FROM dispatch_link_opens o WHERE o.source = 'nps_class_link' AND o.dispatch_id = l.id)::int,
  (SELECT MAX(opened_at) FROM dispatch_link_opens o WHERE o.source = 'nps_class_link' AND o.dispatch_id = l.id),
  l.response_count,
  l.created_at
FROM public.nps_class_links l;

GRANT SELECT ON public.dispatch_history_unified TO authenticated, service_role;

COMMIT;
