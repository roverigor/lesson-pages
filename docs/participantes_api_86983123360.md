# Relatório de Participantes — API Zoom
## Imersão Prática AIOX — Fundamentals

---

### Informações da Reunião

| | |
|--|--|
| **Evento** | Imersão Prática AIOX - Fundamentals |
| **Data** | 30/03/2026 (domingo) |
| **Horário** | 19:38 – 23:28 BRT |
| **Duração efetiva** | 230 min |
| **Zoom Meeting ID** | 86983123360 |
| **Host** | pedagogico@academialendaria.ai |
| **Instâncias** | 2 (sala caiu às 22:38, reaberta às 22:41) |

---

### Metodologia de Coleta

Os dados foram extraídos via **API do Zoom** (Server-to-Server OAuth) usando o script `zoom_api.py`.

**Endpoint:** `GET /v2/report/meetings/{meetingId}/participants`

**Processamento aplicado:**

1. Busca automática de **todas as instâncias** via `/v2/past_meetings/{id}/instances`
2. **Paginação completa** — `page_size=300` com `next_page_token` (a API retorna no máximo 300 registros por página)
3. As 2 instâncias foram **unificadas** em 1 relatório
4. O Zoom registra cada entrada/saída como registro separado (join/leave)
5. Participantes foram **agrupados por nome exato** — cada nome único = 1 participante
6. Duração total = **soma de todas as sessões** do participante (incluindo reconexões)
7. **Bots/Notetakers** identificados por keywords no nome e removidos das métricas

**Observações importantes:**
- A API do Zoom tem **limitações conhecidas com breakout rooms** — pode não retornar todos os participantes que estiveram em salas secundárias
- Participantes que mudaram o nome durante a call são contados como pessoas diferentes
- Participantes com tempo total > 230 min provavelmente usaram múltiplos dispositivos

### Funil de Dados

| Etapa | Qtd |
|-------|-----|
| Registros brutos (API, todas as instâncias) | 1053 |
| Registros parseados | 1053 |
| Nomes únicos (total) | 226 |
| Bots/Notetakers removidos | 8 |
| **Participantes humanos únicos** | **218** |

### Indicadores de Engajamento

| Indicador | Valor |
|-----------|-------|
| Participantes humanos únicos | 218 |
| Pico simultâneo | 186 (às 20:42) |
| Duração média por participante | 148 min (2.5h) |
| Mediana de permanência | 156 min (2.6h) |
| Maior permanência | 455 min |
| Taxa de bounce (≤ 2 min) | 1 (0.5%) |
| Retenção | 100% |
| Participantes com reconexão | 213 de 218 (98%) |
| Total de reconexões | 812 |

### Distribuição de Permanência

| Faixa | Participantes | % |
|-------|--------------|---|
| Até 2 min (bounce) | 1 | 0.5% |
| 2-5 min | 0 | 0.0% |
| 5-10 min | 4 | 1.8% |
| 10-15 min | 9 | 4.1% |
| 15-30 min | 11 | 5.0% |
| 30-60 min | 16 | 7.3% |
| 1-2 horas | 26 | 11.9% |
| > 2 horas | 152 | 69.7% |

### Bots/Notetakers Filtrados (8)

| # | Nome | Duração (min) | Sessões |
|---|------|--------------|---------|
| 1 | Bruno's Fathom Notetaker | 52 | 2 |
| 2 | David's Fathom Notetaker | 153 | 5 |
| 3 | Dr.Lucas's Fathom Notetaker | 83 | 4 |
| 4 | Fran's Fathom Notetaker | 166 | 3 |
| 5 | Marcos's Fathom Notetaker | 54 | 2 |
| 6 | Oskr's Notetaker | 75 | 3 |
| 7 | Talles's Fathom Notetaker | 8 | 2 |
| 8 | Yara's Fathom Notetaker | 55 | 2 |

---

### Participantes Únicos (218)

| # | Nome | Duração (min) | Sessões | Reentradas | Primeira Entrada | Última Saída |
|---|------|--------------|---------|------------|-----------------|-------------|
| 1 | @dr.lucasmoraes | 245 | 7 | 6 | 19:58:07 | 23:28:38 |
| 2 | A.T.M. | 235 | 5 | 4 | 20:14:32 | 23:20:07 |
| 3 | Academia de Lendários | 55 | 1 | 0 | 19:48:57 | 19:49:52 |
| 4 | Adavio Tittoni | 230 | 9 | 8 | 19:50:42 | 23:28:25 |
| 5 | Adriana Duarte.'. | 28 | 2 | 1 | 21:35:28 | 21:35:57 |
| 6 | Adriano De Marqui | 201 | 4 | 3 | 19:44:21 | 22:51:17 |
| 7 | AGENCIA ACEWINGS I.A. | 16 | 2 | 1 | 20:17:17 | 20:26:57 |
| 8 | Alan Cichella | 124 | 4 | 3 | 20:15:13 | 22:08:42 |
| 9 | ALBERTO YANTORNO | 132 | 4 | 3 | 20:16:45 | 22:27:08 |
| 10 | Alexander Frota | 63 | 2 | 1 | 20:36:40 | 21:33:10 |
| 11 | Alexandre Pegoraro de Souza | 164 | 3 | 2 | 19:52:05 | 22:38:18 |
| 12 | Alexandre Rosa | 203 | 4 | 3 | 19:51:26 | 23:05:21 |
| 13 | Alexandre Spada | 33 | 2 | 1 | 20:45:30 | 21:13:55 |
| 14 | Allison Braz | 23 | 5 | 4 | 20:15:46 | 20:53:11 |
| 15 | ALUIZIO  JR | 49 | 2 | 1 | 22:43:11 | 23:28:24 |
| 16 | ALUIZIO C JR | 160 | 3 | 2 | 19:57:20 | 22:38:18 |
| 17 | Alvaro Shoji | 216 | 5 | 4 | 19:58:35 | 23:28:38 |
| 18 | Amanda de Paula Silva | 220 | 5 | 4 | 20:17:13 | 23:28:22 |
| 19 | Anderson Guimarães | 165 | 7 | 6 | 20:02:04 | 21:58:12 |
| 20 | Andre Colen | 176 | 9 | 8 | 20:18:14 | 22:38:18 |
| 21 | Andre Web | 102 | 5 | 4 | 20:17:13 | 21:04:56 |
| 22 | André Kamizono | 75 | 2 | 1 | 20:15:52 | 21:24:15 |
| 23 | André Muller Colaborando Com Seguros | 115 | 6 | 5 | 19:51:35 | 21:03:27 |
| 24 | André Silva | 200 | 8 | 7 | 20:15:43 | 23:28:26 |
| 25 | Anelise Schiavo Franco Silvério | 216 | 6 | 5 | 20:14:59 | 23:28:28 |
| 26 | Angela Feil | 211 | 7 | 6 | 20:17:49 | 23:28:27 |
| 27 | Autonom.IA | 155 | 4 | 3 | 20:00:14 | 22:38:18 |
| 28 | Bart Yantorno | 161 | 3 | 2 | 20:32:29 | 22:38:18 |
| 29 | Bruno Erick Fuchs | 183 | 5 | 4 | 20:31:26 | 23:28:38 |
| 30 | Bruno Gentil | 203 | 8 | 7 | 20:01:19 | 23:28:38 |
| 31 | Bruno SAL | 138 | 3 | 2 | 20:16:04 | 22:26:57 |
| 32 | Caio Matsui Ribeiro | 198 | 6 | 5 | 20:18:47 | 23:28:38 |
| 33 | Camila Goulart | 176 | 5 | 4 | 20:01:18 | 22:38:18 |
| 34 | Carlos Candeira | 70 | 4 | 3 | 20:15:32 | 23:11:43 |
| 35 | Carlos Eduardo | 153 | 3 | 2 | 19:52:13 | 22:27:05 |
| 36 | Carlos La Yunta | 94 | 4 | 3 | 20:15:40 | 21:45:29 |
| 37 | Carolina Rosa | 122 | 3 | 2 | 19:49:04 | 21:53:30 |
| 38 | Ciro Lacerda | 141 | 5 | 4 | 20:19:48 | 22:38:19 |
| 39 | Claudia Dumont | 139 | 4 | 3 | 19:55:23 | 22:00:44 |
| 40 | Claudia PC | 178 | 7 | 6 | 19:49:43 | 22:38:18 |
| 41 | Claudia Pires De Castro | 227 | 4 | 3 | 19:55:59 | 23:28:38 |
| 42 | Claudio Renan | 99 | 2 | 1 | 21:09:22 | 22:38:18 |
| 43 | Cris França | 154 | 4 | 3 | 19:53:42 | 22:29:38 |
| 44 | Daiana Duarte | 82 | 2 | 1 | 20:15:45 | 21:31:58 |
| 45 | Daniel Cunha | 165 | 13 | 12 | 20:35:15 | 21:50:56 |
| 46 | Daniel Lima | 139 | 4 | 3 | 20:00:46 | 22:23:30 |
| 47 | Daniela Campos | 158 | 3 | 2 | 19:58:44 | 22:38:18 |
| 48 | Danyel Gripp | 29 | 6 | 5 | 20:18:55 | 20:39:48 |
| 49 | Davi Carelli | 217 | 5 | 4 | 19:58:07 | 23:27:53 |
| 50 | David | 324 | 11 | 10 | 19:53:10 | 23:28:27 |
| 51 | David De Cunto | 127 | 4 | 3 | 20:28:40 | 22:38:18 |
| 52 | Dayana Critchii | 309 | 10 | 9 | 20:16:32 | 23:28:24 |
| 53 | Denis de Paula | 127 | 4 | 3 | 20:16:40 | 22:19:43 |
| 54 | Diego Andrade | 189 | 7 | 6 | 19:59:08 | 20:20:20 |
| 55 | Diego BNI Alquimia - 65 98111-6464 | 124 | 2 | 1 | 20:17:56 | 21:34:50 |
| 56 | Diego Diniz | 212 | 5 | 4 | 19:55:16 | 23:28:36 |
| 57 | Diogo Galvao | 73 | 4 | 3 | 21:11:30 | 22:07:25 |
| 58 | Edmilson Quesada | 146 | 7 | 6 | 20:02:03 | 22:38:18 |
| 59 | Edson Camargo | 208 | 5 | 4 | 20:16:47 | 23:25:50 |
| 60 | Edu Garretano | 147 | 3 | 2 | 20:16:14 | 22:38:18 |
| 61 | Eduardo Canudo | 166 | 3 | 2 | 20:37:06 | 22:38:18 |
| 62 | Eduardo Passos | 265 | 9 | 8 | 20:16:45 | 22:17:20 |
| 63 | Eduardo Trindade | 157 | 2 | 1 | 20:00:41 | 22:38:18 |
| 64 | Eduardo Vidal | 134 | 3 | 2 | 20:19:58 | 22:17:45 |
| 65 | Eliezer Cardoso - BOB | 163 | 4 | 3 | 19:53:44 | 22:38:18 |
| 66 | Eliezer Cardoso -BOB | 57 | 2 | 1 | 22:44:05 | 23:28:38 |
| 67 | Ellen Dias | 179 | 7 | 6 | 19:56:31 | 22:38:18 |
| 68 | Elton Vinicius | 304 | 15 | 14 | 20:17:40 | 22:38:18 |
| 69 | Elyas Pedro | 106 | 4 | 3 | 21:18:11 | 22:38:18 |
| 70 | Elyas Pedro F. de Aquino | 80 | 3 | 2 | 19:56:43 | 21:18:10 |
| 71 | Emanuela | 156 | 3 | 2 | 20:00:53 | 22:38:18 |
| 72 | Emanuela Barboza | 51 | 2 | 1 | 22:41:53 | 23:28:38 |
| 73 | Emanuela Nascimento | 70 | 4 | 3 | 20:27:09 | 21:29:35 |
| 74 | Enio Souza | 154 | 3 | 2 | 19:50:48 | 22:26:50 |
| 75 | Erica Souza | 217 | 9 | 8 | 21:03:27 | 23:28:38 |
| 76 | Ethel Shuña ♾️ | 204 | 14 | 13 | 20:16:39 | 23:28:38 |
| 77 | Everton Brasil | 219 | 5 | 4 | 20:03:04 | 23:28:38 |
| 78 | Fabiane Sanz ♾️ | 146 | 3 | 2 | 20:15:59 | 22:38:18 |
| 79 | Felipe Catão | 210 | 6 | 5 | 20:24:14 | 22:29:10 |
| 80 | Felipe Oliveira | 187 | 9 | 8 | 20:32:22 | 23:28:16 |
| 81 | Felipe Vieira Domingues Carneiro | 14 | 1 | 0 | 19:49:24 | 20:04:15 |
| 82 | Felipe Zacker | 97 | 3 | 2 | 20:24:18 | 22:02:37 |
| 83 | Fernanda Rodrigues | 134 | 5 | 4 | 20:34:26 | 22:38:18 |
| 84 | Fernando de Santis | 201 | 5 | 4 | 20:17:13 | 23:28:38 |
| 85 | Fernando Melo | 162 | 4 | 3 | 19:50:04 | 22:34:35 |
| 86 | Fernando Souza | 135 | 2 | 1 | 20:23:47 | 22:23:21 |
| 87 | Filipe Costa | 157 | 4 | 3 | 19:52:35 | 22:32:00 |
| 88 | Fran Martins | 160 | 4 | 3 | 19:50:44 | 22:33:15 |
| 89 | Franci Guedes | 146 | 3 | 2 | 20:16:24 | 22:38:18 |
| 90 | Francis Canada | 162 | 4 | 3 | 20:16:37 | 22:38:18 |
| 91 | FRANCIS Canada Advisor de Neg's Fatho... | 12 | 2 | 1 | 20:20:47 | 20:27:52 |
| 92 | Francisco Miyahara | 84 | 7 | 6 | 20:16:29 | 20:46:44 |
| 93 | Fábio Martins | 177 | 9 | 8 | 20:19:29 | 22:35:20 |
| 94 | Gabriel | 208 | 4 | 3 | 20:02:04 | 22:22:07 |
| 95 | Gabriel andrade do santos | 192 | 6 | 5 | 20:15:36 | 23:28:36 |
| 96 | Gabriel Gama | 199 | 5 | 4 | 20:16:33 | 23:28:22 |
| 97 | Gabriela Simoes | 36 | 2 | 1 | 19:59:55 | 20:36:05 |
| 98 | Gleicon | 178 | 4 | 3 | 20:26:49 | 22:38:18 |
| 99 | Gregory Jaboski | 199 | 3 | 2 | 20:01:59 | 22:24:09 |
| 100 | Guilherme | 112 | 10 | 9 | 20:16:55 | 21:29:28 |
| 101 | GUSTAVO BRITO | 207 | 6 | 5 | 20:22:31 | 22:38:18 |
| 102 | Halana Severo | 21 | 2 | 1 | 20:23:47 | 20:33:28 |
| 103 | Helayne Damasio | 156 | 4 | 3 | 20:00:27 | 22:38:18 |
| 104 | Hergamenes Souza | 15 | 2 | 1 | 20:28:28 | 20:38:23 |
| 105 | Hermes | 9 | 2 | 1 | 20:21:14 | 20:24:18 |
| 106 | Igor | 160 | 5 | 4 | 20:00:18 | 22:38:08 |
| 107 | Inacio Dutra | 183 | 3 | 2 | 20:02:22 | 22:26:45 |
| 108 | Isis Marques | 145 | 5 | 4 | 20:16:37 | 22:38:18 |
| 109 | Ivan Furtado | 52 | 5 | 4 | 19:59:32 | 20:54:07 |
| 110 | Jaderson Visentini | 366 | 15 | 14 | 20:15:53 | 23:03:16 |
| 111 | Jancer | 193 | 9 | 8 | 19:59:35 | 23:07:50 |
| 112 | Jaya Roberta ♾️ | 71 | 4 | 3 | 20:18:42 | 21:23:52 |
| 113 | Jaynara | 148 | 2 | 1 | 20:16:07 | 22:38:08 |
| 114 | Jennifer Zacker | 14 | 2 | 1 | 20:17:04 | 20:24:18 |
| 115 | Jhonata Matias | 15 | 2 | 1 | 20:16:48 | 20:29:28 |
| 116 | Johnny Moraiis | 206 | 5 | 4 | 20:15:10 | 23:28:38 |
| 117 | Jordy Fernandes | 107 | 3 | 2 | 20:17:04 | 22:01:18 |
| 118 | Jose Lehn | 159 | 5 | 4 | 20:17:19 | 22:38:18 |
| 119 | José Costacurta | 205 | 6 | 5 | 19:53:46 | 23:26:56 |
| 120 | João Carlos Cazorla | 123 | 2 | 1 | 20:45:46 | 22:37:57 |
| 121 | João Duarte | 136 | 3 | 2 | 20:00:52 | 22:18:15 |
| 122 | João Luiz | 155 | 5 | 4 | 19:57:23 | 22:08:21 |
| 123 | João Marcos | 205 | 5 | 4 | 20:15:24 | 23:28:24 |
| 124 | João Ramos | 133 | 3 | 2 | 20:01:14 | 22:15:43 |
| 125 | João Rosa | 15 | 2 | 1 | 20:30:45 | 20:37:57 |
| 126 | Kallita Molino | 163 | 2 | 1 | 19:53:42 | 22:37:58 |
| 127 | Kelly Lasev | 27 | 2 | 1 | 20:42:40 | 21:05:42 |
| 128 | Kleber Ribeiro | 146 | 3 | 2 | 19:58:45 | 22:26:52 |
| 129 | Kléber Fernandes | 156 | 3 | 2 | 19:49:11 | 22:26:57 |
| 130 | Laura Amorim | 156 | 3 | 2 | 20:00:54 | 22:38:18 |
| 131 | Leandro Castilho | 126 | 2 | 1 | 20:17:32 | 22:18:54 |
| 132 | Leila T Miara | 20 | 2 | 1 | 20:01:53 | 20:22:07 |
| 133 | Leonardo Chaves | 9 | 2 | 1 | 20:42:07 | 20:44:07 |
| 134 | Leonardo Kaniak | 231 | 6 | 5 | 20:17:18 | 23:28:24 |
| 135 | LINCOLN FREIRE | 336 | 6 | 5 | 19:51:46 | 22:38:18 |
| 136 | Lou Ribas | 313 | 6 | 5 | 19:56:25 | 22:38:18 |
| 137 | Lucas | 373 | 12 | 11 | 19:45:35 | 23:28:38 |
| 138 | Lucas Donny | 151 | 3 | 2 | 20:16:24 | 22:38:18 |
| 139 | Lucas Sousa | 214 | 4 | 3 | 20:18:29 | 23:28:37 |
| 140 | Luciana Dias | 306 | 12 | 11 | 20:20:11 | 22:38:18 |
| 141 | Luciana Robaina | 185 | 6 | 5 | 19:52:26 | 23:12:31 |
| 142 | Luciano Eduardo Libardi | 166 | 4 | 3 | 19:57:20 | 22:27:18 |
| 143 | Luciano Souza Ramos | 62 | 5 | 4 | 20:17:47 | 20:42:48 |
| 144 | Luh_Arrais | 230 | 5 | 4 | 19:58:39 | 23:28:38 |
| 145 | luis fernando menezes cristo | 155 | 4 | 3 | 19:48:51 | 22:25:17 |
| 146 | Luiz | 78 | 3 | 2 | 21:18:55 | 22:38:18 |
| 147 | Luiz Feitosa | 223 | 6 | 5 | 19:55:52 | 22:33:42 |
| 148 | Luiz Henrique Cota | 78 | 3 | 2 | 19:59:52 | 21:18:55 |
| 149 | Luiz Leal | 29 | 3 | 2 | 20:02:36 | 20:27:16 |
| 150 | Luís Lopes | 175 | 5 | 4 | 20:02:37 | 22:38:18 |
| 151 | Marcelo Asamura | 57 | 1 | 0 | 20:27:20 | 21:24:50 |
| 152 | Marcelo Azevedo | 36 | 2 | 1 | 19:50:12 | 20:27:20 |
| 153 | Marcelo Toledo | 37 | 4 | 3 | 20:18:31 | 20:33:34 |
| 154 | Marcio Nascimento | 120 | 3 | 2 | 20:30:27 | 22:18:50 |
| 155 | Marcio Silva | 187 | 6 | 5 | 19:59:31 | 23:13:56 |
| 156 | Marcos | 162 | 5 | 4 | 19:53:43 | 22:38:15 |
| 157 | Mariana Cappelin | 170 | 3 | 2 | 20:15:28 | 22:38:18 |
| 158 | Mariana Lussari | 205 | 5 | 4 | 19:59:20 | 23:28:38 |
| 159 | Marina | 1 | 1 | 0 | 20:00:42 | 20:02:08 |
| 160 | Mario Sousa | 455 | 20 | 19 | 20:18:08 | 23:28:38 |
| 161 | Marisa Nogueira Campos | 233 | 4 | 3 | 19:51:48 | 23:28:30 |
| 162 | Marlise Saraiva | 146 | 2 | 1 | 20:14:58 | 22:20:34 |
| 163 | Mateus Mendes | 160 | 4 | 3 | 19:55:24 | 22:38:18 |
| 164 | Mateus Mendes Caetano | 10 | 2 | 1 | 23:22:09 | 23:28:30 |
| 165 | Michael Sahlmann | 55 | 5 | 4 | 21:16:43 | 21:58:44 |
| 166 | miltonlima.369 | 311 | 7 | 6 | 20:21:46 | 22:38:18 |
| 167 | Monica Melo Sales | 127 | 2 | 1 | 20:35:29 | 22:38:18 |
| 168 | Neila Arasanz | 131 | 2 | 1 | 20:26:57 | 22:38:18 |
| 169 | Nelson Rodrigues | 322 | 6 | 5 | 19:50:20 | 22:38:19 |
| 170 | Oskr Leon | 113 | 5 | 4 | 20:24:23 | 22:38:18 |
| 171 | Paulo Andrade | 211 | 9 | 8 | 20:17:31 | 23:28:38 |
| 172 | Paulo Fernandes | 160 | 4 | 3 | 19:55:48 | 22:38:18 |
| 173 | Pedagógico Academia Lendár[IA] | 232 | 9 | 8 | 19:38:48 | 22:49:20 |
| 174 | Pedro Azevedo * | 28 | 2 | 1 | 19:55:33 | 20:24:01 |
| 175 | Rafael Cavalcanti | 75 | 5 | 4 | 20:01:43 | 21:11:53 |
| 176 | Rafael Zanetti | 157 | 3 | 2 | 20:00:45 | 22:38:18 |
| 177 | raynier silva | 229 | 5 | 4 | 19:50:38 | 23:28:23 |
| 178 | Renan Vieira | 160 | 7 | 6 | 20:16:20 | 22:47:08 |
| 179 | Renato Gomes | 157 | 3 | 2 | 19:59:53 | 22:38:18 |
| 180 | Reuniões Boa Vista | 158 | 2 | 1 | 19:58:50 | 22:38:01 |
| 181 | Ricardo Affonso | 149 | 3 | 2 | 20:18:06 | 22:38:18 |
| 182 | Ricardo Quirino | 282 | 6 | 5 | 20:02:17 | 23:28:15 |
| 183 | Ricardo Soares | 38 | 2 | 1 | 20:00:05 | 20:39:15 |
| 184 | Roberto Pinto | 119 | 4 | 3 | 20:00:25 | 21:29:00 |
| 185 | ROBERTO ZANETTA | 188 | 8 | 7 | 19:58:23 | 22:14:35 |
| 186 | Rodrigo Almeida | 295 | 8 | 7 | 19:55:35 | 23:28:28 |
| 187 | Rodrigo Conceição | 305 | 14 | 13 | 19:49:05 | 22:38:18 |
| 188 | Rodrigo Goltzman | 226 | 5 | 4 | 19:55:06 | 23:28:38 |
| 189 | Rodrigo Magina | 171 | 6 | 5 | 20:15:49 | 22:26:52 |
| 190 | Rold Andrade | 231 | 5 | 4 | 20:16:44 | 23:28:38 |
| 191 | Sandro Nogueira | 157 | 3 | 2 | 20:00:14 | 22:38:18 |
| 192 | Sergio rolemberg | 69 | 4 | 3 | 20:00:52 | 21:11:34 |
| 193 | Soraia Regina | 188 | 5 | 4 | 20:27:04 | 23:28:22 |
| 194 | Stefano Roldo | 38 | 2 | 1 | 20:21:10 | 20:21:48 |
| 195 | tais Pellizzer | 26 | 2 | 1 | 20:33:46 | 20:52:22 |
| 196 | Talles Souza | 9 | 2 | 1 | 23:24:12 | 23:28:14 |
| 197 | Taís Melo | 33 | 5 | 4 | 20:42:25 | 21:12:58 |
| 198 | Telmo Cerveira | 60 | 5 | 4 | 20:00:37 | 21:07:00 |
| 199 | Telmo Junior | 151 | 5 | 4 | 20:00:56 | 22:38:18 |
| 200 | Thiago | 134 | 6 | 5 | 19:59:27 | 22:09:28 |
| 201 | Thiago Peixoto | 20 | 1 | 0 | 19:58:32 | 19:58:52 |
| 202 | Tiago Carvalho | 11 | 2 | 1 | 21:44:42 | 21:47:43 |
| 203 | Ulysses Frias | 35 | 3 | 2 | 20:18:14 | 20:44:12 |
| 204 | Valdey Araruna | 105 | 4 | 3 | 19:50:26 | 21:24:10 |
| 205 | Victor Andrade | 11 | 2 | 1 | 20:20:55 | 20:24:19 |
| 206 | Victor Soares | 219 | 12 | 11 | 19:58:26 | 23:28:38 |
| 207 | Vinicius Mafra | 156 | 3 | 2 | 20:00:52 | 22:38:18 |
| 208 | Virginia Lara Marçal | 125 | 7 | 6 | 19:56:12 | 21:25:44 |
| 209 | VLAMIR ALVES DOS ANJOS | 224 | 5 | 4 | 19:47:52 | 23:28:19 |
| 210 | Walter Pitman | 295 | 9 | 8 | 20:00:55 | 22:38:18 |
| 211 | Wellington Vasconcelos | 156 | 5 | 4 | 19:59:51 | 22:38:18 |
| 212 | Wenderson | 155 | 5 | 4 | 20:11:32 | 22:38:18 |
| 213 | Werney Lima | 156 | 3 | 2 | 20:01:04 | 22:38:18 |
| 214 | Wil Resplande | 11 | 2 | 1 | 20:18:21 | 20:20:24 |
| 215 | William Mayrer | 214 | 6 | 5 | 20:16:23 | 23:28:30 |
| 216 | Yan Lima | 182 | 6 | 5 | 20:00:06 | 22:59:54 |
| 217 | Yara Martins | 155 | 3 | 2 | 20:19:12 | 22:38:18 |
| 218 | Ândrius Gabriel | 311 | 10 | 9 | 19:59:32 | 23:03:29 |

---

*Relatório gerado via `zoom_api.py` em 31/03/2026 20:16.*
*Dados extraídos da API do Zoom (Server-to-Server OAuth) com paginação completa e unificação de instâncias.*
