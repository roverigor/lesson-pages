-- Nightly auto-merge of obvious duplicate students.
-- Criteria: same phone (non-null, non-pending) AND same normalized name.
-- Ambiguous cases (same phone but different names) are skipped for manual review.
-- Runs daily at 03:00 UTC via pg_cron.

CREATE OR REPLACE FUNCTION public.auto_merge_obvious_duplicates()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_group RECORD;
  v_primary_id UUID;
  v_secondary_ids UUID[];
  v_merge_result JSONB;
  v_total_merged INT := 0;
  v_total_groups INT := 0;
  v_skipped_ambiguous INT := 0;
  v_errors TEXT[] := '{}';
BEGIN
  -- Find groups of active students with same phone (non-null, non-pending, non-merged)
  FOR v_group IN
    SELECT s.phone,
           array_agg(s.id ORDER BY s.created_at ASC) AS student_ids,
           array_agg(DISTINCT normalize_name(s.name)) AS distinct_names,
           count(*) AS cnt
    FROM students s
    WHERE s.active = true
      AND s.phone IS NOT NULL
      AND s.phone NOT LIKE 'pending_%'
      AND s.phone NOT LIKE 'merged_%'
      AND LENGTH(s.phone) >= 10
    GROUP BY s.phone
    HAVING count(*) > 1
  LOOP
    -- Only auto-merge if all students in the group have the same normalized name
    -- (obvious duplicates). If names differ, skip for manual review.
    IF array_length(v_group.distinct_names, 1) > 1 THEN
      v_skipped_ambiguous := v_skipped_ambiguous + 1;
      CONTINUE;
    END IF;

    -- Primary = oldest (first created), rest are secondaries
    v_primary_id := v_group.student_ids[1];
    v_secondary_ids := v_group.student_ids[2:];

    -- Call the existing merge_students function
    BEGIN
      v_merge_result := merge_students(v_primary_id, v_secondary_ids);
      IF (v_merge_result->>'ok')::boolean THEN
        v_total_merged := v_total_merged + array_length(v_secondary_ids, 1);
        v_total_groups := v_total_groups + 1;
      ELSE
        v_errors := array_append(v_errors,
          'phone=' || v_group.phone || ': ' || COALESCE(v_merge_result->>'error', 'unknown'));
      END IF;
    EXCEPTION WHEN OTHERS THEN
      v_errors := array_append(v_errors,
        'phone=' || v_group.phone || ': ' || SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'groups_merged', v_total_groups,
    'students_deactivated', v_total_merged,
    'skipped_ambiguous', v_skipped_ambiguous,
    'errors', v_errors,
    'ran_at', now()::text
  );
END;
$$;

-- Schedule nightly at 03:00 UTC (midnight BRT)
SELECT cron.unschedule('nightly-auto-merge-duplicates')
WHERE EXISTS (
  SELECT 1 FROM cron.job WHERE jobname = 'nightly-auto-merge-duplicates'
);

SELECT cron.schedule(
  'nightly-auto-merge-duplicates',
  '0 3 * * *',
  $$SELECT public.auto_merge_obvious_duplicates()$$
);
