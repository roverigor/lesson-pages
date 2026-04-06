# Lesson Pages

Páginas de análise de aulas geradas automaticamente.

## Estrutura

- `/aluno/{aula}/` - Páginas públicas para alunos
- `/interno/{aula}/` - Páginas internas para professores

## Deploy

Automático via GitHub Actions em cada push para `main`:
1. Job `test` roda lint + smoke tests (blocante)
2. Job `deploy` só executa se os testes passarem

## Testes

### Pré-requisitos

```bash
node -v   # >= 18.0.0
npm ci    # instala devDependencies (eslint)
```

### Rodar localmente

```bash
# Todos os smoke tests (12 testes, ~10s)
npm test

# Smoke tests contra um ambiente diferente
APP_URL=https://staging.exemplo.com npm test

# Linting (js/*.js)
npm run lint
```

### O que os testes cobrem

| Suite | Testes | O que verifica |
|-------|--------|----------------|
| Calendário Público | 3 | HTTP 200, HTML válido, Supabase config presente |
| Supabase DB Anon | 3 | Tabela `classes` acessível, turmas ativas, `mentors` |
| Edge Function send-whatsapp | 2 | Reachable, JSON válido, não retorna 500 |
| Edge Function zoom-attendance | 1 | Reachable, não retorna 500 |
| Admin Panel | 3 | HTTP 200, HTML válido, Auth endpoint responde |

Os testes de Edge Function não enviam mensagens reais — usam IDs inválidos que resultam em `ok: false` sem disparar ações externas.

