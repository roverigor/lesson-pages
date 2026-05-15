# P2 — Anonymous Group NPS Form (Foundation)

**Status:** Draft
**Date:** 2026-05-15
**Author:** Orion (aiox-master)
**Parent epic:** Post-Class NPS Dispatcher (decomposed into P1/P2/P3 — see brainstorming session 2026-05-15)
**Depends on:** none (foundational)
**Blocks:** P3 (dispatcher), P1 (pre-class intent)

---

## 1. Motivation

After each class, we want to collect NPS feedback from students. Two channels are in scope:

1. **Group WhatsApp message via Evolution API** — anonymous, 1 link per (class, cohort) shared by all attendees.
2. **Individual DM via Meta Cloud API** — 1 link per student, attributable.

This sub-project (P2) is the **landing page + storage layer** that both channels feed. P3 (dispatcher) and P1 (pre-class intent) build on top.

**Why split:** zero external sends in P2 means it can be merged, tested, and exposed publicly without the CLAUDE.md "external comms approval" gate. P3 (which sends messages) gets its own spec and approval workflow.

---

## 2. Goals & Non-Goals

### Goals

- Public landing page at `/survey/grupo/{token}` and `/survey/aluno/{token}` (no auth required).
- Storage of anonymous and attributable NPS responses in `class_nps_responses`.
- Token table (`nps_class_links`) with expiry, scoped to (class, cohort, date, mode).
- Public RPC to fetch token metadata (no direct table access from anon).
- Submit endpoint (`submit-survey-group` edge function) with rate-limit + validation.
- Test seed mechanism (admin can manually generate tokens for QA before P3 exists).

### Non-Goals (deferred)

- Dispatching messages (P3).
- Token generation by cron/dispatcher (P3).
- Pre-class opt-in flow (P1).
- Sentiment analysis on free-text comments (already exists via `analyze-response-sentiment` — integration deferred).
- Auto-flag for detractors (already exists via `survey_low_response_alert` migration — integration deferred).

---

## 3. Database Schema

### 3.1 `nps_class_links` (new table)

Holds tokens that authorize form access. One row per (class, cohort, date, mode[, student]).

```sql
CREATE TABLE public.nps_class_links (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  token         text UNIQUE NOT NULL,         -- url-safe random (24 chars, base62)
  class_id      uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  cohort_id     uuid NOT NULL REFERENCES public.cohorts(id) ON DELETE CASCADE,
  trigger_date  date NOT NULL,                -- date of the class
  mode          text NOT NULL CHECK (mode IN ('group','dm')),
  student_id    uuid REFERENCES public.students(id) ON DELETE CASCADE,
  -- student_id NOT NULL when mode='dm', NULL when mode='group'
  expires_at    timestamptz NOT NULL,         -- default trigger_date + 14 days
  response_count integer NOT NULL DEFAULT 0,
  created_by    text NOT NULL DEFAULT 'system',
  created_at    timestamptz NOT NULL DEFAULT now(),

  CONSTRAINT nps_class_links_mode_student_consistency
    CHECK ((mode = 'dm' AND student_id IS NOT NULL) OR
           (mode = 'group' AND student_id IS NULL))
);

CREATE UNIQUE INDEX idx_nps_class_links_group_unique
  ON public.nps_class_links (class_id, cohort_id, trigger_date)
  WHERE mode = 'group';

CREATE UNIQUE INDEX idx_nps_class_links_dm_unique
  ON public.nps_class_links (class_id, cohort_id, trigger_date, student_id)
  WHERE mode = 'dm';

CREATE INDEX idx_nps_class_links_token ON public.nps_class_links (token);
CREATE INDEX idx_nps_class_links_expires ON public.nps_class_links (expires_at)
  WHERE expires_at > now();
```

### 3.2 `class_nps_responses` (new table)

```sql
CREATE TABLE public.class_nps_responses (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  link_id       uuid NOT NULL REFERENCES public.nps_class_links(id) ON DELETE CASCADE,
  class_id      uuid NOT NULL REFERENCES public.classes(id) ON DELETE CASCADE,
  cohort_id     uuid NOT NULL REFERENCES public.cohorts(id) ON DELETE CASCADE,
  mode          text NOT NULL CHECK (mode IN ('group','dm')),
  student_id    uuid REFERENCES public.students(id) ON DELETE SET NULL,
  -- student_id required for mode='dm', optional for mode='group'

  nps_score     smallint NOT NULL CHECK (nps_score BETWEEN 0 AND 10),
  comment       text,
  name_provided text,                          -- only used in group mode (optional)

  ip_hash       text,                          -- sha256(ip + daily_salt) for spam control
  user_agent    text,
  submitted_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_class_nps_responses_class
  ON public.class_nps_responses (class_id, cohort_id, submitted_at DESC);
CREATE INDEX idx_class_nps_responses_link
  ON public.class_nps_responses (link_id);
CREATE INDEX idx_class_nps_responses_student
  ON public.class_nps_responses (student_id) WHERE student_id IS NOT NULL;
```

### 3.3 RLS

```sql
ALTER TABLE public.nps_class_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.class_nps_responses ENABLE ROW LEVEL SECURITY;

-- Links: authenticated admin can read, service_role full
CREATE POLICY "links: read for auth"
  ON public.nps_class_links FOR SELECT
  TO authenticated USING (true);
CREATE POLICY "links: full for service"
  ON public.nps_class_links FOR ALL
  TO service_role USING (true) WITH CHECK (true);

-- Responses: same pattern (no anon access — only via submit endpoint)
CREATE POLICY "responses: read for auth"
  ON public.class_nps_responses FOR SELECT
  TO authenticated USING (true);
CREATE POLICY "responses: full for service"
  ON public.class_nps_responses FOR ALL
  TO service_role USING (true) WITH CHECK (true);
```

### 3.4 Public RPC (security boundary)

Allows the landing page to fetch link metadata (class name, cohort name, mode, validity) without exposing the raw table to anon clients.

```sql
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
```

---

## 4. Edge Function: `submit-survey-group`

New edge function at `supabase/functions/submit-survey-group/index.ts`.

### Request

```http
POST /functions/v1/submit-survey-group
Content-Type: application/json

{
  "token": "abc123def456",
  "nps_score": 8,
  "comment": "Aula ótima, professor muito didático",
  "name_provided": "Maria (opcional)"  // only for mode='group'
}
```

### Logic

1. **Validate input:** token present, `nps_score` integer 0-10.
2. **Lookup link:** `SELECT id, class_id, cohort_id, mode, student_id, expires_at FROM nps_class_links WHERE token = $1`.
3. **Reject if not found / expired.** Return 404 / 410.
4. **Rate-limit:** count responses from `ip_hash` in last 24h. If >= 5, return 429.
5. **Compute `ip_hash`:** `sha256(client_ip + daily_salt_from_env)` (daily salt rotates so hashes can't be backtracked but are stable within a day).
6. **Insert response:**
   ```sql
   INSERT INTO class_nps_responses (link_id, class_id, cohort_id, mode, student_id,
     nps_score, comment, name_provided, ip_hash, user_agent)
   VALUES (...);
   ```
7. **Increment counter:** `UPDATE nps_class_links SET response_count = response_count + 1 WHERE id = $link_id;`.
8. **Return:** `{ "success": true, "thank_you": "Obrigado pelo feedback!" }`.

### Error responses

| Code | Reason |
|------|--------|
| 400  | Missing token / invalid `nps_score` |
| 404  | Token not found |
| 410  | Token expired |
| 429  | Rate limit exceeded |
| 500  | Internal error |

### CORS

Allow `Access-Control-Allow-Origin: *` (public form). Method whitelist: `POST, OPTIONS`.

---

## 5. Landing Page

Static HTML + vanilla JS, hosted under `/admin/nps-publico/` (or top-level `/survey/`).

### Routes (handled by deployment / nginx)

- `/survey/grupo/{token}` → `nps-publico/index.html?mode=group&token={token}` (or path-extracted by JS)
- `/survey/aluno/{token}` → `nps-publico/index.html?mode=dm&token={token}`

For the VPS (Contabo) setup, simplest is one HTML file at `/admin/nps-publico/index.html` that reads the token from path or query. Nginx rewrites `/survey/grupo/*` to that file.

### Page structure

```
┌──────────────────────────────────────────────────┐
│  [logo]                                          │
│                                                  │
│  Avalie sua aula                                 │
│  {{class_name}} — {{cohort_name}}                │
│  (modo DM: "Olá, {{student_name}}")             │
│                                                  │
│  De 0 a 10, o quanto recomendaria esta aula?    │
│  [ 0 ][ 1 ][ 2 ][ 3 ][ 4 ][ 5 ]                 │
│  [ 6 ][ 7 ][ 8 ][ 9 ][ 10 ]                     │
│                                                  │
│  O que motivou sua nota? (opcional)             │
│  ┌──────────────────────────────────────────┐   │
│  │ [textarea]                               │   │
│  └──────────────────────────────────────────┘   │
│                                                  │
│  ── modo group only ──                          │
│  Nome (opcional, se quiser identificação):      │
│  [_________________________]                    │
│                                                  │
│  [ Enviar feedback ]                            │
└──────────────────────────────────────────────────┘
```

### JS flow

1. On load, extract `token` from URL.
2. Call `rpc('get_nps_link_metadata', { p_token: token })` via anon supabase client.
3. If `!valid`:
   - If `expired`: show "Este link expirou. Obrigado pelo interesse!"
   - Else: show "Link inválido."
4. Render form with `class_name`/`cohort_name`. Hide name field if `mode='dm'`.
5. On submit:
   - Validate score selected.
   - POST to `submit-survey-group`.
   - Show confirmation screen with `thank_you` message.
   - If 429: "Você já respondeu hoje. Obrigado!"

### Styling

Match existing painel (Tailwind / current admin pages). Mobile-first since most responses come from phone.

---

## 6. Admin helper: manual token generation (for QA)

Until P3 dispatcher exists, admin needs a way to generate test tokens. Add to existing `/admin` a small page or SQL helper:

```sql
-- Generate group token for testing
INSERT INTO nps_class_links (token, class_id, cohort_id, trigger_date, mode, expires_at, created_by)
VALUES (
  encode(gen_random_bytes(18), 'base64'),  -- 24 chars roughly
  'CLASS_UUID', 'COHORT_UUID', CURRENT_DATE, 'group',
  CURRENT_DATE + interval '14 days', 'admin-manual'
)
RETURNING token, 'https://painel.igorrover.com.br/survey/grupo/' || token AS url;
```

No UI page required for P2 — SQL snippet in `docs/runbooks/nps-test-tokens.md` is enough.

---

## 7. Security considerations

- **No auth on form** — by design. Token is the auth.
- **Token entropy:** 18 bytes (144 bits) base64 → ~24 chars. Brute force impractical.
- **Token reuse for group mode:** intentional. Anyone with link can submit. Counter-spam via IP rate limit (5/24h).
- **PII in `name_provided`:** stored as plain text. User opt-in. Document in privacy notice.
- **`ip_hash` salt:** rotated daily so hashes can't track across days but are stable within a day.
- **No CSRF token:** stateless endpoint. Token in URL is the only credential.
- **SQL injection:** all queries parameterized via Supabase JS client.

---

## 8. Testing strategy

### Unit / contract tests
- `submit-survey-group` happy path (valid token, score 8, no comment) → 200.
- Invalid score (-1, 11, 'abc') → 400.
- Missing token → 400.
- Non-existent token → 404.
- Expired token → 410.
- 6th submit from same IP in 24h → 429.

### Integration / E2E (manual or Playwright)
- Generate test token via SQL helper.
- Open `https://painel.igorrover.com.br/survey/grupo/{token}` in browser.
- Verify class_name + cohort_name render correctly.
- Submit score=9 + comment.
- Confirm row in `class_nps_responses`.
- Confirm `response_count` incremented on `nps_class_links`.
- Test mobile viewport.

### Data validation queries
```sql
-- Check responses come in
SELECT class_id, cohort_id, mode, COUNT(*), AVG(nps_score)
FROM class_nps_responses
WHERE submitted_at > now() - interval '24h'
GROUP BY 1, 2, 3;
```

---

## 9. Migration plan

3 migrations (one per concern):

1. `20260516010000_nps_class_links.sql` — table + RLS
2. `20260516010100_class_nps_responses.sql` — table + RLS + indexes
3. `20260516010200_get_nps_link_metadata_rpc.sql` — SECURITY DEFINER function + grants

Edge function: `supabase/functions/submit-survey-group/index.ts`

Landing page: `admin/nps-publico/index.html` (+ Nginx rewrite for `/survey/grupo/*` and `/survey/aluno/*`).

---

## 10. Open questions (resolve before plan)

None blocking. Following are deferred to P3/P1 specs:

- How tokens are auto-generated (P3 dispatcher writes to `nps_class_links`).
- Whether DM token expiry should match group token expiry (current: both 14 days).
- Integration with existing `analyze-response-sentiment` to score comments (future enhancement).

---

## 11. Acceptance criteria

1. Migrations apply cleanly via `supabase db push`.
2. Anonymous user can open `/survey/grupo/{token}` and submit a NPS response without authentication.
3. Anonymous user opens an **expired** token → sees friendly "expired" message, no submit possible.
4. Same IP can submit max 5 times per 24h (6th gets 429).
5. Response is queryable via `SELECT * FROM class_nps_responses WHERE link_id = ...` with `class_id`, `cohort_id`, `nps_score`, `submitted_at` populated.
6. `nps_class_links.response_count` increments on each accepted submit.
7. Name field is optional in group mode, hidden in DM mode (which uses pre-attributed `student_id`).
8. Form renders correctly on mobile (≤ 375px viewport).
