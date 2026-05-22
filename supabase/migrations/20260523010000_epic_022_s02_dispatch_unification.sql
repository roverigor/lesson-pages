-- ============================================================
-- Story 22.2 — Dispatch Unification (EPIC-022 S.022.2)
-- ============================================================
-- ESCOPO:
--   - Feature flag `nps_dispatch_engine` em app_config: 'legacy'|'unified'
--   - RPC set_nps_dispatch_engine(text) com gate is_dashboard_admin
--   - Coluna dispatch_type enum em dispatch_history
--   - Default flag 'legacy' (seguro) — flip via RPC pós-smoke sentinela
--
-- OUT-OF-SCOPE desta migration (responsabilidade @dev real durante impl):
--   - Refactor dispatch-survey edge fn pra aceitar survey_type='nps_class'
--   - Refactor dispatch-class-nps pra ler flag + early return se unified
--   - Marcar send-whatsapp dormant (DROP TRIGGER notifications)
--
-- GATE PROD: NON-NEGOTIABLE — autorização literal user antes apply
-- ADR: docs/architecture/ADR-022-dispatch-unification.md
-- ============================================================
-- Autor: @dev (Dex via aiox-master) — 2026-05-22
-- Deps: 22.4 RLS Hardening (app_config Tier 3 + is_dashboard_admin)
-- PG version: 15
-- Idempotência: ON CONFLICT + CREATE OR REPLACE + IF NOT EXISTS
-- ============================================================


-- ============================================================
-- AUDIT TRAIL — INSERT inicial
-- ============================================================

DO $audit$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'dispatch_unification',
        jsonb_build_object(
          'story_id', '22.2',
          'epic_id', 'EPIC-022',
          'migration', '20260523010000_epic_022_s02_dispatch_unification',
          'started_at', now()
        )
      )
    $insert$;
  END IF;
END
$audit$;


-- ============================================================
-- T2 — Feature flag em app_config
-- ============================================================
-- Insere row inicial com value='legacy' (seguro — flip explícito via RPC).
-- ON CONFLICT preserva valor existente em rerun (não força reset).
-- ============================================================

INSERT INTO public.app_config (key, value, updated_at)
VALUES ('nps_dispatch_engine', 'legacy', now())
ON CONFLICT (key) DO NOTHING;

COMMENT ON COLUMN public.app_config.key IS
  'Feature flags + config keys. Ex: nps_dispatch_engine=legacy|unified ref ADR-022.';


-- ============================================================
-- T3 — RPC set_nps_dispatch_engine(text)
-- ============================================================
-- Gate: is_dashboard_admin() obrigatório
-- Validação: value IN ('legacy', 'unified')
-- Audit: INSERT em audit_log event_type='nps_engine_flip'
-- ============================================================

CREATE OR REPLACE FUNCTION public.set_nps_dispatch_engine(p_value text)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_old_value text;
  v_operator  text;
  v_audit_id  uuid;
BEGIN
  -- Gate: admin only
  IF NOT public.is_dashboard_admin() THEN
    RAISE EXCEPTION 'Permission denied: admin only';
  END IF;

  -- Validate
  IF p_value IS NULL OR p_value NOT IN ('legacy', 'unified') THEN
    RAISE EXCEPTION 'Invalid engine value: %. Allowed: legacy, unified', p_value;
  END IF;

  -- Snapshot old
  SELECT value INTO v_old_value
    FROM public.app_config
   WHERE key = 'nps_dispatch_engine';

  IF v_old_value = p_value THEN
    RETURN jsonb_build_object(
      'ok', true,
      'noop', true,
      'message', 'engine already set to ' || p_value
    );
  END IF;

  v_operator := COALESCE(auth.jwt() #>> '{user_metadata,email}', 'unknown');

  -- Flip
  UPDATE public.app_config
     SET value = p_value, updated_at = now()
   WHERE key = 'nps_dispatch_engine';

  -- Audit
  INSERT INTO public.audit_log (event_type, payload)
  VALUES (
    'nps_engine_flip',
    jsonb_build_object(
      'old_value', v_old_value,
      'new_value', p_value,
      'operator', v_operator,
      'flipped_at', now(),
      'story_id', '22.2',
      'adr', 'ADR-022'
    )
  )
  RETURNING id INTO v_audit_id;

  RETURN jsonb_build_object(
    'ok', true,
    'old', v_old_value,
    'new', p_value,
    'operator', v_operator,
    'audit_id', v_audit_id,
    'note', 'Slack alert deve ser disparado pelo caller (UI button) via webhook'
  );
END;
$$;

GRANT EXECUTE ON FUNCTION public.set_nps_dispatch_engine(text) TO authenticated;

COMMENT ON FUNCTION public.set_nps_dispatch_engine(text) IS
  'Flip NPS dispatch engine flag (legacy|unified). Admin gated. Audit logged. Ref: ADR-022.';


-- ============================================================
-- T4 — Helper RPC get_nps_dispatch_engine() pra edge fns
-- ============================================================
-- Edge functions chamarão esse RPC (mais rápido que SELECT app_config).
-- Public read OK (não é informação sensível).
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_nps_dispatch_engine()
RETURNS text
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
    (SELECT value FROM public.app_config WHERE key = 'nps_dispatch_engine'),
    'legacy'
  );
$$;

GRANT EXECUTE ON FUNCTION public.get_nps_dispatch_engine() TO authenticated, anon, service_role;

COMMENT ON FUNCTION public.get_nps_dispatch_engine() IS
  'Returns nps_dispatch_engine flag value (default legacy). STABLE. Public read. Ref: ADR-022.';


-- ============================================================
-- T5 — dispatch_type enum column em dispatch_history
-- ============================================================
-- ALTER TABLE com DEFAULT pra não-bloquear rows existentes.
-- CHECK constraint enforce valores enum.
-- ============================================================

BEGIN;
ALTER TABLE public.dispatch_history
  ADD COLUMN IF NOT EXISTS dispatch_type text DEFAULT 'survey_generic';

-- Drop + recreate CHECK (idempotência)
ALTER TABLE public.dispatch_history
  DROP CONSTRAINT IF EXISTS chk_dispatch_history_type;

ALTER TABLE public.dispatch_history
  ADD CONSTRAINT chk_dispatch_history_type
  CHECK (dispatch_type IN ('nps_class', 'ps_rsvp', 'survey_generic', 'reminder'));

CREATE INDEX IF NOT EXISTS idx_dispatch_history_type
  ON public.dispatch_history (dispatch_type);
COMMIT;


-- ============================================================
-- AUDIT TRAIL — final
-- ============================================================

DO $audit_final$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c
    JOIN pg_namespace n ON c.relnamespace = n.oid
    WHERE n.nspname = 'public' AND c.relname = 'audit_log'
  ) THEN
    EXECUTE $insert$
      INSERT INTO public.audit_log (event_type, payload)
      VALUES (
        'dispatch_unification',
        jsonb_build_object(
          'story_id', '22.2',
          'migration', '20260523010000_epic_022_s02_dispatch_unification',
          'completed_at', now(),
          'status', 'flag_rpcs_dispatch_type_applied',
          'engine_default', 'legacy',
          'note', 'Edge fn refactor (dispatch-survey, dispatch-class-nps, send-whatsapp dormant) é responsabilidade @dev real follow-up'
        )
      )
    $insert$;
  END IF;
END
$audit_final$;
