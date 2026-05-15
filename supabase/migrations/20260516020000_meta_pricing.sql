-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Meta API pricing table for cost estimation
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.meta_pricing (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_category text NOT NULL CHECK (template_category IN
    ('utility','authentication','marketing','service')),
  country_code      text NOT NULL,
  price_usd         numeric(10,5) NOT NULL,
  effective_from    date NOT NULL,
  effective_to      date,
  notes             text,
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_meta_pricing_lookup
  ON public.meta_pricing (template_category, country_code, effective_from DESC)
  WHERE effective_to IS NULL;

ALTER TABLE public.meta_pricing ENABLE ROW LEVEL SECURITY;
CREATE POLICY "meta_pricing: read for auth" ON public.meta_pricing
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "meta_pricing: full for service" ON public.meta_pricing
  FOR ALL TO service_role USING (true) WITH CHECK (true);

INSERT INTO public.meta_pricing (template_category, country_code, price_usd, effective_from, notes) VALUES
  ('utility',        'BR', 0.00450, '2026-01-01', 'Utility/transactional templates BR'),
  ('authentication', 'BR', 0.00150, '2026-01-01', 'OTP BR'),
  ('marketing',      'BR', 0.06250, '2026-01-01', 'Marketing templates BR'),
  ('service',        'BR', 0.00000, '2026-01-01', 'Free-form 24h service window BR')
ON CONFLICT DO NOTHING;

COMMIT;
