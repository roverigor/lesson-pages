-- Helper function: incrementar contador webhook em integration_sources
CREATE OR REPLACE FUNCTION public.increment_source_webhook_count(p_source_id uuid, p_success boolean)
RETURNS void LANGUAGE sql SECURITY DEFINER AS $$
  UPDATE public.integration_sources
  SET webhook_count_total = webhook_count_total + 1,
      webhook_count_success = webhook_count_success + (CASE WHEN p_success THEN 1 ELSE 0 END),
      webhook_count_failed = webhook_count_failed + (CASE WHEN p_success THEN 0 ELSE 1 END),
      last_webhook_at = now()
  WHERE id = p_source_id;
$$;

GRANT EXECUTE ON FUNCTION public.increment_source_webhook_count(uuid, boolean) TO service_role;
