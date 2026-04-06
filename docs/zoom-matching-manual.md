# Como vincular participantes Zoom a alunos (matching manual)

## Contexto

Após importar uma reunião Zoom, os participantes são automaticamente vinculados aos alunos cadastrados pelo algoritmo de matching. Os que não foram vinculados automaticamente precisam ser feitos manualmente.

---

## Passo a passo

### 1. Acesse o painel admin
**URL:** https://calendario.igorrover.com.br/equipe  
Faça login com suas credenciais de administrador.

### 2. Vá para a aba Zoom
Clique no botão **Zoom** na barra de navegação superior.

### 3. Selecione a reunião
No dropdown **"Reunião importada"**, selecione a sessão que deseja revisar.  
Exemplo: `30/03/2026 — Imersão Prática AIOX - Fundamentals (Imersão AIOX Fundamentals)`

### 4. Veja o resumo de match
Após selecionar, aparece a barra de estatísticas:
- **Total** de participantes da sessão
- **Vinculados** (fundo verde) — já têm aluno vinculado
- **Não vinculados** (fundo vermelho) — precisam de ação manual

### 5. Filtre os não vinculados
Use o campo de busca **"Filtrar participantes não vinculados..."** para encontrar um nome específico.

### 6. Vincule cada participante
Para cada participante não vinculado:
1. Localize o nome na lista
2. No dropdown ao lado do nome, selecione o aluno correspondente
3. O vínculo é salvo automaticamente

> **Dica:** Use o campo de busca do dropdown para digitar parte do nome do aluno.

### 7. Repita para todas as reuniões
Faça o mesmo para cada sessão importada. As turmas disponíveis são:
- Fundamental T3 (10 sessões — março 2026)
- Imersão AIOX Fundamentals (3 sessões — março 2026)
- Advanced T1 (1 sessão — abril 2026)
- Dashboard Mission Control (1 sessão — março 2026)

---

## Participantes com maior prioridade (aparecem em várias sessões)

Esses nomes aparecem frequentemente e não foram vinculados automaticamente.  
Foque neles primeiro — ao vincular uma vez, o sistema tenta reusar nas sessões seguintes.

| Nome no Zoom | Sessões | Turma provável |
|---|---|---|
| GUSTAVO BRITO | 36 aparições | Fundamental T3 |
| Diego BNI Alquimia... | 29 aparições | Fundamental T3 |
| Fernando de Santis | 23 aparições | Fundamental T3 |
| Mario Sousa | 22 aparições | Fundamental T3 |
| Lukito | 22 aparições | Fundamental T3 |
| Roberto Pinto | 22 aparições | Fundamental T3 |
| Kléber Fernandes | 19 aparições | Fundamental T3 |
| Ricardo Quirino | 18 aparições | Fundamental T3 |
| Carlos Eduardo | 16 aparições | Fundamental T3 |

---

## O que acontece após vincular

Após vincular todos os participantes possíveis, os dados de presença precisam ser transferidos da tabela `zoom_participants` para a tabela oficial `attendance`.  
Esse processo será implementado em breve — aguarde a próxima atualização do sistema.

---

## Dúvidas

- Participante não está na lista de alunos? Verifique se o aluno está cadastrado em **Alunos**.
- Nome muito diferente? O algoritmo não consegue vincular nomes abreviados ou apelidos — faça manualmente.
- Pedagógico Academia Lendár[IA] aparece como participante? Ignore — é o host da reunião, não um aluno.
