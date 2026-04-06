-- ═══════════════════════════════════════
-- EPIC-004 Story 4.1 — surveys RLS
-- ═══════════════════════════════════════

-- ─── surveys RLS ───
ALTER TABLE surveys ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin read surveys"   ON surveys;
CREATE POLICY "Admin read surveys"   ON surveys FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin insert surveys" ON surveys;
CREATE POLICY "Admin insert surveys" ON surveys FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin update surveys" ON surveys;
CREATE POLICY "Admin update surveys" ON surveys FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin delete surveys" ON surveys;
CREATE POLICY "Admin delete surveys" ON surveys FOR DELETE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── survey_links RLS ───
ALTER TABLE survey_links ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin read survey_links"   ON survey_links;
CREATE POLICY "Admin read survey_links"   ON survey_links FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin insert survey_links" ON survey_links;
CREATE POLICY "Admin insert survey_links" ON survey_links FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin update survey_links" ON survey_links;
CREATE POLICY "Admin update survey_links" ON survey_links FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- Anônimo pode ler survey_link pelo token (para validar na página pública)
-- A edge function usa service_role (bypass RLS), mas permitimos SELECT anon para
-- o JS client-side buscar os dados da survey a exibir antes do submit.
DROP POLICY IF EXISTS "Anon read survey_links by token" ON survey_links;
CREATE POLICY "Anon read survey_links by token" ON survey_links FOR SELECT TO anon
  USING (used_at IS NULL);

-- Anônimo pode ler surveys (para exibir pergunta na página pública via survey_links join)
DROP POLICY IF EXISTS "Anon read surveys" ON surveys;
CREATE POLICY "Anon read surveys" ON surveys FOR SELECT TO anon
  USING (status IN ('active', 'closed'));

-- ─── student_nps: permitir INSERT anon (via edge function service_role) ───
-- A edge function submit-survey usa SERVICE_ROLE_KEY (bypass RLS),
-- mas documentamos que anon NÃO insere diretamente — apenas via edge function.
-- Políticas existentes (admin read/write) permanecem inalteradas.
