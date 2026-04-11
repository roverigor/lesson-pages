# Guia: Configurar WhatsApp Cloud API (Oficial Meta) no Chatwoot

> Este guia te leva do zero até ter um segundo número de WhatsApp integrado ao Chatwoot usando a API oficial da Meta.

---

## Pré-requisitos

- Uma conta pessoal no Facebook
- Um número de telefone **novo** (que NÃO esteja registrado no WhatsApp normal)
- Acesso ao Chatwoot: https://chat.igorrover.com.br

---

## Etapa 1: Criar conta no Meta Business Suite

1. Acesse **[business.facebook.com](https://business.facebook.com)**
2. Clique em **"Criar conta"**
3. Preencha:
   - **Nome da empresa:** Academia Lendária (ou o nome que preferir)
   - **Seu nome**
   - **Email comercial**
4. Confirme o email recebido
5. Pronto — sua conta Meta Business está criada

---

## Etapa 2: Criar um App no Meta for Developers

1. Acesse **[developers.facebook.com/apps](https://developers.facebook.com/apps)**
2. Clique em **"Criar app"**
3. Selecione **"Empresa"** como tipo de app
4. Preencha:
   - **Nome do app:** `Chatwoot WhatsApp` (ou qualquer nome)
   - **Email de contato do app:** seu email
   - **Conta comercial:** selecione a conta criada na Etapa 1
5. Clique em **"Criar app"**

---

## Etapa 3: Adicionar o produto WhatsApp ao App

1. No painel do app, vá em **"Adicionar produtos"**
2. Encontre **"WhatsApp"** e clique em **"Configurar"**
3. Na tela de configuração do WhatsApp, você verá:
   - **Número de telefone de teste** (temporário, fornecido pela Meta)
   - **Token de acesso temporário** (expira em 24h)
4. **IMPORTANTE:** Anote o **Phone Number ID** e o **WhatsApp Business Account ID** que aparecem nessa tela

---

## Etapa 4: Adicionar seu número de telefone real

1. No menu lateral, vá em **WhatsApp → Configuração da API → Números de telefone**
2. Clique em **"Adicionar número de telefone"**
3. Insira:
   - **Nome de exibição:** o nome que os clientes verão (ex: "Academia Lendária")
   - **Número de telefone:** seu número novo com DDI+DDD (ex: +55 43 99999-9999)
4. Escolha receber o código de verificação por **SMS** ou **ligação**
5. Insira o código recebido
6. Pronto — número verificado!

> **Atenção:** O número NÃO pode estar conectado ao WhatsApp normal ou WhatsApp Business app. Desconecte antes.

---

## Etapa 5: Gerar Token de Acesso Permanente

O token temporário expira em 24h. Para produção, você precisa de um **token permanente (System User Token)**.

### Criar System User:

1. Vá em **[business.facebook.com/settings/system-users](https://business.facebook.com/settings/system-users)**
2. Clique em **"Adicionar"**
3. Preencha:
   - **Nome:** `chatwoot-bot`
   - **Função:** Administrador
4. Clique em **"Criar System User"**

### Gerar Token:

1. Clique no system user `chatwoot-bot`
2. Clique em **"Gerar token"**
3. Selecione o app criado na Etapa 2
4. Marque as permissões:
   - `whatsapp_business_management`
   - `whatsapp_business_messaging`
5. Clique em **"Gerar token"**
6. **COPIE E SALVE** o token em lugar seguro — ele só aparece uma vez!

### Vincular assets ao System User:

1. Na página do system user, clique em **"Atribuir ativos"**
2. Selecione **Apps → seu app** → marque **"Gerenciar app"**
3. Selecione **WhatsApp Accounts → sua conta** → marque **"Gerenciar conta"**

---

## Etapa 6: Configurar Webhook no Meta

O Chatwoot precisa receber as mensagens que chegam no WhatsApp. Para isso:

1. No painel do app (developers.facebook.com), vá em **WhatsApp → Configuração**
2. Na seção **Webhook**, clique em **"Editar"**
3. Configure:
   - **URL de callback:** `https://chat.igorrover.com.br/webhooks/whatsapp`
   - **Token de verificação:** qualquer string segura (ex: `cw_webhook_verify_2026`)
4. Clique em **"Verificar e salvar"**
5. Na lista de campos do webhook, **assine (subscribe):**
   - `messages`
   - `message_template_status_update` (opcional)

> Se der erro na verificação, confirme que o Chatwoot está online e acessível publicamente.

---

## Etapa 7: Adicionar inbox no Chatwoot

1. Acesse **https://chat.igorrover.com.br**
2. Faça login com suas credenciais
3. Vá em **Configurações → Caixas de entrada → Adicionar caixa de entrada**
4. Selecione **WhatsApp**
5. Escolha **"WhatsApp Cloud"** (não Twilio, não 360dialog)
6. Preencha:
   - **Número de telefone:** seu número com código do país (ex: `+554399999999`)
   - **Phone Number ID:** o ID do número (copiado da Etapa 3)
   - **Business Account ID:** o WhatsApp Business Account ID (copiado da Etapa 3)
   - **API Key:** o token permanente gerado na Etapa 5
7. Clique em **"Criar caixa de entrada"**
8. Adicione agentes à caixa de entrada

---

## Etapa 8: Configurar Webhook URL no Chatwoot

Após criar o inbox, o Chatwoot gera uma **Webhook URL específica**. Você precisa atualizar isso no Meta:

1. No Chatwoot, vá em **Configurações → Caixas de entrada → WhatsApp Cloud → Configurações**
2. Copie a **Webhook URL** exibida
3. Volte ao **developers.facebook.com → WhatsApp → Configuração → Webhook**
4. Atualize a URL de callback com a URL copiada do Chatwoot

---

## Etapa 9: Solicitar acesso de produção (obrigatório!)

Por padrão, o app começa em modo de desenvolvimento (só envia para números verificados).

1. No painel do app, vá em **Configurações do app → Básico**
2. Preencha todos os campos obrigatórios:
   - URL da política de privacidade (pode ser do seu site)
   - Ícone do app
   - Categoria
3. Vá em **Verificação de negócios** (se ainda não fez):
   - business.facebook.com → Configurações → Central de segurança → Verificação
   - Envie documentos da empresa (CNPJ, contrato social etc.)
4. Vá em **Acesso ao app → Avançado**
5. Alterne de **"Desenvolvimento"** para **"Publicado"**

> **Nota:** A verificação de negócios pode levar de 1 a 7 dias úteis.

---

## Custos

A API oficial do WhatsApp cobra por **conversa** (janela de 24h):

| Tipo de conversa | Custo (BRL, aprox.) |
|-------------------|---------------------|
| Marketing | ~R$ 0,50 |
| Utilidade | ~R$ 0,15 |
| Autenticação | ~R$ 0,15 |
| Serviço (resposta ao cliente) | Grátis (primeiras 1.000/mês) |

- As primeiras **1.000 conversas de serviço por mês são grátis**
- Conversas iniciadas pelo cliente (serviço) são mais baratas
- Preços atualizados: [developers.facebook.com/docs/whatsapp/pricing](https://developers.facebook.com/docs/whatsapp/pricing)

---

## Resumo de dados importantes

Após completar o guia, você terá:

| Dado | Onde usar |
|------|----------|
| **Phone Number ID** | Chatwoot inbox config |
| **Business Account ID** | Chatwoot inbox config |
| **System User Token** (permanente) | Chatwoot inbox config |
| **Webhook URL** | Meta Developer Console |
| **Verify Token** | Meta Developer Console |

---

## Troubleshooting

### "Webhook verification failed"
- Verifique se o Chatwoot está acessível via HTTPS
- Confirme que o verify token está correto nos dois lados

### "Unauthorized" ao testar
- Verifique se o system user tem as permissões corretas
- Verifique se os assets foram atribuídos ao system user

### Mensagens não chegam
- Confirme que o webhook está subscrito ao campo `messages`
- Verifique se o app está em modo **Publicado** (não Desenvolvimento)
- Teste enviando do número verificado primeiro

### Número rejeitado
- O número não pode estar em uso no WhatsApp app normal
- Desinstale o WhatsApp do celular com esse número antes de registrar na API

---

*Documento criado em 2026-04-11 — Referência para integração WhatsApp Cloud API + Chatwoot*
