# NPS Test Tokens — Manual Generation

Until P3 (post-class NPS dispatcher) is implemented, tokens for the NPS landing page must be generated manually for QA / pilot tests.

## Generate a group (anonymous) token

Run in Supabase SQL editor:

```sql
INSERT INTO nps_class_links (
  token, class_id, cohort_id, trigger_date, mode, expires_at, created_by
)
SELECT
  encode(gen_random_bytes(18), 'base64') AS token,
  cc.class_id,
  cc.cohort_id,
  CURRENT_DATE,
  'group',
  CURRENT_DATE + interval '14 days',
  'qa-manual'
FROM class_cohorts cc
WHERE cc.class_id = '<CLASS_UUID>'
  AND cc.cohort_id = '<COHORT_UUID>'
RETURNING
  token,
  'https://painel.igorrover.com.br/survey/grupo/' || token AS url;
```

Replace `<CLASS_UUID>` and `<COHORT_UUID>` with real IDs.

The query returns the token + the full URL to share for testing.

## Generate a DM (per-student) token

```sql
INSERT INTO nps_class_links (
  token, class_id, cohort_id, trigger_date, mode, student_id, expires_at, created_by
)
SELECT
  encode(gen_random_bytes(18), 'base64') AS token,
  '<CLASS_UUID>',
  '<COHORT_UUID>',
  CURRENT_DATE,
  'dm',
  '<STUDENT_UUID>',
  CURRENT_DATE + interval '14 days',
  'qa-manual'
RETURNING
  token,
  'https://painel.igorrover.com.br/survey/aluno/' || token AS url;
```

## Inspect responses

```sql
SELECT
  r.nps_score,
  r.comment,
  r.name_provided,
  r.mode,
  s.name AS student_name,
  c.title AS class_name,
  co.name AS cohort_name,
  r.submitted_at
FROM class_nps_responses r
JOIN classes c ON c.id = r.class_id
JOIN cohorts co ON co.id = r.cohort_id
LEFT JOIN students s ON s.id = r.student_id
WHERE r.submitted_at > now() - interval '7 days'
ORDER BY r.submitted_at DESC;
```

## NPS aggregate per class

```sql
SELECT
  c.title,
  co.name,
  COUNT(*) AS responses,
  ROUND(AVG(nps_score)::numeric, 1) AS avg_score,
  COUNT(*) FILTER (WHERE nps_score >= 9) AS promoters,
  COUNT(*) FILTER (WHERE nps_score <= 6) AS detractors,
  ROUND(
    100.0 * (COUNT(*) FILTER (WHERE nps_score >= 9) - COUNT(*) FILTER (WHERE nps_score <= 6))
    / NULLIF(COUNT(*), 0),
    1
  ) AS nps
FROM class_nps_responses r
JOIN classes c ON c.id = r.class_id
JOIN cohorts co ON co.id = r.cohort_id
GROUP BY c.title, co.name
ORDER BY responses DESC;
```

## Revoke a token early

```sql
UPDATE nps_class_links SET expires_at = now() WHERE token = '<TOKEN>';
```

## Delete a test token and all its responses

```sql
DELETE FROM nps_class_links WHERE token = '<TOKEN>';
-- Cascades to class_nps_responses via FK ON DELETE CASCADE.
```

## Find recent QA tokens

```sql
SELECT token, mode, trigger_date, response_count, expires_at
FROM nps_class_links
WHERE created_by LIKE 'qa-%'
ORDER BY created_at DESC LIMIT 20;
```
