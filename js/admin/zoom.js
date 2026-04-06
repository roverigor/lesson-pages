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
