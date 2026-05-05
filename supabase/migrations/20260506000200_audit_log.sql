-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-016 Story 16.8 — audit_log table + triggers
-- Captura mudanças em tabelas críticas (cohorts, students, surveys, mappings).
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.audit_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  actor_user_id uuid REFERENCES auth.users(id),
  actor_email text,
  action text NOT NULL CHECK (action IN ('insert', 'update', 'delete')),
  entity_type text NOT NULL,
  entity_id uuid,
  before_data jsonb,
  after_data jsonb,
  created_at timestamptz DEFAULT now()
);

-- Helper function pra diff (não-stored — calcula sob demanda em queries)
CREATE OR REPLACE FUNCTION public.audit_log_diff(p_id uuid)
RETURNS jsonb LANGUAGE sql STABLE AS $$
  SELECT
    CASE
      WHEN action = 'insert' THEN after_data
      WHEN action = 'delete' THEN before_data
      ELSE (
        SELECT jsonb_object_agg(key, value)
        FROM jsonb_each(after_data)
        WHERE before_data->key IS DISTINCT FROM value
      )
    END
  FROM public.audit_log
  WHERE id = p_id;
$$;

CREATE INDEX IF NOT EXISTS idx_audit_log_entity
  ON public.audit_log (entity_type, entity_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_actor
  ON public.audit_log (actor_user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_log_recent
  ON public.audit_log (created_at DESC);

-- RLS: admin lê tudo; CS lê próprias ações
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_read_all_audit"
  ON public.audit_log FOR SELECT
  USING ((auth.jwt()->'user_metadata'->>'role') = 'admin');

CREATE POLICY "cs_read_own_audit"
  ON public.audit_log FOR SELECT
  USING (
    (auth.jwt()->'user_metadata'->>'role') = 'cs'
    AND actor_user_id = auth.uid()
  );

GRANT SELECT ON public.audit_log TO authenticated;
GRANT INSERT ON public.audit_log TO service_role;

-- ─── Trigger function genérica ───────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.audit_table_changes()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_actor_id uuid;
  v_actor_email text;
BEGIN
  -- Tenta capturar user via JWT (se chamado via PostgREST/edge)
  BEGIN
    v_actor_id := auth.uid();
    v_actor_email := COALESCE(
      (auth.jwt()->>'email'),
      (SELECT email FROM auth.users WHERE id = v_actor_id)
    );
  EXCEPTION WHEN OTHERS THEN
    v_actor_id := NULL;
    v_actor_email := 'system';
  END;

  IF TG_OP = 'INSERT' THEN
    INSERT INTO public.audit_log (actor_user_id, actor_email, action, entity_type, entity_id, after_data)
    VALUES (v_actor_id, v_actor_email, 'insert', TG_TABLE_NAME, NEW.id, to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO public.audit_log (actor_user_id, actor_email, action, entity_type, entity_id, before_data, after_data)
    VALUES (v_actor_id, v_actor_email, 'update', TG_TABLE_NAME, NEW.id, to_jsonb(OLD), to_jsonb(NEW));
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO public.audit_log (actor_user_id, actor_email, action, entity_type, entity_id, before_data)
    VALUES (v_actor_id, v_actor_email, 'delete', TG_TABLE_NAME, OLD.id, to_jsonb(OLD));
    RETURN OLD;
  END IF;
  RETURN NULL;
END $$;

-- ─── Aplicar triggers em tabelas críticas ────────────────────────────────
DROP TRIGGER IF EXISTS trg_audit_cohorts ON public.cohorts;
CREATE TRIGGER trg_audit_cohorts
  AFTER INSERT OR UPDATE OR DELETE ON public.cohorts
  FOR EACH ROW EXECUTE FUNCTION public.audit_table_changes();

DROP TRIGGER IF EXISTS trg_audit_students ON public.students;
CREATE TRIGGER trg_audit_students
  AFTER INSERT OR UPDATE OR DELETE ON public.students
  FOR EACH ROW EXECUTE FUNCTION public.audit_table_changes();

DROP TRIGGER IF EXISTS trg_audit_surveys ON public.surveys;
CREATE TRIGGER trg_audit_surveys
  AFTER INSERT OR UPDATE OR DELETE ON public.surveys
  FOR EACH ROW EXECUTE FUNCTION public.audit_table_changes();

DROP TRIGGER IF EXISTS trg_audit_meta_templates ON public.meta_templates;
CREATE TRIGGER trg_audit_meta_templates
  AFTER INSERT OR UPDATE OR DELETE ON public.meta_templates
  FOR EACH ROW EXECUTE FUNCTION public.audit_table_changes();

DROP TRIGGER IF EXISTS trg_audit_ac_product_mappings ON public.ac_product_mappings;
CREATE TRIGGER trg_audit_ac_product_mappings
  AFTER INSERT OR UPDATE OR DELETE ON public.ac_product_mappings
  FOR EACH ROW EXECUTE FUNCTION public.audit_table_changes();

COMMENT ON TABLE public.audit_log IS
  'EPIC-016 Story 16.8: registra mudanças em entidades críticas (cohorts, students, surveys, templates, mappings) com diff jsonb gerado automaticamente.';
