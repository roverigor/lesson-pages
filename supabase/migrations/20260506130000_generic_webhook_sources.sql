-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-016 Story 16.5 + 16.6 — Integration Sources + Generic Webhook
-- Suporte multi-plataforma além AC: Hotmart/Eduzz/Kiwify/CRM custom.
-- API key per source, schema body normalizado.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.integration_sources (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name text NOT NULL,
  slug text NOT NULL UNIQUE,  -- ex: 'hotmart', 'eduzz', 'kiwify', 'manychat'
  api_key_hash text NOT NULL UNIQUE,  -- SHA-256 hash do api_key (plain key shown only once)
  api_key_prefix text NOT NULL,  -- primeiros 8 chars do key (display only)
  active boolean DEFAULT true,
  webhook_count_total integer DEFAULT 0,
  webhook_count_success integer DEFAULT 0,
  webhook_count_failed integer DEFAULT 0,
  last_webhook_at timestamptz,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_integration_sources_active
  ON public.integration_sources (slug, active) WHERE active = true;

ALTER TABLE public.integration_sources ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cs_admin_read_sources"
  ON public.integration_sources FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));

CREATE POLICY "admin_write_sources"
  ON public.integration_sources FOR INSERT
  WITH CHECK ((auth.jwt()->'user_metadata'->>'role') = 'admin');

CREATE POLICY "admin_update_sources"
  ON public.integration_sources FOR UPDATE
  USING ((auth.jwt()->'user_metadata'->>'role') = 'admin');

CREATE POLICY "admin_delete_sources"
  ON public.integration_sources FOR DELETE
  USING ((auth.jwt()->'user_metadata'->>'role') = 'admin');

GRANT SELECT, INSERT, UPDATE, DELETE ON public.integration_sources TO authenticated;

-- ─── Extend ac_purchase_events com source_id ───────────────────────────
ALTER TABLE public.ac_purchase_events
  ADD COLUMN IF NOT EXISTS source_id uuid REFERENCES public.integration_sources(id);

CREATE INDEX IF NOT EXISTS idx_ac_events_source ON public.ac_purchase_events (source_id);

-- ─── Function: gerar nova API key (UI chama) ───────────────────────────
CREATE OR REPLACE FUNCTION public.generate_integration_api_key(p_name text, p_slug text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_key text;
  v_hash text;
  v_prefix text;
  v_id uuid;
BEGIN
  IF (auth.jwt()->'user_metadata'->>'role') != 'admin' THEN
    RAISE EXCEPTION 'Permission denied — admin only';
  END IF;

  -- Gera key formato: src_<32 hex chars>
  v_key := 'src_' || encode(gen_random_bytes(24), 'hex');
  v_hash := encode(digest(v_key, 'sha256'), 'hex');
  v_prefix := substring(v_key, 1, 12);

  INSERT INTO public.integration_sources (name, slug, api_key_hash, api_key_prefix, created_by)
  VALUES (p_name, p_slug, v_hash, v_prefix, auth.uid())
  RETURNING id INTO v_id;

  RETURN jsonb_build_object(
    'id', v_id,
    'api_key', v_key,
    'warning', 'GUARDE essa key — não será mostrada novamente. Hash armazenado, plain text descartado.'
  );
END $$;

GRANT EXECUTE ON FUNCTION public.generate_integration_api_key(text, text) TO authenticated;

-- ─── Function: validate_integration_api_key (chamada pelo edge function) ──
CREATE OR REPLACE FUNCTION public.validate_integration_api_key(p_key text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_hash text;
  v_source RECORD;
BEGIN
  v_hash := encode(digest(p_key, 'sha256'), 'hex');
  SELECT * INTO v_source FROM public.integration_sources
  WHERE api_key_hash = v_hash AND active = true;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('valid', false);
  END IF;

  RETURN jsonb_build_object('valid', true, 'source_id', v_source.id, 'slug', v_source.slug, 'name', v_source.name);
END $$;

GRANT EXECUTE ON FUNCTION public.validate_integration_api_key(text) TO service_role;

COMMENT ON TABLE public.integration_sources IS
  'EPIC-016 Story 16.5: registra plataformas externas (Hotmart/Eduzz/Kiwify/AC). Cada uma tem API key própria. Webhook generic-purchase-webhook valida via api_key_hash.';
