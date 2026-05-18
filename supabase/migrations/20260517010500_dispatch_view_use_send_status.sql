-- ═══════════════════════════════════════════════════════════════════════════
-- P3 — Surgical patch to dispatch_history_unified
-- Preserves column shape from 20260516020400_*. Only the nps_class_links arm
-- changes: derives status from COALESCE(l.send_status, 'pending') instead of
-- hardcoded 'sent', and exposes the new P3 columns (sent_at, error_detail,
-- evolution/meta message ids, session_date, dispatch_job_id).
--
-- Architect review 2026-05-17 (NPS.D.1): previous rewrite referenced columns
-- that do not exist on notifications/survey_links/class_reminder_sends —
-- replaced with this surgical patch.
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE VIEW public.dispatch_history_unified AS

-- 1. notifications (unchanged from 20260516020400_*)
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

-- 2. survey_links (unchanged from 20260516020400_*)
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

-- 3. class_reminder_sends (unchanged from 20260516020400_*)
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

-- 4. nps_class_links — ONLY this arm changes (P3 patch)
SELECT
  'nps_class_link', l.id,
  CASE WHEN l.mode = 'group' THEN 'evolution_group' ELSE 'meta_dm' END,
  COALESCE(l.sent_at, l.created_at)                    AS sent_at,
  NULL::timestamptz                                    AS delivered_at,
  NULL::timestamptz                                    AS read_at,
  -- Status derivation (NPS.D.1 fix): respect real send_status, not hardcoded 'sent'
  CASE
    WHEN l.response_count > 0 THEN 'responded'
    ELSE COALESCE(l.send_status, 'pending')
  END                                                  AS status,
  l.error_detail                                       AS error_detail,
  l.student_id, NULL::uuid                             AS mentor_id,
  NULL::text                                           AS recipient_identifier,
  CASE WHEN l.mode = 'group' THEN 'group' ELSE 'individual' END AS recipient_type,
  l.class_id, l.cohort_id,
  'nps'::text                                          AS dispatch_type,
  NULL::text                                           AS template_name,
  'utility'::text                                      AS template_category,
  NULL::text                                           AS rendered_message,
  COALESCE(l.evolution_message_id, l.meta_message_id) AS provider_message_id,
  jsonb_build_object(
    'mode',                  l.mode,
    'token',                 l.token,
    'trigger_date',          l.trigger_date,
    'session_date',          l.session_date,
    'expires_at',            l.expires_at,
    'response_count',        l.response_count,
    'dispatch_job_id',       l.dispatch_job_id,
    'evolution_message_id',  l.evolution_message_id,
    'meta_message_id',       l.meta_message_id
  )                                                    AS metadata,
  (SELECT COUNT(*) FROM dispatch_link_opens o WHERE o.source = 'nps_class_link' AND o.dispatch_id = l.id)::int AS open_count,
  (SELECT MAX(opened_at) FROM dispatch_link_opens o WHERE o.source = 'nps_class_link' AND o.dispatch_id = l.id) AS last_opened_at,
  l.response_count                                     AS response_count,
  l.created_at
FROM public.nps_class_links l;

GRANT SELECT ON public.dispatch_history_unified TO authenticated, service_role;

COMMIT;
