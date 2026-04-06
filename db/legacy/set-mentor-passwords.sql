-- ═══════════════════════════════════════════════════════════
-- Script: Definir senhas iniciais dos mentores
-- Execute no Supabase SQL Editor (Dashboard > SQL Editor)
--
-- COMO USAR:
-- 1. Substitua 'SENHA_FORTE_AQUI' pela senha de cada mentor
-- 2. Execute o bloco completo
-- 3. Comunique as senhas aos mentores por canal seguro
-- 4. Peça que troquem na primeira oportunidade
--
-- REQUISITOS DE SENHA FORTE:
-- - Mínimo 12 caracteres
-- - Letras maiúsculas e minúsculas
-- - Números
-- - Caracteres especiais (!@#$%)
-- ═══════════════════════════════════════════════════════════

-- Atualiza a senha de um mentor pelo telefone:
-- UPDATE mentors
-- SET password_hash = crypt('SENHA_FORTE_AQUI', gen_salt('bf', 12))
-- WHERE phone = '55XXXXXXXXXXX';

-- Exemplo para atualizar vários de uma vez:
-- UPDATE mentors SET password_hash = crypt('SENHA_AQUI', gen_salt('bf', 12)) WHERE phone IN ('55XXX', '55YYY');

-- Para verificar quais mentores já têm senha definida:
SELECT name, phone, role,
  CASE WHEN password_hash IS NOT NULL THEN '✓ senha definida' ELSE '✗ sem senha' END as status
FROM mentors
WHERE active = true
ORDER BY name;
