-- ═══════════════════════════════════════
-- LESSON PAGES — Seed: class_cohorts
-- Story 1.1 — EPIC-001
-- Mapeamento classes → cohorts baseado em dados reais do banco
-- ═══════════════════════════════════════

-- Classes → Cohorts mapeamento:
-- AIOS Fund T2 (Manhã/Tarde) → Fundamental T2
-- Aulas Advanced T1          → Advanced T1
-- Aulas Advanced T2          → Advanced T2
-- Aulas Fund T1              → Fundamental T1
-- Aulas Fund T3              → Fundamental T3
-- Imersão AIOX - Fundamentals → Imersão AIOX Fundamentals
-- PS Advanced                → Advanced T1 + Advanced T2
-- PS Fundamentals            → Fundamental T1 + Fundamental T2 + Fundamental T3

INSERT INTO class_cohorts (class_id, cohort_id) VALUES

  -- AIOS Fund T2 Manhã → Fundamental T2
  ('6fb7434e-c726-48b1-8d6c-1a5f4861d4d3', 'f99c360f-196d-46db-9445-9be6c6d3fdb3'),

  -- AIOS Fund T2 Tarde → Fundamental T2
  ('fb36bf9d-05af-4170-ace9-794c0f76ab4d', 'f99c360f-196d-46db-9445-9be6c6d3fdb3'),

  -- Aulas Advanced T1 → Advanced T1
  ('8ce8180f-b1ae-4448-8e04-c1446b8cf92c', 'c349ffd5-e2a2-446a-b559-96ebcd3958cb'),

  -- Aulas Advanced T2 → Advanced T2
  ('9583c980-35c9-4598-bd19-df4f3893f60f', '9f10cb6c-58c7-4e48-8bed-0603f404730e'),

  -- Aulas Fund T1 → Fundamental T1
  ('d7c791f9-b550-4f78-9beb-6d5b5b1a605e', '6214bbb0-afce-408e-9afb-89ca5aea1694'),

  -- Aulas Fund T3 → Fundamental T3
  ('d07846b9-00d9-4635-b76b-d74b62bcb99f', 'd8abfd5c-a411-413c-b2ff-019b1488329d'),

  -- Imersão AIOX - Fundamentals → Imersão AIOX Fundamentals
  ('5e852074-35cd-4a92-87f3-4e31400c5795', '718f9654-c102-467d-8b0d-eb2b2cc4cf73'),

  -- PS Advanced → Advanced T1
  ('985cb305-bcbb-4997-b7d6-60afa4ee9b29', 'c349ffd5-e2a2-446a-b559-96ebcd3958cb'),
  -- PS Advanced → Advanced T2
  ('985cb305-bcbb-4997-b7d6-60afa4ee9b29', '9f10cb6c-58c7-4e48-8bed-0603f404730e'),

  -- PS Fundamentals → Fundamental T1
  ('0e5df244-8068-4839-a1b1-2bf36616e0ab', '6214bbb0-afce-408e-9afb-89ca5aea1694'),
  -- PS Fundamentals → Fundamental T2
  ('0e5df244-8068-4839-a1b1-2bf36616e0ab', 'f99c360f-196d-46db-9445-9be6c6d3fdb3'),
  -- PS Fundamentals → Fundamental T3
  ('0e5df244-8068-4839-a1b1-2bf36616e0ab', 'd8abfd5c-a411-413c-b2ff-019b1488329d')

ON CONFLICT (class_id, cohort_id) DO NOTHING;

-- Clean up duplicate class_mentors using CTE (UUID has no MIN, use array_agg trick)
WITH dedup AS (
  SELECT DISTINCT ON (class_id, mentor_id, role, weekday) id
  FROM class_mentors
  ORDER BY class_id, mentor_id, role, weekday, id
)
DELETE FROM class_mentors
WHERE id NOT IN (SELECT id FROM dedup);
