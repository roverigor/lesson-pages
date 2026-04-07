-- ═══════════════════════════════════════
-- EPIC-010 — Aulas e Gravações Automatizadas
-- Story 10.1: meeting_id em class_recordings
-- Story 10.3: class_materials
-- Story 10.4: class_recording_notifications
-- ═══════════════════════════════════════

-- Garantir que class_recordings existe com todos os campos necessários
CREATE TABLE IF NOT EXISTS public.class_recordings (
  id               UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  cohort_id        UUID REFERENCES public.cohorts(id),
  recording_date   DATE,
  title            TEXT,
  duration_minutes INT,
  video_url        TEXT,
  audio_url        TEXT,
  summary          TEXT,
  transcript_text  TEXT,
  transcript_vtt   TEXT,
  chat_log         TEXT,
  created_at       TIMESTAMPTZ DEFAULT now()
);

-- Adicionar meeting_id para deduplicação (UPSERT via webhook)
ALTER TABLE public.class_recordings
  ADD COLUMN IF NOT EXISTS meeting_id TEXT;

-- Índice único em meeting_id (para UPSERT on_conflict)
CREATE UNIQUE INDEX IF NOT EXISTS idx_class_recordings_meeting_id
  ON public.class_recordings (meeting_id)
  WHERE meeting_id IS NOT NULL;

-- Permissões
GRANT ALL ON public.class_recordings TO service_role;
ALTER TABLE public.class_recordings DISABLE ROW LEVEL SECURITY;

-- ── Story 10.3: Materiais por Aula ─────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.class_materials (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recording_id UUID NOT NULL REFERENCES public.class_recordings(id) ON DELETE CASCADE,
  file_name    TEXT NOT NULL,
  file_url     TEXT NOT NULL,
  file_type    TEXT,       -- 'pdf', 'pptx', 'image', etc.
  file_size    INT,        -- bytes
  uploaded_by  TEXT NOT NULL DEFAULT 'admin',
  uploaded_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_class_materials_recording
  ON public.class_materials (recording_id);

GRANT ALL ON public.class_materials TO service_role;
ALTER TABLE public.class_materials DISABLE ROW LEVEL SECURITY;

-- ── Story 10.4: Log de Notificações de Gravação ────────────────────────────

CREATE TABLE IF NOT EXISTS public.class_recording_notifications (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  recording_id UUID NOT NULL REFERENCES public.class_recordings(id) ON DELETE CASCADE,
  student_id   UUID NOT NULL REFERENCES public.students(id),
  sent_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  status       TEXT NOT NULL DEFAULT 'sent' CHECK (status IN ('sent', 'error', 'skipped')),
  error_msg    TEXT
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_crn_recording_student
  ON public.class_recording_notifications (recording_id, student_id);

CREATE INDEX IF NOT EXISTS idx_crn_recording
  ON public.class_recording_notifications (recording_id);

GRANT ALL ON public.class_recording_notifications TO service_role;
ALTER TABLE public.class_recording_notifications DISABLE ROW LEVEL SECURITY;
