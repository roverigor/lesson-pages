-- ═══════════════════════════════════════════════════════════════════════════
-- P4 — Dashboard RPCs part 4: get_retry_confirm_token + retry_dispatch
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.get_retry_confirm_token(
  p_source       text,
  p_dispatch_id  uuid
) RETURNS TABLE (
  token        text,
  expires_at   timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_token      text;
  v_expires_at timestamptz;
  v_status     text;
BEGIN
  IF NOT is_dashboard_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  SELECT v.status INTO v_status
  FROM dispatch_history_unified v
  WHERE v.source = p_source AND v.dispatch_id = p_dispatch_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'dispatch_not_found';
  END IF;
  IF v_status <> 'failed' THEN
    RAISE EXCEPTION 'retry_only_allowed_for_failed_dispatches';
  END IF;

  v_token      := encode(gen_random_bytes(24), 'base64');
  v_expires_at := now() + interval '15 minutes';

  INSERT INTO retry_confirm_tokens (token, source, dispatch_id, issued_to, expires_at)
  VALUES (v_token, p_source, p_dispatch_id, auth.uid(), v_expires_at);

  RETURN QUERY SELECT v_token, v_expires_at;
END;
$$;
GRANT EXECUTE ON FUNCTION public.get_retry_confirm_token(text, uuid) TO authenticated;

CREATE OR REPLACE FUNCTION public.retry_dispatch(
  p_source         text,
  p_dispatch_id    uuid,
  p_confirm_token  text
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_user_id    uuid := auth.uid();
  v_fn_url     text;
  v_svc_key    text;
  v_audit_id   uuid;
  v_request_id bigint;
BEGIN
  IF NOT is_dashboard_admin() THEN RAISE EXCEPTION 'forbidden' USING ERRCODE='42501'; END IF;

  IF NOT EXISTS (
    SELECT 1 FROM retry_confirm_tokens
     WHERE token = p_confirm_token
       AND source = p_source
       AND dispatch_id = p_dispatch_id
       AND issued_to = v_user_id
       AND expires_at > now()
       AND consumed_at IS NULL
  ) THEN
    RAISE EXCEPTION 'invalid_or_expired_confirm_token';
  END IF;

  UPDATE retry_confirm_tokens
     SET consumed_at = now()
   WHERE token = p_confirm_token;

  INSERT INTO dispatch_retry_audit (source, dispatch_id, retried_by, retried_at, reason)
  VALUES (p_source, p_dispatch_id, v_user_id, now(), 'manual_admin_retry')
  RETURNING id INTO v_audit_id;

  SELECT value INTO v_fn_url  FROM app_config WHERE key = 'dispatch_retry_url';
  SELECT value INTO v_svc_key FROM app_config WHERE key = 'supabase_service_key';

  IF v_fn_url IS NULL OR v_svc_key IS NULL THEN
    UPDATE dispatch_retry_audit
       SET result = jsonb_build_object('queued', false, 'error', 'missing_app_config')
     WHERE id = v_audit_id;
    RETURN jsonb_build_object('success', false, 'error', 'missing_app_config');
  END IF;

  SELECT net.http_post(
    url     := v_fn_url,
    body    := jsonb_build_object(
      'source', p_source,
      'dispatch_id', p_dispatch_id,
      'audit_id', v_audit_id,
      'retried_by', v_user_id
    ),
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_svc_key,
      'Content-Type',  'application/json'
    )
  ) INTO v_request_id;

  UPDATE dispatch_retry_audit
     SET result = jsonb_build_object('queued', true, 'http_request_id', v_request_id)
   WHERE id = v_audit_id;

  RETURN jsonb_build_object('success', true, 'queued_at', now(), 'audit_id', v_audit_id);
END;
$$;
GRANT EXECUTE ON FUNCTION public.retry_dispatch(text, uuid, text) TO authenticated;

INSERT INTO public.app_config (key, value) VALUES
  ('dispatch_retry_url', 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/dispatch-retry')
ON CONFLICT (key) DO NOTHING;

COMMIT;
