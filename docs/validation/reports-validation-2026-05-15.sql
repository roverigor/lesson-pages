-- Relatórios — Queries de validação 2026-05-15
-- Cruza UI (painel.igorrover.com.br) com fonte de verdade no DB
-- Rodar via: supabase db remote query --file <este arquivo>
--   ou via: psql "$DATABASE_URL" -f <este arquivo>

-- ═══════════════════════════════════════════════════════════════════
-- RELATÓRIO B — Dashboard / Turmas (count alunos por cohort)
-- UI: admin/index.html linhas 1138-1140 + 1180-1188
--   - card "Alunos Ativos"   = COUNT(student_imports)
--   - card "Turmas Ativas"   = COUNT(cohorts WHERE active=true)
--   - card "Reuniões Zoom"   = COUNT(zoom_meetings)
--   - turmas-list[total]     = COUNT(student_imports GROUP BY cohort_id)
-- ═══════════════════════════════════════════════════════════════════

-- B.1 — Cards do dashboard (3 contadores topo)
SELECT
  'Alunos Ativos (student_imports)' AS metric,
  (SELECT COUNT(*) FROM student_imports) AS db_value;

SELECT
  'Turmas Ativas (cohorts.active=true)' AS metric,
  (SELECT COUNT(*) FROM cohorts WHERE active = true) AS db_value;

SELECT
  'Turmas Inativas (cohorts.active=false)' AS metric,
  (SELECT COUNT(*) FROM cohorts WHERE active = false) AS db_value;

SELECT
  'Reuniões Zoom (zoom_meetings)' AS metric,
  (SELECT COUNT(*) FROM zoom_meetings) AS db_value;

-- B.2 — Alunos por turma (ordem alfabética, igual à UI)
SELECT
  c.name AS turma,
  c.active,
  COUNT(si.id) AS alunos
FROM cohorts c
LEFT JOIN student_imports si ON si.cohort_id = c.id
GROUP BY c.id, c.name, c.active
ORDER BY c.active DESC, c.name;

-- B.3 — Checagem: student_imports órfão (cohort_id inválido)?
SELECT COUNT(*) AS imports_orfaos
FROM student_imports si
LEFT JOIN cohorts c ON c.id = si.cohort_id
WHERE c.id IS NULL;

-- ═══════════════════════════════════════════════════════════════════
-- RELATÓRIO D — Relatório de Presenças (/relatorio/)
-- UI: relatorio/index.html linhas 419-420 (loadData)
--   - mentor_attendance (LIMIT 2000)  ← SUSPEITO se DB > 2000
--   - attendance (LIMIT 2000, legacy) ← SUSPEITO
--   - merge dedup por (session_date|mentor_name|class_name)
--   - summary: sessions únicas (date|class), present, absent, members
-- ═══════════════════════════════════════════════════════════════════

-- D.1 — Volume real vs limite UI
SELECT
  'mentor_attendance' AS tabela,
  COUNT(*) AS total_rows,
  CASE WHEN COUNT(*) > 2000 THEN '⚠ EXCEDE LIMIT(2000) DA UI' ELSE 'OK' END AS alerta
FROM mentor_attendance
UNION ALL
SELECT
  'attendance (legacy)',
  COUNT(*),
  CASE WHEN COUNT(*) > 2000 THEN '⚠ EXCEDE LIMIT(2000) DA UI' ELSE 'OK' END
FROM attendance;

-- D.2 — Summary cards (sem filtros, todo período)
--   UI mostra: total aulas (sessions únicas), presenças, faltas, % presença, membros
WITH merged AS (
  -- new records
  SELECT
    ma.session_date,
    m.name AS mentor_name,
    c.name AS class_name,
    ma.status
  FROM mentor_attendance ma
  LEFT JOIN mentors m ON m.id = ma.mentor_id
  LEFT JOIN classes c ON c.id = ma.class_id
  UNION ALL
  -- legacy (apenas onde não há new com mesma chave)
  SELECT
    a.lesson_date AS session_date,
    a.teacher_name AS mentor_name,
    a.course AS class_name,
    a.status
  FROM attendance a
  WHERE NOT EXISTS (
    SELECT 1
    FROM mentor_attendance ma2
    JOIN mentors m2 ON m2.id = ma2.mentor_id
    JOIN classes c2 ON c2.id = ma2.class_id
    WHERE ma2.session_date = a.lesson_date
      AND LOWER(TRIM(m2.name)) = LOWER(TRIM(a.teacher_name))
      AND LOWER(TRIM(c2.name)) = LOWER(TRIM(a.course))
  )
)
SELECT
  COUNT(DISTINCT (session_date::text || '|' || COALESCE(class_name, ''))) AS total_aulas_unicas,
  COUNT(*) FILTER (WHERE status = 'present') AS presencas,
  COUNT(*) FILTER (WHERE status = 'absent')  AS faltas,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE status = 'present')
    / NULLIF(COUNT(*), 0),
    0
  ) AS taxa_presenca_pct,
  COUNT(DISTINCT mentor_name) AS membros
FROM merged;

-- D.3 — Distribuição por mês (detectar truncagem por LIMIT 2000)
SELECT
  TO_CHAR(session_date, 'YYYY-MM') AS mes,
  COUNT(*) AS rows_mentor_attendance
FROM mentor_attendance
GROUP BY 1
ORDER BY 1;

SELECT
  TO_CHAR(lesson_date, 'YYYY-MM') AS mes,
  COUNT(*) AS rows_attendance_legacy
FROM attendance
GROUP BY 1
ORDER BY 1;

-- D.4 — Sanity: registros que UI mostraria como "Desconhecido"
--   (mentor_id sem match em mentors, ou class_id sem match em classes)
SELECT
  'mentor_attendance com mentor_id órfão' AS issue,
  COUNT(*) AS count
FROM mentor_attendance ma
LEFT JOIN mentors m ON m.id = ma.mentor_id
WHERE m.id IS NULL
UNION ALL
SELECT
  'mentor_attendance com class_id órfão',
  COUNT(*)
FROM mentor_attendance ma
LEFT JOIN classes c ON c.id = ma.class_id
WHERE c.id IS NULL;

-- D.5 — Status inválido (esperado: 'present' | 'absent' apenas)
SELECT 'mentor_attendance' AS tabela, status, COUNT(*) AS count
FROM mentor_attendance GROUP BY status
UNION ALL
SELECT 'attendance', status, COUNT(*)
FROM attendance GROUP BY status
ORDER BY 1, 2;

-- ═══════════════════════════════════════════════════════════════════
-- RELATÓRIO C — Admin / Relatório por Mentor (renderReport)
-- UI: js/admin/views.js linha 37 (renderReport)
--   - EVENTS = cronograma derivado de class_mentors (não tem registro)
--   - attendanceCache = mentor_attendance carregado em memória
--   - por mentor: presents / absents / pending baseado em (date|course|name)
-- ═══════════════════════════════════════════════════════════════════

-- C.1 — Por mentor: presenças, faltas, registros pendentes
--   Assume "aula esperada" = class_mentors ativos (valid_until IS NULL)
SELECT
  m.name AS mentor,
  m.role AS role_geral,
  COUNT(*) FILTER (WHERE ma.status = 'present') AS presencas,
  COUNT(*) FILTER (WHERE ma.status = 'absent')  AS faltas,
  COUNT(*) AS registros_total,
  ROUND(
    100.0 * COUNT(*) FILTER (WHERE ma.status = 'present')
    / NULLIF(COUNT(*), 0),
    0
  ) AS frequencia_pct
FROM mentors m
LEFT JOIN mentor_attendance ma ON ma.mentor_id = m.id
WHERE m.active = true
GROUP BY m.id, m.name, m.role
ORDER BY m.name;

-- C.2 — Mentores sem nenhum registro (pendência total)
SELECT m.name, m.role
FROM mentors m
WHERE m.active = true
  AND NOT EXISTS (SELECT 1 FROM mentor_attendance ma WHERE ma.mentor_id = m.id)
ORDER BY m.name;

-- C.3 — class_mentors ativos vs aulas esperadas
--   (Quantas aulas cada mentor deveria ter no período do programa?)
SELECT
  m.name AS mentor,
  c.name AS turma,
  cm.role AS funcao_na_turma,
  cm.weekday,
  cm.valid_until
FROM class_mentors cm
JOIN mentors m ON m.id = cm.mentor_id
JOIN classes c ON c.id = cm.class_id
WHERE cm.valid_until IS NULL
ORDER BY m.name, c.name;

-- ═══════════════════════════════════════════════════════════════════
-- DIAGNÓSTICOS GERAIS
-- ═══════════════════════════════════════════════════════════════════

-- G.1 — Última atividade em cada tabela crítica
SELECT 'mentor_attendance' AS tabela, MAX(created_at) AS ultimo
FROM mentor_attendance
UNION ALL
SELECT 'attendance', MAX(created_at) FROM attendance
UNION ALL
SELECT 'student_imports', MAX(created_at) FROM student_imports
UNION ALL
SELECT 'zoom_meetings', MAX(created_at) FROM zoom_meetings
ORDER BY ultimo DESC NULLS LAST;

-- G.2 — Duplicatas em mentor_attendance (UNIQUE constraint deve bloquear)
SELECT mentor_id, class_id, session_date, COUNT(*)
FROM mentor_attendance
GROUP BY 1, 2, 3
HAVING COUNT(*) > 1;
