-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Link open tracking + public RPC for landing pages
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.dispatch_link_opens (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  source       text NOT NULL CHECK (source IN ('survey_link','nps_class_link')),
  dispatch_id  uuid NOT NULL,
  ip_hash      text,
  user_agent   text,
  referer      text,
  opened_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_dispatch_link_opens_lookup
  ON public.dispatch_link_opens (source, dispatch_id, opened_at DESC);

ALTER TABLE public.dispatch_link_opens ENABLE ROW LEVEL SECURITY;
CREATE POLICY "opens: read for auth" ON public.dispatch_link_opens
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "opens: full for service" ON public.dispatch_link_opens
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE OR REPLACE FUNCTION public.record_link_open(
  p_source     text,
  p_token      text,
  p_user_agent text DEFAULT NULL,
  p_referer    text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_dispatch_id uuid;
BEGIN
  IF p_source = 'nps_class_link' THEN
    SELECT id INTO v_dispatch_id FROM nps_class_links
     WHERE token = p_token AND expires_at > now();
  ELSIF p_source = 'survey_link' THEN
    BEGIN
      SELECT id INTO v_dispatch_id FROM survey_links WHERE token = p_token::uuid;
    EXCEPTION WHEN OTHERS THEN
      v_dispatch_id := NULL;
    END;
  ELSE
    RETURN false;
  END IF;

  IF v_dispatch_id IS NULL THEN RETURN false; END IF;

  INSERT INTO dispatch_link_opens (source, dispatch_id, user_agent, referer)
  VALUES (p_source, v_dispatch_id, p_user_agent, p_referer);

  RETURN true;
END;
$$;

REVOKE ALL ON FUNCTION public.record_link_open(text, text, text, text) FROM public;
GRANT EXECUTE ON FUNCTION public.record_link_open(text, text, text, text) TO anon, authenticated;

COMMIT;
