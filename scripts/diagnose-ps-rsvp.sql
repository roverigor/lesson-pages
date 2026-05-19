-- ═══════════════════════════════════════════════════════════════════════════
-- Diagnóstico dispatch-ps-rsvp: grupos WA + lista alunos
-- Rodar no Supabase Studio → SQL Editor
-- ═══════════════════════════════════════════════════════════════════════════

-- 1) Classes PS ativas
SELECT id, name, weekday, time_start, kind, active
FROM classes
WHERE kind = 'ps' AND active = true
ORDER BY name;

-- 2) Bridge class_cohorts pra cada classe PS — mostra quais cohorts cada classe envia
SELECT
  c.name AS classe,
  c.weekday,
  co.id AS cohort_id,
  co.name AS cohort_name,
  co.active AS cohort_active,
  co.whatsapp_group_jid,
  co.whatsapp_group_name
FROM classes c
LEFT JOIN class_cohorts cc ON cc.class_id = c.id
LEFT JOIN cohorts co ON co.id = cc.cohort_id
WHERE c.kind = 'ps' AND c.active = true
ORDER BY c.name, co.name;

-- 3) Cohorts com grupo WA registrado vs sem
SELECT
  CASE WHEN whatsapp_group_jid IS NULL THEN 'sem_jid' ELSE 'com_jid' END AS status,
  COUNT(*) AS total
FROM cohorts
GROUP BY 1;

-- 4) Contagem alunos elegíveis por classe PS (regra exata do dispatcher)
WITH ps_classes AS (
  SELECT id, name, weekday FROM classes WHERE kind = 'ps' AND active = true
),
class_bound_cohorts AS (
  SELECT cc.class_id, cc.cohort_id FROM class_cohorts cc
  WHERE cc.class_id IN (SELECT id FROM ps_classes)
)
SELECT
  pc.name AS classe,
  pc.weekday,
  COUNT(s.id) FILTER (WHERE s.active = true AND s.is_mentor = false AND s.phone IS NOT NULL) AS elegiveis,
  COUNT(s.id) FILTER (WHERE s.active = true AND s.is_mentor = false AND s.phone IS NULL) AS sem_phone,
  COUNT(s.id) FILTER (WHERE s.active = true AND s.is_mentor = true) AS mentores_excluidos,
  COUNT(s.id) FILTER (WHERE s.active = false) AS inativos
FROM ps_classes pc
LEFT JOIN class_bound_cohorts cbc ON cbc.class_id = pc.id
LEFT JOIN students s ON s.cohort_id = cbc.cohort_id
GROUP BY pc.id, pc.name, pc.weekday
ORDER BY pc.name;

-- 5) Sample alunos elegíveis por classe (10 primeiros)
WITH ps_classes AS (
  SELECT id, name FROM classes WHERE kind = 'ps' AND active = true
)
SELECT
  pc.name AS classe,
  s.name AS aluno,
  s.phone,
  co.name AS cohort,
  s.is_mentor
FROM ps_classes pc
JOIN class_cohorts cc ON cc.class_id = pc.id
JOIN students s ON s.cohort_id = cc.cohort_id
JOIN cohorts co ON co.id = cc.cohort_id
WHERE s.active = true AND s.is_mentor = false AND s.phone IS NOT NULL
ORDER BY pc.name, s.name
LIMIT 30;

-- 6) Grupos WA distintos que receberiam dispatch por classe
SELECT
  c.name AS classe,
  co.name AS cohort,
  co.whatsapp_group_jid,
  co.whatsapp_group_name
FROM classes c
JOIN class_cohorts cc ON cc.class_id = c.id
JOIN cohorts co ON co.id = cc.cohort_id
WHERE c.kind = 'ps' AND c.active = true AND co.whatsapp_group_jid IS NOT NULL
ORDER BY c.name, co.name;

-- 7) Último round dispatch — verificar quem recebeu hoje (pré-migração Meta)
SELECT
  l.session_date,
  c.name AS classe,
  COUNT(*) AS total_links,
  COUNT(*) FILTER (WHERE l.send_status = 'sent') AS sent,
  COUNT(*) FILTER (WHERE l.send_status = 'failed') AS failed,
  COUNT(*) FILTER (WHERE l.send_status = 'pending') AS pending,
  COUNT(*) FILTER (WHERE l.evolution_message_id IS NOT NULL) AS via_evolution
FROM ps_rsvp_links l
JOIN classes c ON c.id = l.class_id
WHERE l.session_date >= CURRENT_DATE - INTERVAL '14 days'
GROUP BY l.session_date, c.name
ORDER BY l.session_date DESC, c.name;

-- 8) Cohorts SEM whatsapp_group_jid bound em classe PS — possíveis grupos faltando registrar
SELECT DISTINCT
  c.name AS classe_ps,
  co.name AS cohort_sem_grupo,
  co.active AS cohort_active
FROM classes c
JOIN class_cohorts cc ON cc.class_id = c.id
JOIN cohorts co ON co.id = cc.cohort_id
WHERE c.kind = 'ps' AND c.active = true
  AND co.whatsapp_group_jid IS NULL
ORDER BY c.name, co.name;
