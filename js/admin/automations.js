// ═══════════════════════════════════════
// Automations Dashboard (Story 12.5)
// ═══════════════════════════════════════

let _autoRefreshTimer = null;

const RUN_TYPE_LABELS = {
  daily_pipeline:          'Pipeline Diário Zoom',
  wa_sync:                 'Sync WhatsApp',
  recording_notification:  'Notificação Gravação',
  health_check:            'Health Check',
  absence_alerts:          'Alerta de Ausência',
};

const RUN_TYPE_ICONS = {
  daily_pipeline:         '🔄',
  wa_sync:                '💬',
  recording_notification: '🎬',
  health_check:           '🩺',
  absence_alerts:         '📊',
};

const CRON_SCHEDULES = {
  daily_pipeline:         '03:00 AM',
  wa_sync:                '04:00 AM',
  health_check:           '06:00 AM',
  absence_alerts:         '18:00 (seg-sex)',
  recording_notification: 'Evento (webhook)',
};

function statusBadge(status) {
  const colors = { success: '#22c55e', error: '#ef4444', running: '#eab308' };
  const labels = { success: 'Sucesso', error: 'Erro', running: 'Rodando' };
  const c = colors[status] || '#666';
  return `<span style="display:inline-flex;align-items:center;gap:4px;padding:2px 8px;border-radius:6px;background:${c}20;color:${c};font-size:11px;font-weight:600">
    <span style="width:6px;height:6px;border-radius:50%;background:${c}"></span>${labels[status] || status}
  </span>`;
}

function timeAgo(dateStr) {
  const d = new Date(dateStr);
  const now = new Date();
  const diff = Math.floor((now - d) / 1000);
  if (diff < 60) return 'agora';
  if (diff < 3600) return `${Math.floor(diff / 60)}min atrás`;
  if (diff < 86400) return `${Math.floor(diff / 3600)}h atrás`;
  return `${Math.floor(diff / 86400)}d atrás`;
}

function formatDate(dateStr) {
  if (!dateStr) return '—';
  const d = new Date(dateStr);
  return d.toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
}

async function loadAutomationsView() {
  const container = document.getElementById('automations-content');
  if (!container) return;
  container.innerHTML = '<div style="text-align:center;padding:40px;color:#444">Carregando...</div>';

  // Fetch last 30 runs grouped by type
  const { data: runs, error } = await sb
    .from('automation_runs')
    .select('*')
    .order('started_at', { ascending: false })
    .limit(100);

  if (error) {
    container.innerHTML = `<div style="padding:20px;color:#ef4444">Erro: ${error.message}</div>`;
    return;
  }

  // Group by run_type
  const byType = {};
  for (const r of (runs || [])) {
    if (!byType[r.run_type]) byType[r.run_type] = [];
    byType[r.run_type].push(r);
  }

  // Summary cards for each pipeline type
  const types = ['daily_pipeline', 'wa_sync', 'absence_alerts', 'recording_notification', 'health_check'];
  let html = '<div style="display:grid;grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:16px;margin-bottom:32px">';

  for (const type of types) {
    const typeRuns = byType[type] || [];
    const latest = typeRuns[0];
    const icon = RUN_TYPE_ICONS[type] || '⚙️';
    const label = RUN_TYPE_LABELS[type] || type;
    const schedule = CRON_SCHEDULES[type] || '—';

    html += `
      <div style="background:#111;border:1px solid #1e1e1e;border-radius:12px;padding:20px">
        <div style="display:flex;align-items:center;gap:10px;margin-bottom:12px">
          <span style="font-size:24px">${icon}</span>
          <div>
            <div style="color:#fff;font-weight:700;font-size:14px">${label}</div>
            <div style="color:#444;font-size:11px">Próximo: ${schedule}</div>
          </div>
        </div>
        ${latest ? `
          <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px">
            ${statusBadge(latest.status)}
            <span style="color:#555;font-size:11px">${timeAgo(latest.started_at)}</span>
          </div>
          <div style="display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px;font-size:11px;color:#666">
            <div>📥 ${latest.records_processed ?? 0}</div>
            <div>✅ ${latest.records_created ?? 0}</div>
            <div>❌ ${latest.records_failed ?? 0}</div>
          </div>
          ${latest.error_message ? `<div style="margin-top:6px;font-size:11px;color:#ef4444;word-break:break-word">${latest.error_message}</div>` : ''}
        ` : `<div style="color:#333;font-size:12px;font-style:italic">Nenhuma execução registrada</div>`}
        <button onclick="triggerPipeline('${type}')" style="margin-top:12px;width:100%;padding:8px;border-radius:8px;border:1px solid #1e1e1e;background:#0d0d0d;color:#a5b4fc;font-size:12px;font-weight:600;cursor:pointer;font-family:inherit">
          ▶ Executar Agora
        </button>
      </div>`;
  }
  html += '</div>';

  // Utility actions
  html += `
    <div style="display:flex;gap:12px;margin-bottom:24px">
      <button onclick="triggerBatchTranscripts()" style="padding:10px 20px;border-radius:8px;border:1px solid #1e1e1e;background:#111;color:#a5b4fc;font-size:12px;font-weight:600;cursor:pointer;font-family:inherit">
        📝 Importar Transcrições Pendentes
      </button>
    </div>`;

  // History table
  html += `
    <div style="background:#111;border:1px solid #1e1e1e;border-radius:12px;padding:20px">
      <div style="color:#fff;font-weight:700;font-size:14px;margin-bottom:16px">Histórico de Execuções</div>
      <div style="overflow-x:auto">
        <table style="width:100%;border-collapse:collapse;font-size:12px">
          <thead>
            <tr style="border-bottom:1px solid #1e1e1e;color:#555">
              <th style="padding:8px;text-align:left">Tipo</th>
              <th style="padding:8px;text-align:left">Step</th>
              <th style="padding:8px;text-align:left">Status</th>
              <th style="padding:8px;text-align:right">Proc.</th>
              <th style="padding:8px;text-align:right">Criados</th>
              <th style="padding:8px;text-align:right">Falhas</th>
              <th style="padding:8px;text-align:left">Início</th>
              <th style="padding:8px;text-align:left">Erro</th>
            </tr>
          </thead>
          <tbody>`;

  for (const r of (runs || []).slice(0, 30)) {
    html += `
      <tr style="border-bottom:1px solid #0e0e0e">
        <td style="padding:6px 8px;color:#888">${RUN_TYPE_ICONS[r.run_type] || ''} ${RUN_TYPE_LABELS[r.run_type] || r.run_type}</td>
        <td style="padding:6px 8px;color:#666">${r.step_name || '—'}</td>
        <td style="padding:6px 8px">${statusBadge(r.status)}</td>
        <td style="padding:6px 8px;text-align:right;color:#888">${r.records_processed ?? 0}</td>
        <td style="padding:6px 8px;text-align:right;color:#888">${r.records_created ?? 0}</td>
        <td style="padding:6px 8px;text-align:right;color:${r.records_failed > 0 ? '#ef4444' : '#888'}">${r.records_failed ?? 0}</td>
        <td style="padding:6px 8px;color:#555">${formatDate(r.started_at)}</td>
        <td style="padding:6px 8px;color:#ef4444;max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap" title="${(r.error_message || '').replace(/"/g, '&quot;')}">${r.error_message || ''}</td>
      </tr>`;
  }

  html += '</tbody></table></div></div>';

  container.innerHTML = html;

  // Auto-refresh every 60s
  clearInterval(_autoRefreshTimer);
  _autoRefreshTimer = setInterval(() => {
    const view = document.getElementById('automations-view');
    if (view && view.style.display !== 'none') loadAutomationsView();
    else clearInterval(_autoRefreshTimer);
  }, 60000);
}

async function triggerPipeline(type) {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { showToast('Sessão expirada', 'error'); return; }

  const endpoints = {
    daily_pipeline:         { fn: 'zoom-attendance', body: { action: 'daily_pipeline' } },
    wa_sync:                { fn: 'sync-wa-group',   body: { action: 'auto_sync' } },
    absence_alerts:         { fn: 'zoom-attendance', body: { action: 'send_absence_alerts' } },
    recording_notification: null,
    health_check:           { fn: 'zoom-attendance', body: { action: 'health_check' } },
  };

  const ep = endpoints[type];
  if (!ep) { showToast('Este pipeline é acionado por evento (webhook)', 'info'); return; }
  if (type === 'batch_transcripts') { triggerBatchTranscripts(); return; }

  showToast('Executando...', 'info');

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/${ep.fn}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${session.access_token}`,
      },
      body: JSON.stringify(ep.body),
    });
    const data = await res.json();
    if (data.ok) {
      showToast(`Pipeline executado com sucesso`, 'success');
      setTimeout(() => loadAutomationsView(), 2000);
    } else {
      showToast(`Erro: ${data.error || 'desconhecido'}`, 'error');
    }
  } catch (e) {
    showToast(`Erro: ${e.message}`, 'error');
  }
}

async function triggerBatchTranscripts() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { showToast('Sessão expirada', 'error'); return; }

  showToast('Importando transcrições...', 'info');

  try {
    const res = await fetch(`${SUPABASE_URL}/functions/v1/zoom-attendance`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${session.access_token}`,
      },
      body: JSON.stringify({ action: 'batch_import_transcripts', batch_size: 5 }),
    });
    const data = await res.json();
    if (data.ok) {
      showToast(`Transcrições: ${data.imported} importadas, ${data.summarized} resumos gerados`, 'success');
    } else {
      showToast(`Erro: ${data.error || 'desconhecido'}`, 'error');
    }
  } catch (e) {
    showToast(`Erro: ${e.message}`, 'error');
  }
}
