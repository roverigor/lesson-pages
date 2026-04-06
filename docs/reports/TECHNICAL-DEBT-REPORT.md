# Relatório de Débito Técnico — lesson-pages

**Projeto:** Academia Lendária — Plataforma Educacional (Cohort AIOS Avançado 2026)
**Data:** 06/04/2026 | **Versão:** 1.0
**Preparado por:** @analyst (Alex) — Brownfield Discovery Assessment

---

## Executive Summary

### Situação Atual

A plataforma lesson-pages sustenta o calendário de aulas, controle de presença, integração de videochamadas (Zoom) e comunicação com alunos via WhatsApp para a Academia Lendária. O sistema cumpre hoje todas as funções operacionais essenciais: alunos acessam o calendário público, mentores fazem login e gerenciam presenças, e notificações de aula são enviadas automaticamente com confirmação de entrega.

Nos últimos 30 dias, dois épicos foram entregues com sucesso: o sistema completo de notificações WhatsApp (EPIC-001) e o agendamento automático de notificações via pg_cron (EPIC-002). Adicionalmente, uma vulnerabilidade de segurança crítica foi corrigida (chave de serviço do Supabase removida do frontend) e as versões de CDN foram fixadas para evitar atualizações inesperadas. A plataforma está funcional e entregando valor real para os alunos.

A fragilidade principal está em dois pontos de risco imediato: credenciais de acesso ao Zoom e ao WhatsApp estão escritas diretamente no código-fonte. Qualquer pessoa com acesso ao repositório pode visualizá-las, e uma eventual exposição pode comprometer as integrações que sustentam a operação das aulas. Além disso, o sistema cresceu organicamente sem estrutura de testes nem organização de banco de dados, o que aumenta o risco de regressões silenciosas a cada nova funcionalidade adicionada.

### Números-Chave

| Métrica | Valor |
|---------|-------|
| Total de Débitos Identificados | 28 |
| Débitos Críticos (segurança) | 2 |
| Débitos Altos | 8 |
| Débitos Médios | 14 |
| Débitos Baixos | 4 |
| Esforço Total Estimado | ~103,5h |
| Custo Estimado de Resolução | R$ 15.525 |
| Débitos Resolvidos Recentemente | 5 |
| Épicos Entregues no Último Mês | 2 |

### Recomendação

**Esta semana:** mover as credenciais do Zoom e da Evolution API (WhatsApp) para variáveis de ambiente seguras — ação que leva menos de 3 horas e elimina o risco imediato de comprometimento. **Próximo mês:** documentar e versionar o banco de dados com as ferramentas corretas e adicionar testes básicos nos fluxos críticos, criando uma base sólida para crescimento sustentável. **Nos próximos 2 meses:** modularizar o painel administrativo e unificar o design, reduzindo em 40–50% o tempo necessário para implementar novas funcionalidades.

---

## Análise de Custos

### Custo de Resolver

| Fase | Foco | Horas | Custo (R$ 150/h) | O que entrega |
|------|------|-------|------------------|---------------|
| Fase 1 — Segurança | Credenciais + CORS + verificação de migration | ~8h | R$ 1.200 | Eliminação do risco de comprometimento das integrações |
| Fase 2 — Fundação DB | Schema documentado, migrations versionadas, testes | ~30h | R$ 4.500 | Base sólida para manutenção e desenvolvimento seguro |
| Fase 3 — Frontend e UX | Admin modular, design system, feedback visual | ~65h | R$ 9.750 | 40–50% de ganho de velocidade em novas features |
| **TOTAL** | | **~103h** | **R$ 15.525** | **Sistema robusto, seguro e escalável** |

### Custo de Não Resolver

| Risco | Probabilidade | Impacto Potencial |
|-------|---------------|-------------------|
| Credenciais Zoom ou WhatsApp expostas e utilizadas indevidamente | Média (repositório acessível a colaboradores) | Perda de acesso às integrações, possível interrupção das aulas |
| Bug silencioso em produção sem detecção | Alta (zero testes existentes) | Retrabalho crescente a cada funcionalidade nova, tempo perdido em debugging |
| Painel administrativo parando de funcionar | Média (crescimento natural do código) | 40–80h de debugging em arquivo de 2.844 linhas sem separação de responsabilidades |
| Abstracts de aula desatualizados para alunos | Alta (edição manual de HTML a cada turma nova) | Risco de informação errada chegando aos alunos |

---

## Impacto no Negócio

### Segurança

Dois pares de credenciais estão escritos diretamente no código-fonte: as chaves de acesso ao Zoom (que controla o ingresso nas videochamadas das aulas) e as credenciais da Evolution API (que dispara os WhatsApps para os alunos). Qualquer pessoa com acesso ao repositório — hoje ou no futuro — pode visualizar esses dados. A correção é simples e rápida; o risco de não corrigir é a interrupção das integrações que sustentam a operação das aulas.

### Velocidade de Desenvolvimento

O painel administrativo é um arquivo único de 2.844 linhas com HTML, CSS e JavaScript misturados. Adicionar uma nova funcionalidade exige navegar por esse arquivo inteiro, entendendo o contexto de cada trecho antes de qualquer mudança. Após a modularização planejada, a estimativa é de 40–50% de redução no tempo de implementação de novas features.

### Escalabilidade

Os textos de apresentação das aulas (abstracts) estão escritos diretamente no HTML. Cada nova turma da Academia Lendária requer edição manual do código-fonte. Com a migração para banco de dados, qualquer membro da equipe pode atualizar o conteúdo pelo próprio painel administrativo, em minutos, sem tocar em código.

### Qualidade

O sistema não possui nenhum teste automatizado. Cada deploy é feito sem rede de proteção: uma mudança de código pode quebrar o calendário público, o envio de WhatsApp ou o controle de presença sem que o problema seja detectado antes de chegar aos alunos. Com smoke tests básicos nos fluxos críticos, regressões seriam detectadas automaticamente antes de qualquer publicação.

---

## Timeline Recomendado

### Fase 1 — Segurança (Esta Semana, ~8h)

**Objetivo:** eliminar os riscos imediatos sem interromper o funcionamento atual.

- Mover credenciais Zoom (client_id, secret, account_id, S2S credentials) para Supabase Secrets
- Mover credenciais Evolution API (URL, API key, instância) para Supabase Secrets
- Restringir CORS nas Edge Functions para domínios conhecidos (calendario.igorrover.com.br, lesson-pages.vercel.app)
- Verificar aplicação da migration de confirmação de entrega em produção

**Custo: R$ 1.200** | Resultado: risco de comprometimento eliminado

### Fase 2 — Fundação (2–4 Semanas, ~30h)

**Objetivo:** criar a estrutura que permite crescimento seguro e manutenção confiável.

- Documentar o esquema completo da tabela `classes` com as ferramentas oficiais do Supabase
- Converter todos os scripts SQL avulsos em migrations versionadas
- Implementar smoke tests para os 3 fluxos críticos: envio de WhatsApp, calendário público e login do admin
- Adicionar verificação automática de qualidade de código (linting)
- Adicionar feedback visual para ações críticas no painel (ex.: confirmação de envio de WhatsApp)

**Custo: R$ 4.500** | Resultado: base sólida para desenvolvimento sustentável

### Fase 3 — UX e Manutenibilidade (4–8 Semanas, ~65h)

**Objetivo:** transformar o sistema em uma plataforma ágil para o crescimento da Academia.

- Modularizar o painel administrativo (separar em arquivos por funcionalidade)
- Unificar o design com tokens CSS consistentes em todas as páginas
- Migrar abstracts de aula do HTML estático para banco de dados gerenciável pelo admin
- Garantir responsividade completa em dispositivos móveis

**Custo: R$ 9.750** | Resultado: 40–50% de ganho de velocidade em novas entregas

---

## ROI da Resolução

| Investimento | Prazo | Retorno Esperado |
|---|---|---|
| R$ 1.200 (Fase 1) | 1 semana | Eliminação do risco de perda de acesso ao Zoom e WhatsApp |
| R$ 4.500 (Fase 2) | 1 mês | Desenvolvimento sustentável, zero regressões silenciosas em produção |
| R$ 9.750 (Fase 3) | 2 meses | 40–50% mais velocidade na entrega de novas funcionalidades |
| **R$ 15.525 total** | **~3 meses** | **Sistema robusto, seguro e pronto para escalar para novas turmas** |

O investimento total de R$ 15.525 se paga na primeira turma onde uma regressão silenciosa seria evitada ou no primeiro novo épico que seria implementado em metade do tempo com a base modularizada.

---

## Próximos Passos Imediatos

1. [ ] **Esta semana:** Mover credenciais Zoom (`ZOOM_CLIENT_ID`, `ZOOM_CLIENT_SECRET`, `ZOOM_ACCOUNT_ID`, `ZOOM_CLIENT_SECRET_S2S`) para Supabase Secrets
2. [ ] **Esta semana:** Mover Evolution API (`EVOLUTION_API_URL`, `EVOLUTION_API_KEY`, `EVOLUTION_INSTANCE`) para Supabase Secrets
3. [ ] **Esta semana:** Verificar via `supabase migration list` que a migration `20260402200000_delivery_status.sql` foi aplicada em produção
4. [ ] **Próxima sprint:** Criar EPIC-003 (Segurança e DB Hardening) com stories para credenciais, CORS, schema `classes` e migrations CLI
5. [ ] **Próxima sprint:** Criar EPIC-004 (Qualidade e UX) com stories para testes, linting, feedback visual e modularização do admin

---

## Anexos Técnicos

- `docs/architecture/system-architecture.md` — Arquitetura completa do sistema v2.0
- `docs/prd/technical-debt-assessment.md` — Assessment técnico detalhado com todos os 28 débitos
- `supabase/docs/DB-AUDIT.md` — Auditoria completa do banco de dados
- `docs/reviews/` — Reviews por especialista (DB, UX, QA)

---

*Relatório gerado como parte do processo de Brownfield Discovery — AIOX Framework v2.0*
*@analyst (Alex) | Synkra AIOX | 06/04/2026*
