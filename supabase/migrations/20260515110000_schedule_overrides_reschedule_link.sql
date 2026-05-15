-- Vincula remarcações: cancelar aula em X + criar em Y → registros em ambos os lados
-- apontam pra contraparte via rescheduled_to (mesmo formato TEXT DD/MM que lesson_date)

ALTER TABLE schedule_overrides
  ADD COLUMN IF NOT EXISTS rescheduled_to TEXT;

COMMENT ON COLUMN schedule_overrides.rescheduled_to IS
  'Quando action=remove, aponta pra nova data DD/MM da aula remarcada. '
  'Quando action=add, aponta pra data original DD/MM da aula que foi remarcada pra cá. '
  'NULL = remoção/adição avulsa (não é parte de uma remarcação).';

CREATE INDEX IF NOT EXISTS idx_schedule_overrides_rescheduled_to
  ON schedule_overrides(rescheduled_to)
  WHERE rescheduled_to IS NOT NULL;
