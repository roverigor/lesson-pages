-- ═══════════════════════════════════════════════════════════════════════════
-- P3 — Update dispatch_history_unified VIEW to reflect real send_status
-- on nps_class_links (now that P3 populates this column).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

DROP VIEW IF EXISTS public.dispatch_history_unified CASCADE;

CREATE OR REPLACE VIEW public.dispatch_history_unified AS

-- 1. notifications (existing)
SELECT
  'notification'::text                AS source,
  n.id                                AS dispatch_id,
  COALESCE(n.channel, 'meta_dm')      AS channel,
  n.created_at                        AS created_at,
  n.scheduled_at                      AS scheduled_at,
  n.sent_at                           AS sent_at,
  COALESCE(n.status, 'pending')       AS status,
  n.phone_number                      AS recipient_phone,
  n.student_id                        AS student_id,
  NULL::uuid                          AS cohort_id,
  NULL::text                          AS group_jid,
  'individual'                        AS recipient_type,
  n.class_id                          AS class_id,
  NULL::uuid                          AS cohort_id_alt,
  n.purpose                           AS purpose,
  n.template_name                     AS template_name,
  'utility'                           AS category,
  n.message_rendered                  AS message_preview,
  n.error                             AS error_detail,
  n.metadata                          AS extra_meta,
  (SELECT COUNT(*) FROM public.dispatch_link_opens o
    WHERE o.source = 'notification' AND o.dispatch_id = n.id)::int AS open_count,
  (SELECT MAX(opened_at) FROM public.dispatch_link_opens o
    WHERE o.source = 'notification' AND o.dispatch_id = n.id)      AS last_opened_at,
  0::int                              AS response_count,
  n.created_at                        AS sort_at
FROM public.notifications n

UNION ALL

-- 2. survey_links (existing)
SELECT
  'survey_link', sl.id,
  COALESCE(sl.send_channel, 'meta_dm'),
  sl.created_at, sl.scheduled_at, sl.sent_at,
  COALESCE(sl.send_status, 'pending'),
  sl.recipient_phone, sl.student_id,
  NULL::uuid, NULL::text, 'individual',
  NULL::uuid, sl.cohort_id, 'survey',
  sl.template_name, 'utility', NULL::text, sl.error_detail,
  jsonb_build_object('survey_id', sl.survey_id, 'token', sl.token),
  (SELECT COUNT(*) FROM public.dispatch_link_opens o
    WHERE o.source = 'survey_link' AND o.dispatch_id = sl.id)::int,
  (SELECT MAX(opened_at) FROM public.dispatch_link_opens o
    WHERE o.source = 'survey_link' AND o.dispatch_id = sl.id),
  CASE WHEN sl.responded_at IS NOT NULL THEN 1 ELSE 0 END,
  sl.created_at
FROM public.survey_links sl

UNION ALL

-- 3. class_reminder_sends (existing)
SELECT
  'class_reminder', s.id,
  'evolution_group',
  s.created_at, s.scheduled_at, s.sent_at,
  COALESCE(s.send_status, 'pending'),
  NULL::text, NULL::uuid,
  s.cohort_id, s.group_jid, 'group',
  s.class_id, s.cohort_id, s.reminder_type,
  NULL::text, 'utility', s.message_preview, s.error_detail,
  jsonb_build_object('batch_id', s.batch_id, 'group_name', s.group_name),
  0::int, NULL::timestamptz, 0::int,
  s.created_at
FROM public.class_reminder_sends s

UNION ALL

-- 4. nps_class_links (updated — uses real send_status from P3)
SELECT
  'nps_class_link', l.id,
  CASE WHEN l.mode = 'group' THEN 'evolution_group' ELSE 'meta_dm' END,
  l.created_at, NULL::timestamptz, l.sent_at,
  CASE
    WHEN l.response_count > 0 THEN 'responded'
    ELSE COALESCE(l.send_status, 'pending')
  END,
  NULL::text, l.student_id, NULL::uuid, NULL::text,
  CASE WHEN l.mode = 'group' THEN 'group' ELSE 'individual' END,
  l.class_id, l.cohort_id, 'nps'::text,
  NULL::text, 'utility'::text, NULL::text, l.error_detail,
  jsonb_build_object(
    'mode', l.mode,
    'token', l.token,
    'trigger_date', l.trigger_date,
    'session_date', l.session_date,
    'expires_at', l.expires_at,
    'response_count', l.response_count,
    'dispatch_job_id', l.dispatch_job_id,
    'evolution_message_id', l.evolution_message_id,
    'meta_message_id', l.meta_message_id
  ),
  (SELECT COUNT(*) FROM public.dispatch_link_opens o
    WHERE o.source = 'nps_class_link' AND o.dispatch_id = l.id)::int,
  (SELECT MAX(opened_at) FROM public.dispatch_link_opens o
    WHERE o.source = 'nps_class_link' AND o.dispatch_id = l.id),
  l.response_count,
  l.created_at
FROM public.nps_class_links l;

GRANT SELECT ON public.dispatch_history_unified TO authenticated, service_role;

COMMIT;
