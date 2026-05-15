-- ═══════════════════════════════════════════════════════════════════════════
-- EPIC-015 Story 15.G — Versioning Trigger
--
-- Auto-cria nova survey_version quando survey_questions é editada após disparos.
-- Preserva v1 existente (links já enviados continuam respondendo v1).
--
-- Refs: FR-13, NFR-15, AC-10 spec.md
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION auto_version_survey()
RETURNS TRIGGER AS $$
DECLARE
  v_survey_id          UUID;
  v_dispatched_count   INTEGER;
  v_current_version_id UUID;
  v_new_version_id     UUID;
  v_new_version_num    INTEGER;
BEGIN
  -- Identifica survey afetada (NEW em INSERT/UPDATE, OLD em DELETE)
  v_survey_id := COALESCE(NEW.survey_id, OLD.survey_id);

  IF v_survey_id IS NULL THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Verifica se survey já tem disparos enviados (sent)
  SELECT COUNT(*) INTO v_dispatched_count
    FROM survey_links
   WHERE survey_id = v_survey_id
     AND send_status = 'sent';

  -- Se nenhum dispatch enviado, edição NÃO cria nova version (v1 ainda mutável)
  IF v_dispatched_count = 0 THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Verifica se já há versão pós-último dispatch (evita criar versão a cada keystroke)
  SELECT current_version_id INTO v_current_version_id
    FROM surveys WHERE id = v_survey_id;

  -- Se a current version não tem links sent associados (ou não existe),
  -- não precisa criar nova ainda — a edição entra na current version draft
  IF NOT EXISTS (
    SELECT 1 FROM survey_links
     WHERE survey_id = v_survey_id
       AND version_id = v_current_version_id
       AND send_status = 'sent'
  ) THEN
    RETURN COALESCE(NEW, OLD);
  END IF;

  -- Cria nova version (próximo number sequencial)
  SELECT COALESCE(MAX(version_number), 0) + 1 INTO v_new_version_num
    FROM survey_versions WHERE survey_id = v_survey_id;

  INSERT INTO survey_versions (survey_id, version_number)
  VALUES (v_survey_id, v_new_version_num)
  RETURNING id INTO v_new_version_id;

  -- Atualiza surveys.current_version_id para nova versão
  UPDATE surveys
     SET current_version_id = v_new_version_id
   WHERE id = v_survey_id;

  RAISE NOTICE 'EPIC-015 G: survey % auto-versioned to v% (% dispatched links em version anterior)',
    v_survey_id, v_new_version_num, v_dispatched_count;

  RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

COMMENT ON FUNCTION auto_version_survey() IS
  'EPIC-015 Story 15.G: cria nova survey_version automaticamente ao editar survey_questions de survey que já tem disparos sent na current version. Preserva integridade respostas históricas.';

-- Trigger AFTER (deixa o INSERT/UPDATE/DELETE da survey_questions completar primeiro,
-- depois decide se cria nova version no OLD vs NEW relacionamento).
DROP TRIGGER IF EXISTS trg_auto_version_survey ON survey_questions;
CREATE TRIGGER trg_auto_version_survey
  AFTER INSERT OR UPDATE OR DELETE ON survey_questions
  FOR EACH ROW
  EXECUTE FUNCTION auto_version_survey();

-- ═══════════════════════════════════════════════════════════════════════════
-- View helper para UI badges (Story 15.6 forms-list)
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE VIEW survey_version_stats AS
SELECT
  s.id           AS survey_id,
  s.name         AS survey_name,
  s.current_version_id,
  sv.version_number AS current_version_number,
  (SELECT COUNT(*) FROM survey_versions WHERE survey_id = s.id) AS total_versions,
  (SELECT COUNT(*) FROM survey_links WHERE survey_id = s.id AND version_id = s.current_version_id AND send_status = 'sent') AS current_version_dispatched,
  (SELECT COUNT(*) FROM survey_links WHERE survey_id = s.id AND send_status = 'sent') AS total_dispatched
FROM surveys s
LEFT JOIN survey_versions sv ON sv.id = s.current_version_id;

COMMENT ON VIEW survey_version_stats IS
  'EPIC-015 Story 15.G/15.6: agregados de versões por survey para UI badges (vN · X disparos).';
