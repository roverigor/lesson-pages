-- Create missing cleanup_oauth_states() function
-- Called by zoom-oauth edge function to purge expired OAuth state tokens
CREATE OR REPLACE FUNCTION public.cleanup_oauth_states()
RETURNS void
LANGUAGE sql
SECURITY DEFINER
AS $$
  DELETE FROM public.oauth_states
  WHERE created_at < now() - INTERVAL '10 minutes';
$$;
