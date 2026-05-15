-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-019 Story 19.1 — Response Metadata Enrichment
-- Adiciona contexto rico em cada survey response: device, channel, completion time,
-- snapshot do estado do aluno no momento (cohort, journey step se houver).
--
-- Tabela auxiliar (não modifica survey_responses pra preservar baseline).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.response_metadata (
  response_id uuid PRIMARY KEY REFERENCES public.survey_responses(id) ON DELETE CASCADE,

  -- Tracking básico
  user_agent text,
  device_type text CHECK (device_type IN ('mobile', 'tablet', 'desktop', 'unknown')),
  channel text CHECK (channel IN ('whatsapp', 'email', 'web_direct', 'unknown')),
  ip_address inet,
  ip_country text,

  -- Performance
  completion_time_seconds integer,
  started_at timestamptz,

  -- Context snapshot (estado aluno NO MOMENTO da resposta — imutável)
  cohort_id_at_response uuid REFERENCES public.cohorts(id),
  days_since_purchase integer,

  -- AI enrichment (Stories 17.4/19.6 — populated quando AI rodar)
  sentiment text CHECK (sentiment IN ('positive', 'neutral', 'negative', 'critical')),
  sentiment_confidence numeric(3,2),
  themes text[],

  -- Tags manuais (CS rep pode adicionar)
  manual_tags text[],

  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_response_metadata_cohort
  ON public.response_metadata (cohort_id_at_response);

CREATE INDEX IF NOT EXISTS idx_response_metadata_sentiment
  ON public.response_metadata (sentiment) WHERE sentiment IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_response_metadata_themes
  ON public.response_metadata USING GIN (themes);

ALTER TABLE public.response_metadata ENABLE ROW LEVEL SECURITY;

CREATE POLICY "cs_admin_read_response_metadata"
  ON public.response_metadata FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));

CREATE POLICY "cs_admin_write_response_metadata"
  ON public.response_metadata FOR INSERT
  WITH CHECK ((auth.jwt()->'user_metadata'->>'role') IN ('admin', 'cs'));

GRANT SELECT, INSERT, UPDATE ON public.response_metadata TO authenticated;

-- ─── Helper: parse user_agent → device_type ──────────────────────────────
CREATE OR REPLACE FUNCTION public.parse_device_type(p_user_agent text)
RETURNS text LANGUAGE sql IMMUTABLE AS $$
  SELECT CASE
    WHEN p_user_agent IS NULL THEN 'unknown'
    WHEN p_user_agent ~* 'mobile|android|iphone|ipod' THEN 'mobile'
    WHEN p_user_agent ~* 'tablet|ipad' THEN 'tablet'
    ELSE 'desktop'
  END;
$$;

COMMENT ON TABLE public.response_metadata IS
  'EPIC-019 Story 19.1: contexto rico per response — device, channel, completion time, snapshot cohort, AI sentiment+themes (futuro).';
