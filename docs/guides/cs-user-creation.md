# Criação de Usuários CS — EPIC-015 Story 15.1

> **Como admin cria/promove usuários para a área CS** (`/cs/`).

## Pré-requisitos

- Acesso ao [Supabase Dashboard](https://supabase.com/dashboard/project/gpufcipkajppykmnmdeh)
- Permissão de admin no projeto Supabase

---

## Opção 1 — Promover usuário existente para CS

### Via SQL Editor

1. Abrir Supabase Dashboard → **SQL Editor**
2. Executar:

```sql
-- Promove usuário para role 'cs'
UPDATE auth.users
   SET raw_user_meta_data = jsonb_set(
     COALESCE(raw_user_meta_data, '{}'::jsonb),
     '{role}',
     '"cs"'
   )
 WHERE email = 'cs1@exemplo.com';
```

3. Verificar:

```sql
SELECT email, raw_user_meta_data->>'role' AS role
  FROM auth.users
 WHERE email = 'cs1@exemplo.com';
```

Deve retornar `role = cs`.

### Via Dashboard UI

1. **Authentication** → **Users**
2. Buscar usuário pelo email
3. Click no usuário → **User Metadata**
4. Editar JSON:
   ```json
   { "role": "cs" }
   ```
5. **Save**

---

## Opção 2 — Criar novo usuário CS do zero

### Via Dashboard

1. **Authentication** → **Users** → **Invite User**
2. Email: `csN@exemplo.com`
3. **Send invite** (usuário recebe email para definir senha)
4. Após usuário definir senha, executar SQL Opção 1 para promover role

### Via SQL (com senha temporária)

```sql
-- Cria user + define role em uma transação
INSERT INTO auth.users (
  email,
  encrypted_password,
  email_confirmed_at,
  raw_user_meta_data,
  raw_app_meta_data
) VALUES (
  'csN@exemplo.com',
  crypt('SenhaTemporaria123!', gen_salt('bf')),
  now(),
  '{"role": "cs"}'::jsonb,
  '{"provider": "email"}'::jsonb
)
ON CONFLICT (email) DO NOTHING;
```

Depois enviar credenciais via canal seguro + pedir para usuário trocar senha no primeiro login.

---

## Opção 3 — Despromover usuário (revogar acesso CS)

```sql
UPDATE auth.users
   SET raw_user_meta_data = jsonb_set(
     COALESCE(raw_user_meta_data, '{}'::jsonb),
     '{role}',
     'null'::jsonb
   )
 WHERE email = 'cs-removed@exemplo.com';
```

Próximo login → mensagem "Acesso não autorizado" + signOut automático.

---

## Validação

### Test E2E manual

1. Login `/admin/login` com email do CS user
2. **Esperado:** redirect automático para `/cs/`
3. Acessar `/admin/` diretamente (com session ativa CS)
4. **Esperado:** redirect para `/cs/` (admin guard reverso bloqueia CS)

### Test Edge Function

```bash
# Pegar JWT do usuário CS após login
JWT="<obtido via DevTools → Application → Local Storage → sb-...auth-token>"

# Testar dispatch-survey (deve retornar 200, anteriormente seria 401)
curl -X POST \
  -H "Authorization: Bearer $JWT" \
  -H "Content-Type: application/json" \
  -d '{"survey_id": "test-id", "prepare_only": true}' \
  https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/dispatch-survey

# Esperado: response sem erro 401
```

---

## Auth Flow Completo (referência)

```
1. CS user → /admin/login (email + senha)
   ↓
2. Supabase Auth signInWithPassword → JWT com user_metadata.role
   ↓
3. handleRoleRouting() lê role:
   ├─ 'cs'    → redirect /cs/
   ├─ 'admin' → showApp() (painel admin)
   └─ outros  → signOut + erro
   ↓
4a. CS em /cs/ → cs-portal/src/shared/auth-guard.js valida role IN ('cs','admin')
4b. Admin em /admin/ → painel funciona normalmente
   ↓
5. Edge functions: verifyAdminOrCs() em _shared/auth.ts aceita ambos roles
```

---

## Roles Aceitas (matriz)

| Role | `/admin/*` | `/cs/*` | Edge Functions |
|---|---|---|---|
| `admin` | ✅ Acesso total | ✅ Super-acesso | ✅ Aceita |
| `cs` | ❌ Bloqueado (redirect /cs/) | ✅ Acesso total | ✅ Aceita |
| (sem role) | ❌ Logout + erro | ❌ Logout + erro | ❌ 401 |
| `service_role` (server-to-server) | N/A | N/A | ✅ Bypass |

---

## Troubleshooting

### "Acesso não autorizado" após login válido

- Verificar `raw_user_meta_data->>'role'` está em `('admin', 'cs')`
- JWT pode estar cacheado — pedir user logout completo + re-login

### CS user em loop redirect /admin → /cs → /admin

- Pode indicar role corrompida — verificar JSON válido em `raw_user_meta_data`
- Forçar logout via `DELETE FROM auth.refresh_tokens WHERE user_id = X`

### Edge function 401 mesmo com JWT válido

- JWT pode ter expirado — refresh via `supabase.auth.refreshSession()`
- Verificar `_shared/auth.ts` está deployado: `supabase functions deploy dispatch-survey`

---

## Referências

- Story 15.1: `docs/stories/15.1.story.md`
- Spec EPIC-015: `docs/stories/EPIC-015-cs-area/spec/spec.md` §5 AC-1/2/3
- ASM-11: admin tem super-acesso a `/cs/*`
- Helper SQL: `is_cs_or_admin()` em migration `20260505100000_epic015_schema.sql`
