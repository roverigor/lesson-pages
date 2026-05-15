-- ═══════════════════════════════════════════════════════════════════════
-- SECURITY P0 — Enable RLS em tabelas expostas via anon
-- ═══════════════════════════════════════════════════════════════════════
-- Antes: anon retornava service_role key + transcrições + audit log.
-- Depois: cada tabela com policy mínima necessária.
--
-- Tabelas:
--   app_config                       → service_role only (segredos)
--   zoom_link_audit                  → admin only
--   class_recordings                 → authenticated read, admin write
--   class_materials                  → authenticated read, admin write
--   class_recording_notifications    → admin only
-- ═══════════════════════════════════════════════════════════════════════

-- ─── app_config (CRÍTICO — vaza service_role key) ───
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "service_role full access app_config" ON public.app_config;
-- Sem policy pra anon/authenticated = bloqueio total. service_role bypassa RLS por padrão.

-- ─── zoom_link_audit (logs admin) ───
ALTER TABLE public.zoom_link_audit ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin read zoom_link_audit" ON public.zoom_link_audit;
CREATE POLICY "Admin read zoom_link_audit" ON public.zoom_link_audit
  FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- service_role bypassa RLS automaticamente — sem policy explícita necessária

-- ─── class_recordings (lido em /aulas por authenticated) ───
ALTER TABLE public.class_recordings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read class_recordings" ON public.class_recordings;
CREATE POLICY "Authenticated read class_recordings" ON public.class_recordings
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admin write class_recordings" ON public.class_recordings;
CREATE POLICY "Admin write class_recordings" ON public.class_recordings
  FOR ALL TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── class_materials (lido em /aulas, escrita admin) ───
ALTER TABLE public.class_materials ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read class_materials" ON public.class_materials;
CREATE POLICY "Authenticated read class_materials" ON public.class_materials
  FOR SELECT TO authenticated USING (true);

DROP POLICY IF EXISTS "Admin write class_materials" ON public.class_materials;
CREATE POLICY "Admin write class_materials" ON public.class_materials
  FOR ALL TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── class_recording_notifications (admin only) ───
ALTER TABLE public.class_recording_notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin manage class_recording_notifications" ON public.class_recording_notifications;
CREATE POLICY "Admin manage class_recording_notifications" ON public.class_recording_notifications
  FOR ALL TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin')
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── Verificação ───
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT tablename, rowsecurity
    FROM pg_tables
    WHERE schemaname = 'public'
      AND tablename IN ('app_config','zoom_link_audit','class_recordings','class_materials','class_recording_notifications')
  LOOP
    IF NOT r.rowsecurity THEN
      RAISE EXCEPTION 'RLS NOT enabled on %', r.tablename;
    END IF;
  END LOOP;
  RAISE LOG 'RLS verified on 5 tables';
END $$;
