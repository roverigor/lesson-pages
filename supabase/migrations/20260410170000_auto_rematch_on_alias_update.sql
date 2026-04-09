-- Auto-rematch trigger: when students.aliases is updated,
-- re-match unmatched zoom_participants against new aliases.
-- Replicates the normalize() logic from zoom-attendance/index.ts in SQL.

-- Helper: normalize name (lowercase, strip accents, remove non-alnum, collapse spaces)
CREATE OR REPLACE FUNCTION public.normalize_name(input TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
  SELECT TRIM(
    regexp_replace(
      regexp_replace(
        lower(unaccent(COALESCE(input, ''))),
        '[^a-z0-9\s]', '', 'g'
      ),
      '\s+', ' ', 'g'
    )
  )
$$;

-- Helper: clean participant name (remove " - suffix" and phone patterns)
CREATE OR REPLACE FUNCTION public.clean_participant_name(raw TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE AS $$
  SELECT TRIM(
    regexp_replace(
      regexp_replace(
        COALESCE(raw, ''),
        '\s+-\s+.+$', '', 'g'
      ),
      '\s*[\+\(]?\d[\d\s\(\)\-\.]{4,}\d\s*', ' ', 'g'
    )
  )
$$;

-- Trigger function: on aliases update, rematch unmatched participants
CREATE OR REPLACE FUNCTION public.trg_rematch_on_alias_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_alias TEXT;
  v_norm_alias TEXT;
  v_participant RECORD;
  v_meeting RECORD;
  v_matched_count INT := 0;
BEGIN
  -- Only proceed if aliases actually changed
  IF OLD.aliases IS NOT DISTINCT FROM NEW.aliases THEN
    RETURN NEW;
  END IF;

  -- Determine which aliases are new (in NEW but not in OLD)
  -- For each new alias, try to match unmatched participants
  FOR v_alias IN
    SELECT unnest(COALESCE(NEW.aliases, '{}'))
    EXCEPT
    SELECT unnest(COALESCE(OLD.aliases, '{}'))
  LOOP
    v_norm_alias := normalize_name(v_alias);
    IF v_norm_alias = '' THEN CONTINUE; END IF;

    -- Find unmatched zoom_participants where normalized name matches
    FOR v_participant IN
      SELECT zp.id AS zp_id,
             zp.meeting_id,
             zp.participant_name,
             zp.duration_minutes
      FROM zoom_participants zp
      WHERE zp.matched = false
        AND zp.student_id IS NULL
        AND (
          -- Exact alias match
          normalize_name(clean_participant_name(zp.participant_name)) = v_norm_alias
          -- Prefix match: participant starts with alias or alias starts with participant
          OR normalize_name(clean_participant_name(zp.participant_name)) LIKE v_norm_alias || ' %'
          OR v_norm_alias LIKE normalize_name(clean_participant_name(zp.participant_name)) || ' %'
        )
    LOOP
      -- Update zoom_participant as matched
      UPDATE zoom_participants
      SET student_id = NEW.id, matched = true
      WHERE id = v_participant.zp_id;

      -- Get meeting info for attendance record
      SELECT zm.id, zm.meeting_date, zm.cohort_id
      INTO v_meeting
      FROM zoom_meetings zm
      WHERE zm.id = v_participant.meeting_id;

      -- Create student_attendance if not exists
      IF v_meeting.id IS NOT NULL AND v_meeting.meeting_date IS NOT NULL THEN
        INSERT INTO student_attendance (
          student_id, class_date, cohort_id, zoom_meeting_id,
          zoom_participant_id, source, duration_minutes
        )
        VALUES (
          NEW.id,
          v_meeting.meeting_date::date,
          v_meeting.cohort_id,
          v_meeting.id,
          v_participant.zp_id,
          'alias_rematch',
          v_participant.duration_minutes
        )
        ON CONFLICT DO NOTHING;
      END IF;

      v_matched_count := v_matched_count + 1;
    END LOOP;
  END LOOP;

  -- Also try matching by full student name (in case name was updated too)
  IF OLD.name IS DISTINCT FROM NEW.name AND NEW.name IS NOT NULL THEN
    FOR v_participant IN
      SELECT zp.id AS zp_id,
             zp.meeting_id,
             zp.participant_name,
             zp.duration_minutes
      FROM zoom_participants zp
      WHERE zp.matched = false
        AND zp.student_id IS NULL
        AND normalize_name(clean_participant_name(zp.participant_name)) = normalize_name(NEW.name)
    LOOP
      UPDATE zoom_participants
      SET student_id = NEW.id, matched = true
      WHERE id = v_participant.zp_id;

      SELECT zm.id, zm.meeting_date, zm.cohort_id
      INTO v_meeting
      FROM zoom_meetings zm
      WHERE zm.id = v_participant.meeting_id;

      IF v_meeting.id IS NOT NULL AND v_meeting.meeting_date IS NOT NULL THEN
        INSERT INTO student_attendance (
          student_id, class_date, cohort_id, zoom_meeting_id,
          zoom_participant_id, source, duration_minutes
        )
        VALUES (
          NEW.id,
          v_meeting.meeting_date::date,
          v_meeting.cohort_id,
          v_meeting.id,
          v_participant.zp_id,
          'alias_rematch',
          v_participant.duration_minutes
        )
        ON CONFLICT DO NOTHING;
      END IF;
    END LOOP;
  END IF;

  RETURN NEW;
END;
$$;

-- Create the trigger
DROP TRIGGER IF EXISTS trg_student_alias_rematch ON students;
CREATE TRIGGER trg_student_alias_rematch
  AFTER UPDATE OF aliases, name ON students
  FOR EACH ROW
  EXECUTE FUNCTION trg_rematch_on_alias_update();
