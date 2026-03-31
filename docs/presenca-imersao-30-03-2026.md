# Relatório de Presença
## Imersão Prática AIOX — Fundamentals

---

### Informações da Reunião

| | |
|--|--|
| **Evento** | Imersão Prática AIOX - Fundamentals |
| **Data** | 30/03/2026 (domingo) |
| **Horário** | 19:38 – 23:28 BRT |
| **Duração efetiva** | 3h48min (228 min) |
| **Zoom Meeting ID** | 86983123360 |
| **Host** | pedagogico@academialendaria.ai |
| **Incidente** | Sala caiu às 22:38 BRT, reaberta às 22:41 BRT (3 min fora) |

---

### Metodologia de Coleta

Os dados foram extraídos automaticamente via **API do Zoom** (Server-to-Server OAuth)
usando o endpoint `past_meetings/{uuid}/participants`.

**Processamento aplicado:**

1. A queda da sala gerou **2 instâncias** do mesmo Meeting ID no Zoom
2. As 2 instâncias foram **unificadas** em 1 relatório
3. Participantes que aparecem em ambas tiveram a **duração somada**
4. O Zoom registra cada entrada/saída como registro separado (join/leave)
5. Participantes duplicados foram **deduplicados por nome** (mantendo maior duração)
6. **IAs/Bots** de transcrição foram identificados e removidos
7. **Contas da equipe** foram separadas dos alunos
8. Alunos foram **vinculados automaticamente** à base cadastral por nome (primeiro + último)

### Funil de Dados

| Etapa | Qtd | Observação |
|-------|-----|-----------|
| Registros brutos do Zoom (joins/leaves) | 427 | Cada entrada/saída = 1 registro |
| Deduplicação por nome | -265 | Mesma pessoa com múltiplas entradas |
| **Pessoas únicas** | **162** | |
| IAs/Bots de transcrição | -7 | Fathom Notetakers e outros |
| Contas da equipe | -9 | Mentores, coordenação, contas institucionais |
| **Alunos únicos** | **147** | |
| → Vinculados à base (com telefone) | 86 | Match automático por nome |
| → Sem vínculo (match manual pendente) | 61 | |

> **Nota:** O pico de ~180 conexões simultâneas reportado pelo Zoom inclui reconexões,
> múltiplos dispositivos, bots de transcrição e contas da equipe.
> O número real de alunos únicos que participaram é **147**.

### Indicadores de Engajamento (alunos vinculados)

| Indicador | Valor |
|-----------|-------|
| Duração média por aluno | 42 min |
| Maior permanência | 201 min |
| Ficaram 60+ min | 17 alunos (20%) |
| Ficaram 30+ min | 38 alunos (44%) |

### Reconexões

A queda da sala e instabilidades de conexão geraram **265 reconexões**
de **152 participantes** (de 162 únicos).
Apenas **10** participantes tiveram entrada única sem reconexão.

---

### 1. Equipe (9)

| # | Nome | Duração (min) | Papel |
|---|------|---------------|-------|
| 1 | Adavio Tittoni | 74 | Mentor |
| 2 | Adriano De Marqui | 182 | Mentor |
| 3 | Bruno Gentil | 85 | Mentor |
| 4 | Erica Souza | 43 | Coordenação |
| 5 | Fran Martins | 30 | Coordenação |
| 6 | Luh_Arrais | 200 | Coordenação |
| 7 | Talles Souza | 4 | Mentor |
| 8 | Pedagógico Academia Lendár[IA] | — | Conta institucional |
| 9 | Academia de Lendários | — | Conta institucional |

### 2. Alunos Vinculados (86)

Alunos identificados automaticamente na base cadastral. Possuem telefone e email para contato.

| # | Nome no Zoom | Min | Aluno Cadastrado | Telefone | Email |
|---|-------------|-----|-----------------|----------|-------|
| 1 | Alan Cichella | 15 | Alan Jones Cichella | 554691144429 | alanjonescichella@gmail.com |
| 2 | Alexandre Pegoraro de Souza | 21 | Alexandre Pegoraro de Souza | 5514998482174 | xand.pegoraro@gmail.com |
| 3 | Alexandre Rosa | 176 | Alexandre Antunes da Rosa | 555192716066 | aar.advogado@icloud.com |
| 4 | Allison Braz | 3 | Allison Gustavo Braz | 556496277870 | allisonbraz@gmail.com |
| 5 | Alvaro Shoji | 72 | Alvaro shoji cavaguti | 5511959019707 | alvaroshoji@gmail.com |
| 6 | Amanda de Paula Silva | 45 | Amanda Silva | 554888080251 | amandapaula2005@hotmail.com |
| 7 | Anderson Guimarães | 23 | Anderson Barbosa Guimarães | 558282358901 | abarbosa.guimaraes@gmail.com |
| 8 | André Kamizono | 68 | André Kamizono | 5519990145569 | andrekamizono@hotmail.com |
| 9 | André Silva | 56 | André Silva | 5521993149669 | alss.commerce@gmail.com |
| 10 | Anelise Schiavo Franco Silvério | 58 | Anelise Schiavo Franco Silvério | 5519981701859 | anelise.negocios@gmail.com |
| 11 | Angela Feil | 43 | Angela Feil | 555197791919 | angelafeil@gmail.com |
| 12 | Bruno Erick Fuchs | 43 | Bruno Fuchs | 554799149737 | brunoefuchs@gmail.com |
| 13 | Caio Matsui Ribeiro | 45 | Caio Matsui Ribeiro | 553599798917 | caiomatsuir@hotmail.com |
| 14 | Carlos La Yunta | 9 | Carlos de Castro La Yunta | 556281158857 | carlos.layunta@gmail.com |
| 15 | Claudia Dumont | 23 | Claudia Dumont | 553191633000 | claudiadumont@hotmail.com |
| 16 | Claudia Pires De Castro | 200 | Claudia Pires de Castro | 5519991647478 | claudiapires.br@gmail.com |
| 17 | Daniel Lima | 24 | Daniel Lima | 553197876428 | danielgoi235@gmail.com |
| 18 | Daniela Campos | 27 | Daniela Campos | 553195456057 | danicrodrigues@gmail.com |
| 19 | Davi Carelli | 69 | Davi Gomes Carelli | 554188091213 | dcarelli84@gmail.com |
| 20 | Dayana Critchii | 57 | Dayana Mesquita Critchii | 554185130303 | critchiidayana@gmail.com |
| 21 | Diego Andrade | 8 | Diego Chaves de Andrade | 556581116464 | diegochaves64@gmail.com |
| 22 | Edmilson Quesada | 23 | Edmilson da Silva Quesada | 5519981896166 | edmilson.quesada@hotmail.com |
| 23 | Edson Camargo | 41 | Edson Camargo Camargo | 554188774475 | edbcamargo@gmail.com |
| 24 | Eliezer Cardoso -BOB | 66 | Eliezer Cardoso Cardoso | 554799525562 | iai.get137@gmail.com |
| 25 | Ellen Dias | 5 | Ellen Pereira Gonçalves Dias | 553599182728 | el.pgd27@gmail.com |
| 26 | Emanuela | 27 | Emanuela | 557591316426 | — |
| 27 | Enio Souza | 22 | Enio Souza | 556184548398 | eniodesouza2@gmail.com |
| 28 | Ethel Shuña ♾️ | 47 | Ethel Shuña Queiroz Shuña Queiroz | 5511993181962 | ethesq12@gmail.com |
| 29 | Everton Brasil | 67 | Everton Silveira Brasil Brasil | 5511986117375 | ebrasill@yahoo.com.br |
| 30 | Fabiane Sanz ♾️ | 10 | Fabiane Antunes Sanz | 555140420808 | eufabianesanz@gmail.com |
| 31 | Felipe Oliveira | 20 | Felipe L N Oliveira | 5517997172715 | felipelazov@gmail.com |
| 32 | Felipe Vieira Domingues Carneiro | 15 | Felipe Vieira Domingues Carneiro | 554899191914 | felipevdcarneiro@gmail.com |
| 33 | Fernando de Santis | 44 | Fernando Henrique de Santis | 5512988480406 | fernandodesantis@yahoo.com.br |
| 34 | Fernando Melo | 23 | Fernando Marcos Rosa de Melo | 5561981600038 | fernandomelo.digital@gmail.com |
| 35 | Filipe Costa | 22 | Filipe Costa | 5512997534278 | filipegomesdacosta@gmail.com |
| 36 | Franci Guedes | 12 | Franci Guedes | 558191329780 | franci.guedes@gmail.com |
| 37 | Francis Canada | 0 | Francis A Canada Andrade | 5519546479140 | a.francisandrade@icloud.com |
| 38 | Francisco Miyahara | 0 | Francisco Takashi Cabrera Miyahara | 5511996029921 | fm7chico@gmail.com |
| 39 | Gabriel | 22 | Gabriel | 5524988270522 | — |
| 40 | Gabriel Gama | 60 | Gabriel Gama | 5515974015100 | gamagab@gmail.com |
| 41 | Gregory Jaboski | 24 | Gregory Jaboski | 554888334857 | gregory@cloudtreinamentos.com |
| 42 | Helayne Damasio | 26 | Helayne Alves de Oliveira Damasio | 556186060051 | helaynealves@gmail.com |
| 43 | Inacio Dutra | 26 | Inácio Dutra | 558599867550 | inaciodutra@gmail.com |
| 44 | Ivan Furtado | 25 | Ivan Nicholas Furtado | 553598717592 | academy.cdr@gmail.com |
| 45 | Jaderson Visentini | 32 | Jaderson Denardin Visentini | 5555996489288 | ado.jdv@live.com |
| 46 | João Luiz | 23 | João Luiz | 558892497706 | joaodocedro@gmail.com |
| 47 | Kallita Molino | 155 | Kallita Ester Magalhães Molino | 5511948369636 | hallokallita@hotmail.com |
| 48 | Laura Amorim | 27 | Laura Amorim | 5511998050433 | amorim.le@hotmail.com |
| 49 | Leila T Miara | 19 | Leila Tramontim Miara | 5513982321033 | leilatmiara@gmail.com |
| 50 | Leonardo Kaniak | 43 | Leonardo Kaniak | 554199674759 | leonardo@kaniak.com.br |
| 51 | LINCOLN FREIRE | 155 | Lincoln Freire | 5521985662777 | lincolntf@uol.com.br |
| 52 | Lucas Sousa | 42 | Lucas Donizetti Kanzawa de Sousa | 5511964922455 | rucazu@hotmail.com |
| 53 | Luciano Eduardo Libardi | 22 | Luciano Eduardo Libardi | 555484011000 | libardi@smarton.com.br |
| 54 | Luiz Henrique Cota | 21 | Luiz H da Silva Cota | 553199958307 | luizhenriquecota@gmail.com |
| 55 | Luís Lopes | 21 | Luis Lopes | 351966015020 | — |
| 56 | Marcelo Azevedo | 24 | Marcelo Azevedo | 5511940485506 | ma.asamura@gmail.com |
| 57 | Marcio Silva | 33 | Marcio Silva | 5511962003060 | marcioatlondon@gmail.com |
| 58 | Mariana Cappelin | 11 | Mariana Cappelin ⭕ | 5511964116314 | ma_cappelin@hotmail.com |
| 59 | Mariana Lussari | 65 | Mariana Duarte Lussari | 5519981373527 | marianalussari@stcgroup.com.br |
| 60 | Mario Sousa | 41 | Mario Sousa | 351968308441 | mariodesousa7@sapo.pt |
| 61 | Marisa Nogueira Campos | 201 | Marisa Nogueira Campos | 5521996327764 | marisacampos2006@gmail.com |
| 62 | Mateus Mendes Caetano | 6 | Mateus Mendes Caetano | 557781267005 | mateusengenheirof@gmail.com |
| 63 | Nelson Rodrigues | 155 | Nelson Rodrigues | 5524940873726 | ketson85@hotmail.com |
| 64 | Paulo Andrade | 47 | Paulo Andrade | 553299713060 | pgcandrade@hotmail.com |
| 65 | Paulo Fernandes | 29 | Paulo Fernandes | 5521964644646 | paulofernandes1610@gmail.com |
| 66 | Pedro Azevedo * | 20 | Pedro Azevedo | 5511956592872 | versopedro2000@gmail.com |
| 67 | Rafael Cavalcanti | 24 | Rafael Cavalcanti | 558183694904 | rafaelcavalcantimkt@gmail.com |
| 68 | raynier silva | 72 | Raynier Silva Nascimento | 5527999455692 | rayniersn@gmail.com |
| 69 | Renan Vieira | 12 | Renan Vieira | 558198751352 | sergio.renan.fv@gmail.com |
| 70 | Renato Gomes | 23 | Renato Aparecido Gomes | 5511940273663 | renatoapgomes@gmail.com |
| 71 | Rodrigo Almeida | 69 | Rodrigo José de Almeida | 555499531168 | almeida.rodrigoj@gmail.com |
| 72 | Rodrigo Magina | 1 | Rodrigo Agape Vieira Magina | 5521981501650 | rvmagina@gmail.com |
| 73 | Rold Andrade | 47 | Rold Andrade Pereira | 554898139031 | roldmestre06@gmail.com |
| 74 | Soraia Regina | 45 | Soraia Regina | 553185096955 | so.rsantos85@gmail.com |
| 75 | Telmo Cerveira | 2 | Telmo Cerveira | 351918700778 | trcerveira@gmail.com |
| 76 | Telmo Junior | 28 | Telmo Penha da Silva Junior | 554888310605 | tpsjunior@hotmail.com |
| 77 | Thiago | 28 | Thiago | 5511992966688 | — |
| 78 | Thiago Peixoto | 0 | Thiago Miranda Peixoto | 5511992966688 | thiagompeixoto@outlook.com |
| 79 | Valdey Araruna | 81 | VALDEY ALVES ARARUNA FILHO ALVES ARARUNA FILHO | 558897129386 | valdeyfilho@hotmail.com |
| 80 | Victor Soares | 51 | Victor Soares | 554388397667 | victorsoares3105@gmail.com |
| 81 | Virginia Lara Marçal | 23 | Virgínia Lara Marcal | 556392122339 | virginiamarcal@gmail.com |
| 82 | VLAMIR ALVES DOS ANJOS | 68 | Vlamir Alves dos Anjos Alves dos Anjos | 5511983721967 | vlamir.anjos@gmail.com |
| 83 | Wellington Vasconcelos | 22 | Wellington Vasconcelos | 5511973429233 | wellvasc@hotmail.com |
| 84 | Werney Lima | 26 | Werney Antunes Lima | 558393504242 | werneyal7@gmail.com |
| 85 | William Mayrer | 58 | William Mayrer | 555496089390 | wmayrer@gmail.com |
| 86 | Yan Lima | 40 | Yan Lima | 557186801998 | whicher765@gmail.com |

### 3. Sem Vínculo (61)

Participantes não vinculados automaticamente. Podem ser alunos com nome diferente do cadastro,
convidados, ou pessoas que ainda não estão na base.
Vínculo manual disponível em: lesson-pages.vercel.app/presenca → aba "Vincular".

| # | Nome no Zoom | Min | Observação |
|---|-------------|-----|-----------|
| 1 | @dr.lucasmoraes | 68 | Alta permanência |
| 2 | A.T.M. | 58 |  |
| 3 | Academia de Lendários | 1 | Breve passagem |
| 4 | ALUIZIO  JR | 45 |  |
| 5 | ALUIZIO C JR | 21 |  |
| 6 | André Muller Colaborando Com Seguros | 11 |  |
| 7 | Autonom.IA | 33 | Possível empresa de aluno |
| 8 | Bruno SAL | 10 |  |
| 9 | Camila Goulart | 23 |  |
| 10 | Carlos Candeira | 9 |  |
| 11 | Carlos Eduardo | 22 |  |
| 12 | Carolina Rosa | 31 |  |
| 13 | Claudia PC | 25 |  |
| 14 | Cris França | 24 |  |
| 15 | Daiana Duarte | 76 | Alta permanência |
| 16 | David | 72 | Alta permanência |
| 17 | Denis de Paula | 0 | Breve passagem |
| 18 | Diego Diniz | 57 |  |
| 19 | Edu Garretano | 5 |  |
| 20 | Eduardo Trindade | 155 | Alta permanência |
| 21 | Elyas Pedro F. de Aquino | 24 |  |
| 22 | Emanuela Barboza | 47 |  |
| 23 | Gabriel andrade do santos | 55 |  |
| 24 | Gabriela Simoes | 33 |  |
| 25 | Igor | 29 |  |
| 26 | Isis Marques | 0 | Breve passagem |
| 27 | Jancer | 66 | Alta permanência |
| 28 | Jaynara | 142 | Alta permanência |
| 29 | Johnny Moraiis | 58 |  |
| 30 | José Costacurta | 68 | Alta permanência |
| 31 | João Duarte | 22 |  |
| 32 | João Marcos | 54 |  |
| 33 | João Ramos | 22 |  |
| 34 | Kleber Ribeiro | 24 |  |
| 35 | Kléber Fernandes | 24 |  |
| 36 | Lou Ribas | 155 | Alta permanência |
| 37 | Lucas | 68 | Alta permanência |
| 38 | Lucas Donny | 13 |  |
| 39 | Luciana Robaina | 44 |  |
| 40 | luis fernando menezes cristo | 35 |  |
| 41 | Luiz Feitosa | 22 |  |
| 42 | Luiz Leal | 0 | Breve passagem |
| 43 | Marcos | 29 |  |
| 44 | Marina | 1 | Breve passagem |
| 45 | Marlise Saraiva | 125 | Alta permanência |
| 46 | Mateus Mendes | 31 |  |
| 47 | Pedagógico Academia Lendár[IA] | 48 |  |
| 48 | Rafael Zanetti | 22 |  |
| 49 | Reuniões Boa Vista | 155 | Sala de reunião |
| 50 | Ricardo Quirino | 67 | Alta permanência |
| 51 | Ricardo Soares | 36 |  |
| 52 | Roberto Pinto | 25 |  |
| 53 | ROBERTO ZANETTA | 23 |  |
| 54 | Rodrigo Conceição | 22 |  |
| 55 | Rodrigo Goltzman | 64 | Alta permanência |
| 56 | Sandro Nogueira | 24 |  |
| 57 | Sergio rolemberg | 25 |  |
| 58 | Vinicius Mafra | 48 |  |
| 59 | Walter Pitman | 25 |  |
| 60 | Wenderson | 14 |  |
| 61 | Ândrius Gabriel | 34 |  |

### 4. IAs/Bots Filtrados (7)

Bots de transcrição automática identificados e removidos do relatório de presença.

| # | Nome | Serviço |
|---|------|---------|
| 1 | Bruno's Fathom Notetaker | Fathom |
| 2 | Dr.Lucas's Fathom Notetaker | Fathom |
| 3 | Fran's Fathom Notetaker | Fathom |
| 4 | Marcos's Fathom Notetaker | Fathom |
| 5 | Oskr's Notetaker | Outro |
| 6 | Talles's Fathom Notetaker | Fathom |
| 7 | Yara's Fathom Notetaker | Fathom |

---

### Resumo Executivo

| Categoria | Qtd | % |
|-----------|-----|---|
| Registros brutos Zoom | 427 | — |
| Pessoas únicas | 162 | 100% |
| Equipe | 9 | 6% |
| IAs/Bots | 7 | 4% |
| **Alunos únicos** | **147** | **91%** |
| → Vinculados (com dados de contato) | 86 | 59% dos alunos |
| → Sem vínculo (match manual pendente) | 61 | 41% dos alunos |

---

*Relatório gerado automaticamente via Zoom API + Supabase em 31/03/2026.*
*Vinculação por matching de nomes (primeiro + último). Vínculo manual: lesson-pages.vercel.app/presenca*