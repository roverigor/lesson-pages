-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Helper functions: cost estimator + admin guard
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.estimate_dispatch_cost_usd(
  p_template_category text,
  p_country_code      text DEFAULT 'BR',
  p_at_date           date DEFAULT CURRENT_DATE
) RETURNS numeric
LANGUAGE sql STABLE
SET search_path = public AS $$
  SELECT price_usd
  FROM public.meta_pricing
  WHERE template_category = p_template_category
    AND country_code      = p_country_code
    AND effective_from   <= p_at_date
    AND (effective_to IS NULL OR effective_to >= p_at_date)
  ORDER BY effective_from DESC LIMIT 1;
$$;
GRANT EXECUTE ON FUNCTION public.estimate_dispatch_cost_usd(text, text, date) TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.is_dashboard_admin()
RETURNS boolean
LANGUAGE sql STABLE AS $$
  SELECT COALESCE((auth.jwt()->'user_metadata'->>'role') = 'admin', false);
$$;
GRANT EXECUTE ON FUNCTION public.is_dashboard_admin() TO authenticated, anon, service_role;

COMMIT;
