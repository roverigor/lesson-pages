-- ═══════════════════════════════════════════════════════════════════════
-- Diagnostic — Zoom Pipeline Sync Health
-- Cole no Supabase Studio (https://app.supabase.com/project/gpufcipkajppykmnmdeh/sql)
-- e revise outputs. Cada bloco é independente.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Última execução do cron daily-zoom-pipeline ───
SELECT
  run_type,
  step_name,
  status,
  processed,
  created,
  failed,
  error_message,
  metadata,
  started_at
FROM automation_runs
WHERE run_type = 'daily_pipeline'
ORDER BY started_at DESC
LIMIT 20;

-- ─── 2. Cron job está ativo + agendado ───
SELECT jobname, schedule, active, jobid
FROM cron.job
WHERE jobname IN ('daily-zoom-pipeline', 'wa-sync', 'absence-alerts');

-- ─── 3. Histórico de runs do cron (last 7 days) ───
SELECT jobname, status, start_time, end_time, return_message
FROM cron.job_run_details d
JOIN cron.job j ON j.jobid = d.jobid
WHERE jobname = 'daily-zoom-pipeline'
  AND start_time > NOW() - INTERVAL '7 days'
ORDER BY start_time DESC
LIMIT 30;

-- ─── 4. Mais recente zoom_meeting importada (gap = data atual - mais recente) ───
SELECT
  MAX(start_time AT TIME ZONE 'America/Sao_Paulo') AS last_meeting_brt,
  COUNT(*) AS total_meetings,
  COUNT(*) FILTER (WHERE start_time > NOW() - INTERVAL '7 days') AS last_7d,
  COUNT(*) FILTER (WHERE start_time > NOW() - INTERVAL '24 hours') AS last_24h
FROM zoom_meetings;

-- ─── 5. Meetings sem class_id resolvido (skipped no sync) ───
SELECT
  zm.id AS zoom_meeting_id,
  zm.zoom_meeting_id AS zoom_id,
  zm.topic,
  zm.start_time AT TIME ZONE 'America/Sao_Paulo' AS start_brt,
  zm.cohort_id,
  c.name AS cohort_name,
  zm.class_id
FROM zoom_meetings zm
LEFT JOIN cohorts c ON c.id = zm.cohort_id
WHERE zm.start_time > NOW() - INTERVAL '14 days'
  AND zm.class_id IS NULL
ORDER BY zm.start_time DESC
LIMIT 30;

-- ─── 6. Mentors esperados vs registrados por aula (últimos 7 dias) ───
WITH expected AS (
  SELECT
    c.id AS class_id,
    c.name AS class_name,
    cm.mentor_id,
    m.name AS mentor_name,
    cm.weekday,
    cm.role
  FROM classes c
  JOIN class_mentors cm ON cm.class_id = c.id
  JOIN mentors m ON m.id = cm.mentor_id
  WHERE c.active = true
    AND cm.valid_until IS NULL
    AND m.active = true
),
attended_recent AS (
  SELECT class_id, mentor_id, session_date
  FROM mentor_attendance
  WHERE session_date > CURRENT_DATE - INTERVAL '7 days'
)
SELECT
  e.class_name,
  e.mentor_name,
  e.role,
  e.weekday,
  COUNT(a.session_date) AS attended_sessions
FROM expected e
LEFT JOIN attended_recent a ON a.class_id = e.class_id AND a.mentor_id = e.mentor_id
GROUP BY e.class_name, e.mentor_name, e.role, e.weekday
ORDER BY e.class_name, attended_sessions ASC, e.mentor_name;

-- ─── 7. Mentor_attendance vs attendance (legacy) — totais por turma ───
SELECT
  COALESCE(c.name, '—') AS class_name,
  COUNT(DISTINCT ma.session_date) AS sessions_with_records,
  COUNT(*) AS total_records,
  COUNT(*) FILTER (WHERE ma.status = 'present') AS present,
  COUNT(*) FILTER (WHERE ma.status = 'absent') AS absent
FROM mentor_attendance ma
LEFT JOIN classes c ON c.id = ma.class_id
WHERE ma.session_date > CURRENT_DATE - INTERVAL '30 days'
GROUP BY c.name
ORDER BY sessions_with_records DESC;

-- ─── 8. Participantes Zoom não matched com mentor (potencial alias gap) ───
SELECT
  zp.participant_name,
  COUNT(*) AS occurrences,
  MIN(zm.start_time AT TIME ZONE 'America/Sao_Paulo') AS first_seen,
  MAX(zm.start_time AT TIME ZONE 'America/Sao_Paulo') AS last_seen
FROM zoom_participants zp
JOIN zoom_meetings zm ON zm.id = zp.meeting_id
WHERE zm.start_time > NOW() - INTERVAL '14 days'
  AND NOT EXISTS (
    SELECT 1 FROM mentors m
    WHERE LOWER(TRIM(m.name)) = LOWER(TRIM(zp.participant_name))
       OR LOWER(TRIM(zp.participant_name)) LIKE LOWER(TRIM(m.name)) || ' %'
       OR LOWER(TRIM(m.name)) LIKE LOWER(TRIM(zp.participant_name)) || ' %'
  )
  AND NOT EXISTS (
    SELECT 1 FROM student_imports si
    WHERE LOWER(TRIM(si.name)) = LOWER(TRIM(zp.participant_name))
  )
GROUP BY zp.participant_name
HAVING COUNT(*) >= 2
ORDER BY occurrences DESC
LIMIT 50;

-- ─── 9. Backfill manual — rodar sync de N dias atrás (se gap detectado) ───
-- SELECT * FROM public.sync_staff_attendance_from_zoom(p_days_back := 14);
