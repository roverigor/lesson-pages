-- ═══════════════════════════════════════
-- EPIC-011: Map WhatsApp group JIDs to cohorts
-- Based on name matching between WA groups and cohort names
-- Run AFTER confirming cohort names match
-- ═══════════════════════════════════════

-- Log cohort names for verification
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT id, name FROM public.cohorts ORDER BY name LOOP
    RAISE NOTICE 'COHORT: % | %', r.id, r.name;
  END LOOP;
END;
$$;

-- Update JIDs based on name patterns found in Evolution API
-- Fundamentals T1
UPDATE public.cohorts
SET whatsapp_group_jid = '120363407322736559@g.us'
WHERE name ILIKE '%T1%' AND (name ILIKE '%Fundamental%' OR name ILIKE '%Fund%' OR name ILIKE '%AIOS%')
  AND whatsapp_group_jid IS NULL;

-- Fundamentals T2
UPDATE public.cohorts
SET whatsapp_group_jid = '120363406009222289@g.us'
WHERE name ILIKE '%T2%' AND (name ILIKE '%Fundamental%' OR name ILIKE '%Fund%' OR name ILIKE '%AIOS%')
  AND whatsapp_group_jid IS NULL;

-- Fundamentals T3
UPDATE public.cohorts
SET whatsapp_group_jid = '120363408861350309@g.us'
WHERE name ILIKE '%T3%' AND (name ILIKE '%Fundamental%' OR name ILIKE '%Fund%' OR name ILIKE '%AIOS%')
  AND whatsapp_group_jid IS NULL;

-- Fundamentals T4
UPDATE public.cohorts
SET whatsapp_group_jid = '120363426800752386@g.us'
WHERE name ILIKE '%T4%' AND (name ILIKE '%Fundamental%' OR name ILIKE '%Fund%' OR name ILIKE '%AIOS%')
  AND whatsapp_group_jid IS NULL;

-- Advanced (T1 / sem número = primeiro Advanced)
UPDATE public.cohorts
SET whatsapp_group_jid = '120363423250471692@g.us'
WHERE (name ILIKE '%Advanced%' OR name ILIKE '%Avançado%')
  AND name NOT ILIKE '%T2%'
  AND whatsapp_group_jid IS NULL;

-- Advanced T2
UPDATE public.cohorts
SET whatsapp_group_jid = '120363423278234924@g.us'
WHERE (name ILIKE '%Advanced%' OR name ILIKE '%Avançado%')
  AND name ILIKE '%T2%'
  AND whatsapp_group_jid IS NULL;

-- Pronto Socorro
UPDATE public.cohorts
SET whatsapp_group_jid = '120363377271161130@g.us'
WHERE name ILIKE '%Pronto%Socorro%'
  AND whatsapp_group_jid IS NULL;

-- Verify result
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN SELECT name, whatsapp_group_jid FROM public.cohorts ORDER BY name LOOP
    RAISE NOTICE 'MAPPED: % -> %', r.name, COALESCE(r.whatsapp_group_jid, '(sem mapeamento)');
  END LOOP;
END;
$$;
