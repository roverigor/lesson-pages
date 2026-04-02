-- ═══════════════════════════════════════
-- LESSON PAGES — Delivery Status Tracking
-- Adds delivered/read statuses + evolution_message_ids for delivery webhook
-- ═══════════════════════════════════════

-- ─── 1. ADD COLUMNS ───
ALTER TABLE public.notifications
  ADD COLUMN IF NOT EXISTS evolution_message_ids TEXT[] DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;

-- ─── 2. UPDATE STATUS CHECK CONSTRAINT ───
-- Drop existing constraint (name may vary) and re-add with delivered/read
DO $$
DECLARE v_constraint TEXT;
BEGIN
  SELECT conname INTO v_constraint
  FROM pg_constraint
  WHERE conrelid = 'public.notifications'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%status IN%';
  IF v_constraint IS NOT NULL THEN
    EXECUTE 'ALTER TABLE public.notifications DROP CONSTRAINT ' || quote_ident(v_constraint);
  END IF;
END $$;

ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_status_check CHECK (status IN (
    'pending',     -- Aguardando processamento
    'processing',  -- Edge Function pegou, está enviando
    'sent',        -- Enviado com sucesso para WhatsApp
    'partial',     -- Grupo OK mas individual falhou (ou vice-versa)
    'failed',      -- Falhou completamente
    'cancelled',   -- Cancelado antes do envio
    'delivered',   -- Confirmação de entrega no dispositivo (DELIVERY_ACK)
    'read'         -- Confirmação de leitura (READ/PLAYED)
  ));

-- ─── 3. GIN INDEX FOR MESSAGE ID LOOKUP ───
CREATE INDEX IF NOT EXISTS idx_notifications_evolution_msg_ids
  ON public.notifications USING GIN (evolution_message_ids);
