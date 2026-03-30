-- ═══════════════════════════════════════
-- LESSON PAGES — Notifications & Mentors Schema
-- Run this in Supabase SQL Editor AFTER students-schema.sql
-- ═══════════════════════════════════════

-- ─── 1. MENTORS TABLE ───
-- Separada de students: mentores têm telefone, papel e vínculo com aulas.
-- Um mentor pode atuar em múltiplos cohorts/classes sem duplicação de registro.
CREATE TABLE IF NOT EXISTS mentors (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name TEXT NOT NULL,
  phone TEXT NOT NULL UNIQUE,
  role TEXT NOT NULL DEFAULT 'Professor' CHECK (role IN ('Professor', 'Host', 'Both')),
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_mentors_phone ON mentors(phone);
CREATE INDEX IF NOT EXISTS idx_mentors_active ON mentors(active);

-- ─── 2. CLASSES ↔ COHORTS BRIDGE TABLE ───
-- Vincula cada classe a um ou mais cohorts para saber QUAL grupo WhatsApp notificar.
-- A tabela classes já existe; adicionamos a relação N:N via bridge.
CREATE TABLE IF NOT EXISTS class_cohorts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  class_id UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  cohort_id UUID NOT NULL REFERENCES cohorts(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(class_id, cohort_id)
);

CREATE INDEX IF NOT EXISTS idx_class_cohorts_class ON class_cohorts(class_id);
CREATE INDEX IF NOT EXISTS idx_class_cohorts_cohort ON class_cohorts(cohort_id);

-- ─── 3. CLASS ↔ MENTORS BRIDGE TABLE ───
-- Vincula mentores escalados a cada classe (professor e/ou host).
-- Permite saber quem notificar individualmente para cada aula.
CREATE TABLE IF NOT EXISTS class_mentors (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  class_id UUID NOT NULL REFERENCES classes(id) ON DELETE CASCADE,
  mentor_id UUID NOT NULL REFERENCES mentors(id) ON DELETE CASCADE,
  role TEXT NOT NULL DEFAULT 'Professor' CHECK (role IN ('Professor', 'Host')),
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(class_id, mentor_id, role)
);

CREATE INDEX IF NOT EXISTS idx_class_mentors_class ON class_mentors(class_id);
CREATE INDEX IF NOT EXISTS idx_class_mentors_mentor ON class_mentors(mentor_id);

-- ─── 4. NOTIFICATIONS TABLE ───
-- Registro de auditoria: TODA mensagem WhatsApp passa por aqui.
-- status='pending' → Edge Function processa → 'sent' | 'failed'
CREATE TABLE IF NOT EXISTS notifications (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,

  -- Tipo de notificação
  type TEXT NOT NULL CHECK (type IN (
    'class_reminder',     -- Lembrete de aula (grupo + mentores)
    'mentor_individual',  -- Mensagem direta para mentor
    'group_announcement', -- Aviso geral para grupo do cohort
    'schedule_change',    -- Mudança de escala / substituição
    'custom'              -- Mensagem customizada do admin
  )),

  -- Referências (nullable conforme tipo)
  class_id UUID REFERENCES classes(id) ON DELETE SET NULL,
  cohort_id UUID REFERENCES cohorts(id) ON DELETE SET NULL,
  mentor_id UUID REFERENCES mentors(id) ON DELETE SET NULL,

  -- Destino
  target_type TEXT NOT NULL CHECK (target_type IN ('group', 'individual', 'both')),
  target_phone TEXT,           -- Para individual: número do mentor
  target_group_jid TEXT,       -- Para grupo: JID do WhatsApp

  -- Conteúdo
  message_template TEXT NOT NULL, -- Template da mensagem com placeholders
  message_rendered TEXT,          -- Mensagem final renderizada
  metadata JSONB DEFAULT '{}',   -- Dados extras (zoom_link, professor, horário, etc.)

  -- Status machine
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN (
    'pending',     -- Aguardando processamento
    'processing',  -- Edge Function pegou, está enviando
    'sent',        -- Enviado com sucesso
    'partial',     -- Grupo OK mas individual falhou (ou vice-versa)
    'failed',      -- Falhou completamente
    'cancelled'    -- Cancelado antes do envio
  )),

  -- Rastreamento
  error_message TEXT,
  evolution_response JSONB,       -- Response body da Evolution API
  sent_at TIMESTAMPTZ,
  retry_count INT DEFAULT 0,
  max_retries INT DEFAULT 3,

  -- Auditoria
  created_by UUID REFERENCES auth.users(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  processed_at TIMESTAMPTZ
);

-- Indexes para queries frequentes
CREATE INDEX IF NOT EXISTS idx_notifications_status ON notifications(status);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_class ON notifications(class_id);
CREATE INDEX IF NOT EXISTS idx_notifications_cohort ON notifications(cohort_id);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notifications_pending ON notifications(status) WHERE status = 'pending';

-- ─── 5. RLS POLICIES ───

ALTER TABLE mentors ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_cohorts ENABLE ROW LEVEL SECURITY;
ALTER TABLE class_mentors ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Mentors: leitura para autenticados, escrita para admin
CREATE POLICY "Authenticated read mentors" ON mentors
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admin insert mentors" ON mentors
  FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin update mentors" ON mentors
  FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin delete mentors" ON mentors
  FOR DELETE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- Class-Cohorts bridge: mesma policy
CREATE POLICY "Authenticated read class_cohorts" ON class_cohorts
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admin insert class_cohorts" ON class_cohorts
  FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin update class_cohorts" ON class_cohorts
  FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin delete class_cohorts" ON class_cohorts
  FOR DELETE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- Class-Mentors bridge: mesma policy
CREATE POLICY "Authenticated read class_mentors" ON class_mentors
  FOR SELECT TO authenticated USING (true);
CREATE POLICY "Admin insert class_mentors" ON class_mentors
  FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin update class_mentors" ON class_mentors
  FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin delete class_mentors" ON class_mentors
  FOR DELETE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- Notifications: leitura admin-only (dados sensíveis), escrita admin + service_role
CREATE POLICY "Admin read notifications" ON notifications
  FOR SELECT TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin insert notifications" ON notifications
  FOR INSERT TO authenticated
  WITH CHECK ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');
CREATE POLICY "Admin update notifications" ON notifications
  FOR UPDATE TO authenticated
  USING ((auth.jwt() -> 'user_metadata' ->> 'role') = 'admin');

-- Service role bypass para Edge Function atualizar status
-- (service_role key ignora RLS por padrão, mas documentamos a intenção)

-- ─── 6. TRIGGERS ───

-- updated_at automático (reutiliza function existente de schema.sql)
CREATE TRIGGER mentors_updated_at
  BEFORE UPDATE ON mentors
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

CREATE TRIGGER notifications_updated_at
  BEFORE UPDATE ON notifications
  FOR EACH ROW EXECUTE FUNCTION update_updated_at();

-- ─── 7. SEED: MENTORS ───
INSERT INTO mentors (name, phone, role) VALUES
  ('Talles',          '556499425822',    'Both'),
  ('Jose Amorim',     '559281951096',    'Professor'),
  ('Klaus',           '5516996308617',   'Professor'),
  ('Day',             '5511978031078',   'Professor'),
  ('Sidney',          '556199496931',    'Professor'),
  ('Rodrigo Feldman', '5511952961036',   'Professor'),
  ('Bruno Gentil',    '556199331574',    'Both'),
  ('Diego',           '558386181165',    'Both'),
  ('Adavio',          '558296838800',    'Professor'),
  ('Alan Nicolas',    '554891642424',    'Professor'),
  ('Adriano',         '5515997425595',   'Professor'),
  ('Douglas',         '5521998628489',   'Host'),
  ('Lucas Charao',    '555191882447',    'Host'),
  ('Fran',            '5518988119126',   'Host')
ON CONFLICT (phone) DO UPDATE SET
  name = EXCLUDED.name,
  role = EXCLUDED.role;

-- ─── 8. WEBHOOK SETUP (via Dashboard) ───
-- Configure no Supabase Dashboard > Database > Webhooks:
--
-- Name:     notify-whatsapp-on-pending
-- Table:    notifications
-- Events:   INSERT
-- Condition: status = 'pending'
-- Type:     Supabase Edge Function
-- Function: send-whatsapp
-- HTTP Headers:
--   Authorization: Bearer <SUPABASE_SERVICE_ROLE_KEY>
--
-- NOTA: Webhooks de DB não suportam filtro condicional nativo.
-- A Edge Function fará a verificação de status='pending' internamente.
