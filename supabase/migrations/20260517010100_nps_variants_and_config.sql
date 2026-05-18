-- ═══════════════════════════════════════════════════════════════════════════
-- P3 — NPS message variants (round-robin) + dispatch config flag
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.nps_message_variants (
  id                  TEXT PRIMARY KEY,
  channel             TEXT NOT NULL CHECK (channel IN ('group','dm')),
  body_template       TEXT NOT NULL,
  meta_template_name  TEXT,
  active              BOOLEAN NOT NULL DEFAULT true,
  weight              INT NOT NULL DEFAULT 1 CHECK (weight > 0),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_nps_variants_channel_active
  ON public.nps_message_variants (channel, active)
  WHERE active = true;

CREATE TABLE IF NOT EXISTS public.nps_variant_rotation_state (
  channel             TEXT PRIMARY KEY CHECK (channel IN ('group','dm')),
  last_variant_id     TEXT REFERENCES public.nps_message_variants(id) ON DELETE SET NULL,
  rotation_count      BIGINT NOT NULL DEFAULT 0,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Config table (gate-protected)
CREATE TABLE IF NOT EXISTS public.nps_dispatch_config (
  key                 TEXT PRIMARY KEY,
  value               TEXT NOT NULL,
  description         TEXT,
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

INSERT INTO public.nps_dispatch_config (key, value, description) VALUES
  ('nps_dispatch_enabled', 'false', 'Master flag — leave false until Meta templates approved and smoke-tested.'),
  ('nps_cohort_cooldown_hours', '12', 'Min hours between two dispatch jobs for same cohort.'),
  ('nps_dispatch_delay_minutes', '5', 'Delay between enqueue and earliest send (lets attendance import settle).'),
  ('nps_dispatch_max_dm_per_run', '50', 'Max DMs per dispatch-class-nps cron tick.'),
  ('nps_dispatch_dm_throttle_ms', '10000', 'Throttle between Meta API DM calls.')
ON CONFLICT (key) DO NOTHING;

-- Seed variants — body_template uses {{class_name}}, {{cohort_name}}, {{link}}
INSERT INTO public.nps_message_variants (id, channel, body_template, meta_template_name, active, weight) VALUES
  -- Group variants (Evolution — free text)
  ('group_v1', 'group',
   E'Pessoal, obrigado pela presença em *{{class_name}}* hoje! 💜\n\nQueremos saber como foi pra vocês.\nResponde rapidinho aqui (anônimo, opção de colocar nome): {{link}}',
   NULL, true, 1),
  ('group_v2', 'group',
   E'Galera, fechamos *{{class_name}}* agora! 🚀\n\nUma pergunta rápida pra gente continuar evoluindo o conteúdo: {{link}}\n\nLeva 30s, podem responder sem se identificar.',
   NULL, true, 1),
  ('group_v3', 'group',
   E'Time {{cohort_name}}! 👋\n\nFeedback express da aula de hoje (*{{class_name}}*) — sua opinião direciona os próximos encontros:\n{{link}}',
   NULL, true, 1),
  -- DM variants (Meta templates — names referenced; deploy needs approval)
  ('dm_v1', 'dm', 'NPS pós-aula individual — variant 1', 'nps_post_class_v1', false, 1),
  ('dm_v2', 'dm', 'NPS pós-aula individual — variant 2', 'nps_post_class_v2', false, 1),
  ('dm_v3', 'dm', 'NPS pós-aula individual — variant 3', 'nps_post_class_v3', false, 1)
ON CONFLICT (id) DO NOTHING;

-- Initialize rotation state
INSERT INTO public.nps_variant_rotation_state (channel, last_variant_id) VALUES
  ('group', NULL),
  ('dm', NULL)
ON CONFLICT (channel) DO NOTHING;

-- RLS
ALTER TABLE public.nps_message_variants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nps_variant_rotation_state ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.nps_dispatch_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS nps_variants_service_all ON public.nps_message_variants;
CREATE POLICY nps_variants_service_all ON public.nps_message_variants
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS nps_variants_admin_read ON public.nps_message_variants;
CREATE POLICY nps_variants_admin_read ON public.nps_message_variants
  FOR SELECT TO authenticated
  USING ((auth.jwt() ->> 'user_metadata')::jsonb ->> 'role' = 'admin');

DROP POLICY IF EXISTS nps_rotation_service_all ON public.nps_variant_rotation_state;
CREATE POLICY nps_rotation_service_all ON public.nps_variant_rotation_state
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS nps_config_service_all ON public.nps_dispatch_config;
CREATE POLICY nps_config_service_all ON public.nps_dispatch_config
  FOR ALL TO service_role USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS nps_config_admin_read ON public.nps_dispatch_config;
CREATE POLICY nps_config_admin_read ON public.nps_dispatch_config
  FOR SELECT TO authenticated
  USING ((auth.jwt() ->> 'user_metadata')::jsonb ->> 'role' = 'admin');

COMMENT ON TABLE public.nps_dispatch_config IS
  'P3: feature flags + tuning knobs for post-class NPS dispatcher. Gate-protected.';

COMMENT ON COLUMN public.nps_message_variants.active IS
  'DM variants ship inactive — flip to true after Meta template approval (see runbook).';
