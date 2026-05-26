-- ═══════════════════════════════════════════════════════════════════════════
-- L1 defense: refresh expires_at quando send_status flip pra 'sent'
-- ═══════════════════════════════════════════════════════════════════════════
-- Bug observado 2026-05-26: 153 links ps_rsvp_links criados em 22/05 com
-- session_date=26/05 ficaram send_status='pending' + expires_at=23/05.
-- Dispatcher de hoje fez UPSERT só com {class_id, student_id, session_date} →
-- ON CONFLICT DO UPDATE preservou expires_at antigo → DMs disparadas com
-- tokens já mortos há 3 dias → alunos viram "Link expirado".
--
-- Defesa bulletproof: trigger DB-side garante que sempre que send_status flip
-- pra 'sent', expires_at seja refresh pra now()+24h. Independe de bug no
-- código do dispatcher.
--
-- Aplica em 3 tabelas de magic-link: ps_rsvp_links, nps_class_links,
-- survey_links. Todas têm colunas (send_status, expires_at, sent_at).
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

-- ─── shared trigger function ────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.refresh_link_expires_at_on_send()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Flip de qualquer estado != 'sent' pra 'sent' → refresh expires_at.
  -- Cobre: pending→sent (caso normal), failed→sent (retry), skipped→sent (manual).
  IF NEW.send_status = 'sent' AND (OLD.send_status IS DISTINCT FROM 'sent') THEN
    NEW.expires_at := now() + interval '24 hours';
    IF NEW.sent_at IS NULL THEN
      NEW.sent_at := now();
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.refresh_link_expires_at_on_send IS
  'BEFORE UPDATE trigger: refresh expires_at = now()+24h quando send_status flip pra sent. Defesa contra UPSERT que não refreshes expires_at no payload. Ref bug 2026-05-26.';


-- ─── ps_rsvp_links ──────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_ps_rsvp_links_refresh_expires_at ON public.ps_rsvp_links;
CREATE TRIGGER trg_ps_rsvp_links_refresh_expires_at
  BEFORE UPDATE ON public.ps_rsvp_links
  FOR EACH ROW
  EXECUTE FUNCTION public.refresh_link_expires_at_on_send();


-- ─── nps_class_links ────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_nps_class_links_refresh_expires_at ON public.nps_class_links;
CREATE TRIGGER trg_nps_class_links_refresh_expires_at
  BEFORE UPDATE ON public.nps_class_links
  FOR EACH ROW
  EXECUTE FUNCTION public.refresh_link_expires_at_on_send();


-- ─── survey_links ───────────────────────────────────────────────────────
DROP TRIGGER IF EXISTS trg_survey_links_refresh_expires_at ON public.survey_links;
CREATE TRIGGER trg_survey_links_refresh_expires_at
  BEFORE UPDATE ON public.survey_links
  FOR EACH ROW
  EXECUTE FUNCTION public.refresh_link_expires_at_on_send();


-- audit_log entry intencionalmente omitido (constraint apertado em action enum,
-- não vale o overhead pra schema defense — git history serve de audit).

COMMIT;
