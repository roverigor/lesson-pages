# P2 — Anonymous Group NPS Form Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the public NPS landing page + storage layer that lets students submit feedback after a class without authentication, supporting both anonymous group links (1 link per class+cohort+date) and attributable DM links (1 link per student).

**Architecture:** Three new migrations (token table, response table, public RPC), one new edge function (`submit-survey-group`) with rate-limit + validation, one static HTML page (`survey/index.html`) accessed via Nginx rewrite rules `/survey/grupo/{token}` and `/survey/aluno/{token}`. All sends/dispatching is deferred to P3 — this sub-project only builds the receiving side.

**Tech Stack:** PostgreSQL (Supabase), Deno (edge functions), vanilla JS + Tailwind on landing page, Nginx for path rewrite.

**Spec reference:** `docs/superpowers/specs/2026-05-15-nps-anonymous-group-form-design.md`

---

## File Structure

**Migrations (new):**
- `supabase/migrations/20260516010000_nps_class_links.sql` — token table + RLS
- `supabase/migrations/20260516010100_class_nps_responses.sql` — response table + RLS + indexes
- `supabase/migrations/20260516010200_get_nps_link_metadata_rpc.sql` — SECURITY DEFINER RPC + grants

**Edge function (new):**
- `supabase/functions/submit-survey-group/index.ts` — POST handler with token validation, rate limit, response insert

**Public landing page (new):**
- `survey/index.html` — static, no auth, vanilla JS (top-level, NOT under `/admin/`)
- `survey/styles.css` — minimal styling (Inter font, mobile-first)
- `survey/app.js` — token extraction, RPC call, form render, submit

**Runbook (new):**
- `docs/runbooks/nps-test-tokens.md` — SQL snippet to generate test tokens for QA before P3 exists

**Nginx config update (manual on VPS):**
- `/etc/nginx/sites-available/painel-lesson-pages` — add `location ~ ^/survey/(grupo|aluno)/(.+)$` rewrite

---

## Task 1: Migration — `nps_class_links` table

**Files:**
- Create: `supabase/migrations/20260516010000_nps_class_links.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P2 — NPS class links (tokens that authorize anonymous form access)
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.nps_class_links (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token          text UNIQUE NOT NULL,
  class_id       uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  cohort_id      uuid NOT NULL REFERENCES public.cohorts(id) ON DELETE CASCADE,
  trigger_date   date NOT NULL,
  mode           text NOT NULL CHECK (mode IN ('group','dm')),
  student_id     uuid REFERENCES public.students(id) ON DELETE CASCADE,
  expires_at     timestamptz NOT NULL,
  response_count integer NOT NULL DEFAULT 0,
  created_by     text NOT NULL DEFAULT 'system',
  created_at     timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT nps_class_links_mode_student_consistency
    CHECK (
      (mode = 'dm' AND student_id IS NOT NULL) OR
      (mode = 'group' AND student_id IS NULL)
    )
);

-- One group link per (class, cohort, date)
CREATE UNIQUE INDEX IF NOT EXISTS idx_nps_class_links_group_unique
  ON public.nps_class_links (class_id, cohort_id, trigger_date)
  WHERE mode = 'group';

-- One DM link per (class, cohort, date, student)
CREATE UNIQUE INDEX IF NOT EXISTS idx_nps_class_links_dm_unique
  ON public.nps_class_links (class_id, cohort_id, trigger_date, student_id)
  WHERE mode = 'dm';

CREATE INDEX IF NOT EXISTS idx_nps_class_links_token
  ON public.nps_class_links (token);

CREATE INDEX IF NOT EXISTS idx_nps_class_links_expires
  ON public.nps_class_links (expires_at)
  WHERE expires_at > now();

ALTER TABLE public.nps_class_links ENABLE ROW LEVEL SECURITY;

CREATE POLICY "nps_links: read for auth"
  ON public.nps_class_links FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "nps_links: full for service"
  ON public.nps_class_links FOR ALL
  TO service_role USING (true) WITH CHECK (true);

COMMIT;
```

- [ ] **Step 2: Verify migration applies cleanly**

Run: `supabase db push --include-all`
Expected: migration `20260516010000_nps_class_links` listed as applied; no error.

- [ ] **Step 3: Verify constraints work**

Run in psql / Supabase SQL editor:
```sql
-- This should FAIL (group mode with student_id):
INSERT INTO nps_class_links (token, class_id, cohort_id, trigger_date, mode, student_id, expires_at)
SELECT 'test_fail_1', c.id, co.id, CURRENT_DATE, 'group', s.id, CURRENT_DATE + 14
FROM classes c, cohorts co, students s LIMIT 1;
-- Expected: ERROR: nps_class_links_mode_student_consistency

-- This should FAIL (dm mode without student_id):
INSERT INTO nps_class_links (token, class_id, cohort_id, trigger_date, mode, expires_at)
SELECT 'test_fail_2', c.id, co.id, CURRENT_DATE, 'dm', CURRENT_DATE + 14
FROM classes c, cohorts co LIMIT 1;
-- Expected: ERROR: nps_class_links_mode_student_consistency
```

Expected: both INSERTs fail with the constraint violation.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260516010000_nps_class_links.sql
git commit -m "feat(nps): add nps_class_links table for anonymous form tokens"
```

---

## Task 2: Migration — `class_nps_responses` table

**Files:**
- Create: `supabase/migrations/20260516010100_class_nps_responses.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P2 — Class NPS responses (anonymous + attributable)
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE TABLE IF NOT EXISTS public.class_nps_responses (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  link_id        uuid NOT NULL REFERENCES public.nps_class_links(id) ON DELETE CASCADE,
  class_id       uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  cohort_id      uuid NOT NULL REFERENCES public.cohorts(id) ON DELETE CASCADE,
  mode           text NOT NULL CHECK (mode IN ('group','dm')),
  student_id     uuid REFERENCES public.students(id) ON DELETE SET NULL,
  nps_score      smallint NOT NULL CHECK (nps_score BETWEEN 0 AND 10),
  comment        text,
  name_provided  text,
  ip_hash        text,
  user_agent     text,
  submitted_at   timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_class_nps_responses_class
  ON public.class_nps_responses (class_id, cohort_id, submitted_at DESC);

CREATE INDEX IF NOT EXISTS idx_class_nps_responses_link
  ON public.class_nps_responses (link_id);

CREATE INDEX IF NOT EXISTS idx_class_nps_responses_student
  ON public.class_nps_responses (student_id)
  WHERE student_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_class_nps_responses_ip_window
  ON public.class_nps_responses (ip_hash, submitted_at DESC)
  WHERE ip_hash IS NOT NULL;

ALTER TABLE public.class_nps_responses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "nps_responses: read for auth"
  ON public.class_nps_responses FOR SELECT
  TO authenticated USING (true);

CREATE POLICY "nps_responses: full for service"
  ON public.class_nps_responses FOR ALL
  TO service_role USING (true) WITH CHECK (true);

COMMIT;
```

- [ ] **Step 2: Verify migration applies**

Run: `supabase db push --include-all`
Expected: migration `20260516010100_class_nps_responses` applied.

- [ ] **Step 3: Verify nps_score check works**

Run in SQL editor:
```sql
-- Should FAIL (score = 11):
INSERT INTO class_nps_responses (link_id, class_id, cohort_id, mode, nps_score)
SELECT l.id, l.class_id, l.cohort_id, l.mode, 11
FROM nps_class_links l LIMIT 1;
-- Expected: ERROR: violates check constraint "class_nps_responses_nps_score_check"
```

Expected: INSERT fails. If no link rows exist yet, skip this step — it will be re-validated in Task 4.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/20260516010100_class_nps_responses.sql
git commit -m "feat(nps): add class_nps_responses table"
```

---

## Task 3: Migration — `get_nps_link_metadata` RPC

**Files:**
- Create: `supabase/migrations/20260516010200_get_nps_link_metadata_rpc.sql`

- [ ] **Step 1: Write the migration**

```sql
-- ═══════════════════════════════════════════════════════════════════════════
-- P2 — Public RPC for landing page to fetch link metadata without exposing
--      nps_class_links to anon clients.
-- Date: 2026-05-16
-- ═══════════════════════════════════════════════════════════════════════════

BEGIN;

CREATE OR REPLACE FUNCTION public.get_nps_link_metadata(p_token text)
RETURNS TABLE (
  valid        boolean,
  expired      boolean,
  mode         text,
  class_name   text,
  cohort_name  text,
  student_name text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link nps_class_links%ROWTYPE;
BEGIN
  SELECT * INTO v_link FROM nps_class_links WHERE token = p_token;

  IF NOT FOUND THEN
    RETURN QUERY SELECT false, false, NULL::text, NULL::text, NULL::text, NULL::text;
    RETURN;
  END IF;

  IF v_link.expires_at < now() THEN
    RETURN QUERY SELECT false, true, v_link.mode, NULL::text, NULL::text, NULL::text;
    RETURN;
  END IF;

  RETURN QUERY
    SELECT
      true,
      false,
      v_link.mode,
      c.title,
      coh.name,
      CASE WHEN v_link.mode = 'dm' THEN s.name ELSE NULL END
    FROM classes c
    JOIN cohorts coh ON coh.id = v_link.cohort_id
    LEFT JOIN students s ON s.id = v_link.student_id
    WHERE c.id = v_link.class_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_nps_link_metadata(text) FROM public;
GRANT EXECUTE ON FUNCTION public.get_nps_link_metadata(text) TO anon, authenticated;

COMMIT;
```

- [ ] **Step 2: Verify migration applies**

Run: `supabase db push --include-all`
Expected: migration applied.

- [ ] **Step 3: Verify RPC behavior — invalid token**

Run in SQL editor as `anon` role (or with anon key via REST):
```sql
SELECT * FROM get_nps_link_metadata('nonexistent_token_xyz');
-- Expected: 1 row with valid=false, expired=false, others NULL
```

- [ ] **Step 4: Verify RPC behavior — valid token (after seeding one)**

```sql
-- Seed test link manually:
INSERT INTO nps_class_links (token, class_id, cohort_id, trigger_date, mode, expires_at)
SELECT 'rpc_test_token_001', c.id, co.id, CURRENT_DATE, 'group', CURRENT_DATE + 14
FROM classes c, class_cohorts cc, cohorts co
WHERE cc.class_id = c.id AND cc.cohort_id = co.id
LIMIT 1
RETURNING token, class_id, cohort_id;

-- Then call RPC:
SELECT * FROM get_nps_link_metadata('rpc_test_token_001');
-- Expected: valid=true, expired=false, mode='group', class_name + cohort_name populated, student_name=NULL
```

- [ ] **Step 5: Clean up test seed**

```sql
DELETE FROM nps_class_links WHERE token = 'rpc_test_token_001';
```

- [ ] **Step 6: Commit**

```bash
git add supabase/migrations/20260516010200_get_nps_link_metadata_rpc.sql
git commit -m "feat(nps): add public RPC get_nps_link_metadata for landing page"
```

---

## Task 4: Edge function — `submit-survey-group`

**Files:**
- Create: `supabase/functions/submit-survey-group/index.ts`

Following the structure of existing edge functions in this repo (e.g., `dispatch-survey/index.ts`, `submit-survey/index.ts`).

- [ ] **Step 1: Write the edge function**

```typescript
// ═══════════════════════════════════════════════════════════════════════════
// submit-survey-group — Public endpoint to submit anonymous NPS responses.
//
// Request body:
//   {
//     "token":         string (required),
//     "nps_score":     number 0-10 (required),
//     "comment":       string (optional),
//     "name_provided": string (optional, only honored when link.mode='group')
//   }
//
// Validates token, rate-limits by ip_hash (5 / 24h), inserts response, bumps counter.
// ═══════════════════════════════════════════════════════════════════════════

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const IP_HASH_SALT = Deno.env.get("NPS_IP_HASH_SALT") ?? "fallback-rotate-me";
const MAX_SUBMITS_PER_IP_24H = 5;

const CORS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const buf = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(input));
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function clientIp(req: Request): string {
  return (
    req.headers.get("x-forwarded-for")?.split(",")[0].trim() ??
    req.headers.get("cf-connecting-ip") ??
    req.headers.get("x-real-ip") ??
    "unknown"
  );
}

function dailySaltSuffix(): string {
  // Stable within UTC day, rotates daily so IP hashes can't track across days.
  return new Date().toISOString().slice(0, 10);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return jsonResponse({ error: "method_not_allowed" }, 405);

  let body: {
    token?: string;
    nps_score?: number;
    comment?: string;
    name_provided?: string;
  };
  try {
    body = await req.json();
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400);
  }

  const token = (body.token ?? "").trim();
  const nps_score = body.nps_score;
  const comment = (body.comment ?? "").trim() || null;
  const nameProvided = (body.name_provided ?? "").trim() || null;

  if (!token) return jsonResponse({ error: "missing_token" }, 400);
  if (
    typeof nps_score !== "number" ||
    !Number.isInteger(nps_score) ||
    nps_score < 0 ||
    nps_score > 10
  ) {
    return jsonResponse({ error: "invalid_nps_score" }, 400);
  }

  const sb = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  // 1. Lookup link
  const { data: link, error: linkErr } = await sb
    .from("nps_class_links")
    .select("id, class_id, cohort_id, mode, student_id, expires_at")
    .eq("token", token)
    .maybeSingle();

  if (linkErr) return jsonResponse({ error: "internal_error" }, 500);
  if (!link) return jsonResponse({ error: "token_not_found" }, 404);
  if (new Date(link.expires_at).getTime() < Date.now()) {
    return jsonResponse({ error: "token_expired" }, 410);
  }

  // 2. Rate limit by IP hash
  const ip = clientIp(req);
  const ipHash = await sha256Hex(`${ip}|${IP_HASH_SALT}|${dailySaltSuffix()}`);
  const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

  const { count: recentCount, error: countErr } = await sb
    .from("class_nps_responses")
    .select("id", { count: "exact", head: true })
    .eq("ip_hash", ipHash)
    .gte("submitted_at", since);

  if (countErr) return jsonResponse({ error: "internal_error" }, 500);
  if ((recentCount ?? 0) >= MAX_SUBMITS_PER_IP_24H) {
    return jsonResponse({ error: "rate_limited" }, 429);
  }

  // 3. Insert response
  const userAgent = req.headers.get("user-agent")?.slice(0, 500) ?? null;

  const { error: insertErr } = await sb.from("class_nps_responses").insert({
    link_id: link.id,
    class_id: link.class_id,
    cohort_id: link.cohort_id,
    mode: link.mode,
    student_id: link.mode === "dm" ? link.student_id : null,
    nps_score,
    comment,
    name_provided: link.mode === "group" ? nameProvided : null,
    ip_hash: ipHash,
    user_agent: userAgent,
  });

  if (insertErr) return jsonResponse({ error: "internal_error" }, 500);

  // 4. Increment counter (best-effort, not transactional)
  await sb.rpc("increment_nps_link_response_count", { p_link_id: link.id }).then(() => {});

  return jsonResponse({
    success: true,
    thank_you: "Obrigado pelo feedback! Sua opinião é fundamental.",
  });
});
```

- [ ] **Step 2: Add the increment RPC helper migration**

The function above uses `increment_nps_link_response_count`. Add a small migration so it exists.

Create: `supabase/migrations/20260516010300_increment_nps_link_response_count.sql`

```sql
BEGIN;

CREATE OR REPLACE FUNCTION public.increment_nps_link_response_count(p_link_id uuid)
RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.nps_class_links
  SET response_count = response_count + 1
  WHERE id = p_link_id;
$$;

REVOKE ALL ON FUNCTION public.increment_nps_link_response_count(uuid) FROM public;
GRANT EXECUTE ON FUNCTION public.increment_nps_link_response_count(uuid) TO service_role;

COMMIT;
```

- [ ] **Step 3: Apply migration**

Run: `supabase db push --include-all`
Expected: migration applied.

- [ ] **Step 4: Set `NPS_IP_HASH_SALT` secret**

Run locally for testing:
```bash
supabase secrets set NPS_IP_HASH_SALT="$(openssl rand -hex 32)"
```

Expected: secret stored. Production deploy will need same.

- [ ] **Step 5: Deploy edge function**

```bash
supabase functions deploy submit-survey-group --no-verify-jwt
```

Note: `--no-verify-jwt` because the endpoint is public (no JWT required from clients).
Expected: function deployed, URL printed.

- [ ] **Step 6: Integration test — happy path**

First seed a token in SQL editor:
```sql
INSERT INTO nps_class_links (token, class_id, cohort_id, trigger_date, mode, expires_at)
SELECT 'integ_test_001', cc.class_id, cc.cohort_id, CURRENT_DATE, 'group', CURRENT_DATE + 14
FROM class_cohorts cc LIMIT 1
RETURNING token;
```

Then call function:
```bash
curl -X POST 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/submit-survey-group' \
  -H 'Content-Type: application/json' \
  -d '{"token":"integ_test_001","nps_score":9,"comment":"Aula muito boa","name_provided":"Teste"}'
```

Expected response:
```json
{"success":true,"thank_you":"Obrigado pelo feedback! Sua opinião é fundamental."}
```

Then verify in SQL editor:
```sql
SELECT nps_score, comment, name_provided, mode
FROM class_nps_responses
WHERE link_id = (SELECT id FROM nps_class_links WHERE token = 'integ_test_001');
-- Expected: 1 row with nps_score=9, comment='Aula muito boa', name_provided='Teste', mode='group'

SELECT response_count FROM nps_class_links WHERE token = 'integ_test_001';
-- Expected: 1
```

- [ ] **Step 7: Integration test — invalid score**

```bash
curl -X POST 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/submit-survey-group' \
  -H 'Content-Type: application/json' \
  -d '{"token":"integ_test_001","nps_score":11}'
```

Expected response (HTTP 400):
```json
{"error":"invalid_nps_score"}
```

- [ ] **Step 8: Integration test — missing token**

```bash
curl -X POST 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/submit-survey-group' \
  -H 'Content-Type: application/json' \
  -d '{"nps_score":8}'
```

Expected response (HTTP 400):
```json
{"error":"missing_token"}
```

- [ ] **Step 9: Integration test — nonexistent token**

```bash
curl -X POST 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/submit-survey-group' \
  -H 'Content-Type: application/json' \
  -d '{"token":"does_not_exist_xyz","nps_score":7}'
```

Expected response (HTTP 404):
```json
{"error":"token_not_found"}
```

- [ ] **Step 10: Integration test — expired token**

```sql
-- Force expiry on the test token:
UPDATE nps_class_links SET expires_at = now() - interval '1 day'
WHERE token = 'integ_test_001';
```

```bash
curl -X POST 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/submit-survey-group' \
  -H 'Content-Type: application/json' \
  -d '{"token":"integ_test_001","nps_score":7}'
```

Expected response (HTTP 410):
```json
{"error":"token_expired"}
```

- [ ] **Step 11: Integration test — rate limit (6th submit gets 429)**

Reset expiry first:
```sql
UPDATE nps_class_links SET expires_at = CURRENT_DATE + interval '14 days'
WHERE token = 'integ_test_001';
```

Submit 5 times (Steps 6 already did 1; do 4 more):
```bash
for i in 2 3 4 5; do
  curl -s -X POST 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/submit-survey-group' \
    -H 'Content-Type: application/json' \
    -d "{\"token\":\"integ_test_001\",\"nps_score\":$i}"
  echo
done
```

Expected: 4 successes.

Then 6th attempt:
```bash
curl -X POST 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/submit-survey-group' \
  -H 'Content-Type: application/json' \
  -d '{"token":"integ_test_001","nps_score":6}'
```

Expected response (HTTP 429):
```json
{"error":"rate_limited"}
```

- [ ] **Step 12: Clean up integration test data**

```sql
DELETE FROM nps_class_links WHERE token = 'integ_test_001';
-- class_nps_responses rows cascade-delete via FK.
```

- [ ] **Step 13: Commit**

```bash
git add supabase/functions/submit-survey-group/index.ts \
        supabase/migrations/20260516010300_increment_nps_link_response_count.sql
git commit -m "feat(nps): add submit-survey-group edge function with rate limit"
```

---

## Task 5: Landing page — static HTML + JS

**Files:**
- Create: `survey/index.html`
- Create: `survey/styles.css`
- Create: `survey/app.js`

The page lives at top-level `survey/` (NOT under `admin/`) so Nginx can serve it without the admin auth gate.

- [ ] **Step 1: Create directory**

```bash
mkdir -p /home/rover/lesson-pages/survey
```

- [ ] **Step 2: Write `survey/index.html`**

```html
<!DOCTYPE html>
<html lang="pt-BR">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Avaliar aula — Academia Lendária</title>
  <link rel="icon" href="data:image/svg+xml,<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 100 100'><text y='.9em' font-size='90'>📝</text></svg>">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&display=swap" rel="stylesheet">
  <link rel="stylesheet" href="/survey/styles.css">
</head>
<body>
  <main class="container">

    <header class="brand">
      <div class="logo">🏛️</div>
      <h1>Academia Lendária</h1>
    </header>

    <section id="loading" class="card">
      <p class="muted">Carregando…</p>
    </section>

    <section id="invalid" class="card hidden">
      <h2>Link inválido</h2>
      <p class="muted">Este link não foi reconhecido. Verifique se você copiou a URL completa.</p>
    </section>

    <section id="expired" class="card hidden">
      <h2>Link expirado</h2>
      <p class="muted">O período de avaliação para esta aula encerrou. Obrigado pelo interesse!</p>
    </section>

    <section id="form" class="card hidden">
      <h2 id="title">Avalie sua aula</h2>
      <p class="subtitle" id="subtitle"></p>

      <div class="field">
        <label for="nps">De 0 a 10, o quanto você recomendaria esta aula a um amigo?</label>
        <div id="nps" class="nps-grid" role="radiogroup" aria-label="Nota NPS">
          <!-- buttons inserted by JS -->
        </div>
      </div>

      <div class="field">
        <label for="comment">O que motivou sua nota? <span class="muted">(opcional)</span></label>
        <textarea id="comment" rows="3" maxlength="2000" placeholder="Conte mais…"></textarea>
      </div>

      <div class="field" id="name-field">
        <label for="name">Nome <span class="muted">(opcional, se quiser identificação)</span></label>
        <input id="name" type="text" maxlength="120" placeholder="Seu nome">
      </div>

      <button id="submit" type="button" class="primary" disabled>Enviar feedback</button>
      <p id="error" class="error hidden" role="alert"></p>
    </section>

    <section id="thank-you" class="card hidden">
      <div class="checkmark">✓</div>
      <h2>Obrigado!</h2>
      <p class="muted" id="thank-you-msg">Sua opinião é fundamental.</p>
    </section>

  </main>

  <script type="module" src="/survey/app.js"></script>
</body>
</html>
```

- [ ] **Step 3: Write `survey/styles.css`**

```css
:root {
  --bg: #0a0a0a;
  --card-bg: #111;
  --border: #1e1e1e;
  --text: #ddd;
  --muted: #777;
  --accent: #6366f1;
  --accent-hover: #8b5cf6;
  --danger: #ef4444;
  --success: #10b981;
}

* { box-sizing: border-box; margin: 0; padding: 0; }

body {
  font-family: 'Inter', system-ui, sans-serif;
  background: var(--bg);
  color: var(--text);
  min-height: 100vh;
  padding: 24px 16px;
  line-height: 1.5;
}

.container { max-width: 560px; margin: 0 auto; }

.brand { text-align: center; margin-bottom: 24px; }
.brand .logo { font-size: 40px; margin-bottom: 8px; }
.brand h1 { font-size: 16px; font-weight: 600; color: var(--muted); }

.card {
  background: var(--card-bg);
  border: 1px solid var(--border);
  border-radius: 16px;
  padding: 28px 24px;
  margin-bottom: 16px;
}

.card.hidden { display: none; }

h2 { font-size: 22px; font-weight: 700; color: #fff; margin-bottom: 8px; }
.subtitle { color: var(--muted); margin-bottom: 24px; font-size: 14px; }
.muted { color: var(--muted); }

.field { margin-bottom: 20px; }
.field label {
  display: block;
  font-size: 14px;
  color: var(--text);
  margin-bottom: 10px;
  font-weight: 500;
}

.nps-grid {
  display: grid;
  grid-template-columns: repeat(6, 1fr);
  gap: 6px;
}

@media (min-width: 480px) {
  .nps-grid { grid-template-columns: repeat(11, 1fr); }
}

.nps-btn {
  background: #0d0d0d;
  border: 1px solid var(--border);
  color: var(--text);
  padding: 12px 0;
  border-radius: 8px;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
  transition: all 0.12s;
}

.nps-btn:hover { border-color: var(--accent); }
.nps-btn.selected {
  background: linear-gradient(135deg, var(--accent), var(--accent-hover));
  border-color: var(--accent);
  color: #fff;
}

textarea, input[type="text"] {
  width: 100%;
  background: #0d0d0d;
  border: 1px solid var(--border);
  color: var(--text);
  padding: 12px 14px;
  border-radius: 10px;
  font-family: inherit;
  font-size: 14px;
  outline: none;
  transition: border-color 0.15s;
}

textarea { resize: vertical; min-height: 80px; }
textarea:focus, input[type="text"]:focus { border-color: var(--accent); }

.primary {
  width: 100%;
  padding: 14px;
  background: linear-gradient(135deg, var(--accent), var(--accent-hover));
  color: #fff;
  border: none;
  border-radius: 10px;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
  transition: opacity 0.15s;
}
.primary:disabled { opacity: 0.4; cursor: not-allowed; }

.error {
  color: var(--danger);
  font-size: 13px;
  margin-top: 12px;
  padding: 10px 12px;
  background: rgba(239, 68, 68, 0.1);
  border: 1px solid rgba(239, 68, 68, 0.3);
  border-radius: 8px;
}
.error.hidden { display: none; }

.checkmark {
  width: 64px;
  height: 64px;
  margin: 0 auto 16px;
  border-radius: 50%;
  background: linear-gradient(135deg, var(--success), #059669);
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 32px;
  color: #fff;
  font-weight: 800;
}

#thank-you { text-align: center; padding: 40px 24px; }
```

- [ ] **Step 4: Write `survey/app.js`**

```javascript
// ─── Config ──────────────────────────────────────────────────────────────
const SUPABASE_URL = "https://gpufcipkajppykmnmdeh.supabase.co";
const SUPABASE_ANON_KEY = "REPLACE_WITH_ANON_KEY_AT_DEPLOY";  // see Step 5

// ─── DOM helpers ─────────────────────────────────────────────────────────
const $ = (id) => document.getElementById(id);
const show = (id) => $(id).classList.remove("hidden");
const hide = (id) => $(id).classList.add("hidden");

function showOnly(id) {
  ["loading", "invalid", "expired", "form", "thank-you"].forEach((s) =>
    s === id ? show(s) : hide(s),
  );
}

// ─── Token extraction ────────────────────────────────────────────────────
function getToken() {
  // Path style: /survey/grupo/{token} or /survey/aluno/{token}
  const m = location.pathname.match(/^\/survey\/(grupo|aluno)\/([^/]+)$/);
  if (m) return { mode: m[1] === "grupo" ? "group" : "dm", token: m[2] };

  // Query fallback: ?token=...&mode=group
  const params = new URLSearchParams(location.search);
  const token = params.get("token");
  const mode = params.get("mode");
  if (token) return { mode: mode || null, token };

  return null;
}

// ─── Metadata fetch ──────────────────────────────────────────────────────
async function fetchMetadata(token) {
  const url = `${SUPABASE_URL}/rest/v1/rpc/get_nps_link_metadata`;
  const res = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "apikey": SUPABASE_ANON_KEY,
      "Authorization": `Bearer ${SUPABASE_ANON_KEY}`,
    },
    body: JSON.stringify({ p_token: token }),
  });
  if (!res.ok) throw new Error(`metadata_${res.status}`);
  const rows = await res.json();
  return Array.isArray(rows) ? rows[0] : rows;
}

// ─── Render NPS buttons ──────────────────────────────────────────────────
let selectedScore = null;

function renderNpsButtons() {
  const grid = $("nps");
  grid.innerHTML = "";
  for (let i = 0; i <= 10; i++) {
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "nps-btn";
    btn.textContent = String(i);
    btn.setAttribute("role", "radio");
    btn.setAttribute("aria-checked", "false");
    btn.addEventListener("click", () => selectScore(i));
    grid.appendChild(btn);
  }
}

function selectScore(score) {
  selectedScore = score;
  document.querySelectorAll(".nps-btn").forEach((b, idx) => {
    const isSelected = idx === score;
    b.classList.toggle("selected", isSelected);
    b.setAttribute("aria-checked", String(isSelected));
  });
  $("submit").disabled = false;
}

// ─── Submit ──────────────────────────────────────────────────────────────
async function submitResponse(token) {
  hide("error");
  $("submit").disabled = true;
  $("submit").textContent = "Enviando…";

  const comment = $("comment").value.trim();
  const name = $("name").value.trim();

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/submit-survey-group`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        token,
        nps_score: selectedScore,
        comment: comment || undefined,
        name_provided: name || undefined,
      }),
    });

    const data = await res.json().catch(() => ({}));

    if (res.ok && data.success) {
      $("thank-you-msg").textContent = data.thank_you ?? "Obrigado pelo feedback!";
      showOnly("thank-you");
      return;
    }

    let msg = "Não foi possível enviar. Tente novamente.";
    if (res.status === 410) msg = "Este link expirou. Obrigado pelo interesse!";
    else if (res.status === 429) msg = "Você já respondeu hoje. Obrigado!";
    else if (res.status === 404) msg = "Link inválido.";

    const errEl = $("error");
    errEl.textContent = msg;
    show("error");
    $("submit").disabled = false;
    $("submit").textContent = "Enviar feedback";
  } catch (e) {
    const errEl = $("error");
    errEl.textContent = "Erro de conexão. Verifique sua internet.";
    show("error");
    $("submit").disabled = false;
    $("submit").textContent = "Enviar feedback";
  }
}

// ─── Bootstrap ───────────────────────────────────────────────────────────
async function init() {
  showOnly("loading");
  const parsed = getToken();
  if (!parsed) {
    showOnly("invalid");
    return;
  }

  let meta;
  try {
    meta = await fetchMetadata(parsed.token);
  } catch {
    showOnly("invalid");
    return;
  }

  if (!meta || !meta.valid) {
    showOnly(meta?.expired ? "expired" : "invalid");
    return;
  }

  renderNpsButtons();

  const title = meta.mode === "dm" && meta.student_name
    ? `Olá, ${meta.student_name}!`
    : "Avalie sua aula";
  $("title").textContent = title;
  $("subtitle").textContent = `${meta.class_name} — ${meta.cohort_name}`;

  if (meta.mode === "dm") hide("name-field");

  $("submit").addEventListener("click", () => submitResponse(parsed.token));
  showOnly("form");
}

init();
```

- [ ] **Step 5: Replace anon key placeholder**

Find your Supabase anon key:
```bash
supabase status --output env | grep ANON
# or read from .env
```

Then replace `REPLACE_WITH_ANON_KEY_AT_DEPLOY` in `survey/app.js` with the actual anon key value (it's safe to commit — anon keys are public per Supabase design).

- [ ] **Step 6: Local visual test**

Serve the directory locally:
```bash
cd /home/rover/lesson-pages
python3 -m http.server 8000
```

Then open `http://localhost:8000/survey/index.html?token=integ_test_001&mode=group` in a browser.

Seed a token in SQL editor first if `integ_test_001` was cleaned up:
```sql
INSERT INTO nps_class_links (token, class_id, cohort_id, trigger_date, mode, expires_at)
SELECT 'integ_test_001', cc.class_id, cc.cohort_id, CURRENT_DATE, 'group', CURRENT_DATE + 14
FROM class_cohorts cc LIMIT 1;
```

Expected behavior:
- Page loads with class name + cohort name in subtitle.
- 11 NPS buttons render (0–10).
- Comment textarea present.
- Name field visible (mode=group).
- Submit disabled until a score is clicked.
- Click a button → it highlights, submit enables.
- Click submit → "Enviando…" → "Obrigado!" screen.

Verify in SQL:
```sql
SELECT nps_score, mode, name_provided FROM class_nps_responses
WHERE link_id = (SELECT id FROM nps_class_links WHERE token = 'integ_test_001')
ORDER BY submitted_at DESC LIMIT 1;
```

- [ ] **Step 7: Test mobile viewport**

In browser dev tools, switch to iPhone SE / 375px viewport. Verify:
- NPS grid wraps to 6 columns (then 5 below).
- All fields readable without horizontal scroll.
- Submit button full-width and tappable.

- [ ] **Step 8: Test DM mode rendering**

Seed a DM token:
```sql
INSERT INTO nps_class_links (token, class_id, cohort_id, trigger_date, mode, student_id, expires_at)
SELECT 'integ_test_dm_001', cc.class_id, cc.cohort_id, CURRENT_DATE, 'dm', s.id, CURRENT_DATE + 14
FROM class_cohorts cc, students s WHERE s.cohort_id = cc.cohort_id LIMIT 1;
```

Open `http://localhost:8000/survey/index.html?token=integ_test_dm_001&mode=dm`. Verify:
- Title shows "Olá, {student name}!".
- Name field is HIDDEN.

- [ ] **Step 9: Test expired token rendering**

```sql
UPDATE nps_class_links SET expires_at = now() - interval '1 day'
WHERE token = 'integ_test_001';
```

Reload page. Expected: "Link expirado" message.

- [ ] **Step 10: Test invalid token rendering**

Open `http://localhost:8000/survey/index.html?token=nope`. Expected: "Link inválido" message.

- [ ] **Step 11: Clean up test data**

```sql
DELETE FROM nps_class_links WHERE token IN ('integ_test_001', 'integ_test_dm_001');
```

- [ ] **Step 12: Commit**

```bash
git add survey/
git commit -m "feat(nps): add public landing page for anonymous NPS submission"
```

---

## Task 6: Nginx rewrite configuration

The VPS uses Nginx (per CLAUDE.md: `/etc/nginx/sites-available/painel-lesson-pages`). Static files are served from the container. Need a path rewrite so `/survey/grupo/{token}` and `/survey/aluno/{token}` serve `/survey/index.html` (which handles routing in JS).

**Files:**
- Create: `docs/runbooks/nps-nginx-rewrite.md` (runbook for manual VPS update)

- [ ] **Step 1: Write the runbook**

```markdown
# NPS Landing Page — Nginx Rewrite Setup

The public NPS landing page lives at `/survey/index.html` and reads the token from the URL path. Nginx must rewrite `/survey/grupo/{token}` and `/survey/aluno/{token}` to that file (without redirecting — the browser must see the original URL so JS can parse it).

## SSH to VPS

```bash
ssh -i ~/.ssh/contabo root@194.163.179.68
```

## Edit Nginx config

```bash
sudo nano /etc/nginx/sites-available/painel-lesson-pages
```

Inside the `server { ... }` block for `painel.igorrover.com.br`, **before** any existing `location /` block, add:

```nginx
# NPS public landing — rewrite token paths to static index.html
location ~ ^/survey/(grupo|aluno)/[A-Za-z0-9_\-+/=]+$ {
    try_files /survey/index.html =404;
    add_header Cache-Control "no-cache" always;
}

# NPS static assets — pass through normally
location ^~ /survey/ {
    proxy_pass http://localhost:3080;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
}
```

## Test config

```bash
sudo nginx -t
# Expected: nginx: configuration file /etc/nginx/nginx.conf test is successful
```

## Reload

```bash
sudo systemctl reload nginx
```

## Verify

```bash
# Token URL serves the form (HTTP 200, HTML body)
curl -sI 'https://painel.igorrover.com.br/survey/grupo/test_token_xyz' | head -1
# Expected: HTTP/2 200

curl -s 'https://painel.igorrover.com.br/survey/grupo/test_token_xyz' | grep -o '<title>.*</title>'
# Expected: <title>Avaliar aula — Academia Lendária</title>

# Static asset (CSS) loads
curl -sI 'https://painel.igorrover.com.br/survey/styles.css' | head -1
# Expected: HTTP/2 200
```
```

- [ ] **Step 2: Apply on VPS**

Follow the runbook on the VPS. This is a manual step — does NOT happen via GitHub Actions deploy.

- [ ] **Step 3: Verify path works on production**

```bash
curl -sI 'https://painel.igorrover.com.br/survey/grupo/whatever_token' | head -3
# Expected: HTTP/2 200, content-type text/html
```

- [ ] **Step 4: Commit the runbook**

```bash
git add docs/runbooks/nps-nginx-rewrite.md
git commit -m "docs: add nginx rewrite runbook for NPS survey paths"
```

---

## Task 7: QA token generation runbook

**Files:**
- Create: `docs/runbooks/nps-test-tokens.md`

This documents how an admin generates test tokens for QA before the P3 dispatcher exists.

- [ ] **Step 1: Write the runbook**

```markdown
# NPS Test Tokens — Manual Generation

Until P3 (post-class NPS dispatcher) is implemented, tokens for the NPS landing page
must be generated manually for QA / pilot tests.

## Generate a group (anonymous) token

Run in Supabase SQL editor:

```sql
INSERT INTO nps_class_links (
  token, class_id, cohort_id, trigger_date, mode, expires_at, created_by
)
SELECT
  encode(gen_random_bytes(18), 'base64') AS token,
  cc.class_id,
  cc.cohort_id,
  CURRENT_DATE,
  'group',
  CURRENT_DATE + interval '14 days',
  'qa-manual'
FROM class_cohorts cc
WHERE cc.class_id = '<CLASS_UUID>'
  AND cc.cohort_id = '<COHORT_UUID>'
RETURNING
  token,
  'https://painel.igorrover.com.br/survey/grupo/' || token AS url;
```

Replace `<CLASS_UUID>` and `<COHORT_UUID>` with real IDs.

The query returns the token + the full URL to share for testing.

## Generate a DM (per-student) token

```sql
INSERT INTO nps_class_links (
  token, class_id, cohort_id, trigger_date, mode, student_id, expires_at, created_by
)
SELECT
  encode(gen_random_bytes(18), 'base64') AS token,
  '<CLASS_UUID>',
  '<COHORT_UUID>',
  CURRENT_DATE,
  'dm',
  '<STUDENT_UUID>',
  CURRENT_DATE + interval '14 days',
  'qa-manual'
RETURNING
  token,
  'https://painel.igorrover.com.br/survey/aluno/' || token AS url;
```

## Inspect responses

```sql
SELECT
  r.nps_score,
  r.comment,
  r.name_provided,
  r.mode,
  s.name AS student_name,
  c.title AS class_name,
  co.name AS cohort_name,
  r.submitted_at
FROM class_nps_responses r
JOIN classes c ON c.id = r.class_id
JOIN cohorts co ON co.id = r.cohort_id
LEFT JOIN students s ON s.id = r.student_id
WHERE r.submitted_at > now() - interval '7 days'
ORDER BY r.submitted_at DESC;
```

## NPS aggregate per class

```sql
SELECT
  c.title,
  co.name,
  COUNT(*) AS responses,
  ROUND(AVG(nps_score)::numeric, 1) AS avg_score,
  COUNT(*) FILTER (WHERE nps_score >= 9) AS promoters,
  COUNT(*) FILTER (WHERE nps_score <= 6) AS detractors,
  ROUND(
    100.0 * (COUNT(*) FILTER (WHERE nps_score >= 9) - COUNT(*) FILTER (WHERE nps_score <= 6))
    / NULLIF(COUNT(*), 0),
    1
  ) AS nps
FROM class_nps_responses r
JOIN classes c ON c.id = r.class_id
JOIN cohorts co ON co.id = r.cohort_id
GROUP BY c.title, co.name
ORDER BY responses DESC;
```

## Revoke a token early

```sql
UPDATE nps_class_links SET expires_at = now() WHERE token = '<TOKEN>';
```
```

- [ ] **Step 2: Commit**

```bash
git add docs/runbooks/nps-test-tokens.md
git commit -m "docs: add NPS manual token generation runbook"
```

---

## Task 8: End-to-end validation on production

This is a final acceptance test against the deployed system.

**Files:** none (verification only)

- [ ] **Step 1: Confirm production migrations applied**

In Supabase Studio for project `gpufcipkajppykmnmdeh`:
```sql
SELECT name, executed_at FROM supabase_migrations.schema_migrations
WHERE name LIKE '%nps_class_links%'
   OR name LIKE '%class_nps_responses%'
   OR name LIKE '%get_nps_link_metadata%'
   OR name LIKE '%increment_nps_link_response_count%'
ORDER BY executed_at DESC;
```

Expected: 4 rows for the 4 migrations.

- [ ] **Step 2: Confirm edge function deployed**

```bash
supabase functions list --project-ref gpufcipkajppykmnmdeh
```

Expected: `submit-survey-group` listed as deployed.

- [ ] **Step 3: Confirm Nginx rewrite applied**

```bash
curl -sI 'https://painel.igorrover.com.br/survey/grupo/foo' | head -1
# Expected: HTTP/2 200

curl -s 'https://painel.igorrover.com.br/survey/grupo/foo' | grep -o '<title>[^<]*</title>'
# Expected: <title>Avaliar aula — Academia Lendária</title>
```

- [ ] **Step 4: Generate a real test token**

Use the runbook from Task 7. Pick a real (active) class+cohort:

```sql
-- Pick a PS Fundamentals + Cohort Fund T5 bridge for example:
INSERT INTO nps_class_links (
  token, class_id, cohort_id, trigger_date, mode, expires_at, created_by
)
SELECT
  encode(gen_random_bytes(18), 'base64'),
  '0e5df244-8068-4839-a1b1-2bf36616e0ab',  -- PS Fundamentals
  '144dcb82-f6ac-4f44-8e73-67b4213b42c5',  -- Cohort Fund T5
  CURRENT_DATE, 'group', CURRENT_DATE + interval '7 days', 'qa-e2e'
RETURNING
  token,
  'https://painel.igorrover.com.br/survey/grupo/' || token AS url;
```

Copy the URL.

- [ ] **Step 5: Open URL in mobile browser + submit**

On your phone (or desktop with mobile viewport in dev tools):
1. Open the URL.
2. Confirm class name + cohort name show in the subtitle.
3. Tap a NPS score (e.g. 9).
4. Fill the comment field with "E2E test".
5. Fill the name field with "QA Bot".
6. Tap "Enviar feedback".
7. Confirm "Obrigado!" screen appears.

- [ ] **Step 6: Verify response landed in DB**

```sql
SELECT nps_score, comment, name_provided, mode, submitted_at
FROM class_nps_responses
WHERE comment = 'E2E test'
ORDER BY submitted_at DESC LIMIT 1;
```

Expected: 1 row with nps_score=9, comment='E2E test', name_provided='QA Bot', mode='group'.

- [ ] **Step 7: Verify response_count incremented**

```sql
SELECT response_count FROM nps_class_links WHERE created_by = 'qa-e2e';
```

Expected: 1.

- [ ] **Step 8: Try submitting an invalid score (negative test)**

Edit `survey/app.js` temporarily in browser dev tools console:
```js
fetch('https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/submit-survey-group', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ token: '<copy_token_here>', nps_score: 11 })
}).then(r => r.status).then(console.log);
```

Expected: console logs `400`.

- [ ] **Step 9: Clean up E2E test data**

```sql
DELETE FROM nps_class_links WHERE created_by = 'qa-e2e';
-- responses cascade-delete via FK
```

- [ ] **Step 10: Mark P2 done**

Update memory with completion status:
```
- P2 (NPS anonymous form) — DEPLOYED 2026-05-16
  - Migrations: 4 applied (links, responses, RPC, increment counter)
  - Edge function: submit-survey-group live
  - Landing page: /survey/grupo/{token} + /survey/aluno/{token}
  - Nginx rewrite: applied
  - Ready for P3 dispatcher to start writing tokens
```

---

## Self-review checklist

- [x] All migrations have rollback safety (`IF NOT EXISTS`, `CREATE OR REPLACE`).
- [x] No placeholder TODO / TBD strings in implementation steps.
- [x] Every edge function step includes a curl command with expected output.
- [x] HTML/CSS/JS code is complete — no "// rest of implementation" comments.
- [x] Each task ends with a commit step.
- [x] Function names match across tasks (e.g., `submit-survey-group` used in Task 4 + Task 5 + Task 8 consistently).
- [x] All spec sections have a corresponding task:
  - Spec §3.1 (links table) → Task 1
  - Spec §3.2 (responses table) → Task 2
  - Spec §3.3 (RLS) → Tasks 1 + 2 (inline)
  - Spec §3.4 (public RPC) → Task 3
  - Spec §4 (submit edge function) → Task 4
  - Spec §5 (landing page) → Task 5
  - Spec §6 (manual token helper) → Task 7
  - Spec §7 (security) → Task 4 (rate limit + IP hash) + Task 5 (no auth path)
  - Spec §8 (testing) → Task 4 (integration) + Task 5 (visual) + Task 8 (E2E)
  - Spec §9 (migration plan) → Tasks 1–3 + Task 4 step 2
  - Spec §11 (acceptance criteria) → Task 8

## Out of scope (deferred to P3 / P1)

- Automatic token generation by cron job (P3).
- Sending the link via WhatsApp group or DM (P3).
- Pre-class intent capture (P1).
- Admin UI to view aggregated NPS reports (could be P2.1 follow-up, not blocking).
- Sentiment analysis on free-text comments (integrate with existing `analyze-response-sentiment` later).
