-- ============================================================================
-- Merge Cohort Advanced T2 (paralela) → Advanced T2 (canonical)
-- Date: 2026-05-15
-- ============================================================================
-- Canonical: Advanced T2 (9f10cb6c-58c7-4e48-8bed-0603f404730e)
-- Duplicada:  Cohort Advanced T2 (d45766ed-1a9e-4070-b2d6-ea7a48a1851b)
--
-- Move todos refs cohort_id da duplicada pra canonical, deativa duplicada.
-- ============================================================================

BEGIN;

-- 1. Bridge tables com unique (X, cohort_id) — usar INSERT ON CONFLICT + DELETE
-- student_cohorts (student_id, cohort_id)
INSERT INTO public.student_cohorts (student_id, cohort_id, enrolled_at)
SELECT student_id, '9f10cb6c-58c7-4e48-8bed-0603f404730e'::uuid, enrolled_at
  FROM public.student_cohorts
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b'
ON CONFLICT (student_id, cohort_id) DO NOTHING;
DELETE FROM public.student_cohorts WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

-- class_cohorts (class_id, cohort_id)
INSERT INTO public.class_cohorts (class_id, cohort_id)
SELECT class_id, '9f10cb6c-58c7-4e48-8bed-0603f404730e'::uuid
  FROM public.class_cohorts
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b'
ON CONFLICT (class_id, cohort_id) DO NOTHING;
DELETE FROM public.class_cohorts WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

-- 2. Tables sem unique constraint — UPDATE direto
UPDATE public.students SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.student_imports SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.surveys SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.wa_group_members SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.zoom_meetings SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.student_attendance SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.student_engagement_scores SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.student_nps SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.notification_schedules SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.notifications SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.zoom_chat_messages SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.zoom_absence_alerts SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.whatsapp_group_messages SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.anomaly_alerts SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.class_cohort_access SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.class_recordings SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.class_reminder_sends SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.ac_product_mappings SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

UPDATE public.engagement_daily_ranking SET cohort_id='9f10cb6c-58c7-4e48-8bed-0603f404730e'
 WHERE cohort_id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

-- 3. Deactivate + rename duplicada
UPDATE public.cohorts
   SET active=false,
       name=name||' [merged→Advanced T2]'
 WHERE id='d45766ed-1a9e-4070-b2d6-ea7a48a1851b';

COMMIT;
