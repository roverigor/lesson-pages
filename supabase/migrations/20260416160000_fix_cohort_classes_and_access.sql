-- ═══════════════════════════════════════
-- Fix Cohort classes: reactivate T3, add class_cohort_access for all Cohort classes
-- Problem: Cohort Fundamentals T3 was inactive with no zoom_meeting_id,
--          and Cohort Advanced T2 / Cohort Fundamentals T4 had no cohort links.
-- ═══════════════════════════════════════

-- 1. Reactivate "Cohort Fundamentals T3" and set zoom_meeting_id
UPDATE classes
SET active = true,
    zoom_meeting_id = '78496807361',
    end_date = '2026-05-15'
WHERE id = 'd07846b9-00d9-4635-b76b-d74b62bcb99f'
  AND name = 'Cohort Fundamentals T3';

-- 2. Add class_cohort_access entries (idempotent with ON CONFLICT DO NOTHING)
-- access_until = class end_date + 1 month margin (matching existing pattern)

-- Cohort Advanced T2 → Advanced T2 (class end_date: 2026-05-27)
INSERT INTO class_cohort_access (class_id, cohort_id, access_until)
VALUES ('9583c980-35c9-4598-bd19-df4f3893f60f', '9f10cb6c-58c7-4e48-8bed-0603f404730e', '2026-06-28')
ON CONFLICT DO NOTHING;

-- Cohort Fundamentals T3 → Fundamental T3 (class end_date: 2026-05-15)
INSERT INTO class_cohort_access (class_id, cohort_id, access_until)
VALUES ('d07846b9-00d9-4635-b76b-d74b62bcb99f', 'd8abfd5c-a411-413c-b2ff-019b1488329d', '2026-06-15')
ON CONFLICT DO NOTHING;

-- Cohort Fundamentals T4 → Fundamental T4 (class end_date: 2026-05-13)
INSERT INTO class_cohort_access (class_id, cohort_id, access_until)
VALUES ('53244281-e47b-4985-a7cd-b19182b5db36', '7e807cad-483e-4248-a534-a03d13752731', '2026-06-13')
ON CONFLICT DO NOTHING;

-- 3. Backfill class_id on zoom_meetings for newly linked classes
UPDATE zoom_meetings zm
SET class_id = c.id
FROM classes c
WHERE c.zoom_meeting_id = zm.zoom_meeting_id
  AND c.active = true
  AND zm.class_id IS NULL;
