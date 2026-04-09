-- Fix: engagement_daily_ranking uses ref_date, not ranking_date

CREATE OR REPLACE FUNCTION public.merge_students(
  p_primary_id UUID,
  p_secondary_ids UUID[]
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_primary RECORD;
  v_sec_id UUID;
  v_sec RECORD;
  v_moved JSONB := '{}'::JSONB;
  v_count INT;
  v_all_aliases TEXT[] := '{}';
  v_all_cohort_ids UUID[] := '{}';
  v_cohort_id UUID;
BEGIN
  -- Validate primary exists and is active
  SELECT * INTO v_primary FROM students WHERE id = p_primary_id AND active = true;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Primary student not found or inactive');
  END IF;

  v_all_aliases := COALESCE(v_primary.aliases, '{}');
  v_all_cohort_ids := ARRAY[v_primary.cohort_id];

  FOREACH v_sec_id IN ARRAY p_secondary_ids LOOP
    IF v_sec_id = p_primary_id THEN CONTINUE; END IF;

    SELECT * INTO v_sec FROM students WHERE id = v_sec_id;
    IF NOT FOUND THEN CONTINUE; END IF;

    IF v_sec.aliases IS NOT NULL THEN
      v_all_aliases := v_all_aliases || v_sec.aliases;
    END IF;
    IF v_sec.name IS NOT NULL AND v_sec.name <> '' AND v_sec.name <> v_primary.name THEN
      v_all_aliases := array_append(v_all_aliases, v_sec.name);
    END IF;
    IF v_sec.cohort_id IS NOT NULL THEN
      v_all_cohort_ids := array_append(v_all_cohort_ids, v_sec.cohort_id);
    END IF;

    -- student_attendance
    UPDATE student_attendance SET student_id = p_primary_id
    WHERE student_id = v_sec_id
      AND NOT EXISTS (
        SELECT 1 FROM student_attendance sa2
        WHERE sa2.student_id = p_primary_id
          AND sa2.class_date = student_attendance.class_date
          AND sa2.zoom_meeting_id IS NOT DISTINCT FROM student_attendance.zoom_meeting_id
      );
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('student_attendance', COALESCE((v_moved->>'student_attendance')::int, 0) + v_count);
    DELETE FROM student_attendance WHERE student_id = v_sec_id;

    -- zoom_participants
    UPDATE zoom_participants SET student_id = p_primary_id WHERE student_id = v_sec_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('zoom_participants', COALESCE((v_moved->>'zoom_participants')::int, 0) + v_count);

    -- student_cohorts
    INSERT INTO student_cohorts (student_id, cohort_id)
    SELECT p_primary_id, sc.cohort_id
    FROM student_cohorts sc
    WHERE sc.student_id = v_sec_id
      AND NOT EXISTS (
        SELECT 1 FROM student_cohorts sc2
        WHERE sc2.student_id = p_primary_id AND sc2.cohort_id = sc.cohort_id
      );
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('student_cohorts', COALESCE((v_moved->>'student_cohorts')::int, 0) + v_count);
    DELETE FROM student_cohorts WHERE student_id = v_sec_id;

    -- student_nps
    UPDATE student_nps SET student_id = p_primary_id WHERE student_id = v_sec_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('student_nps', COALESCE((v_moved->>'student_nps')::int, 0) + v_count);

    -- survey_links
    UPDATE survey_links SET student_id = p_primary_id WHERE student_id = v_sec_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('survey_links', COALESCE((v_moved->>'survey_links')::int, 0) + v_count);

    -- survey_responses
    UPDATE survey_responses SET student_id = p_primary_id WHERE student_id = v_sec_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('survey_responses', COALESCE((v_moved->>'survey_responses')::int, 0) + v_count);

    -- whatsapp_group_messages
    UPDATE whatsapp_group_messages SET student_id = p_primary_id WHERE student_id = v_sec_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('whatsapp_group_messages', COALESCE((v_moved->>'whatsapp_group_messages')::int, 0) + v_count);

    -- zoom_absence_alerts
    UPDATE zoom_absence_alerts SET student_id = p_primary_id WHERE student_id = v_sec_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('zoom_absence_alerts', COALESCE((v_moved->>'zoom_absence_alerts')::int, 0) + v_count);

    -- zoom_chat_messages
    UPDATE zoom_chat_messages SET student_id = p_primary_id WHERE student_id = v_sec_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('zoom_chat_messages', COALESCE((v_moved->>'zoom_chat_messages')::int, 0) + v_count);

    -- zoom_link_audit
    UPDATE zoom_link_audit SET student_id = p_primary_id WHERE student_id = v_sec_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('zoom_link_audit', COALESCE((v_moved->>'zoom_link_audit')::int, 0) + v_count);

    -- class_recording_notifications
    UPDATE class_recording_notifications SET student_id = p_primary_id WHERE student_id = v_sec_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('class_recording_notifications', COALESCE((v_moved->>'class_recording_notifications')::int, 0) + v_count);

    -- engagement_daily_ranking
    UPDATE engagement_daily_ranking SET student_id = p_primary_id
    WHERE student_id = v_sec_id
      AND NOT EXISTS (
        SELECT 1 FROM engagement_daily_ranking edr2
        WHERE edr2.student_id = p_primary_id
          AND edr2.ref_date = engagement_daily_ranking.ref_date
      );
    DELETE FROM engagement_daily_ranking WHERE student_id = v_sec_id;
    GET DIAGNOSTICS v_count = ROW_COUNT;
    v_moved := v_moved || jsonb_build_object('engagement_daily_ranking', COALESCE((v_moved->>'engagement_daily_ranking')::int, 0) + v_count);

    -- Deactivate secondary
    UPDATE students SET active = false, phone = 'merged_into_' || p_primary_id::text
    WHERE id = v_sec_id;
  END LOOP;

  -- Deduplicate aliases
  SELECT ARRAY(SELECT DISTINCT unnest FROM unnest(v_all_aliases) WHERE unnest IS NOT NULL AND unnest <> '')
  INTO v_all_aliases;

  UPDATE students SET aliases = v_all_aliases WHERE id = p_primary_id;

  -- Fill phone from secondaries if primary has pending
  IF v_primary.phone IS NULL OR v_primary.phone LIKE 'pending_%' THEN
    UPDATE students SET phone = sub.phone
    FROM (
      SELECT phone FROM students
      WHERE id = ANY(p_secondary_ids)
        AND phone IS NOT NULL AND phone NOT LIKE 'pending_%' AND phone NOT LIKE 'merged_%'
      LIMIT 1
    ) sub
    WHERE students.id = p_primary_id;
  END IF;

  -- Fill email from secondaries if null
  IF v_primary.email IS NULL THEN
    UPDATE students SET email = sub.email
    FROM (
      SELECT email FROM students
      WHERE id = ANY(p_secondary_ids) AND email IS NOT NULL
      LIMIT 1
    ) sub
    WHERE students.id = p_primary_id;
  END IF;

  -- Ensure all cohorts in student_cohorts
  FOREACH v_cohort_id IN ARRAY v_all_cohort_ids LOOP
    INSERT INTO student_cohorts (student_id, cohort_id)
    VALUES (p_primary_id, v_cohort_id)
    ON CONFLICT DO NOTHING;
  END LOOP;

  RETURN jsonb_build_object(
    'ok', true,
    'primary_id', p_primary_id,
    'merged_count', array_length(p_secondary_ids, 1),
    'moved', v_moved,
    'aliases', v_all_aliases,
    'cohorts', v_all_cohort_ids
  );
END;
$$;
