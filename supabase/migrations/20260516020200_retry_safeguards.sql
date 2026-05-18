-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Retry safeguards: confirm tokens + audit log
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.retry_confirm_tokens (
  token        text PRIMARY KEY,
  source       text NOT NULL,
  dispatch_id  uuid NOT NULL,
  issued_to    uuid REFERENCES auth.users(id) ON DELETE CASCADE,
  issued_at    timestamptz NOT NULL DEFAULT now(),
  expires_at   timestamptz NOT NULL DEFAULT now() + interval '15 minutes',
  consumed_at  timestamptz
);
CREATE INDEX IF NOT EXISTS idx_retry_tokens_active
  ON public.retry_confirm_tokens (token) WHERE consumed_at IS NULL;

ALTER TABLE public.retry_confirm_tokens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "retry_tokens: service full" ON public.retry_confirm_tokens
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE TABLE IF NOT EXISTS public.dispatch_retry_audit (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source       text NOT NULL,
  dispatch_id  uuid NOT NULL,
  retried_by   uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  retried_at   timestamptz NOT NULL DEFAULT now(),
  reason       text,
  result       jsonb
);
CREATE INDEX IF NOT EXISTS idx_retry_audit_dispatch
  ON public.dispatch_retry_audit (source, dispatch_id, retried_at DESC);

ALTER TABLE public.dispatch_retry_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY "retry_audit: read for auth" ON public.dispatch_retry_audit
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "retry_audit: service full" ON public.dispatch_retry_audit
  FOR ALL TO service_role USING (true) WITH CHECK (true);

COMMIT;
