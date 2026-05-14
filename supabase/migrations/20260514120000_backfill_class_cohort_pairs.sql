-- ═══════════════════════════════════════════════════════════════════════
-- Backfill: cria cohorts faltantes pra classes existentes + vincula
-- ═══════════════════════════════════════════════════════════════════════
-- Contexto: "Config. Turmas" no admin inseria em `classes` mas /turma/
-- lista `cohorts`. Turmas cadastradas antes da sync (fix 1ee6c1e) não
-- apareciam em /turma/. Esta migration cria cohorts retroativos com
-- mesmo nome de cada class órfã + popula class_cohorts pivot.
--
-- Idempotente: ON CONFLICT DO NOTHING em ambos INSERTs.
-- ═══════════════════════════════════════════════════════════════════════

-- ─── 1. Criar cohort com mesmo nome de cada class sem cohort homônimo ───
INSERT INTO public.cohorts (name, start_date, end_date, zoom_link, active)
SELECT DISTINCT
  c.name,
  c.start_date,
  c.end_date,
  c.zoom_link,
  COALESCE(c.active, true)
FROM public.classes c
LEFT JOIN public.cohorts co ON co.name = c.name
WHERE co.id IS NULL
ON CONFLICT (name) DO NOTHING;

-- ─── 2. Vincular cada class ao cohort de mesmo nome via class_cohorts ───
INSERT INTO public.class_cohorts (class_id, cohort_id)
SELECT c.id, co.id
FROM public.classes c
JOIN public.cohorts co ON co.name = c.name
LEFT JOIN public.class_cohorts cc ON cc.class_id = c.id AND cc.cohort_id = co.id
WHERE cc.id IS NULL
ON CONFLICT (class_id, cohort_id) DO NOTHING;

-- ─── Verificação (opcional, só loga) ───
DO $$
DECLARE
  orphan_count INT;
BEGIN
  SELECT COUNT(*) INTO orphan_count
  FROM public.classes c
  LEFT JOIN public.cohorts co ON co.name = c.name
  WHERE co.id IS NULL;

  IF orphan_count > 0 THEN
    RAISE WARNING 'Backfill: % class(es) ainda sem cohort homônimo após backfill', orphan_count;
  ELSE
    RAISE LOG 'Backfill: todas classes têm cohort homônimo';
  END IF;
END $$;
