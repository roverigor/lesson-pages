# Story NPS.D.3 — Add Auth to Edge Functions

**Epic:** EPIC-NPS-DISPATCH
**Status:** Ready
**Type:** Edge Function / Security
**Wave:** 1 (BLOCKER)
**Estimated:** 1-2h (S)
**Primary Agent:** @dev
**Assist Agents:** @architect (security review)
**Severity:** CRITICAL — CLAUDE.md NON-NEGOTIABLE violation

## O que fazer

`dispatch-retry/index.ts` e `dispatch-class-nps/index.ts` aceitam POST sem auth. URLs são previsíveis (`gpufcipkajppykmnmdeh.supabase.co/functions/v1/{name}`). Quando `nps_dispatch_enabled=true`, qualquer POST anônimo dispara mensagens.

**Risco real:** atacante com URL flipa flag (ex: JWT de admin roubado) + POST direto = mass send.

## Fix

Adicionar em ambas as functions, no início do handler:

```typescript
const auth = req.headers.get("authorization") ?? "";
const bearer = auth.replace(/^Bearer\s+/i, "").trim();
if (bearer !== SUPABASE_SERVICE_ROLE_KEY) {
  return new Response(
    JSON.stringify({ error: "unauthorized" }),
    { status: 401, headers: { ...CORS, "Content-Type": "application/json" } },
  );
}
```

Centralizar em `_shared/auth.ts` (export `verifyServiceRole(req): boolean`).

## Acceptance Criteria

### Bloco A — Auth Helper

- [ ] **AC-1:** `_shared/auth.ts` exporta `verifyServiceRole(req: Request): boolean` que compara `Authorization: Bearer <key>` com `SUPABASE_SERVICE_ROLE_KEY` env var (timing-safe compare se possível).
- [ ] **AC-2:** Helper retorna `false` se header ausente, mal formatado, ou key incorreta.

### Bloco B — Apply to Functions

- [ ] **AC-3:** `dispatch-retry/index.ts` rejeita 401 sem service-role bearer.
- [ ] **AC-4:** `dispatch-class-nps/index.ts` rejeita 401 sem service-role bearer.
- [ ] **AC-5:** Cron continua funcionando (já passa `Authorization: Bearer ${svc_key}`).
- [ ] **AC-6:** `retry_dispatch` SQL function passa header corretamente via `net.http_post`.

### Bloco C — Test

- [ ] **AC-7:** `curl -X POST {url} -d '{}'` retorna 401.
- [ ] **AC-8:** `curl -X POST {url} -H "Authorization: Bearer {service_key}" -d '{}'` retorna 200 (no-op se feature off).

## Dependencies

Nenhuma — independente das D.1/D.2

## Risk

LOW (mudança aditiva) — desde que cron passe header correto

## Files

- `supabase/functions/_shared/auth.ts` (extend)
- `supabase/functions/dispatch-retry/index.ts`
- `supabase/functions/dispatch-class-nps/index.ts`
- `supabase/migrations/20260516020800_dispatch_rpcs_part4.sql` (verify retry_dispatch passes header)
