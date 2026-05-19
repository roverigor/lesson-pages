-- ═══════════════════════════════════════════════════════════════════════════
-- PS RSVP — Meta Cloud API migration
--   • Adds meta_message_id column to ps_rsvp_links
--   • Adds ps_rsvp_variants table for rotation across approved Meta templates
--   • Seeds 5 inactive variants (flip active=true after Meta Business Manager approval)
-- ═══════════════════════════════════════════════════════════════════════════

ALTER TABLE ps_rsvp_links
  ADD COLUMN IF NOT EXISTS meta_message_id text;

CREATE TABLE IF NOT EXISTS ps_rsvp_variants (
  id                  TEXT PRIMARY KEY,
  meta_template_name  TEXT NOT NULL,
  body_preview        TEXT NOT NULL,
  active              BOOLEAN NOT NULL DEFAULT false,
  weight              INT NOT NULL DEFAULT 1 CHECK (weight > 0),
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ps_rsvp_variants_active
  ON ps_rsvp_variants (active)
  WHERE active = true;

INSERT INTO ps_rsvp_variants (id, meta_template_name, body_preview, active, weight) VALUES
  ('ps_rsvp_v1', 'ps_rsvp_v1',
   E'Bom dia, {{1}}.\n\nHoje rola *{{2}}* — {{3}} (Brasília).\n\nPra eu chegar preparado pro seu caso específico, me conta em 30s.',
   false, 1),
  ('ps_rsvp_v2', 'ps_rsvp_v2',
   E'{{1}}, bom dia.\n\nPS de hoje é *{{2}}*, {{3}}.\n\nQual ponto travado você quer destravar hoje? Conta aqui pro mentor já chegar com material relevante.',
   false, 1),
  ('ps_rsvp_v3', 'ps_rsvp_v3',
   E'Bom dia, {{1}}!\n\n*{{2}}* abre {{3}}. Pra valer cada minuto seu, o mentor adapta o foco baseado no que vocês trouxerem.\n\nLeva 30s.',
   false, 1),
  ('ps_rsvp_v4', 'ps_rsvp_v4',
   E'{{1}}, {{2}} hoje {{3}} (Brasília).\n\nMe diz o que você quer trabalhar — o PS rende muito mais com pauta pré-definida.',
   false, 1),
  ('ps_rsvp_v5', 'ps_rsvp_v5',
   E'Bom dia, {{1}}.\n\nHoje tem *{{2}}* — {{3}}. Conta rapidamente onde você está e o que precisa destravar; chega tudo pro mentor antes da sessão.',
   false, 1)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE ps_rsvp_variants ENABLE ROW LEVEL SECURITY;

CREATE POLICY ps_rsvp_variants_service ON ps_rsvp_variants
  FOR ALL TO service_role USING (true) WITH CHECK (true);

CREATE POLICY ps_rsvp_variants_admin_read ON ps_rsvp_variants
  FOR SELECT TO authenticated
  USING ((auth.jwt() ->> 'user_metadata')::jsonb ->> 'role' = 'admin');

GRANT ALL ON ps_rsvp_variants TO service_role;
GRANT SELECT ON ps_rsvp_variants TO authenticated;

COMMENT ON TABLE ps_rsvp_variants IS
  'PS RSVP rotation pool. Each row maps to an approved Meta Cloud API template (body params: {{1}}=first_name, {{2}}=class_name, {{3}}=time_start; button URL param: token). Seeded inactive — flip active=true per template after Meta Business Manager approval.';

COMMENT ON COLUMN ps_rsvp_links.meta_message_id IS
  'wamid returned by Meta Cloud API (graph.facebook.com). Replaces evolution_message_id for new sends; legacy column kept for historical rows.';
