# Redesign: Sistema de Vinculacao Zoom — Documento Consolidado

> **Data:** 2026-04-13
> **Escopo:** Painel Coordenador (admin) + Detalhe da Turma (turma/detalhe)
> **Objetivo:** Unificar o sistema de vinculacao de participantes Zoom com CSV (alunos), Staff (equipe) e WhatsApp, tornando tudo mais facil, transparente e persistente.

---

## 1. Diagnostico Atual

### 1.1 Fontes de Identidade

| Fonte | Tabela | Registros | Papel |
|-------|--------|-----------|-------|
| **CSV** | `student_imports` | ~490 | Fonte da verdade para alunos pagantes |
| **Equipe** | `staff` / `mentors` | ~15 | Professores, mentores, hosts |
| **WhatsApp** | `wa_group_members` | variavel | Membros do grupo WA por turma |
| **Zoom** | `zoom_participants` | milhares | Registros brutos de conexao |
| **Students (legado)** | `students` | 641 | Tabela antiga, usada como FK target |

### 1.2 Problemas Identificados

#### A) Painel Coordenador — Aba Zoom (`admin/index.html` + `js/admin/zoom.js`)

| # | Problema | Causa Raiz | Impacto |
|---|---------|-----------|---------|
| A1 | **Nomes duplicados na lista** | Query traz registros brutos sem agrupar por nome; cada reconexao = nova linha | Coordenador ve 3-5 entradas para o mesmo aluno |
| A2 | **Select "Selecionar aluno" puxa tabela errada** | `loadZoomMeetings()` linha 191 faz `sb.from('students')` em vez de `student_imports` | Lista 641 nomes obsoletos misturados |
| A3 | **Nao distingue Aluno vs Equipe** | Dropdown unico sem separacao | Impossivel saber se esta vinculando a aluno ou mentor |
| A4 | **Fuzzy match contra tabela errada** | `autoMatchParticipants()` usa `zoomAllStudents` da tabela `students` | Auto-match impreciso |
| A5 | **Dedup existe no DB mas nunca e chamado** | RPC `dedup_zoom_participants()` precisa ser executada manualmente | Duplicatas se acumulam |
| A6 | **Vincular nao salva alias** | So atualiza `student_id` no registro, nao salva o nome Zoom como alias | Vinculo nao se propaga para futuras reunioes |

#### B) Detalhe da Turma — Aba Presenca (`turma/detalhe.html`)

| # | Problema | Causa Raiz | Impacto |
|---|---------|-----------|---------|
| B1 | **Modal de vincular busca na tabela `students`** | `searchStudentsForLink()` linha 1703 faz `sb.from('students')` | Mostra registros legados, nao CSV |
| B2 | **"Criar novo aluno" insere em `students`** | `createAndLink()` faz insert em `students` | Cria registro na tabela errada |
| B3 | **Overrides manuais nao persistem** | `window._manualOverrides` vive so na sessao | Recarregou a pagina, perdeu os vinculos manuais |
| B4 | **Matching por nome falha para nomes curtos** | `nameMatch()` exige 2+ tokens (fix recente) | Alunos com 1 nome no CSV nunca matcheiam por nome |
| B5 | **Nao usa aliases para matching** | Auto-match nao consulta aliases do staff nem aliases salvos | Vinculos anteriores ignorados |

#### C) Cadastros — Staff (`admin` + `js/admin/staff.js`)

| # | Problema | Status |
|---|---------|--------|
| C1 | Campo "Aliases Zoom" no formulario | ✅ JA IMPLEMENTADO (commit d7fea6a) |
| C2 | Aliases sincronizados com `mentors.aliases` | ✅ JA IMPLEMENTADO |
| C3 | Equipe identificada na presenca | ✅ JA IMPLEMENTADO (secao "Equipe Presente") |

---

## 2. Arquitetura Proposta

### 2.1 Principio Central

> **Todo participante Zoom deve ser classificado em exatamente 1 de 3 categorias:**

| Categoria | Fonte Match | Cor | Icone |
|-----------|------------|-----|-------|
| **Aluno** | `student_imports` (CSV) por email, nome ou alias | Verde (#4ade80) | ✓ |
| **Equipe** | `staff` por nome ou aliases | Indigo (#a5b4fc) | 🎓 |
| **Desconhecido** | Nenhum match | Ambar (#f59e0b) | ? |

### 2.2 Matching Engine Unificado

Ordem de prioridade do match (aplicada em ambas as telas):

```
1. Email exato (CSV email == Zoom email)
2. Alias exato (nome Zoom == alias salvo no CSV ou Staff)
3. Nome exato (normalizeName match)
4. Nome tokenizado (nameMatch: primeiro + ultimo token)
5. Fuzzy (Jaro-Winkler >= 0.92 para auto, >= 0.80 para sugestao)
```

### 2.3 Persistencia de Vinculos

Ao vincular manualmente um participante Zoom a um aluno CSV ou membro de equipe:

| Destino | Onde salva o alias | Efeito |
|---------|-------------------|--------|
| Aluno (CSV) | `student_imports.aliases` (nova coluna `TEXT[]`) | Proxima reuniao faz auto-match |
| Equipe | `staff.aliases` + `mentors.aliases` (ja existe) | Idem |

> Isso elimina a necessidade de `window._manualOverrides` e de revincular a cada reuniao.

---

## 3. Mudancas por Arquivo

### 3.1 Banco de Dados (Supabase)

| Mudanca | Tabela | SQL |
|---------|--------|-----|
| Adicionar coluna aliases | `student_imports` | `ALTER TABLE student_imports ADD COLUMN aliases TEXT[] DEFAULT '{}'` |
| Chamar dedup ao carregar | - | Executar `dedup_zoom_participants()` 1x para limpar historico |

### 3.2 `js/admin/zoom.js` — Painel Coordenador

| Item | Funcao | Mudanca |
|------|--------|---------|
| **Dedup JS** | `loadZoomParticipants()` | Agrupar registros por `participant_name` normalizado, somar `duration_minutes`, manter 1 registro por nome |
| **Fonte do select** | `loadZoomMeetings()` | Trocar `sb.from('students')` por `student_imports` + `staff` |
| **Optgroups** | `renderZoomParticipants()` | Dropdown com `<optgroup label="Alunos (CSV)">` e `<optgroup label="Equipe">` |
| **Auto-classificar equipe** | `renderZoomParticipants()` | Antes de renderizar, marcar participantes que matcheiam com staff como "Equipe" (mostrar badge, nao pedir vinculo) |
| **Fuzzy contra CSV+Staff** | `autoMatchParticipants()` | Usar `student_imports` + `staff` em vez de `students` |
| **Salvar alias ao vincular** | `linkParticipant()` | Apos vincular, salvar `participant_name` como alias no registro CSV ou staff correspondente |
| **Filtro por turma** | `loadZoomMeetings()` | Ao selecionar reuniao de uma turma, filtrar CSV por `cohort_id` correspondente |

### 3.3 `turma/detalhe.html` — Detalhe da Turma

| Item | Funcao | Mudanca |
|------|--------|---------|
| **Modal busca em CSV+Staff** | `searchStudentsForLink()` | Trocar `sb.from('students')` por busca local em `allStudents` (CSV) + `staffMembers` |
| **Remover "Criar novo aluno"** | `createAndLink()` | Substituir por opcao "Marcar como Equipe" ou "Ignorar" |
| **Persistir vinculos** | `executeRelink()` | Ao relinkar, salvar alias no `student_imports.aliases` via Supabase update |
| **Matching com aliases** | `loadPresencaForMeeting()` | Incluir aliases do CSV e staff no auto-match |
| **Remover overrides de sessao** | - | Eliminar `window._manualOverrides`, usar aliases persistentes |

### 3.4 `admin/index.html` — Formulario Staff

| Item | Status |
|------|--------|
| Campo "Aliases Zoom" | ✅ Ja implementado |
| Exibicao de aliases na tabela | ✅ Ja implementado |

---

## 4. Plano de Execucao

### Fase 1 — Fundacao (banco + matching)

| Step | Descricao | Arquivos |
|------|-----------|----------|
| 1.1 | Criar migration: `student_imports.aliases TEXT[]` | `supabase/migrations/` |
| 1.2 | Executar `dedup_zoom_participants()` para limpar historico | Supabase CLI |
| 1.3 | Criar funcao JS unificada `classifyParticipant(name, email, csvStudents, staffList)` que retorna `{ type: 'aluno'|'equipe'|'desconhecido', match, matchMethod }` | Funcao compartilhada |

### Fase 2 — Painel Coordenador (admin/zoom)

| Step | Descricao | Arquivos |
|------|-----------|----------|
| 2.1 | Dedup JS no `loadZoomParticipants()` — agrupar por nome, somar duracao | `js/admin/zoom.js` |
| 2.2 | Trocar fonte do select: CSV (`student_imports`) + Staff com optgroups | `js/admin/zoom.js` |
| 2.3 | Auto-classificar equipe na lista (badge, sem pedir vinculo) | `js/admin/zoom.js` |
| 2.4 | Fuzzy match contra CSV + Staff | `js/admin/zoom.js` |
| 2.5 | Salvar alias ao vincular (CSV ou Staff) | `js/admin/zoom.js` |
| 2.6 | Filtrar CSV pela turma da reuniao selecionada | `js/admin/zoom.js` |

### Fase 3 — Detalhe da Turma (presenca)

| Step | Descricao | Arquivos |
|------|-----------|----------|
| 3.1 | Modal busca em CSV local + Staff (sem query ao banco) | `turma/detalhe.html` |
| 3.2 | Remover "Criar novo aluno", adicionar "Marcar como Equipe" | `turma/detalhe.html` |
| 3.3 | Matching engine com aliases do CSV e Staff | `turma/detalhe.html` |
| 3.4 | Persistir vinculo como alias no `student_imports` | `turma/detalhe.html` |
| 3.5 | Eliminar `window._manualOverrides` | `turma/detalhe.html` |

---

## 5. Resultado Esperado

### Antes

```
Coordenador abre Zoom no admin:
  → Ve 180 participantes (muitos duplicados)
  → Select com 641 nomes da tabela students (legado)
  → Nao sabe quem e equipe vs aluno
  → Vincula manualmente 1 por 1, a cada reuniao

Coordenador abre Presenca na turma:
  → Ve vinculos sem saber a origem
  → Modal busca na tabela errada
  → Pode "criar aluno" na tabela legada
  → Vinculos manuais perdem ao recarregar
```

### Depois

```
Coordenador abre Zoom no admin:
  → Ve participantes agrupados (sem duplicatas)
  → Equipe ja identificada automaticamente com badge
  → Select com CSV da turma + Equipe (optgroups)
  → Vincula 1 vez, alias salvo, vale para sempre

Coordenador abre Presenca na turma:
  → Ve vinculo transparente: "nome CSV ↔ nome Zoom (via nome/email/alias)"
  → Modal busca nos alunos CSV da turma + equipe
  → Vinculo salvo como alias, persiste entre sessoes
  → Equipe separada em secao propria
```

---

## 6. O que NAO muda

- Tabela `students` e seus FKs — permanece como target de `zoom_participants.student_id`
- RPC `propagate_zoom_links()` — continua funcional
- Fluxo "Descobrir Reunioes" — sem alteracao
- Pool de Hosts — sem alteracao
- Presencas da Equipe (`applyStaffAttendanceFromZoom`) — sem alteracao
- Estrutura de tabelas `zoom_meetings`, `zoom_participants` — sem mudanca de schema

---

## 7. Riscos e Mitigacoes

| Risco | Mitigacao |
|-------|----------|
| Dedup pode apagar registros que tinham `student_id` vinculado | Dedup mantem o registro com maior duracao; se tinha student_id, preserva |
| Aliases duplicados entre CSV e Staff | Match prioriza CSV > Staff > Fuzzy; ambiguidade resolvida por ordem |
| Reunioes sem cohort_id nao filtram CSV | Fallback: mostrar todos os CSV students quando cohort_id e null |
| Performance ao carregar todos os CSV | `student_imports` tem ~490 registros, cabe em memoria |
