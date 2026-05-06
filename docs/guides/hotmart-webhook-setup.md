# Hotmart Webhook — Setup pra CS Team

**Status:** Pronto pra produção
**Endpoint:** `https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/hotmart-purchase-webhook`
**Auth:** API key (Header `X-API-Key`)
**Template Meta:** `boas_vindas_aiox` (aprovado)

---

## 🔑 Credenciais (CS team — anotar)

```
Endpoint URL:   https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/hotmart-purchase-webhook
Source name:    Hotmart Production
Source slug:    hotmart
API Key:        src_ab54ddd5f872ab5dfac8e0dd425b64a835224ddd3d61cab8
```

⚠️ **API Key acima é mostrada apenas 1x neste doc.** Guarde em vault seguro.

---

## 📋 Passo-a-passo Hotmart Settings

### 1. Acesse Hotmart Producer
https://app.hotmart.com → Login → Sua conta produtor

### 2. Vá em Tools → Webhook (Postback)
Menu lateral: **Ferramentas → Webhook (URL Postback)**

### 3. Adicionar novo webhook
Clica **"+ Novo Postback"**

### 4. Preencher campos

| Campo | Valor |
|-------|-------|
| **Nome** | AIOX CS Onboarding |
| **URL** | `https://gpufcipkajppykmnmdeh.supabase.co/functions/v1/hotmart-purchase-webhook` |
| **Versão** | 2.0.0 |
| **Eventos** | ✅ Compra aprovada (PURCHASE_APPROVED)<br>✅ Compra completa (PURCHASE_COMPLETE) |
| **Status** | Ativo |

### 5. Headers customizados (CRÍTICO)

Hotmart permite headers extras. **Adicione:**

| Header | Valor |
|--------|-------|
| `X-API-Key` | `src_ab54ddd5f872ab5dfac8e0dd425b64a835224ddd3d61cab8` |

Sem esse header → webhook rejeita com HTTP 401.

### 6. Salvar

---

## 🗺️ Configurar Mappings (CS team — UI)

Pra cada produto Hotmart, configurar onde aluno deve ir:

1. Acessa https://painel.igorrover.com.br/cs/#/integrations
2. Sub-tab **"🔌 Mappings AC"**
3. Click **"+ Novo Mapping"**
4. Preencher:
   - **Produto AC** = ID do produto Hotmart (ex: `123456`)
   - **Cohort** = qual turma aluno vai entrar
   - **Survey** = qual formulário enviar (opcional)
   - **Template Meta** = `boas_vindas_aiox`

> Repetir pra cada produto Hotmart distinto.

---

## ✅ Como verificar se funciona

### Teste 1 — Webhook conexão
Hotmart Producer → seu Postback → "Testar postback"
Resultado esperado: HTTP 200 com `{"ok":true,"status":"queued"}`

### Teste 2 — Compra teste real
1. Faça compra teste (Hotmart sandbox OR produto barato)
2. Acessa `/cs/integrations` → sub-tab **"📋 Eventos AC"**
3. Deve aparecer evento com prefix `hotmart:` em até 30 segundos
4. Aluno cadastrado em `/cs/students` com email da compra
5. Mensagem WhatsApp boas-vindas chega no celular do comprador

### Teste 3 — Em caso de falha
- `/cs/dead-letter` mostra eventos failed com retry automático
- `/cs/audit-log` lista mudanças
- Slack alerts disparam pra severidade high

---

## 📨 Texto do template enviado

Ao receber compra Hotmart, aluno recebe via WhatsApp:

> *Olá [NOME]! 👋*
>
> *Seja muito bem-vindo(a) ao AIOX!*
>
> *Sua compra foi confirmada com sucesso. Em breve você receberá:*
> - *Acesso à plataforma de aulas*
> - *Calendário das próximas turmas*
> - *Suporte do nosso time CS*
>
> *Qualquer dúvida, fale com a gente!*

---

## 🔄 Outras integrações futuras

Mesmo padrão funciona pra outros gateways:
- Eduzz: criar source slug `eduzz` + edge function `eduzz-purchase-webhook` (TODO)
- Kiwify: idem
- Custom CRM: usar `generic-purchase-webhook` (já deployed) com schema próprio

---

## 🆘 Troubleshooting

| Erro | Causa | Fix |
|------|-------|-----|
| HTTP 401 "X-API-Key header required" | Header faltando OU key errada | Verificar header config Hotmart |
| HTTP 400 "invalid buyer.email" | Hotmart não enviou email | Configurar checkout Hotmart pra capturar email obrigatório |
| HTTP 400 "data.product.id required" | Produto sem ID | Erro Hotmart payload — abrir suporte |
| Evento `ignored` | Status compra não é APPROVED/COMPLETE | Normal — apenas vendas confirmadas processam |
| Aluno não recebe WhatsApp | Mapping não configurado OR template não aprovado | Verificar `/cs/integrations` mappings |

---

## 📊 Métricas operacionais

CS team pode acompanhar em:
- **`/cs/dashboard`** — KPIs gerais
- **`/cs/integrations` → "🌐 Sources"** — webhook count per source
- **`/cs/dead-letter`** — falhas com retry
- **`/cs/audit-log`** — quem mudou o que

---

**Suporte técnico:** dev@academialendaria.ai
