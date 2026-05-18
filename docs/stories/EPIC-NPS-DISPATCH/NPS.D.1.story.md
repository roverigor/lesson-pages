# Story NPS.D.1 — Fix `dispatch_history_unified` VIEW Rewrite

**Epic:** EPIC-NPS-DISPATCH
**Status:** Ready
**Type:** Migration / Backend
**Wave:** 1 (BLOCKER — must close first)
**Estimated:** 2-3h (M)
**Primary Agent:** @data-engineer
**Assist Agents:** @architect (review SQL), @qa (regression test all P4 RPCs)
**Severity:** CRITICAL — blocks every other deploy

## O que fazer

A migration `20260517010500_dispatch_view_use_send_status.sql` tentou reescrever a VIEW unificada para refletir `send_status` real do P3 mas:

1. **Referencia colunas que não existem** em `notifications` (channel, scheduled_at, phone_number, purpose, template_name, error) e `survey_links` (send_channel, scheduled_at, recipient_phone, cohort_id, template_name, error_detail, responded_at).
2. **Reshapeia o output incompatível** com a VIEW original (`20260516020400_*`), quebrando todos os P4 RPCs (`list_dispatch_history`, `dispatch_summary_kpis`, etc.).

Aplicar `supabase db push` falha nesta migration. Se forçado, todo dashboard P4 quebra com "column ... does not exist".

## Fix

**Substituir** o conteúdo de `20260517010500_*` por um patch cirúrgico que:

- Preserve EXATAMENTE o column shape de `20260516020400_*`
- Mude APENAS o arm de `nps_class_links`: derive `status` de `COALESCE(l.send_status, 'pending')` em vez de hardcoded `'sent'`
- Mantenha todos os outros arms (notifications, survey_links, class_reminder_sends) idênticos

## Business Value

- **Destrava deploy:** sem isso, `supabase db push` quebra em produção.
- **Não quebra retroativamente:** P4 dashboard continua funcional.
- **Reflete realidade do P3:** dispatcher pós-aula reporta send_status real.

## Acceptance Criteria

### Bloco A — Migration Fix

- [ ] **AC-1:** Reescrever `supabase/migrations/20260517010500_dispatch_view_use_send_status.sql` mantendo a estrutura/columns de `20260516020400_*`.
- [ ] **AC-2:** Único change vs original: arm `nps_class_links` usa `CASE WHEN l.response_count > 0 THEN 'responded' ELSE COALESCE(l.send_status, 'pending') END` em vez de `... ELSE 'sent' END`.
- [ ] **AC-3:** Migration aplica clean (`supabase db push --dry-run` retorna sem erros).
- [ ] **AC-4:** Todos os P4 RPCs (`list_dispatch_history`, `dispatch_summary_kpis`, `dispatch_trend_daily`, `dispatch_top_classes`, `dispatch_recent_failures`, `dispatch_channel_breakdown`, `dispatch_funnel`) retornam linhas sem erro de coluna.

### Bloco B — Regression Test

- [ ] **AC-5:** Abrir `/admin/envios/` em staging — KPIs carregam, tabela renderiza, sem erros 500.
- [ ] **AC-6:** Verificar que rows P3 (nps_class_link) aparecem com status `pending` (ainda não enviadas) e `sent` (quando enviadas) corretamente.

## Dependencies

- Nenhuma (este é o pré-requisito de tudo)

## Risk

**HIGH** — toca data plane. Validate em staging antes de prod. Backup `dispatch_history_unified` definition antes de aplicar.

## Files

- Modify: `supabase/migrations/20260517010500_dispatch_view_use_send_status.sql`
- Reference: `supabase/migrations/20260516020400_dispatch_history_unified_view.sql` (golden source)
- Test: `admin/envios/app.js` (consumer)

## Architect note

Spec original P4 (`docs/superpowers/specs/2026-05-15-dispatch-history-dashboard-design.md`) é a fonte de verdade do column shape. O rewrite P3 foi acidente.
