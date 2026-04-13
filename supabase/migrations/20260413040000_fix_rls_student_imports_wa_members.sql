-- Fix RLS: restrict student_imports and wa_group_members to admin-only writes
-- Same pattern as students table: authenticated read, admin write/update/delete

-- ── student_imports ──
DROP POLICY IF EXISTS "Authenticated full access on student_imports" ON public.student_imports;

CREATE POLICY "Authenticated read student_imports"
  ON public.student_imports FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admin insert student_imports"
  ON public.student_imports FOR INSERT
  TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

CREATE POLICY "Admin update student_imports"
  ON public.student_imports FOR UPDATE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

CREATE POLICY "Admin delete student_imports"
  ON public.student_imports FOR DELETE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- ── wa_group_members ──
DROP POLICY IF EXISTS "Authenticated full access on wa_group_members" ON public.wa_group_members;

CREATE POLICY "Authenticated read wa_group_members"
  ON public.wa_group_members FOR SELECT
  TO authenticated
  USING (true);

CREATE POLICY "Admin insert wa_group_members"
  ON public.wa_group_members FOR INSERT
  TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

CREATE POLICY "Admin update wa_group_members"
  ON public.wa_group_members FOR UPDATE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

CREATE POLICY "Admin delete wa_group_members"
  ON public.wa_group_members FOR DELETE
  TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
