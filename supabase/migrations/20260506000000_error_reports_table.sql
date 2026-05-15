-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-016 Story 16.7 — error_reports table
-- Recebe reports manuais de usuários CS via widget sidebar.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE TABLE IF NOT EXISTS public.error_reports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid REFERENCES auth.users(id),
  user_email text,
  severity text NOT NULL CHECK (severity IN ('low', 'medium', 'high', 'critical')),
  description text NOT NULL,
  page text,
  user_agent text,
  captured_errors jsonb,
  meta jsonb,
  resolved boolean DEFAULT false,
  resolved_at timestamptz,
  resolved_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_error_reports_unresolved
  ON public.error_reports (created_at DESC) WHERE resolved = false;

CREATE INDEX IF NOT EXISTS idx_error_reports_severity
  ON public.error_reports (severity, created_at DESC);

-- RLS: CS+admin podem inserir; admin lê tudo; CS lê próprios
ALTER TABLE public.error_reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "anyone_authenticated_insert_error_reports"
  ON public.error_reports FOR INSERT
  WITH CHECK (auth.role() = 'authenticated');

CREATE POLICY "admin_read_all_error_reports"
  ON public.error_reports FOR SELECT
  USING (
    (auth.jwt()->'user_metadata'->>'role') = 'admin'
  );

CREATE POLICY "cs_read_own_error_reports"
  ON public.error_reports FOR SELECT
  USING (
    (auth.jwt()->'user_metadata'->>'role') = 'cs'
    AND user_id = auth.uid()
  );

GRANT INSERT ON public.error_reports TO authenticated;
GRANT SELECT ON public.error_reports TO authenticated;

COMMENT ON TABLE public.error_reports IS
  'EPIC-016 Story 16.7: reports de erro enviados manualmente por CS team via widget sidebar. Slack alert disparado em INSERT via trigger.';

-- ─── Trigger: notifica Slack em novo report (severidade >= medium) ───────
CREATE OR REPLACE FUNCTION public.notify_slack_on_error_report()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER AS $$
DECLARE
  v_msg TEXT;
BEGIN
  IF NEW.severity IN ('high', 'critical') THEN
    v_msg := format(
      '🐛 [%s] Novo error report de %s na página %s: %s',
      upper(NEW.severity),
      NEW.user_email,
      NEW.page,
      LEFT(NEW.description, 200)
    );
    PERFORM public.send_slack_alert('error_report_' || NEW.id::text, v_msg);
  END IF;
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_error_reports_slack ON public.error_reports;
CREATE TRIGGER trg_error_reports_slack
  AFTER INSERT ON public.error_reports
  FOR EACH ROW EXECUTE FUNCTION public.notify_slack_on_error_report();
