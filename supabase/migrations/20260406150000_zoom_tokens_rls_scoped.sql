-- ═══════════════════════════════════════
-- LESSON PAGES — DB-R3: zoom_tokens RLS scoped por mentor_id
-- A política anterior "Admin all zoom_tokens" (FOR ALL) permite que qualquer
-- admin leia/escreva tokens de qualquer mentor. Melhoramos para:
--   - Mentores: podem ler APENAS seu próprio token (via user_metadata.mentor_id)
--   - Admins: acesso completo (mantido para gestão)
--   - Edge Functions com service_role: bypass RLS (sem mudança)
-- ═══════════════════════════════════════

ALTER TABLE public.zoom_tokens ENABLE ROW LEVEL SECURITY;

-- Remove política ampla (FOR ALL sem distinção de operação)
DROP POLICY IF EXISTS "Admin all zoom_tokens" ON public.zoom_tokens;

-- SELECT: admin vê todos; mentor vê apenas o seu
DROP POLICY IF EXISTS "Mentor or admin read zoom_tokens" ON public.zoom_tokens;
CREATE POLICY "Mentor or admin read zoom_tokens"
  ON public.zoom_tokens FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'
    OR mentor_id = (auth.jwt() -> 'user_metadata' ->> 'mentor_id')::uuid
  );

-- INSERT: apenas admin (Edge Functions usam service_role — bypass)
DROP POLICY IF EXISTS "Admin insert zoom_tokens" ON public.zoom_tokens;
CREATE POLICY "Admin insert zoom_tokens"
  ON public.zoom_tokens FOR INSERT
  TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- UPDATE: admin pode atualizar qualquer token; mentor pode atualizar o seu
DROP POLICY IF EXISTS "Mentor or admin update zoom_tokens" ON public.zoom_tokens;
CREATE POLICY "Mentor or admin update zoom_tokens"
  ON public.zoom_tokens FOR UPDATE
  TO authenticated
  USING (
    (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'
    OR mentor_id = (auth.jwt() -> 'user_metadata' ->> 'mentor_id')::uuid
  );

-- DELETE: apenas admin
DROP POLICY IF EXISTS "Admin delete zoom_tokens" ON public.zoom_tokens;
CREATE POLICY "Admin delete zoom_tokens"
  ON public.zoom_tokens FOR DELETE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
