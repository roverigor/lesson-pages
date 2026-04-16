-- Temporary helper to list cron jobs (will be used once then dropped)
CREATE OR REPLACE FUNCTION public.list_cron_jobs()
RETURNS TABLE(jobid bigint, jobname text, schedule text, command text)
LANGUAGE sql
SECURITY DEFINER
SET search_path = public, cron
AS $$
  SELECT jobid, jobname, schedule, command FROM cron.job ORDER BY jobname;
$$;
