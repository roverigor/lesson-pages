-- ═══════════════════════════════════════
-- LESSON PAGES — Schema Completo: Classes, Class Mentors, Class Cohort Access
-- Gerado por Story 3.3 (EPIC-003) — @data-engineer (Dara) — 06/04/2026
-- Este arquivo é documentação de referência, NÃO deve ser executado diretamente.
-- Para aplicar mudanças, use supabase/migrations/.
-- ═══════════════════════════════════════

-- ─── CLASSES ───────────────────────────────────────────────────────────────────
-- Representa uma turma/modalidade de ensino (PS, Aula regular, Imersão, Workshop).
-- Cada classe tem um intervalo de datas (start_date → end_date) e um dia da semana
-- principal (weekday, legacy), além de múltiplos dias via class_mentors.weekday.
--
-- Campos legacy (presentes por compatibilidade retroativa):
--   - weekday: dia da semana principal; substituído por class_mentors.weekday para
--              turmas com múltiplos dias
--   - professor: nome textual (legado); substituído por class_mentors (FK para mentors)
--   - host: nome textual (legado); substituído por class_mentors
--   - date: data única (legado); substituído por start_date/end_date + weekday
--   - zoom_link: link Zoom da turma; coexiste com cohorts.zoom_link
--
-- RLS:
--   SELECT: anon + authenticated (calendário público lê sem autenticação)
--   INSERT/UPDATE/DELETE: authenticated WHERE user_metadata.role = 'admin'

CREATE TABLE IF NOT EXISTS public.classes (
  id         UUID        DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT        NOT NULL,
  type       TEXT        CHECK (type IN ('PS', 'Aula', 'Imersão', 'Workshop')),
  start_date DATE,                          -- início do ciclo da turma
  end_date   DATE,                          -- fim do ciclo da turma
  weekday    INTEGER     CHECK (weekday BETWEEN 0 AND 6),  -- 0=Dom, 1=Seg... (legacy)
  time_start TIME        NOT NULL DEFAULT '18:00',
  time_end   TIME        NOT NULL DEFAULT '20:00',
  date       DATE,                          -- (legacy) data única de aula
  professor  TEXT,                          -- (legacy) nome do professor
  host       TEXT,                          -- (legacy) nome do host
  color      TEXT,                          -- hex color para exibição no calendário
  zoom_link  TEXT,                          -- link Zoom da turma (opcional)
  active     BOOLEAN     NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Trigger de updated_at
-- CREATE TRIGGER classes_updated_at BEFORE UPDATE ON public.classes
--   FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- Índices
-- CREATE INDEX idx_classes_weekday    ON public.classes(weekday);
-- CREATE INDEX idx_classes_date       ON public.classes(date);
-- CREATE INDEX idx_classes_active     ON public.classes(active);
-- CREATE INDEX idx_classes_start_date ON public.classes(start_date);  -- Story 3.3
-- CREATE INDEX idx_classes_end_date   ON public.classes(end_date);    -- Story 3.3
-- CREATE INDEX idx_classes_type       ON public.classes(type);        -- Story 3.3


-- ─── CLASS_MENTORS ─────────────────────────────────────────────────────────────
-- Bridge N:N entre classes e mentors com papel e dia da semana.
-- Suporta temporal cycles: valid_from → valid_until define o período de vigência
-- de cada vínculo. valid_until IS NULL = ciclo ativo atualmente.
--
-- Fluxo de ciclo:
--   1. Edição normal: deleta registros com valid_until IS NULL e re-insere
--   2. closeClassCycle(): seta valid_until = hoje em registros ativos,
--      duplica com valid_from = amanhã e valid_until = NULL (novo ciclo)
--
-- Unique constraint: (class_id, mentor_id, role, weekday) — permite o mesmo mentor
-- atuar em papéis diferentes e/ou dias diferentes da mesma turma.
--
-- RLS:
--   SELECT: anon + authenticated (calendário público exibe professor/host)
--   INSERT/UPDATE/DELETE: authenticated WHERE user_metadata.role = 'admin'

CREATE TABLE IF NOT EXISTS public.class_mentors (
  id         UUID     DEFAULT gen_random_uuid() PRIMARY KEY,
  class_id   UUID     NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  mentor_id  UUID     NOT NULL REFERENCES public.mentors(id) ON DELETE CASCADE,
  role       TEXT     NOT NULL DEFAULT 'Professor'
                      CHECK (role IN ('Professor', 'Host', 'Mentor')),
  weekday    SMALLINT,           -- dia da semana deste vínculo (0=Dom...6=Sáb)
  valid_from DATE     NOT NULL DEFAULT '2000-01-01',  -- início do ciclo (Story 3.3)
  valid_until DATE,              -- fim do ciclo; NULL = ativo (Story 3.3)
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(class_id, mentor_id, role, weekday)
);

-- Índices
-- CREATE INDEX idx_class_mentors_class         ON public.class_mentors(class_id);
-- CREATE INDEX idx_class_mentors_mentor        ON public.class_mentors(mentor_id);
-- CREATE INDEX idx_class_mentors_active_cycle  ON public.class_mentors(class_id)
--   WHERE valid_until IS NULL;                 -- Story 3.3: filtro de ciclo ativo
-- CREATE INDEX idx_class_mentors_valid_from    ON public.class_mentors(valid_from);


-- ─── CLASS_COHORT_ACCESS ───────────────────────────────────────────────────────
-- Define quais cohorts têm acesso a uma classe e até quando.
-- Usado para controlar visibilidade e notificações por turma.
-- Diferente de class_cohorts (bridge simples), aqui há uma data de expiração.
--
-- RLS:
--   SELECT: authenticated (não é dado público)
--   INSERT/UPDATE/DELETE: authenticated WHERE user_metadata.role = 'admin'

CREATE TABLE IF NOT EXISTS public.class_cohort_access (
  id           UUID  DEFAULT gen_random_uuid() PRIMARY KEY,
  class_id     UUID  NOT NULL REFERENCES public.classes(id)  ON DELETE CASCADE,
  cohort_id    UUID  NOT NULL REFERENCES public.cohorts(id)  ON DELETE CASCADE,
  access_until DATE  NOT NULL,   -- data até a qual o cohort tem acesso à classe
  notes        TEXT,             -- observações opcionais
  created_at   TIMESTAMPTZ DEFAULT now(),
  UNIQUE(class_id, cohort_id)    -- um cohort aparece no máximo uma vez por classe
);

-- Índices
-- CREATE INDEX idx_class_cohort_access_class  ON public.class_cohort_access(class_id);
-- CREATE INDEX idx_class_cohort_access_cohort ON public.class_cohort_access(cohort_id);
-- CREATE INDEX idx_class_cohort_access_until  ON public.class_cohort_access(access_until);


-- ─── MENTORS ───────────────────────────────────────────────────────────────────
-- Equipe pedagógica: professores, hosts e mentorias.
-- phone UNIQUE: identificador para Evolution API (WhatsApp individual).
--
-- RLS:
--   SELECT: anon + authenticated (calendário público exibe nomes dos mentores)
--   INSERT/UPDATE/DELETE: authenticated WHERE user_metadata.role = 'admin'

CREATE TABLE IF NOT EXISTS public.mentors (
  id         UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name       TEXT NOT NULL,
  phone      TEXT NOT NULL UNIQUE,
  role       TEXT NOT NULL DEFAULT 'Professor'
             CHECK (role IN ('Professor', 'Host', 'Both')),
  active     BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Índices
-- CREATE INDEX idx_mentors_phone  ON public.mentors(phone);
-- CREATE INDEX idx_mentors_active ON public.mentors(active);


-- ─── RELAÇÕES ─────────────────────────────────────────────────────────────────
--
--  classes (1) ──< class_mentors (N) >── mentors (1)
--    │                                        │
--    │ via class_cohort_access               via notifications.mentor_id
--    └──< cohorts (N)
--
--  classes (N) >──< cohorts (N)  [via class_cohorts — bridge simples sem expiração]
--  classes (N) >──< cohorts (N)  [via class_cohort_access — com data de expiração]
--
-- ─── NOTAS SOBRE CAMPOS LEGACY ────────────────────────────────────────────────
--
-- classes.weekday, classes.professor, classes.host, classes.date:
--   Presentes para compatibilidade com código legado. O calendário público faz
--   fallback para esses campos se class_mentors não tiver dados.
--   Não remover sem migração de dados e auditoria completa do frontend.
