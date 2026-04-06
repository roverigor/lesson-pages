// ═══════════════════════════════════════
// ZOOM MATCHING
// ═══════════════════════════════════════
async function loadZoomMeetings() {
  const { data: meetings, error } = await sb.from('zoom_meetings')
    .select('id, topic, start_time, participants_count, cohort_id, cohorts(name)')
    .order('start_time', { ascending: false });
  if (error) { showToast('Erro ao carregar reuniões: ' + error.message, 'error'); return; }

  const sel = document.getElementById('zoom-meeting-select');
  sel.innerHTML = '<option value="">— Selecione uma reunião —</option>';
  for (const m of (meetings || [])) {
    const d = new Date(m.start_time);
    const label = `${d.toLocaleDateString('pt-BR')} — ${m.topic}${m.cohorts?.name ? ' ('+m.cohorts.name+')' : ''}`;
    sel.innerHTML += `<option value="${m.id}">${label}</option>`;
  }

  const { data: students } = await sb.from('students').select('id, name, phone').order('name');
  zoomAllStudents = (students || []).filter(s => s.name && s.name.trim());
}

async function loadZoomParticipants() {
  const meetingId = document.getElementById('zoom-meeting-select').value;
  if (!meetingId) return;

  document.getElementById('zoom-participants-list').innerHTML = '<div style="color:#555;padding:20px">Carregando...</div>';

  const { data: parts, error } = await sb.from('zoom_participants')
    .select('id, participant_name, duration_minutes, matched, student_id, students(name)')
    .eq('meeting_id', meetingId)
    .order('duration_minutes', { ascending: false });

  if (error) { showToast('Erro: ' + error.message, 'error'); return; }
  zoomParticipantsData = parts || [];

  const total = zoomParticipantsData.length;
  const matched = zoomParticipantsData.filter(p => p.matched).length;
  const unmatched = total - matched;

  document.getElementById('zoom-stats').style.display = 'flex';
  document.getElementById('zoom-stats').innerHTML = `
    <span style="font-size:13px;color:#888"><span style="color:#fff;font-weight:700;font-size:20px">${total}</span> participantes</span>
    <span style="font-size:13px;color:#888"><span style="color:#4ade80;font-weight:700;font-size:20px">${matched}</span> vinculados</span>
    <span style="font-size:13px;color:#888"><span style="color:#f87171;font-weight:700;font-size:20px">${unmatched}</span> não vinculados</span>
  `;
  document.getElementById('zoom-search-wrap').style.display = '';
  renderZoomParticipants();
}

function filterZoomRows() {
  const q = document.getElementById('zoom-student-search').value.toLowerCase();
  document.querySelectorAll('.zoom-part-row').forEach(row => {
    const name = row.dataset.name.toLowerCase();
    row.style.display = (!q || name.includes(q)) ? '' : 'none';
  });
}

function renderZoomParticipants() {
  const container = document.getElementById('zoom-participants-list');
  if (!zoomParticipantsData.length) { container.innerHTML = '<div style="color:#555;padding:20px">Nenhum participante.</div>'; return; }

  const unmatched = zoomParticipantsData.filter(p => !p.matched);
  const matched   = zoomParticipantsData.filter(p =>  p.matched);

  const studentOptions = zoomAllStudents.map(s =>
    `<option value="${s.id}">${s.name}${s.phone ? ' · '+s.phone : ''}</option>`
  ).join('');

  const rowHTML = (p, isMatched) => {
    const dur = p.duration_minutes;
    const pct = Math.round(dur / 272 * 100);
    const barColor = dur >= 200 ? '#4ade80' : dur >= 100 ? '#facc15' : '#f87171';
    if (isMatched) {
      return `<div class="zoom-part-row" data-name="${p.participant_name}" data-id="${p.id}"
        style="display:flex;align-items:center;gap:12px;padding:10px 16px;border-bottom:1px solid #161616">
        <span style="flex:1;font-size:13px;color:#555">${p.participant_name}</span>
        <span style="font-size:12px;color:#4ade80;font-weight:600">${p.students?.name || '—'}</span>
        <span style="font-size:11px;color:#555;min-width:60px;text-align:right">${dur} min</span>
        <button onclick="unlinkParticipant('${p.id}')"
          style="font-size:10px;padding:3px 8px;border-radius:4px;border:1px solid #333;background:transparent;color:#555;cursor:pointer">✕</button>
      </div>`;
    }
    return `<div class="zoom-part-row" data-name="${p.participant_name}" data-id="${p.id}"
      style="display:flex;align-items:center;gap:12px;padding:12px 16px;border-bottom:1px solid #1a1a1a">
      <div style="flex:1;min-width:0">
        <div style="font-size:13px;color:#ddd;font-weight:600;margin-bottom:2px">${p.participant_name}</div>
        <div style="display:flex;align-items:center;gap:6px;margin-top:4px">
          <div style="height:4px;width:80px;background:#1e1e1e;border-radius:2px;overflow:hidden">
            <div style="height:100%;width:${Math.min(pct,100)}%;background:${barColor};border-radius:2px"></div>
          </div>
          <span style="font-size:11px;color:#555">${dur} min (${pct}%)</span>
        </div>
      </div>
      <div style="display:flex;gap:8px;align-items:center;flex-shrink:0">
        <select class="substitute-select" style="padding:6px 8px;font-size:12px;min-width:200px" id="sel-${p.id}">
          <option value="">— Selecionar aluno —</option>
          ${studentOptions}
        </select>
        <button onclick="linkParticipant('${p.id}')"
          style="padding:6px 14px;border-radius:6px;border:none;background:#6366f1;color:#fff;font-size:12px;font-weight:700;cursor:pointer">Vincular</button>
      </div>
    </div>`;
  };

  container.innerHTML = `
    ${unmatched.length ? `
      <div style="font-size:12px;font-weight:700;color:#f87171;text-transform:uppercase;letter-spacing:.06em;margin-bottom:8px">
        Não vinculados (${unmatched.length})
      </div>
      <div style="background:#111;border:1px solid #1e1e1e;border-radius:12px;overflow:hidden;margin-bottom:20px">
        ${unmatched.map(p => rowHTML(p, false)).join('')}
      </div>` : ''}
    ${matched.length ? `
      <details>
        <summary style="font-size:12px;font-weight:700;color:#4ade80;text-transform:uppercase;letter-spacing:.06em;cursor:pointer;margin-bottom:8px">
          Vinculados (${matched.length})
        </summary>
        <div style="background:#111;border:1px solid #1e1e1e;border-radius:12px;overflow:hidden;margin-top:8px">
          ${matched.map(p => rowHTML(p, true)).join('')}
        </div>
      </details>` : ''}
  `;
}

async function linkParticipant(partId) {
  const studentId = document.getElementById(`sel-${partId}`)?.value;
  if (!studentId) { showToast('Selecione um aluno', 'error'); return; }
  const { error } = await sb.from('zoom_participants')
    .update({ student_id: studentId, matched: true })
    .eq('id', partId);
  if (error) { showToast('Erro: ' + error.message, 'error'); return; }
  showToast('Vinculado!', 'success');
  await loadZoomParticipants();
}

async function unlinkParticipant(partId) {
  const { error } = await sb.from('zoom_participants')
    .update({ student_id: null, matched: false })
    .eq('id', partId);
  if (error) { showToast('Erro: ' + error.message, 'error'); return; }
  showToast('Vínculo removido', 'success');
  await loadZoomParticipants();
}

// ═══════════════════════════════════════
// ZOOM DISCOVER MEETINGS
// ═══════════════════════════════════════
function zoomDiscoverMeetings() {
  const panel = document.getElementById('zoom-discover-panel');
  panel.style.display = panel.style.display === 'none' ? '' : 'none';
  if (panel.style.display !== 'none') {
    const now = new Date();
    const from = new Date(now - 90 * 24 * 60 * 60 * 1000);
    document.getElementById('zoom-discover-from').value = from.toISOString().slice(0, 10);
    document.getElementById('zoom-discover-to').value   = now.toISOString().slice(0, 10);
  }
}

async function runZoomDiscover() {
  const from = document.getElementById('zoom-discover-from').value;
  const to   = document.getElementById('zoom-discover-to').value;
  const el   = document.getElementById('zoom-discover-results');

  if (!from || !to) { showToast('Informe o período', 'error'); return; }

  el.innerHTML = '<div style="color:#555;font-size:13px;padding:8px 0">Consultando Zoom API...</div>';

  try {
    const res = await fetch(SUPABASE_URL + '/functions/v1/zoom-attendance', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + SUPABASE_KEY },
      body: JSON.stringify({ action: 'list_meetings', from, to }),
    });
    const data = await res.json();

    if (!data.ok) {
      el.innerHTML = `<div style="color:#f87171;font-size:13px">${data.error || 'Erro desconhecido'}</div>`;
      return;
    }

    const meetings = data.meetings || [];
    if (!meetings.length) {
      el.innerHTML = '<div style="color:#555;font-size:13px">Nenhuma reunião encontrada no período.</div>';
      return;
    }

    el.innerHTML = `
      <div style="font-size:12px;color:#555;margin-bottom:12px">${data.total_raw} sessões brutas → ${meetings.length} meeting IDs únicos</div>
      <table style="width:100%;border-collapse:collapse;font-size:13px">
        <thead><tr style="color:#555;text-align:left">
          <th style="padding:6px 8px">Meeting ID</th>
          <th style="padding:6px 8px">Tópico</th>
          <th style="padding:6px 8px;text-align:center">Sessões</th>
          <th style="padding:6px 8px;text-align:center">Participantes</th>
          <th style="padding:6px 8px">Última</th>
          <th style="padding:6px 8px"></th>
        </tr></thead>
        <tbody>
          ${meetings.map(m => `
            <tr style="border-top:1px solid #1e1e1e">
              <td style="padding:8px;font-family:monospace;color:#7c7cff">${m.id}</td>
              <td style="padding:8px;color:#ccc">${m.topic}</td>
              <td style="padding:8px;text-align:center;color:#fff">${m.instances}</td>
              <td style="padding:8px;text-align:center;color:#fff">${m.total_participants}</td>
              <td style="padding:8px;color:#555">${m.latest?.slice(0,10)}</td>
              <td style="padding:8px">
                <button onclick="zoomImportMeeting('${m.id}')" style="background:#222;border:1px solid #333;color:#aaa;font-size:11px;padding:4px 10px;border-radius:5px;cursor:pointer">
                  Importar
                </button>
              </td>
            </tr>`).join('')}
        </tbody>
      </table>`;
  } catch (err) {
    el.innerHTML = `<div style="color:#f87171;font-size:13px">Erro: ${err.message}</div>`;
  }
}

async function zoomImportMeeting(meetingId) {
  showToast('Importando meeting ' + meetingId + '...', 'success');
  let offset = 0;
  let hasMore = true;
  let totalProcessed = 0;

  while (hasMore) {
    const res = await fetch(SUPABASE_URL + '/functions/v1/zoom-attendance', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + SUPABASE_KEY },
      body: JSON.stringify({ meeting_id: meetingId, offset, batch_size: 3 }),
    });
    const data = await res.json();
    if (!data.ok) { showToast('Erro: ' + (data.error || 'desconhecido'), 'error'); return; }

    const processed = (data.instances || []).filter(i => i.status === 'processed').length;
    totalProcessed += processed;
    hasMore = data.has_more;
    offset = data.next_offset || 0;

    if (hasMore) await new Promise(r => setTimeout(r, 500));
  }

  showToast(`✓ Importado! ${totalProcessed} sessões novas processadas.`, 'success');
  await loadZoomMeetings();
}

// ═══════════════════════════════════════
// ZOOM HOST POOL
// ═══════════════════════════════════════
function zoomShowHostPool() {
  const panel = document.getElementById('zoom-host-pool');
  panel.style.display = panel.style.display === 'none' ? '' : 'none';
  if (panel.style.display !== 'none') loadHostPool();
}

async function loadHostPool() {
  const el = document.getElementById('zoom-host-pool-list');
  el.innerHTML = '<span style="color:#555;font-size:13px">Carregando...</span>';

  const { data, error } = await sb.from('zoom_host_sessions')
    .select('*')
    .order('started_at', { ascending: false })
    .limit(20);

  if (error) { el.innerHTML = `<span style="color:#f87171;font-size:13px">${error.message}</span>`; return; }

  if (!data?.length) {
    el.innerHTML = '<span style="color:#555;font-size:13px">Nenhuma sessão registrada.</span>';
    return;
  }

  const active   = data.filter(s => !s.released_at);
  const released = data.filter(s => s.released_at);

  const hostColors = { available: '#4ade80', busy: '#f59e0b' };

  el.innerHTML = `
    <div style="display:flex;gap:16px;margin-bottom:16px;flex-wrap:wrap">
      <span style="font-size:13px;color:#888">
        <span style="color:#f59e0b;font-weight:700;font-size:20px">${active.length}</span> ocupados
      </span>
      <span style="font-size:13px;color:#888">
        <span style="color:#4ade80;font-weight:700;font-size:20px">${released.length}</span> liberados (histórico)
      </span>
    </div>
    <table style="width:100%;border-collapse:collapse;font-size:12px">
      <thead><tr style="color:#555">
        <th style="padding:5px 8px;text-align:left">Host</th>
        <th style="padding:5px 8px;text-align:left">Meeting</th>
        <th style="padding:5px 8px;text-align:left">Início</th>
        <th style="padding:5px 8px;text-align:left">Status</th>
        <th style="padding:5px 8px"></th>
      </tr></thead>
      <tbody>
        ${data.map(s => {
          const isActive = !s.released_at;
          const started = new Date(s.started_at).toLocaleString('pt-BR');
          const status = isActive
            ? '<span style="color:#f59e0b;font-weight:700">● Ativo</span>'
            : `<span style="color:#4ade80">✓ ${s.released_by || 'liberado'}</span>`;
          const releaseBtn = isActive
            ? `<button onclick="zoomReleaseHost('${s.id}')" style="background:none;border:1px solid #333;color:#888;font-size:11px;padding:3px 8px;border-radius:4px;cursor:pointer">Liberar</button>`
            : '';
          return `<tr style="border-top:1px solid #1a1a1a">
            <td style="padding:6px 8px;color:#ccc">${s.host_email}</td>
            <td style="padding:6px 8px;color:#7c7cff;font-family:monospace">${s.meeting_id || '—'}</td>
            <td style="padding:6px 8px;color:#555">${started}</td>
            <td style="padding:6px 8px">${status}</td>
            <td style="padding:6px 8px">${releaseBtn}</td>
          </tr>`;
        }).join('')}
      </tbody>
    </table>`;
}

async function zoomReleaseHost(sessionId) {
  const { error } = await sb.from('zoom_host_sessions')
    .update({ released_at: new Date().toISOString(), released_by: 'manual' })
    .eq('id', sessionId);
  if (error) { showToast('Erro: ' + error.message, 'error'); return; }
  showToast('Host liberado manualmente', 'success');
  await loadHostPool();
}
