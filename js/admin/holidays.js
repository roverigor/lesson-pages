// ═══════════════════════════════════════
// HOLIDAYS / FERIADOS
// CRUD de feriados que suprimem disparos automáticos.
// ═══════════════════════════════════════

const HOLIDAY_SCOPE_LABELS = {
  national: 'Nacional',
  regional: 'Regional',
  custom:   'Custom',
};

const HOLIDAY_SCOPE_COLORS = {
  national: '#a5b4fc',
  regional: '#fbbf24',
  custom:   '#34d399',
};

async function loadHolidaysView() {
  const today = new Date().toISOString().slice(0, 10);
  document.getElementById('holiday-date').value = '';
  document.getElementById('holiday-name').value = '';
  document.getElementById('holiday-scope').value = 'custom';
  await renderHolidaysList();
}

async function renderHolidaysList() {
  const today = new Date().toISOString().slice(0, 10);
  const { data, error } = await sb
    .from('holidays')
    .select('*')
    .order('date', { ascending: true });

  const el = document.getElementById('holidays-list');
  if (error) {
    el.innerHTML = `<div style="text-align:center;color:#ef4444;padding:40px;font-size:13px">Erro: ${error.message}</div>`;
    return;
  }
  if (!data?.length) {
    el.innerHTML = '<div style="text-align:center;color:#333;padding:40px;font-size:13px">Nenhum feriado cadastrado</div>';
    return;
  }

  const upcoming = data.filter(h => h.date >= today);
  const past     = data.filter(h => h.date <  today);

  const renderRow = (h) => {
    const d = new Date(h.date + 'T12:00:00').toLocaleDateString('pt-BR', { weekday:'short', day:'2-digit', month:'2-digit', year:'numeric' });
    const scopeColor = HOLIDAY_SCOPE_COLORS[h.scope] || '#666';
    const scopeLabel = HOLIDAY_SCOPE_LABELS[h.scope] || h.scope;
    const statusColor = h.active ? '#4ade80' : '#555';
    const statusLabel = h.active ? 'Ativo' : 'Desativado';
    const isToday = h.date === today;
    const dateColor = isToday ? '#fbbf24' : (h.date < today ? '#444' : '#ddd');

    return `<div style="background:#111;border:1px solid #1e1e1e;border-radius:10px;padding:14px;margin-bottom:8px">
      <div style="display:flex;gap:12px;align-items:center;flex-wrap:wrap">
        <div style="flex:1;min-width:200px">
          <div style="display:flex;gap:8px;align-items:center;margin-bottom:4px">
            <span style="font-size:13px;font-weight:700;color:${dateColor}">${d}${isToday ? ' (hoje)' : ''}</span>
            <span style="font-size:10px;padding:2px 8px;border-radius:999px;background:rgba(99,102,241,0.1);border:1px solid ${scopeColor}40;color:${scopeColor}">${scopeLabel}</span>
            <span style="font-size:10px;padding:2px 8px;border-radius:999px;border:1px solid #222;color:${statusColor}">${statusLabel}</span>
          </div>
          <div style="font-size:12px;color:#888">${h.name}</div>
        </div>
        <div style="display:flex;gap:6px;flex-shrink:0">
          <button onclick="toggleHoliday('${h.date}', ${!h.active})" style="padding:6px 12px;border-radius:6px;border:1px solid #222;background:#1a1a1a;color:#888;font-size:11px;font-weight:700;cursor:pointer;font-family:var(--font-sans)">${h.active ? 'Desativar' : 'Ativar'}</button>
          <button onclick="deleteHoliday('${h.date}', ${JSON.stringify(h.name).replace(/"/g, '&quot;')})" style="padding:6px 10px;border-radius:6px;border:1px solid #44403c;background:rgba(168,162,158,0.08);color:#a8a29e;font-size:13px;cursor:pointer;font-family:var(--font-sans)">✕</button>
        </div>
      </div>
    </div>`;
  };

  let html = '';

  if (upcoming.length > 0) {
    html += `<div style="font-size:11px;color:#555;text-transform:uppercase;letter-spacing:0.05em;margin:8px 0 12px">Próximos (${upcoming.length})</div>`;
    html += upcoming.map(renderRow).join('');
  }

  if (past.length > 0) {
    html += `<div style="font-size:11px;color:#555;text-transform:uppercase;letter-spacing:0.05em;margin:24px 0 12px">Passados (${past.length})</div>`;
    html += past.slice(-12).reverse().map(renderRow).join('');
  }

  el.innerHTML = html;
}

async function saveHoliday() {
  const date  = document.getElementById('holiday-date').value;
  const name  = document.getElementById('holiday-name').value.trim();
  const scope = document.getElementById('holiday-scope').value;

  if (!date)  { showToast('Data obrigatória', 'error'); return; }
  if (!name)  { showToast('Nome obrigatório', 'error'); return; }
  if (!scope) { showToast('Escopo obrigatório', 'error'); return; }

  const { error } = await sb
    .from('holidays')
    .upsert({ date, name, scope, active: true }, { onConflict: 'date' });

  if (error) {
    showToast(`Erro: ${error.message}`, 'error');
    return;
  }
  showToast('Feriado salvo', 'success');
  document.getElementById('holiday-date').value  = '';
  document.getElementById('holiday-name').value  = '';
  document.getElementById('holiday-scope').value = 'custom';
  await renderHolidaysList();
}

async function toggleHoliday(date, active) {
  const { error } = await sb
    .from('holidays')
    .update({ active })
    .eq('date', date);
  if (error) { showToast(`Erro: ${error.message}`, 'error'); return; }
  showToast(active ? 'Feriado ativado' : 'Feriado desativado', 'success');
  await renderHolidaysList();
}

async function deleteHoliday(date, name) {
  if (!confirm(`Excluir feriado "${name}" (${date})?\n\nDisparos voltarão a acontecer normalmente nessa data.`)) return;
  const { error } = await sb
    .from('holidays')
    .delete()
    .eq('date', date);
  if (error) { showToast(`Erro: ${error.message}`, 'error'); return; }
  showToast('Feriado excluído', 'success');
  await renderHolidaysList();
}

window.loadHolidaysView = loadHolidaysView;
window.saveHoliday      = saveHoliday;
window.toggleHoliday    = toggleHoliday;
window.deleteHoliday    = deleteHoliday;
