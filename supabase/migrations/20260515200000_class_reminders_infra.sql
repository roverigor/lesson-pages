-- ============================================================================
-- Class Reminders Infrastructure
-- Date: 2026-05-15
-- ============================================================================
-- Purpose:
--   1. Create class_reminder_batches (preview/approval workflow per date)
--   2. Create class_reminder_sends (1 row per class+time+group dispatched)
--   3. Inactivate Cohort Fund T3/T4 classes (encerradas)
--   4. Update bridges:
--      - PS Fundamentals + Fund T5, Cohort Fund T5/T6
--      - PS Advanced + Cohort Advanced T2
-- ============================================================================

BEGIN;

-- ─── 1. class_reminder_batches ──────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.class_reminder_batches (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  target_date  date NOT NULL,
  status       text NOT NULL DEFAULT 'preview' CHECK (status IN ('preview','approved','sent','cancelled')),
  total_sends  integer NOT NULL DEFAULT 0,
  created_by   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_by  uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  approved_at  timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now(),
  notes        text
);
CREATE INDEX IF NOT EXISTS idx_class_reminder_batches_date ON public.class_reminder_batches (target_date DESC);
CREATE INDEX IF NOT EXISTS idx_class_reminder_batches_status ON public.class_reminder_batches (status, target_date);

-- ─── 2. class_reminder_sends ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.class_reminder_sends (
  id                   uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id             uuid NOT NULL REFERENCES public.class_reminder_batches(id) ON DELETE CASCADE,
  class_id             uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  cohort_id            uuid NOT NULL REFERENCES public.cohorts(id) ON DELETE CASCADE,
  group_jid            text,                                 -- WhatsApp group JID (snapshot)
  group_name           text,                                 -- snapshot pra audit
  reminder_type        text NOT NULL CHECK (reminder_type IN ('1h_before','start','holiday')),
  scheduled_at         timestamptz NOT NULL,                 -- when this should fire (BRT converted)
  message_preview      text NOT NULL,                        -- rendered message
  zoom_link_snapshot   text,                                 -- captured at preview time
  send_status          text NOT NULL DEFAULT 'pending' CHECK (send_status IN ('pending','sent','failed','skipped','cancelled')),
  evolution_message_id text,                                 -- response from Evolution API
  error_detail         text,                                 -- on failure
  sent_at              timestamptz,
  created_at           timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_class_reminder_sends_batch ON public.class_reminder_sends (batch_id, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_class_reminder_sends_status ON public.class_reminder_sends (send_status, scheduled_at) WHERE send_status='pending';
CREATE INDEX IF NOT EXISTS idx_class_reminder_sends_class ON public.class_reminder_sends (class_id, cohort_id);

-- ─── RLS ──────────────────────────────────────────────────────────────────
ALTER TABLE public.class_reminder_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.class_reminder_sends ENABLE ROW LEVEL SECURITY;

CREATE POLICY "batches: read for auth"
  ON public.class_reminder_batches FOR SELECT
  TO authenticated USING (true);
CREATE POLICY "batches: full for service"
  ON public.class_reminder_batches FOR ALL
  TO service_role USING (true) WITH CHECK (true);

CREATE POLICY "sends: read for auth"
  ON public.class_reminder_sends FOR SELECT
  TO authenticated USING (true);
CREATE POLICY "sends: full for service"
  ON public.class_reminder_sends FOR ALL
  TO service_role USING (true) WITH CHECK (true);

-- ─── 3. Inactivate encerradas ──────────────────────────────────────────────
UPDATE public.classes SET active=false
 WHERE id IN (
   'd07846b9-00d9-4635-b76b-d74b62bcb99f', -- Cohort Fundamentals T3
   '53244281-e47b-4985-a7cd-b19182b5db36'  -- Cohort Fundamentals T4
 );

-- ─── 4. Update bridges class_cohorts ──────────────────────────────────────
-- Add Fund T5, Cohort Fund T5/T6 ao bridge da aula PS Fundamentals
INSERT INTO public.class_cohorts (class_id, cohort_id)
VALUES
  ('0e5df244-8068-4839-a1b1-2bf36616e0ab', '9211de1a-de4f-46dd-b343-fdc63f4c8b6b'), -- PS Fund + Fund T5
  ('0e5df244-8068-4839-a1b1-2bf36616e0ab', '144dcb82-f6ac-4f44-8e73-67b4213b42c5'), -- PS Fund + Cohort Fund T5
  ('0e5df244-8068-4839-a1b1-2bf36616e0ab', '27be92d6-e11e-4176-823e-53093e36648b'), -- PS Fund + Cohort Fund T6
  ('985cb305-bcbb-4997-b7d6-60afa4ee9b29', 'd45766ed-1a9e-4070-b2d6-ea7a48a1851b')  -- PS Advanced + Cohort Advanced T2
ON CONFLICT (class_id, cohort_id) DO NOTHING;

COMMIT;
