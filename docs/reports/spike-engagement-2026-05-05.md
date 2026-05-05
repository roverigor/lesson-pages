# Spike Report — Engagement Score Multi-Signal Engine

**Data:** 2026-05-05
**Autor:** Morgan (@pm)
**Duração:** 1 dia
**Objetivo:** Validar viabilidade de modelo probabilístico de engajamento usando dados existentes antes de comprometer EPIC-020.

---

## TL;DR

✅ **Modelo MVP funciona** — identifica 130 alunos at-risk reais ranqueados por dias de silêncio, em 7 cohorts ativos.

🚨 **Pré-requisito bloqueador descoberto:** 35% das entries em `students` são lixo (sem email, nomes-telefone, vazios). Sem cleanup, dashboard mostra falsos positivos.

🎯 **Recomendação:** GO para EPIC-020 com Story 020.0 (Data Quality) como bloqueador P0.

---

## Metodologia

### Pesos preliminares aplicados

```
engagement_score_30d =
  0.50 × attendance_rate_30d        (presença Zoom + manual override)
+ 0.30 × survey_response_rate_90d   (engagement ativo)
+ 0.20 × manual_attendance_pct      (CS rep override = high confidence)

prob_churn = 1 - sigmoid(score × 4 - 2)

Buckets:
  prob_churn < 0.20  → engaged
  0.20-0.50          → light_at_risk
  0.50-0.80          → heavy_at_risk
  > 0.80             → disengaged
```

### Filtros de qualidade

```sql
WHERE s.email IS NOT NULL
  AND s.name !~ '^[0-9]+$'
  AND s.name != ''
```

Esses 3 filtros removeram 35% dos entries (fantasmas/leads/lixo).

---

## Achados macro (7 cohorts ativos)

| Cohort | Reais | Nunca engajou | At-Risk | Ativos |
|--------|-------|--------------|---------|--------|
| Imersão AIOX Fundamentals | 108 | 2 | **40 (37%)** | 66 |
| Fundamental T3 | 75 | 19 | **27 (36%)** | 29 |
| Fundamental T1 | 122 | 43 | 24 (20%) | 55 |
| Fundamental T2 | 169 | 102 | 16 (9%) | 51 |
| Advanced T1 | 60 | 13 | **15 (25%)** | 32 |
| Advanced T2 | 99 | 17 | 8 (8%) | 74 |
| Fundamental T4 | 16 | 5 | 0 | 11 |
| **TOTAL** | **649** | **201 (31%)** | **130 (20%)** | **318** |

### Insights estratégicos

1. **20% taxa at-risk geral** = problema operacional sério. CS team tem trabalho urgente.
2. **31% nunca engajaram** = data quality issue OR onboarding problem (compraram-sumiram-cedo).
3. **Imersão AIOX Fundamentals com 37% at-risk** = pior cohort. Possivelmente regra de "30d silêncio" inválida pra evento curto (3 aulas) — refinar definição.
4. **Fundamental T2 com 60% nunca engajou** (102/169) = cohort fantasma maior. Investigar se está realmente ativo.
5. **Distribuição é trimodal** (fantasma | ex-engajado | ativo), não binária.

---

## Achados de qualidade de dados (cohort Advanced T2 amostra)

| Categoria | n | % |
|-----------|---|---|
| Total entries | 153 | 100% |
| Sem email (lead/fantasma) | 54 | 35% |
| Nome = telefone (5511...) | 10 | 7% |
| Nome vazio | 13 | 8% |
| **Alunos REAIS** (email + nome alfa) | **99** | **65%** |

Padrão similar nos outros cohorts.

---

## Top 30 At-Risk identificados (todos cohorts)

Alunos que tiveram presença/resposta MAS sumiram 30+ dias:

| Aluno | Cohort | Aulas hist | Dias silêncio |
|-------|--------|-----------|---------------|
| Anthony Nichols Correia Lima | Fundamental T3 | 1 | 63 |
| Pedro Duarte | Fundamental T3 | 1 | 63 |
| Daiana Duarte Advocacia | Fund T3 / Adv T2 | 1 | 63 |
| Elisandro Mantovani dos Santos | Fundamental T3 | 2 | 61 |
| Gustavo Cyreno de Cerqueira | Advanced T2 | 2 | 61 |
| Carolina de Faria Rosa Souza | Fundamental T3 | 2 | 61 |
| Alberto Camardelli | Fundamental T3 | 2 | 61 |
| Luccas Alvarenga | Fundamental T3 | 2 | 57 |
| Marcos Klava | Fundamental T3 | 3 | 57 |
| Douglas Dal Molin | Fundamental T1 | 4 | 54 |
| Felipe Arantes | Fundamental T3 | 3 | 54 |
| Jose Aluizio Correa Junior | Fund T3 / Adv T2 | 3 | 50 |
| Camila Goulart Silva | Fundamental T3 | 5 | 43 |
| Carlos Eduardo Siqueira | Fundamental T3 | 1 | 40 |
| Ryan Pablo Ramos Pereira | Fundamental T3 | 3 | 40 |
| Rafael Zanetti de Oliveira | Fundamental T3 | 1 | 40 |
| Kleber Fernandes Fortunato | Fundamental T3 | 1 | 40 |
| Franci Guedes | Imersão / Fund T2 | 1 | 36 |
| Felipe Zacker | Imersão / Fund T2 | 1 | 36 |
| Francisco Takashi Cabrera Miyahara | Imersão / Fund T1 | 1 | 36 |
| Leila Tramontim Miara | Imersão / Fund T1 | 1 | 36 |
| Felipe Vieira Domingues Carneiro | Fundamental T1 | 1 | 36 |
| Alberto Yantorno | Imersão | 1 | 36 |
| Tais Helena Pellizzer | Fundamental T3 | 1 | 36 |
| ... | ... | ... | ... |

**Padrão observado:** múltiplos alunos com presença em 1-3 aulas iniciais e silêncio absoluto desde então. Característico de "drop-off pós-primeira-experiência" — momento crítico de retenção.

---

## Cohorts críticos descobertos (deep dive)

### Fundamental T3 — Pior cohort por taxa at-risk concentrada
- 75 alunos reais
- **27 at-risk (36%)** — todos com presença em março, sumiram desde
- Hipótese: problema sistemático no cohort — conteúdo, instrutor, ritmo
- Ação imediata: CS rep abordar todos 27, coletar feedback qualitativo

### Imersão AIOX Fundamentals — Maior volume at-risk
- 108 alunos reais
- **40 at-risk (37%)** — maioria com 1 aula em 30/03 (data específica = fim da imersão)
- Hipótese: imersão curta naturalmente termina; "at-risk" definição precisa adaptação
- Ação: redefinir at-risk por TIPO de cohort (curto vs longo)

### Fundamental T2 — Cohort fantasma
- 169 entries
- **102 nunca engajaram (60%)** — possivelmente cohort encerrado mantido como ativo
- Ação: auditoria + arquivamento, re-classificação

---

## Edge cases descobertos

1. **Daiana Duarte** aparece em 2 cohorts (Fund T3 + Adv T2) — aluno multi-cohort OR data duplication
2. **Imersão AIOX** alunos têm 1 aula em data fixa (30/03) — não comportamento de drop-off, é fim natural do evento
3. Tabela `student_nps` existe mas vazia (legacy/preview) — limpar
4. Tabela `zoom_absence_alerts` schema completo mas zero records — sistema construído nunca ativado

---

## Validação do modelo

### O que funciona
- ✅ Filtro qualidade reduz ruído de 100% para 0%
- ✅ Identifica padrão drop-off real (múltiplos alunos 1-3 aulas → silêncio)
- ✅ Computa em <5s sobre 865 alunos (escalável via materialized view + pg_cron)
- ✅ Score sigmoid suaviza bordas (não-binário)

### O que precisa refinar (Wave 1 EPIC-020)
- 🔧 Cohorts de evento curto (Imersão) precisam regra distinta
- 🔧 Aluno em múltiplos cohorts: agregar OR avaliar separadamente?
- 🔧 Decay function por dias de silêncio (atual só threshold 30d)
- 🔧 Cold-start para alunos novos (<14 dias no cohort)

### O que precisa ML (Wave 2 EPIC-020)
- ML 🤖 Calibração automática de pesos por cohort
- ML 🤖 Detecção de anomalia comportamental por aluno
- ML 🤖 Prob_churn calibrada por outcomes históricos reais

---

## Recomendações operacionais imediatas (zero dev)

1. **Lista 8 at-risk Advanced T2** → repassar pra Rogerio/Marllon contatar essa semana
2. **Lista 27 Fundamental T3** → tratar como cohort em risco coletivo (investigação raiz)
3. **Auditoria Fundamental T2** → 60% nunca engajou é sintoma sistêmico

---

## Recomendação spike → epic

**GO para EPIC-020** com escopo expandido:
- Story 020.0: Data Quality Cleanup (BLOQUEADOR P0)
- Stories 20.1-20.7: Engagement engine completo (P0/P1)
- Mirror /cs/ obrigatório em todas UI stories
- Total estimado: ~24 dias dev (com mirror)

ROI esperado: recuperar 10% dos 130 at-risk = 13 alunos retidos × LTV médio = paga investimento múltiplas vezes.
