# Story NPS.T.1 — Submit 3 Meta DM Templates for Approval

**Epic:** EPIC-NPS-DISPATCH
**Status:** Ready
**Type:** External / Meta Business Manager
**Wave:** 2 (gates DM activation, parallel to Chapter D fixes)
**Estimated:** 2h trabalho + 24-48h Meta approval (S+wait)
**Primary Agent:** @pm (drafting copy) + @devops (Meta submission)
**Severity:** HIGH — sem isso, DM dispatch nunca funciona

## O que fazer

Submeter 3 templates pra Meta Business Manager (cada um corresponde a uma variant DM no router):

- `nps_post_class_v1`
- `nps_post_class_v2`
- `nps_post_class_v3`

Estrutura comum: `{{1}}` = first_name, `{{2}}` = class_name. Button URL com `{{1}}` = token (link `painel.academialendaria.ai/survey/aluno/{{1}}`).

## Drafts iniciais (variant copy)

### v1 — formal, agradecimento

```
Body:
Olá {{1}}! 👋

Obrigado por estar conosco em {{2}} hoje. Sua opinião nos ajuda a evoluir.

Pode dar uma nota rápida (1-2 min)? Anônimo se preferir.

Button (URL): "Avaliar aula"
URL: https://painel.academialendaria.ai/survey/aluno/{{1}}
```

### v2 — casual, energético

```
Body:
{{1}}, fechamos {{2}} agora! 🚀

Sua nota direciona os próximos encontros. Leva 30s:

Button (URL): "Dar nota"
URL: https://painel.academialendaria.ai/survey/aluno/{{1}}
```

### v3 — direto, comunidade

```
Body:
{{1}}, valeu pela presença em {{2}}!

Avalia rapidinho pra gente acertar cada vez mais:

Button (URL): "Avaliar"
URL: https://painel.academialendaria.ai/survey/aluno/{{1}}
```

## Acceptance Criteria

### Bloco A — Submission

- [ ] **AC-1:** 3 templates submetidos via Meta Business Manager (ou via edge function `create-meta-template` se ainda funcional).
- [ ] **AC-2:** Cada template: language=`pt_BR`, category=`UTILITY` (não `MARKETING` — vide concern #4 da review, custo 14x).
- [ ] **AC-3:** Body com 2 placeholders + 1 button URL param.
- [ ] **AC-4:** `meta_templates` table tem 3 rows com `status='PENDING'`.

### Bloco B — Tracking

- [ ] **AC-5:** Slack alert quando Meta webhook reportar `status='APPROVED'` ou `REJECTED` (verificar se `meta-delivery-webhook` ou outro já trata).
- [ ] **AC-6:** Se rejeitado: documentar motivo no PR, ajustar copy, ressubmeter.

## Dependencies

Nenhuma direta — independente das D stories

## Risk

MED — Meta approval timing (24-48h típico, pode estender) + risco de rejeição se copy ambígua

## External dependencies

- Conta Meta Business ativa
- Phone number ID configurado
- Domain `painel.academialendaria.ai` resolve (após NPS.O.x DNS setup)

## Files

- Drafts pra registro: `docs/runbooks/nps-meta-templates-drafts.md` (criar)
- Update memory `meta-secrets-gap.md` se relevante
