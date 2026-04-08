# EPIC-010 — Student Life: Turma como Hub e Perfil 360 do Aluno

## Metadata

```yaml
epic_id: EPIC-010
title: Student Life — Turma como hub central e Perfil 360 do Aluno com NPS tokenizado
status: Ready
created_by: "@pm (Morgan)"
created_at: 2026-04-07
priority: P1
estimated_complexity: XL (21+ pontos)
dependency: EPIC-006 (Done), EPIC-007 (Done)
```

---

## Decisões de Produto (registradas em sessão com Igor)

| Decisão | Escolha |
|---------|---------|
| NPS anônimo ou identificado? | Identificado via token — sem aviso ao aluno (anonimato nunca foi prometido) |
| Quem vê NPS individual? | Coordenador + Mentores da turma. Aluno NÃO acessa próprio perfil |
| Escopo do perfil 360? | Apenas dados do ecossistema atual (sem Cal.com, sem notas manuais por ora) |
| Tela de turma | Página separada (`/turma/[slug]`) — não dentro do admin existente |
| Prioridade | Ambos (perfil + NPS tokenizado) são P1 simultâneos |

---

## Visão Estratégica

As turmas são o centro operacional da Academia Lendária, mas hoje não existe uma interface que as coloque como hub. Coordenadores navegam entre `/presenca`, `/calendario` e `/equipe` para montar manualmente a visão de um aluno.

Este épico cria dois produtos novos:
1. **Página de Turma** — hub central com alunos matriculados, presença agregada e navegação para perfis individuais
2. **Perfil 360 do Aluno** — visão completa da vida do aluno: aulas, presença, avaliações NPS dadas
3. **NPS Tokenizado** — link único por aluno/ciclo enviado via WhatsApp, resposta atribuída automaticamente sem login

---

## Problema que Resolve

| Situação Atual | Situação Alvo |
|----------------|--------------|
| Coordenador monta visão do aluno manualmente em 3 painéis | 1 clique no nome do aluno → tudo visível |
| NPS anônimo — não há como saber quem avaliou o quê | Token único no link → resposta atribuída ao aluno automaticamente |
| Turma é só uma entrada no banco, não um hub navegável | `/turma/[slug]` mostra alunos, presença e atalhos de ação |
| Taxa de resposta de NPS incerta — aluno precisa informar dados | Um clique do WhatsApp → form pronto → submit → atribuído |

---

## Escopo do Épico

### IN — O que este épico entrega

- Página `/turma/[slug]` com lista de alunos, presença e acesso ao perfil individual
- Página de Perfil 360 do Aluno (acessível apenas por coordenador/mentor)
- Geração de token único por aluno + ciclo/turma para NPS
- Form de NPS com token na URL (one-time use, expira em 7 dias)
- Atribuição automática de resposta ao aluno no perfil 360

### OUT — O que este épico NÃO entrega

- Acesso do aluno ao próprio perfil
- Integração com Cal.com ou notas manuais de mentores
- Export PDF de perfil individual
- Sistema de alertas automáticos baseados em NPS baixo (future)

---

## Stories

| Story | Título | Prioridade | Complexidade | Dependência |
|-------|--------|-----------|-------------|------------|
| 10.1 | Página de Turma — hub com alunos e presença agregada | P1 | M (5pts) | — |
| 10.2 | Perfil 360 do Aluno — presença, histórico e avaliações | P1 | M (5pts) | 10.1 |
| 10.3 | NPS tokenizado — geração de link único por aluno/ciclo | P1 | M (5pts) | 10.2 |
| 10.4 | Form de NPS com token (one-time use, expira 7 dias) | P1 | S (3pts) | 10.3 |
| 10.5 | Atribuição de resposta NPS ao perfil 360 do aluno | P1 | S (3pts) | 10.4 |

**Total estimado:** 21 pontos

---

## Arquitetura de Dados

```
classes
  └── cohort_students (alunos matriculados)
       └── student_attendance (presença por sessão)

nps_tokens (nova tabela)
  ├── id (uuid PK)
  ├── student_id → students
  ├── class_id → classes
  ├── cohort_id → cohorts
  ├── token (text UNIQUE — slug curto ex: "x7k2p9")
  ├── used (boolean default false)
  ├── used_at (timestamptz)
  ├── expires_at (timestamptz — sent_at + 7 dias)
  └── sent_at (timestamptz)

survey_responses (já existe — verificar schema)
  └── nps_token_id → nps_tokens (FK nova)
       → permite JOIN para identificar respondente
```

---

## Fluxo NPS Tokenizado

```
1. Coordenador dispara NPS para turma no admin
2. Sistema gera 1 token por aluno matriculado (nps_tokens)
3. WhatsApp enviado: "Avalie → https://calendario.igorrover.com.br/avaliacao?t=x7k2p9"
4. Aluno clica → form carrega sem login
5. Aluno submete → sistema valida token (não expirado, não usado)
6. Resposta salva em survey_responses com nps_token_id
7. Token marcado como used=true
8. Perfil 360 do aluno exibe a resposta atribuída
```

---

## Métricas de Sucesso

- **Tempo para coordenador ver situação completa de 1 aluno:** hoje ~5min → alvo <30s
- **Taxa de resposta NPS atribuída:** hoje 0% (anônimas) → alvo >60% dos alunos com token
- **Turma navegável em 1 clique:** hoje ❌ → alvo ✅

---

## Riscos

| Risco | Probabilidade | Mitigação |
|-------|-------------|-----------|
| Aluno compartilha token com outro | Baixo | One-time use — segundo submit recebe "avaliação já registrada" |
| Token expirado quando aluno clica | Médio | Mensagem clara "prazo encerrado" + coordenador pode regenerar |
| Alunos não vinculados no Zoom não têm telefone confiável | Médio | NPS só enviado para alunos com phone validado; os demais ficam sem token |
| Survey_responses já tem schema incompatível | Baixo | Ler schema antes de Story 10.3; adaptar ou criar nova tabela se necessário |
