# Análise Q&A - PS (Pronto Socorro) | 10/02/2026

> **Contexto:** Sessão de tira-dúvidas do cohort avançado sobre AIOS, desenvolvimento com IA, e implementação de projetos reais.

**Data:** 10 de fevereiro de 2026
**Tipo:** Pronto Socorro (Tira-dúvidas)
**Especialistas:** João, Zé Carlos, Talles, equipe Academia Lendária
**Participantes:** ~15-20 alunos do cohort avançado

---

## 📊 Estatísticas Gerais

- **Perguntas identificadas:** 28
- **Temas principais:** AIOS setup (9), Workflow desenvolvimento (8), Casos de uso/negócios (6), Ferramentas/Integrações (5)
- **Duração:** ~2h (00:00:00 - 01:54:19)
- **Formato:** Sala principal + salas simultâneas (Fundamentos, Business, Técnico Avançado)

---

## 🎯 Principais Perguntas e Respostas

### 1️⃣ SETUP E CONFIGURAÇÃO DO AIOS

#### **Q1: Qual a última versão do Squad Creator do Alan? Onde está?**
**Perguntado por:** Fábio (00:29:25)

**Resposta (Academia Lendária):**
- Está disponível no **GitHub** (repositório oficial)
- Alan também envia atualizações no **grupo do WhatsApp**
- Versão mencionada: "5-2-26 squad-creator 3h33"
- Recomendação: Atualizar via `git pull` do GitHub

---

#### **Q2: Para instalar AIOS em projeto novo, copio pasta ou instalo do zero?**
**Perguntado por:** Alexandre (00:20:42)

**Resposta (João):**
**Opção 1 - Copiar:**
- Copiar TODAS as pastas de infraestrutura do AIOS:
  - `.aios-core/`
  - `.aios/`
  - `.claude/commands/` (agentes e comandos slash)
- **IMPORTANTE:** NÃO copiar o `CLAUDE.md` (é específico do projeto original)
- Colar na pasta exatamente espelhado

**Opção 2 - Instalar do zero:**
- Rodar `claude init` na pasta nova
- Rodar `aios install` para configurar

**Regra de ouro:**
- Cada projeto precisa de seu próprio `CLAUDE.md` (cérebro do sistema)
- Se copiar CLAUDE.md de outro projeto → vai quebrar (contexto errado)

---

#### **Q3: Quando tiver atualização do AIOS, como atualizo em todos os projetos?**
**Perguntado por:** Fábio (00:24:36)

**Resposta (João):**
1. Ir em cada repositório/pasta onde AIOS está instalado
2. Rodar `aios install` ou `aios update`
3. Atualiza automaticamente em cada projeto

**Dica Pro (João):**
- Se você tem vários projetos, vale ter um **workspace central**
- O workspace opera outras pastas filhas
- Assim você concentra atualizações

---

#### **Q4: CloudMD deve ser por projeto ou pode ser global?**
**Perguntado por:** João (aluno) (00:23:45)

**Resposta (João - instrutor):**
- **O ideal é por PROJETO**
- CloudMD = cérebro do sistema, primeira coisa carregada
- Se você colocar um CloudMD "frankenste

in" (misturando vários contextos) → vai confundir a LLM

**Por quê:**
- Cada projeto tem contexto, arquivos, pastas específicas
- CloudMD global não sabe quais arquivos existem em cada projeto
- Seria como colocar cérebro de um projeto em outro corpo

**Exceção:**
- Você pode ter um CloudMD MASTER (na raiz do workspace)
- Ele rege todos os projetos
- Cada projeto ainda tem seu próprio CloudMD específico
- O MASTER contém heurísticas transversais (design system comum, etc.)

---

#### **Q5: Como organizar workspace vs projetos individuais?**
**Perguntado por:** Alexandre (discussão 01:37:00+)

**Resposta (João):**

**Estrutura recomendada:**

```
~/code/                          # Workspace master
├── .claude/CLAUDE.md            # CloudMD MASTER (heurísticas globais)
├── projeto-api/                 # Projeto 1
│   ├── .claude/CLAUDE.md        # CloudMD específico do projeto
│   ├── .aios-core/              # Infraestrutura AIOS
│   └── .aios/
├── projeto-camban/              # Projeto 2
│   ├── .claude/CLAUDE.md
│   ├── .aios-core/
│   └── .aios/
└── projeto-loja-bio/            # Projeto 3
    ├── .claude/CLAUDE.md
    ├── .aios-core/
    └── .aios/
```

**Pastas auxiliares (separadas do workspace):**

```
~/marketing/                     # Pasta de agentes marketing
├── agente-copy.md
├── agente-ux.md
└── agente-vendedor.md

~/mentes-clonadas/              # Mentes dos mentores
├── alan.md
├── ze.md
├── pedro.md
└── minha-mente.md
```

**Workflow:**
1. Abrir IDE (Cursor, AntiGravity, VSCode) na pasta do projeto
2. Dentro da IDE, usar terminal com Cloud Code
3. Quando precisar de agente externo (ex: UX master) → copiar pra dentro do projeto

---

### 2️⃣ WORKFLOW DE DESENVOLVIMENTO

#### **Q6: Como você trabalha hoje - faz tudo fora e traz pro AIOS depois?**
**Perguntado por:** João (aluno) (00:27:04)

**Resposta (João - instrutor) - WORKFLOW COMPLETO:**

```
1️⃣ SESSÃO DE DESCARREGO (Fora do AIOS)
   └─> Gravar áudio OU fazer call + transcrição
       └─> Vomitar ideias, contexto, dores

2️⃣ TRANSFORMAR EM BRIEFING
   └─> Jogar transcrição pra LLM
       └─> Output: Briefing estruturado

3️⃣ PESQUISAS (Enriquecer + Preencher Lacunas)
   └─> Pesquisa de mercado (concorrentes, tendências)
   └─> Tech research (bibliotecas, APIs, stack)
   └─> Pode usar Deep Serve, Perplexity, ou agente de busca

4️⃣ ENRIQUECER O BRIEFING
   └─> Adicionar resultados das pesquisas ao briefing

5️⃣ PROVA DE FOGO 🔥
   └─> "Destrua sua ideia"
   └─> Ponto cegos, SWOT, validações
   └─> O que NÃO faz sentido? Onde estou viajando?

6️⃣ ENRIQUECER DE NOVO
   └─> Ajustar briefing com insights da prova de fogo

7️⃣ DOCUMENTAÇÃO MODULARIZADA (Doc Specs)
   └─> NÃO fazer PRD gigante de uma vez!
   └─> Quebrar em mini-specs multidimensionais:
       • Doc Spec: UI/UX
       • Doc Spec: Filosofia/Conceito
       • Doc Spec: Tech Stack (bibliotecas, APIs, integrações)
       • Doc Spec: Wireframes + Fluxos de usuário
       • Doc Spec: Features
       • Doc Spec: Design System

   🧠 POR QUÊ MODULARIZAR?
   - LLM tem 100% capacidade cognitiva num ciclo input→output
   - PRD gigante = prova de vestibular gigante = LLM cansada no final
   - Specs modulares = laser focus = 100% capacidade em cada spec

8️⃣ CONSOLIDAR PRD (Dentro do AIOS)
   └─> Jogar todas as specs pro AIOS
   └─> AIOS junta tudo e cria PRD final
   └─> PRD já vem modularizado por Épicos + Stories (metodologia AIOS)

9️⃣ DESENVOLVIMENTO (AIOS)
   └─> AIOS orquestra agentes (DevOps, QA, etc.)
   └─> Épicos = camadas do prédio (foundation, features, auth, etc.)
   └─> Stories = sprints dentro de cada épico
   └─> Tasks = ações atômicas dentro de cada story
```

**Ferramenta favorita do João:**
- **Architect Agent** (Google AI Studio)
  - Input: Briefing
  - Output: Sitemap completo, wireframes, estrutura de navegação, fluxos
  - Dá tangibilidade ANTES de começar a codar

---

#### **Q7: PRD precisa ser do projeto inteiro ou pode ser só pra feature?**
**Perguntado implicitamente durante explicação (00:43:20)

**Resposta (João):**

**AMBOS! Você pode:**

**Opção A - PRD do Zero:**
- Do zero até MVP
- Grandes épicos, muitas stories

**Opção B - PRD Incremental (Recomendado):**
- Produto já existe
- PRD só pra adicionar 3 novas telas + 3 features
- Épicos menores, menos stories

**Vantagens do incremental:**
- Menos pontos de conexão = menos chance de erro probabilístico
- LLMs são voláteis - quanto maior o processo, maior risco
- Agilidade - você valida e segue pro próximo

**Exemplo:**
1. PRD Foundation (setup, database, auth básico)
2. PRD Feature: Adicionar OAuth
   - 2 épicos, 3 stories → rápido, testado, pronto
3. PRD Feature: Adicionar sistema de notificações
   - 1 épico, 4 stories → deploy, valida, segue

**Metáfora:**
- Melhor fazer vários PRDs pequenos (mini-mansões) do que um PRD gigante ("construir Google novo")

---

#### **Q8: Fluxo recomendado depois do PRD?**
**Compartilhado por:** Torriani (01:03:06)

**Resposta (aprendida na sala avançada):**

```
PRD pronto
   ↓
Project Manager (@pm)
   ├─> Criar épicos
   ↓
Product Owner (@po)
   ├─> Executar checklist de validação
   ↓
Scrum Master (@sm)
   ├─> Refinar histórias (stories)
   ↓
Product Owner (@po)
   ├─> Validar tudo de novo
   ↓
Developer (@dev)
   └─> Implementar
```

**Dica de Torriani:**
- Ter uma janela do `@aios-master` aberta só pra perguntas
- Outra janela pro desenvolvimento
- Perguntar TUDO pro master - ele ensina o processo

---

### 3️⃣ CASOS DE USO E NEGÓCIOS

#### **Q9: Como você está aplicando AIOS em clientes reais?**
**Perguntado implicitamente por:** Cristiano (discussão 00:07:00+)

**Caso 1 - Consultoria Jurídica Empresarial:**

**Problema:**
- Cliente com 30-50+ clientes (triplicou nos últimos anos)
- Não consegue dar qualidade de atendimento
- Processos empíricos dependentes dos sócios
- Quando tiram o olho da operação → processos se perdem
- Gargalos em várias áreas (financeiro, jurídico, RH, processos)

**Solução proposta:**
- Criar sistemas com AIOS para consistência operacional
- Identificar gargalos que impedem escala
- Implantar IA nos processos do cliente

**Desafio cultural:**
- "Time que tá ganhando não se mexe" (mentalidade do cliente)
- Funcionários usando IA errado (delegando decisões em vez de agilizar processos)
- Respostas rasas porque estão sendo preguiçosos
- **Desafio:** Quebrar barreira do ranço com IA criado por mal uso

---

**Caso 2 - Saúde Masculina (Urologia):**

**Problema:**
- Homem historicamente não cuida da saúde
- Barreira cultural pra falar sobre saúde masculina/urologia
- Atendimento episódico vs. acompanhamento contínuo
- Pessoas não querem falar com humano sobre certas coisas

**Oportunidades com IA:**
- Agilizar triagem e diagnóstico inicial
- Uso de IA para robótica médica (hospitais/universidades já fazem)
- **Destaque:** IA como primeiro atendimento anônimo
  - Pessoas preferem falar com IA do que com médico sobre certos assuntos
  - Reduz vergonha/embaraço
- Acompanhamento contínuo (ex: reação alérgica à meia-noite → CS da IA responde)

**Desafio:**
- Solução tem potencial MAS quadramento (monetização) é complexo
- Precisa minerar mais pra entender onde encaixa no processo
- Não é episódico (consulta única) - é acompanhamento
- Mais tempo pra desenvolver vs. soluções rápidas

---

#### **Q10: Estou desenvolvendo disparador de WhatsApp (Evolution API)**
**Compartilhado por:** Zé Carlos (discussão inicial, 00:00:57+)

**Contexto:**
- Criando disparador com Evolution API (WhatsApp não-oficial)
- Stack: Evolution API + Cloud Code + AIOS

**Processo:**
1. Pegou documentação completa da Evolution API
2. Jogou no Cloud Code pra entender todos os endpoints
3. Cloud Code construiu tudo
4. Refatorou com Cloud Code + AIOS (segurança, best practices)

**Features implementadas:**
- Criar instância
- Vincular proxy da instância
- Vincular webhook
- Vincular eventos
- Processar grupos
- Gerar QR Code (base64 → imagem)

**Desafio atual:**
- WhatsApp normal bloqueando muito
- Solução: **Co-existência de 5 instâncias por cliente**
- Sistema alterna entre números automaticamente
  - 5 mensagens do número 1
  - 5 mensagens do número 2
  - Rotação manual pra não conversar sempre com mesmo número
- Evita bloqueio

**Dica (Zé + Talles):**
- Começar pela **Evolution API** (não-oficial) pra aprender
- API Oficial do WhatsApp (Meta Business) é muito burocrática:
  - Cliente precisa aprovar várias coisas
  - Você tem que pegar na mão do cliente
  - Pessoas cobram só pra fazer cadastro na Meta
  - Quem gira muito tráfego sofre com Meta Business

---

#### **Q11: Integração com Meta Ads - como conectar campanhas?**
**Perguntado por:** Davidson (00:13:01)

**Contexto:**
- Quer puxar custo por lead, ROAS de campanha em tempo real
- Análise de lead na hora que chega
- Tudo funcionando, **falta conectar com Meta Ads**

**Resposta (João + Zé):**
**Caminho oficial (ÚNICO recomendado):**
1. Criar aplicativo no Facebook Developers
2. Solicitar permissões da API de Ads
3. Aguardar liberação da Meta (aprovações, autenticações)
4. Implementar OAuth + tokens

**Via não-oficial (Instagram/Facebook):**
- ❌ **NÃO RECOMENDADO**
- Meta coloca flag na conta
- Pode banir pra sempre
- Nunca mais consegue fazer nada

**Resposta:**
- Não tem caminho mais rápido
- Tem que seguir processo burocrático oficial
- Enquanto isso: trabalhar no resto da solução

---

### 4️⃣ FERRAMENTAS E CONFIGURAÇÃO

#### **Q12: Diferença entre IDE e Cloud Code?**
**Perguntado por:** Monica (00:49:48)

**Contexto da confusão:**
- Cloud AI Studio recomendou "IDE: Cloud Code"
- Monica achou que eram a mesma coisa

**Resposta (João - analogia perfeita):**

**IDE = Obsidian do código**
- Ambiente visual pra ver arquivos, pastas, código
- Exemplos: Cursor, AntiGravity, VSCode, Windsurf
- Só muda a plataforma, conceito é o mesmo
- Como usar Obsidian vs. Notion vs. Evernote pra notas

**Cloud Code = Motor de IA conectado ao terminal**
- Roda dentro do terminal (pode ser dentro da IDE ou terminal puro)
- É o cérebro que conversa com você
- Não é uma IDE - é uma ferramenta

**Analogia:**
```
Obsidian (IDE)  ←→  Cursor/AntiGravity/VSCode (IDE)
   ↓                       ↓
Visualizar notas    Visualizar código
```

**Preferência do João:**
- Usa IDE (AntiGravity) **MAS** roda Cloud Code no terminal dentro da IDE
- Vantagens:
  - Visualização de pastas
  - Controle de versionamento (git)
  - Ver o que tá sendo editado
  - Terminal integrado rodando Cloud Code

**Preferência do Alan:**
- Terminal puro (prompt de comando)
- Sem IDE, sem interface visual
- Mais leve, mas menos visual

**Quando usar terminal puro (sem IDE)?**
- Quando rodar 4+ terminais simultâneos
- IDE começa a sobrecarregar
- Poluição visual com muitos terminais
- Terminal puro é infinitamente escalável (20+ tabs sem travar)

**Dica pra iniciantes:**
- Começar com IDE + terminal integrado
- Melhor visualização, mais fácil se achar
- Depois migrar pra terminal puro se quiser escalar

---

#### **Q13: Como usar Deep Serve + Cloud para pesquisa de mercado?**
**Perguntado por:** Marcos (00:15:51)

**Resposta (Marcos compartilhando descoberta):**

**Processo:**
1. Abrir Cloud AI Studio (ou Google AI Studio)
2. Fazer pesquisa de mercado:
   - "Pesquise sobre [seu nicho/produto]"
   - Busca na internet inteira
   - Retorna contexto rico
3. Estruturar projeto:
   - "Com base nessa pesquisa, estruture um projeto para implementar X usando AIOS"
   - Output: Plano de projeto estruturado
4. Jogar resultado pro AIOS pra criar PRD

**Por que funciona:**
- Deep Serve procura em toda internet
- Traz gaps (lacunas) que você não pensou
- Identifica concorrentes
- Sugere tech stack (bibliotecas que você nem conhecia)
- Direcionamento de features

**Marcos:** "Tá dando muito certo aqui pra mim"

---

#### **Q14: Como trabalhar com múltiplas janelas Cloud Code?**
**Perguntado implicitamente, respondido por:** Torriani (01:04:19)

**Setup recomendado:**

**Janela 1 - AIOS Master (Perguntas):**
- Terminal aberto só com `@aios-master`
- Usar pra fazer TODAS as perguntas
- "Como faço X?", "O que é Y?", "Qual próximo passo?"
- Ele ensina tudo

**Janela 2 - Desenvolvimento:**
- Terminal do projeto
- Onde você roda agentes (@dev, @po, @sm, etc.)
- Onde acontece o trabalho

**Vantagens:**
- Contextos separados
- Histórico de perguntas não polui histórico de dev
- AIOS Master vira seu mentor pessoal

---

### 5️⃣ MINDSET E BOAS PRÁTICAS

#### **Q15: Como não ficar preso esperando próxima versão do Squad Creator?**
**Discussão geral** (01:01:00+)

**Problema:**
- Alan lança versões novas constantemente
- Alunos ficam esperando próxima versão
- Nunca começam de verdade

**Resposta (João):**

**80/20 do aprendizado:**
- Não é dominar ferramentas
- Não é acompanhar todas atualizações do Alan
- É dominar o **PROCESSO**
  - Como tudo se conecta
  - Como tudo se amarra
  - Lógica por trás
  - Motor do sistema

**Por quê Alan lança tantas versões?**
- Ele tá num nível avançado
- Precisa de funcionalidades que você ainda não precisa
- Se você não sente necessidade de atualização → versão atual serve perfeitamente

**Conselho:**
1. Pegue versão atual do Squad Creator
2. Salve numa pasta
3. **COMECE A DESENVOLVER**
4. Se bloquear, atualiza
5. Se não bloquear, segue com o que tem

**Metáfora:**
- Se você ficar na sombra do Alan esperando próxima novidade...
- Nunca vai materializar nada
- Vai ficar eternamente na ideação

---

#### **Q16: Não saia perfeito na primeira vez - e agora?**
**Discussão** (Torriani + João, 01:00:33)

**Resposta:**
- **FAZ DE NOVO**
- Não importa o app que vai sair
- O que importa é dominar o processo
- Conhecimento empírico > conhecimento teórico

**Torriani:**
- "Fiz tudo no Cloud, achei que nunca ia conseguir no Cloud Code"
- "Hoje tá tudo no Cloud Code, não quero nem olhar pro Cloud"
- **Progresso incremental:** Hoje melhor que ontem

**Conselho (Torriani):**
- Não tenha medo de começar do zero de novo
- Pegue processo que João ensinou
- Crie qualquer coisa (lista de tarefas, organizador de notas)
- Teste o processo
- Vai aprender FAZENDO

**João:**
- Não existe conhecimento mais valioso que conhecimento empírico
- Campo de batalha (skin in the game)
- 80/20: Colocar mão na massa

---

## 📚 FRAMEWORKS E METODOLOGIAS MENCIONADOS

### AIOS Workflow (Metodologia)
```
PRD
 └─> Épicos (camadas do prédio)
      └─> Stories (sprints)
           └─> Tasks (ações atômicas)
```

### Doc Specs Multidimensionais (João)
- UI/UX Spec
- Tech Spec (stack, bibliotecas, APIs)
- Wireframes & Fluxos Spec
- Features Spec
- Philosophy/Concept Spec
- Design System Spec

### Prova de Fogo (Validação)
1. Sessão de descarrego
2. Transformar em briefing
3. Pesquisas (mercado + tech)
4. Enriquecer briefing
5. **PROVA DE FOGO:** Destrua sua ideia
6. Enriquecer de novo com ajustes

---

## 🔧 FERRAMENTAS CITADAS

| Ferramenta | Uso |
|------------|-----|
| **Evolution API** | WhatsApp não-oficial (Zé Carlos) |
| **Cloud Code** | Motor IA no terminal |
| **AIOS** | Framework orquestração de agentes |
| **Google AI Studio** | Pesquisa de mercado + agente Architect |
| **Deep Serve** | Pesquisa de mercado profunda |
| **Perplexity** | Pesquisa na web |
| **Cursor / AntiGravity / VSCode** | IDEs para desenvolvimento |
| **Meta Business API** | WhatsApp/Instagram oficial |
| **Obsidian** | Gerenciamento de notas |

---

## 🎓 PRINCIPAIS APRENDIZADOS

### Para iniciantes:
1. ✅ **Use IDE com terminal integrado** (não comece direto no terminal puro)
2. ✅ **CloudMD por projeto** (não tente fazer global/frankenstein)
3. ✅ **Comece com projeto simples** (lista de tarefas, organizador)
4. ✅ **Duas janelas:** Master (perguntas) + Dev (trabalho)
5. ✅ **Não espere próxima versão** - comece com o que tem

### Para intermediários:
1. ✅ **Modularize PRD em specs** (UI, tech, features separados)
2. ✅ **PRDs incrementais** (feature por feature) > PRD gigante
3. ✅ **Sessão de descarrego + pesquisas** antes de entrar no AIOS
4. ✅ **Prova de fogo** sempre (destrua sua ideia)
5. ✅ **Workspace + projetos** (estrutura organizada)

### Para avançados:
1. ✅ **Terminal puro** quando rodar 4+ agentes simultâneos
2. ✅ **Agents customizados** em pastas separadas (marketing/, mentes-clonadas/)
3. ✅ **Architect agent** (Google AI) pra wireframes antes de codar
4. ✅ **Copiar AIOS infra** entre projetos (exceto CLAUDE.md)
5. ✅ **Rotação de instâncias** (WhatsApp - evitar bloqueio)

---

## 💬 CITAÇÕES MEMORÁVEIS

> **"Se você ficar esperando a próxima versão do Alan, vai ficar pra sempre na sombra dele e nunca vai materializar nada."**
> — João

> **"LLM fazendo PRD inteiro é igual você no final da prova de vestibular - não consegue nem ler a pergunta direito."**
> — João

> **"80/20 não é dominar ferramenta, é dominar o PROCESSO. A ferramenta vai evoluir, o processo fica."**
> — João

> **"Não existe conhecimento mais valioso que o conhecimento empírico - campo de batalha, skin in the game."**
> — João

> **"Fiz tudo no Cloud, achei que nunca ia conseguir no Cloud Code. Hoje não quero nem olhar pro Cloud."**
> — Torriani

> **"Não tenha medo de começar do zero. Cria qualquer coisa - lista de tarefas, qualquer coisa. Você vai aprender fazendo."**
> — Torriani

> **"CloudMD é o cérebro do sistema. Se você colocar cérebro frankenstein que não tem aqueles arquivos, aquelas pastas - vai quebrar."**
> — João

---

## 📊 ANÁLISE DE SENTIMENTO

### 😊 Pontos Positivos (Elogios)
- Explicação do João sobre workflow foi "incrível", "fantástica"
- Torriani compartilhou evolução pessoal ("hoje tô melhor que ontem")
- Marcos compartilhou descoberta do Deep Serve com sucesso
- Comunidade ajudando uns aos outros nas salas simultâneas
- Processo de aprendizado empírico funcionando

### ⚠️ Pontos de Atenção (Reclamações/Dificuldades)
- Confusão entre IDE vs Cloud Code (Monica)
- Ansiedade com atualizações constantes do Squad Creator
- Dificuldade pra entender estrutura de pastas (Fábio, Alexandre)
- Meta Business API muito burocrática (Davidson)
- Bloqueios de WhatsApp normal (Zé Carlos)
- Ranço com IA em cliente jurídico (uso errado dos funcionários)

---

## 🔗 RECURSOS COMPARTILHADOS

- **Squad Creator** (versão 5-2-26): GitHub + grupo WhatsApp
- **Evolution API**: Documentação completa (Zé Carlos usou)
- **Architect Agent**: Google AI Studio (João usa pra wireframes)
- **Processo de workflow**: Diagrama desenhado por João (screenshot compartilhado)

---

## 🎯 PRÓXIMOS PASSOS (Mencionados)

1. **Amanhã (11/02):** Aula do Alan (preparar-se para "rajada")
2. **Sexta-feira (14/02):** Próximo PS
3. **Ações recomendadas:**
   - Implementar projeto simples usando workflow ensinado
   - Testar separação workspace + projetos
   - Configurar 2 janelas (Master + Dev)
   - Praticar modularização de specs

---

**Análise gerada por:** Academia Lendária
**Ferramentas utilizadas:** AIOS Lesson Analysis Squad
**Formato:** Pronto Socorro (Q&A)
