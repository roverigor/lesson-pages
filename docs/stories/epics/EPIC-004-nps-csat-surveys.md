# EPIC-004 — Sistema NPS/CSAT Próprio

**Status:** Ready  
**Prioridade:** High  
**Arquiteto:** Aria (@architect)

---

## Objetivo

Substituir o Tally por um sistema de pesquisa NPS/CSAT próprio, integrado ao painel admin, com:
- Disparo de links personalizados via WhatsApp (Evolution API)
- Resposta em página pública conversacional (dark premium)
- Dashboard de resultados em tempo real no admin e em `/avaliacao`

---

## Contexto Técnico

### O que já existe
| Recurso | Status |
|---------|--------|
| `student_nps` table | Existe, tem `tally_response_id` (legado) |
| Edge Function `send-whatsapp` | Funcional, usado para notificações |
| `/avaliacao/index.html` | Existe, dados hardcoded (será migrado para DB) |
| Design system dark premium | `design-tokens-dark-premium.css` + `admin-shared.css` |
| Admin panel com 14 módulos JS | Padrão: tab + módulo JS separado |
| RLS admin-only pattern | `auth.jwt() -> 'user_metadata' ->> 'role' = 'admin'` |

### O que precisa ser criado
1. Tabelas `surveys` e `survey_links`
2. Edge Function `submit-survey` (pública, token-based)
3. Edge Function `dispatch-survey` (admin, gera tokens + envia WhatsApp)
4. Módulo admin `js/admin/surveys.js` + tab no `admin.html`
5. Página pública `/avaliacao/responder.html` (conversacional, Tally-like)
6. Migrar `/avaliacao/index.html` para ler do banco

---

## Arquitetura

### Fluxo completo

```
Admin cria survey → seleciona turma/cohort → clica "Disparar"
    ↓
dispatch-survey (Edge Function)
    ↓ gera UUID token por aluno → insere em survey_links
    ↓ envia WhatsApp para cada aluno com link personalizado
    
Aluno recebe: "Responda a pesquisa: https://calendario.igorrover.com.br/avaliacao/responder?token=xxx"
    ↓
/avaliacao/responder.html valida token → exibe survey conversacional
    ↓ aluno responde → POST para submit-survey (Edge Function)
    ↓ salva em student_nps + marca survey_links.used_at
    
Admin vê resultados no painel → tab Avaliações → NPS score, distribuição, comentários
```

### Schema

```sql
-- surveys: campanhas de pesquisa
CREATE TABLE surveys (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  name        TEXT NOT NULL,
  type        TEXT NOT NULL CHECK (type IN ('nps', 'csat')),
  cohort_id   UUID REFERENCES cohorts(id),
  class_id    UUID REFERENCES classes(id),
  question    TEXT NOT NULL,  -- pergunta principal
  follow_up   TEXT,           -- pergunta aberta opcional ("O que motivou sua nota?")
  status      TEXT DEFAULT 'draft' CHECK (status IN ('draft','active','closed')),
  dispatched_at TIMESTAMPTZ,
  created_by  TEXT,           -- email do admin
  created_at  TIMESTAMPTZ DEFAULT now()
);

-- survey_links: tokens únicos por aluno
CREATE TABLE survey_links (
  id          UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  survey_id   UUID REFERENCES surveys(id) ON DELETE CASCADE,
  student_id  UUID REFERENCES students(id) ON DELETE CASCADE,
  token       UUID DEFAULT gen_random_uuid() UNIQUE NOT NULL,
  used_at     TIMESTAMPTZ,
  created_at  TIMESTAMPTZ DEFAULT now(),
  UNIQUE(survey_id, student_id)
);

-- student_nps: adicionar survey_id (mantém retrocompat)
ALTER TABLE student_nps ADD COLUMN survey_id UUID REFERENCES surveys(id);
ALTER TABLE student_nps ADD COLUMN survey_type TEXT DEFAULT 'nps'; -- 'nps' | 'csat'
```

### RLS
- `surveys`: admin lê/escreve; anônimo sem acesso
- `survey_links`: admin lê/escreve; anônimo valida por token (SELECT WHERE token = $1 AND used_at IS NULL)
- `student_nps`: admin lê; anônimo insere (sem auth, via service role no Edge Function)

### Edge Functions

**`submit-survey`** (pública, sem auth):
- Input: `{ token, score, feedback? }`
- Valida token em `survey_links` (existe + não usado)
- Insere em `student_nps` com `survey_id`, `student_id`, `score`, `feedback`
- Atualiza `survey_links.used_at = now()`
- Usa SERVICE_ROLE_KEY (bypass RLS)

**`dispatch-survey`** (admin JWT obrigatório):
- Input: `{ survey_id }`
- Busca todos os alunos do cohort/turma da survey
- Para cada aluno: cria registro em `survey_links` (se não existe)
- Envia WhatsApp via Evolution API com link personalizado
- Atualiza `surveys.dispatched_at`

### Admin Module `surveys.js`
- Tab "Avaliações" no admin.html
- Seção "Criar Survey": nome, tipo (NPS/CSAT), turma, pergunta principal, follow-up
- Lista de surveys com status (draft/active/closed) e badges de resposta (X/Y responderam)
- Botão "Disparar" → chama dispatch-survey
- Botão "Ver Resultados" → abre drawer com NPS score, distribuição, comentários
- Botão "Encerrar" → muda status para 'closed'

### Página Pública `/avaliacao/responder.html`
- URL: `/avaliacao/responder?token=uuid`
- Conversacional (uma tela por vez)
- Tela 1: saudação + pergunta principal (NPS: 0-10 botões | CSAT: 1-5 estrelas)
- Tela 2: follow-up aberto (opcional, se configurado)
- Tela 3: obrigado (com animação de confetti ou check mark)
- Token inválido ou já usado → tela de "pesquisa encerrada"
- Dark premium, sem auth, responsivo

### Dashboard `/avaliacao/index.html`
- Migrar de dados hardcoded para leitura do banco
- Carrega via admin Supabase client (admin-only)
- Mantém layout e UX atual, só conecta ao banco

---

## Stories

| Story | Título | Estimativa |
|-------|--------|-----------|
| 4.1 | DB Schema — surveys + survey_links + RLS | Small |
| 4.2 | Edge Functions — submit-survey + dispatch-survey | Medium |
| 4.3 | Admin UI — tab Avaliações + surveys.js | Medium |
| 4.4 | Página pública — /avaliacao/responder.html | Medium |
| 4.5 | Dashboard — /avaliacao/index.html conectado ao DB | Small |

---

## Decisões Arquiteturais

| Decisão | Escolha | Motivo |
|---------|---------|--------|
| Auth na resposta | Token UUID, sem login | Alunos não têm conta. Link WhatsApp é suficiente |
| Um token por aluno por survey | Sim (`UNIQUE(survey_id, student_id)`) | Impede resposta dupla |
| Submissão via Edge Function | Service Role | Bypass RLS para INSERT público sem expor key no browser |
| Reusar `student_nps` | Sim + nova coluna `survey_id` | Evita quebrar o dashboard existente e histórico do Tally |
| Disparo separado do WhatsApp | Nova Edge Function `dispatch-survey` | `send-whatsapp` usa DB webhook trigger, não é adequado para bulk dispatch |
| Questão única por survey | Por ora sim | Suficiente para NPS/CSAT. Multi-pergunta pode ser adicionado depois |

---

## Dependências

- `students` table com campo `phone` (verificar se existe)
- Evolution API já configurada (env vars no Supabase)
- Admin JWT auth já funcionando
