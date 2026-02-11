# Lista Completa: Perguntas → Respostas | PS 10/02/2026

> Formato enxuto para referência rápida

---

## SETUP E CONFIGURAÇÃO

**P1:** Qual a última versão do Squad Creator? Onde está?
**R:** GitHub oficial + grupo WhatsApp. Versão: 5-2-26.

**P2:** Copiar pasta AIOS ou instalar do zero em projeto novo?
**R:** Ambos funcionam. Copiar: toda infraestrutura EXCETO CLAUDE.md. Instalar: `claude init` + `aios install`.

**P3:** Como atualizar AIOS em todos os projetos?
**R:** Rodar `aios install` em cada repositório/pasta.

**P4:** CloudMD por projeto ou global?
**R:** Por projeto. CloudMD global = frankenstein (quebra contexto).

**P5:** Como organizar workspace vs projetos?
**R:** Workspace master na raiz + projetos individuais com AIOS próprio. Cada um com seu CLAUDE.md.

**P6:** Pastas auxiliares (agentes customizados) - onde ficam?
**R:** Fora do workspace (ex: ~/marketing/, ~/mentes-clonadas/). Copiar pra dentro do projeto quando precisar.

---

## WORKFLOW DE DESENVOLVIMENTO

**P7:** Fazer tudo fora do AIOS e trazer depois?
**R:** Sim (preferência do João):
1. Sessão descarrego (áudio/call)
2. Transformar em briefing
3. Pesquisas (mercado + tech)
4. Enriquecer briefing
5. Prova de fogo (destrua ideia)
6. Enriquecer novamente
7. Doc specs modularizadas (UI, tech, wireframes, features)
8. AIOS consolida PRD

**P8:** PRD inteiro ou só feature?
**R:** Ambos. Incremental (feature por feature) é melhor que PRD gigante.

**P9:** Fluxo recomendado depois do PRD?
**R:** PM → PO → checklist → SM → PO valida → Dev implementa.

**P10:** Por que modularizar specs ao invés de PRD gigante de uma vez?
**R:** LLM tem 100% capacidade num ciclo. PRD gigante = prova de vestibular gigante = cansaço no final. Specs modulares = laser focus = qualidade.

**P11:** Como validar ideia antes de codar?
**R:** Prova de fogo - "Destrua sua ideia". Ponto cego, SWOT, o que NÃO faz sentido.

---

## CASOS DE USO / NEGÓCIOS

**P12:** Como aplicar AIOS em consultoria jurídica?
**R:** Cliente com 30-50+ clientes, não escala. AIOS pra criar sistemas de consistência operacional, identificar gargalos. Desafio: ranço com IA (funcionários usaram errado).

**P13:** Como aplicar AIOS em saúde masculina (urologia)?
**R:** IA como primeiro atendimento anônimo (reduz vergonha), acompanhamento contínuo, CS da IA 24/7. Desafio: quadramento (monetização) complexo, precisa minerar mais.

**P14:** Disparador WhatsApp - como fazer?
**R:** Evolution API (não-oficial). Pegar documentação → jogar no Cloud Code → construir tudo. Desafio atual: bloqueios. Solução: rotação entre 5 instâncias.

**P15:** WhatsApp: Evolution API ou Meta Business API?
**R:** Começar Evolution (simples). Meta Business é burocrático (cliente precisa aprovar várias coisas, você pega na mão).

**P16:** Como conectar com Meta Ads (campanhas, ROAS)?
**R:** Via oficial (aplicativo Facebook Developers, solicitar permissões, aguardar aprovação). Via não-oficial = ban permanente.

---

## FERRAMENTAS

**P17:** Diferença entre IDE e Cloud Code?
**R:** IDE = Obsidian do código (visualizar arquivos). Cloud Code = motor IA no terminal. São coisas diferentes.

**P18:** IDE ou terminal puro?
**R:** Iniciantes: IDE + terminal integrado. Avançados rodando 4+ terminais: terminal puro (mais leve, escalável).

**P19:** Como usar Deep Serve pra pesquisa de mercado?
**R:** Cloud AI Studio → pesquisa de mercado → estruturar projeto → jogar pro AIOS. Traz gaps, concorrentes, tech stack.

**P20:** Como trabalhar com múltiplas janelas Cloud Code?
**R:** Janela 1: @aios-master (só perguntas). Janela 2: projeto (desenvolvimento). Contextos separados.

**P21:** Architect Agent - o que é?
**R:** Agente do João (Google AI Studio). Input: briefing. Output: sitemap, wireframes, estrutura navegação, fluxos. Dá tangibilidade antes de codar.

---

## MINDSET E PRÁTICAS

**P22:** Como não ficar preso esperando próxima versão do Squad Creator?
**R:** Alan lança versões pra necessidades dele (nível avançado). Se você não sente necessidade → versão atual serve. 80/20 = dominar PROCESSO, não ferramenta.

**P23:** E se não sair perfeito na primeira vez?
**R:** Faz de novo. Conhecimento empírico > teórico. Progresso incremental (hoje melhor que ontem).

**P24:** Como começar se estou perdido?
**R:** Crie QUALQUER COISA simples (lista de tarefas, organizador de notas). Siga workflow do João. Teste processo. Aprende FAZENDO.

**P25:** Devo me preocupar com atualizações constantes?
**R:** Não. Se tá funcionando, não precisa atualizar. Atualiza só se bloquear.

**P26:** Quanto tempo ficar planejando antes de codar?
**R:** Não ficar eternamente. Fazer prova de fogo, validar, e IR PRA PRÁTICA. Senão fica só na ideação.

**P27:** Como saber se estou no caminho certo?
**R:** Pergunta pro @aios-master. Ele ensina tudo. Janela separada só pra perguntas.

**P28:** Qual o erro mais comum?
**R:** Ficar na teoria, não colocar mão na massa. Esperar tudo perfeito antes de começar. Comparar-se com Alan (ele tá 10 níveis à frente).

---

**Total de perguntas rastreadas:** 28
**Especialistas:** João (líder), Zé Carlos, Talles, equipe Academia Lendária
**Participantes que mais perguntaram:** Fábio, Alexandre, Monica, Torriani, Cristiano, Davidson, Marcos
