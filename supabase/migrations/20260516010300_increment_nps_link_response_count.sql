BEGIN;

CREATE OR REPLACE FUNCTION public.increment_nps_link_response_count(p_link_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.nps_class_links
  SET response_count = response_count + 1
  WHERE id = p_link_id;
$$;

REVOKE ALL ON FUNCTION public.increment_nps_link_response_count(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.increment_nps_link_response_count(uuid) TO service_role;

COMMIT;
