-- ═══════════════════════════════════════
-- LESSON PAGES — DB-R1: RLS scoped por mentor para tabelas relevantes
-- Mentores precisam ver notificações direcionadas a eles (mentor_id = seu id).
-- A maioria das tabelas já tem RLS adequado (mentor_attendance, zoom_tokens).
-- Este arquivo fecha os gaps restantes.
-- ═══════════════════════════════════════

-- ─── 1. NOTIFICATIONS — mentores veem suas próprias notificações ────────────
-- Um mentor deve poder ver notificações em que é o destinatário (mentor_id = seu id).
-- O admin continua tendo acesso total.
-- INSERT/UPDATE: service_role (Edge Functions) ou admin.

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin read notifications" ON public.notifications;
DROP POLICY IF EXISTS "Mentor read own notifications" ON public.notifications;
CREATE POLICY "Mentor or admin read notifications"
  ON public.notifications FOR SELECT
  TO authenticated
  USING (
    (auth.jwt() -> 'user_metadata' ->> 'role') = 'admin'
    OR mentor_id = (auth.jwt() -> 'user_metadata' ->> 'mentor_id')::uuid
  );

DROP POLICY IF EXISTS "Admin insert notifications" ON public.notifications;
CREATE POLICY "Admin insert notifications"
  ON public.notifications FOR INSERT
  TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin update notifications" ON public.notifications;
CREATE POLICY "Admin update notifications"
  ON public.notifications FOR UPDATE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

DROP POLICY IF EXISTS "Admin delete notifications" ON public.notifications;
CREATE POLICY "Admin delete notifications"
  ON public.notifications FOR DELETE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ─── 2. CLASS_COHORTS — leitura anônima (necessário para calendário público) ─
-- O calendário público lê class_cohorts para construir o mapa de turmas.
-- A política anterior era "Authenticated read" — atualiza para incluir anon.

ALTER TABLE public.class_cohorts ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Authenticated read class_cohorts" ON public.class_cohorts;
CREATE POLICY "Public read class_cohorts"
  ON public.class_cohorts FOR SELECT
  TO anon, authenticated
  USING (true);

-- Políticas de escrita: mantém admin-only (não precisam de alteração)

-- ─── 3. MENTORS — confirma leitura pública (complementa Story 3.3) ────────
-- Já criada em 20260406120000_classes_schema_rls.sql.
-- Esta migration apenas documenta que o padrão está consolidado.
-- (sem DDL novo — a policy "Public read mentors" já existe)
