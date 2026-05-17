-- ═══════════════════════════════════════════════════════════════════════════
-- P3 — Extend nps_class_links (P2) with delivery tracking + auto token
-- Idempotent ALTERs; do not break P2 manual-token flow.
-- ═══════════════════════════════════════════════════════════════════════════

-- 1. Default token: 32 hex chars (16 random bytes)
ALTER TABLE public.nps_class_links
  ALTER COLUMN token SET DEFAULT encode(gen_random_bytes(16), 'hex');

-- 2. Make class_id nullable (cohort-only dispatch in some PS edge cases)
ALTER TABLE public.nps_class_links
  ALTER COLUMN class_id DROP NOT NULL;

-- 3. Delivery tracking
ALTER TABLE public.nps_class_links
  ADD COLUMN IF NOT EXISTS send_status TEXT DEFAULT 'pending'
    CHECK (send_status IN ('pending','sent','failed','skipped')),
  ADD COLUMN IF NOT EXISTS sent_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS evolution_message_id TEXT,
  ADD COLUMN IF NOT EXISTS meta_message_id TEXT,
  ADD COLUMN IF NOT EXISTS error_detail TEXT,
  ADD COLUMN IF NOT EXISTS session_date DATE,
  ADD COLUMN IF NOT EXISTS dispatch_job_id UUID
    REFERENCES public.nps_class_dispatch_jobs(id) ON DELETE SET NULL;

-- 4. Backfill session_date from trigger_date if NULL (legacy P2 rows)
UPDATE public.nps_class_links
   SET session_date = trigger_date
 WHERE session_date IS NULL;

-- 5. Index for dispatch retry lookups
CREATE INDEX IF NOT EXISTS idx_nps_links_dispatch_status
  ON public.nps_class_links (send_status, sent_at);

CREATE INDEX IF NOT EXISTS idx_nps_links_dispatch_job
  ON public.nps_class_links (dispatch_job_id);

-- 6. Drop old unique constraints to allow nullable class_id
DROP INDEX IF EXISTS public.idx_nps_class_links_group_unique;
DROP INDEX IF EXISTS public.idx_nps_class_links_dm_unique;

-- 7. Recreate unique constraints with NULL handling
CREATE UNIQUE INDEX IF NOT EXISTS idx_nps_class_links_group_unique
  ON public.nps_class_links (
    COALESCE(class_id, '00000000-0000-0000-0000-000000000000'::uuid),
    cohort_id,
    COALESCE(session_date, trigger_date)
  )
  WHERE mode = 'group';

CREATE UNIQUE INDEX IF NOT EXISTS idx_nps_class_links_dm_unique
  ON public.nps_class_links (
    COALESCE(class_id, '00000000-0000-0000-0000-000000000000'::uuid),
    cohort_id,
    COALESCE(session_date, trigger_date),
    student_id
  )
  WHERE mode = 'dm';

COMMENT ON COLUMN public.nps_class_links.send_status IS
  'P3: delivery state. P2 manual-token rows default pending and stay there if not dispatched.';

COMMENT ON COLUMN public.nps_class_links.dispatch_job_id IS
  'P3: link back to nps_class_dispatch_jobs row that emitted this token.';
