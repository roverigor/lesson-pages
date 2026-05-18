CREATE OR REPLACE VIEW dispatch_history_unified AS
 SELECT 'notification'::text AS source,
    n.id AS dispatch_id,
        CASE
            WHEN (n.target_type = 'group'::text) THEN 'evolution_group'::text
            ELSE 'meta_dm'::text
        END AS channel,
    n.created_at AS sent_at,
    n.delivered_at,
    NULL::timestamp with time zone AS read_at,
    n.status,
    NULL::text AS error_detail,
    NULL::uuid AS student_id,
    n.mentor_id,
    COALESCE(n.target_phone, n.target_group_jid) AS recipient_identifier,
    n.target_type AS recipient_type,
    n.class_id,
    n.cohort_id,
    n.type AS dispatch_type,
    NULL::text AS template_name,
    'utility'::text AS template_category,
    n.message_rendered AS rendered_message,
        CASE
            WHEN ((n.evolution_message_ids IS NOT NULL) AND (array_length(n.evolution_message_ids, 1) > 0)) THEN n.evolution_message_ids[1]
            ELSE NULL::text
        END AS provider_message_id,
    n.metadata,
    (( SELECT count(*) AS count
           FROM dispatch_link_opens o
          WHERE ((o.source = 'notification'::text) AND (o.dispatch_id = n.id))))::integer AS open_count,
    ( SELECT max(o.opened_at) AS max
           FROM dispatch_link_opens o
          WHERE ((o.source = 'notification'::text) AND (o.dispatch_id = n.id))) AS last_opened_at,
    0 AS response_count,
    n.created_at
   FROM notifications n
UNION ALL
 SELECT 'survey_link'::text AS source,
    sl.id AS dispatch_id,
    'meta_dm'::text AS channel,
    sl.sent_at,
    sl.delivered_at,
    sl.read_at,
        CASE
            WHEN (sl.used_at IS NOT NULL) THEN 'responded'::text
            WHEN (sl.read_at IS NOT NULL) THEN 'read'::text
            WHEN (sl.delivered_at IS NOT NULL) THEN 'delivered'::text
            WHEN (sl.sent_at IS NOT NULL) THEN 'sent'::text
            ELSE 'pending'::text
        END AS status,
    NULL::text AS error_detail,
    sl.student_id,
    NULL::uuid AS mentor_id,
    NULL::text AS recipient_identifier,
    'individual'::text AS recipient_type,
    sv.class_id AS class_id,
    sv.cohort_id AS cohort_id,
    'survey'::text AS dispatch_type,
    NULL::text AS template_name,
    'utility'::text AS template_category,
    NULL::text AS rendered_message,
    NULL::text AS provider_message_id,
    jsonb_build_object('survey_id', sl.survey_id, 'survey_name', sv.name, 'token', (sl.token)::text) AS metadata,
    (( SELECT count(*) AS count
           FROM dispatch_link_opens o
          WHERE ((o.source = 'survey_link'::text) AND (o.dispatch_id = sl.id))))::integer AS open_count,
    ( SELECT max(o.opened_at) AS max
           FROM dispatch_link_opens o
          WHERE ((o.source = 'survey_link'::text) AND (o.dispatch_id = sl.id))) AS last_opened_at,
        CASE
            WHEN (sl.used_at IS NOT NULL) THEN 1
            ELSE 0
        END AS response_count,
    sl.created_at
   FROM survey_links sl
   LEFT JOIN surveys sv ON sv.id = sl.survey_id
UNION ALL
 SELECT 'class_reminder'::text AS source,
    s.id AS dispatch_id,
    'evolution_group'::text AS channel,
    s.scheduled_at AS sent_at,
    s.sent_at AS delivered_at,
    NULL::timestamp with time zone AS read_at,
    s.send_status AS status,
    s.error_detail,
    NULL::uuid AS student_id,
    NULL::uuid AS mentor_id,
    s.group_jid AS recipient_identifier,
    'group'::text AS recipient_type,
    s.class_id,
    s.cohort_id,
    'class_reminder'::text AS dispatch_type,
    NULL::text AS template_name,
    'utility'::text AS template_category,
    s.message_preview AS rendered_message,
    s.evolution_message_id AS provider_message_id,
    jsonb_build_object('batch_id', s.batch_id, 'reminder_type', s.reminder_type, 'zoom_link', s.zoom_link_snapshot, 'group_name', s.group_name) AS metadata,
    0 AS open_count,
    NULL::timestamp with time zone AS last_opened_at,
    0 AS response_count,
    s.created_at
   FROM class_reminder_sends s
UNION ALL
 SELECT 'nps_class_link'::text AS source,
    l.id AS dispatch_id,
        CASE
            WHEN (l.mode = 'group'::text) THEN 'evolution_group'::text
            ELSE 'meta_dm'::text
        END AS channel,
    COALESCE(l.sent_at, l.created_at) AS sent_at,
    NULL::timestamp with time zone AS delivered_at,
    NULL::timestamp with time zone AS read_at,
        CASE
            WHEN (l.response_count > 0) THEN 'responded'::text
            ELSE COALESCE(l.send_status, 'pending'::text)
        END AS status,
    l.error_detail,
    l.student_id,
    NULL::uuid AS mentor_id,
    NULL::text AS recipient_identifier,
        CASE
            WHEN (l.mode = 'group'::text) THEN 'group'::text
            ELSE 'individual'::text
        END AS recipient_type,
    l.class_id,
    l.cohort_id,
    'nps'::text AS dispatch_type,
    NULL::text AS template_name,
    'utility'::text AS template_category,
    NULL::text AS rendered_message,
    COALESCE(l.evolution_message_id, l.meta_message_id) AS provider_message_id,
    jsonb_build_object('mode', l.mode, 'token', l.token, 'trigger_date', l.trigger_date, 'session_date', l.session_date, 'expires_at', l.expires_at, 'response_count', l.response_count, 'dispatch_job_id', l.dispatch_job_id, 'evolution_message_id', l.evolution_message_id, 'meta_message_id', l.meta_message_id) AS metadata,
    (( SELECT count(*) AS count
           FROM dispatch_link_opens o
          WHERE ((o.source = 'nps_class_link'::text) AND (o.dispatch_id = l.id))))::integer AS open_count,
    ( SELECT max(o.opened_at) AS max
           FROM dispatch_link_opens o
          WHERE ((o.source = 'nps_class_link'::text) AND (o.dispatch_id = l.id))) AS last_opened_at,
    l.response_count,
    l.created_at
   FROM nps_class_links l;
