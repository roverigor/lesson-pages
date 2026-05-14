# Spec — Encerramento Fundamentals T4 Survey

**Data:** 2026-05-14
**Owner:** roverigor.empresas@gmail.com
**Status:** Design aprovado, implementação em andamento

---

## 1. Contexto

Turma Fundamentals T4 teve última aula em 2026-05-13. Necessário coletar
feedback de encerramento de curso: NPS, CSAT, pontos fortes/fracos,
intenção de continuar próximo nível, depoimento opcional.

Decisão estratégica: criar **template reusável** na biblioteca de surveys
(`survey_templates`) E instância específica T4 (`surveys` + `survey_questions`).
Template servirá futuras turmas (Advanced T1, próximos Fundamentals).

## 2. Decisões-Chave

| # | Decisão | Justificativa |
|---|---------|---------------|
| D1 | Reuso 100% sistema `surveys` existente | EPIC-005 já entrega builder, dispatch, results, CSV/MD export |
| D2 | Template biblioteca `survey_templates` + instância separada | Reuso futuro turmas; instância T4 customizável sem afetar template |
| D3 | Status `draft` na criação, dispatch manual via admin UI | Alinha com NON-NEGOTIABLE rule: zero envio externo automático |
| D4 | Detractor follow-up via `automation_rules` existente (Story 16.11) | Reuso rule pré-built "NPS Detractor → Pendência CS". Zero código novo. CS humano resolve melhor que automação cega |
| D5 | Template Meta WhatsApp novo `encerramento_curso_fundamentals` | Body customizado pelo user. Submissão via `create-meta-template`. Aprovação Meta 24-48h |
| D6 | Domínio link: `painel.academialendaria.ai` (novo domínio oficial) | VPS configurado 2026-05-14 (cert Let's Encrypt expandido) |

## 3. Perguntas do Formulário (9)

| # | Tipo | Label | Required | Notas |
|---|------|-------|----------|-------|
| 1 | nps | De 0 a 10, quanto você recomendaria o Fundamentals pra um colega? | true | — |
| 2 | text | O que motivou sua nota? | false | Opcional. CS contata detractors via automation_rule |
| 3 | csat | Como avalia o curso de forma geral? | true | 1-5 estrelas |
| 4 | scale | O curso atendeu suas expectativas iniciais? | true | scale_max=5 |
| 5 | text | Quais foram os pontos mais fortes do curso pra você? | true | — |
| 6 | text | O que poderíamos melhorar? | false | — |
| 7 | scale | Como avalia o ritmo das aulas? (1=muito lento, 5=muito rápido) | false | scale_max=5 |
| 8 | choice | Pretende continuar com a gente no próximo nível? | true | Opções: Sim, Talvez, Não, Já estou inscrito |
| 9 | text | Deixe um depoimento que possamos usar pra divulgar a próxima turma | false | placeholder marketing |

**Intro:** "A turma acabou ontem 🎓. Sua opinião vai ajudar a tornar o próximo Fundamentals ainda melhor. Leva uns 4 min."

**Follow-up:** "Valeu pelo feedback! Sua resposta foi registrada."

**Accent color:** `#6366f1` (indigo padrão admin)

## 4. Template Meta WhatsApp

**Nome:** `encerramento_curso_fundamentals`
**Idioma:** `pt_BR`
**Categoria:** `MARKETING`

**Body:**
```
Olá {{1}}, ontem encerramos as aulas da sua turma do Cohort Fundamentals, e queremos saber sua opinião sincera. Responda clicando no link abaixo:
```

- `{{1}}` = primeiro nome do aluno (injetado pelo dispatch-survey)

**Botão CTA:**
- Tipo: URL
- Texto: `Responder pesquisa`
- URL: `https://painel.academialendaria.ai/avaliacao/responder.html?token={{1}}`
- URL exemplo: `https://painel.academialendaria.ai/avaliacao/responder.html?token=abc123def456`

## 5. Automation Rule (Detractor Follow-up)

Ativação da rule pré-built (`automation_rules` migration `20260506120000`):

```sql
UPDATE public.automation_rules
   SET active = true, updated_at = now()
 WHERE name = 'NPS Detractor → Pendência CS';
```

**Comportamento:** worker pg_cron 5min processa `survey_responses` recentes.
Aluno responde NPS ≤6 → cria `pending_student_assignments` interna →
CS vê no admin → CS contata aluno humanamente.

**Zero envio externo automático.**

## 6. Arquivos a Criar

```
supabase/migrations/20260514000000_survey_template_encerramento_curso.sql
supabase/migrations/20260514000010_survey_fundamentals_t4_encerramento.sql
supabase/migrations/20260514000020_enable_nps_detractor_rule.sql
docs/superpowers/specs/2026-05-14-encerramento-fundamentals-t4-design.md
```

## 7. Plano de Execução

### Fase 1 — Hoje (2026-05-14)
1. Commit 3 migrations SQL + spec doc
2. `supabase db push` aplica migrations no projeto `gpufcipkajppykmnmdeh`
3. Submeter template Meta via edge function `create-meta-template`
4. Validar: survey aparece em `/admin/surveys` com status `draft`
5. Validar: template aparece em `meta_templates` com `status='pending'`

### Fase 2 — 24-48h (aguardar Meta)
- Meta revisa template
- Sync via edge function `sync-meta-templates` atualiza `status='active'`
- Confirmar via `SELECT * FROM meta_templates WHERE name = 'encerramento_curso_fundamentals'`

### Fase 3 — Após aprovação Meta (com autorização explícita do user)
1. Teste piloto: disparo único `encerramento_curso_fundamentals` pro `43999250490`
2. Validar UX responder.html + recebimento WhatsApp
3. Se OK: dispatch massa via admin `/surveys` → botão "Disparar"

## 8. Riscos & Mitigação

| Risco | Probabilidade | Mitigação |
|-------|--------------|-----------|
| Meta rejeita template | Baixa | Body limpo, MARKETING category, sem CTA suspeito |
| Aluno T4 sem phone válido | Média | dispatch-survey já marca `send_status='skipped'` se phone vazio |
| Baixa taxa resposta | Média | Survey curto (~4min), 9 perguntas, accent color custom |
| Survey detractor inflada | Baixa | Automation rule cria pendência interna, não polui DB |

## 9. Constitutional Compliance

- **Article III (Story-Driven):** spec doc precede implementação ✅
- **Article IV (No Invention):** todas perguntas trazem semântica clara, sem features inventadas além de schema existente ✅
- **Article V (Quality First):** reuso sistema validado (EPIC-005/016/017), zero código novo ✅
- **NON-NEGOTIABLE (Comunicação externa):** dispatch só após autorização humana explícita momento da execução ✅

## 10. Aprovação

Design aprovado pelo user em conversa de 2026-05-14:
- ✅ Escopo: template + instância T4
- ✅ Foco: avaliação completa curso
- ✅ Canal: criar agora, dispatch manual depois
- ✅ Condicional P2: usar caminho C (detractor follow-up via automation_rules)
- ✅ P2 label sem parêntese
- ✅ Body Meta template definido
- ✅ Domínio novo: `painel.academialendaria.ai`
- ✅ Teste piloto: `43999250490` antes massa
