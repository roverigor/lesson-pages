---
name: No WhatsApp dispatch without authorization
description: Never send WhatsApp messages or trigger dispatches without explicit user approval
type: feedback
---

Never trigger WhatsApp dispatches (send-whatsapp, Evolution API, absence alerts, etc.) without explicit user authorization.

**Why:** User explicitly said "não faça nenhum disparo sem autorização expressa" — dispatches reach real students/mentors and cannot be undone.

**How to apply:** Build dispatch UI with preview/confirmation step. Never call send endpoints automatically. Always show the list and wait for user to click "Enviar" or explicitly say to send.
