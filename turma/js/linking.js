// ═══════════════════════════════════════════════════════════
// turma/js/linking.js — Zoom/WA participant linking modals
// Depends on globals: sb, allStudents, staffMembers, turmaMeetings, escHtml
// ═══════════════════════════════════════════════════════════

// ── LINK UNMATCHED PARTICIPANT TO STUDENT ──
let linkZoomName = '';
let linkMeetingId = '';
let linkSearchCache = [];

function openLinkModal(zoomName) {
  linkZoomName = zoomName;
  linkMeetingId = document.getElementById('presenca-date-select').value;
  document.getElementById('link-title').textContent = `Vincular: "${zoomName}"`;
  document.getElementById('link-sub').textContent = `Escolha o aluno (CSV) ou membro da equipe que usou "${zoomName}" no Zoom`;
  document.getElementById('link-search').value = '';
  document.getElementById('link-results').innerHTML = '';
  document.getElementById('link-feedback').innerHTML = '';
  document.querySelector('.link-actions').innerHTML = `
    <button class="link-btn" onclick="closeLinkModal()">Cancelar</button>
  `;
  document.getElementById('link-search').placeholder = 'Filtrar alunos ou equipe...';
  document.getElementById('link-search').oninput = searchLocalForLink;
  document.getElementById('link-modal').classList.remove('hidden');
  document.getElementById('link-search').focus();
  document.getElementById('link-search').value = zoomName.split(' ')[0];
  searchLocalForLink();
}

function closeLinkModal() {
  document.getElementById('link-modal').classList.add('hidden');
  linkZoomName = '';
}

function searchLocalForLink() {
  const q = document.getElementById('link-search').value.toLowerCase().trim();

  const csvResults = (allStudents || []).filter(s => {
    if (q.length < 2) return true;
    const name = (s.name || '').toLowerCase();
    const email = (s.email || '').toLowerCase();
    const phone = (s.phone || '').replace(/\D/g, '');
    return name.includes(q) || email.includes(q) || phone.includes(q);
  }).slice(0, 15);

  const staffResults = (staffMembers || []).filter(s => {
    if (q.length < 2) return true;
    const name = (s.name || '').toLowerCase();
    const aliases = (s.aliases || []).join(' ').toLowerCase();
    return name.includes(q) || aliases.includes(q);
  });

  let html = '';

  if (csvResults.length) {
    html += '<div style="font-size:10px;color:#4ade80;font-weight:700;text-transform:uppercase;letter-spacing:.05em;padding:6px 8px;margin-top:4px">Alunos CSV</div>';
    html += csvResults.map(s => {
      const phone = s.phone && !s.phone.startsWith('pending_') ? formatPhoneShort(s.phone) : '';
      const aliases = (s.aliases || []).length ? ` · ${s.aliases.join(', ')}` : '';
      return `<div class="link-result" onclick="executeLinkCSV('${s.id}', '${escHtml(s.name || '').replace(/'/g,"\\'")}')">
        <div style="flex:1">
          <div class="lr-name">${escHtml(s.name || 'Sem nome')}</div>
          <div class="lr-meta">${phone || 'Sem telefone'}${aliases}</div>
        </div>
        <div style="font-size:11px;color:#4ade80;font-weight:600">Aluno</div>
      </div>`;
    }).join('');
  }

  if (staffResults.length) {
    html += '<div style="font-size:10px;color:#a5b4fc;font-weight:700;text-transform:uppercase;letter-spacing:.05em;padding:6px 8px;margin-top:8px">Equipe</div>';
    html += staffResults.map(s => {
      const aliases = (s.aliases || []).length ? ` · ${s.aliases.join(', ')}` : '';
      return `<div class="link-result" onclick="executeLinkStaff('${s.name.replace(/'/g,"\\'")}')">
        <div style="flex:1">
          <div class="lr-name">${escHtml(s.name)}</div>
          <div class="lr-meta">${s.category}${aliases}</div>
        </div>
        <div style="font-size:11px;color:#a5b4fc;font-weight:600">Equipe</div>
      </div>`;
    }).join('');
  }

  if (!html) {
    html = '<div style="font-size:12px;color:#555;padding:8px">Nenhum resultado encontrado.</div>';
  }

  document.getElementById('link-results').innerHTML = html;
}

function formatPhoneShort(phone) {
  if (!phone) return '';
  if (phone.startsWith('55') && phone.length >= 12) {
    return `+55 (${phone.slice(2,4)}) •••••${phone.slice(-4)}`;
  }
  return `+${phone.slice(0, -4)}•••${phone.slice(-4)}`;
}

async function executeLinkCSV(csvId, csvName) {
  document.getElementById('link-feedback').innerHTML = '<div style="font-size:12px;color:#a5b4fc;padding:8px">Vinculando...</div>';

  const csvStudent = (allStudents || []).find(s => s.id === csvId);
  const currentAliases = csvStudent?.aliases || [];
  if (!currentAliases.includes(linkZoomName)) {
    const newAliases = [...currentAliases, linkZoomName];
    const { error } = await sb.from('student_imports').update({ aliases: newAliases }).eq('id', csvId);
    if (error) {
      document.getElementById('link-feedback').innerHTML = `<div style="color:#f87171;font-size:12px;padding:8px">Erro: ${error.message}</div>`;
      return;
    }
    if (csvStudent) csvStudent.aliases = newAliases;
  }

  document.getElementById('link-feedback').innerHTML = `<div class="link-success">Vinculado! "${linkZoomName}" agora é alias de "${csvName}". Valido para todas as reunioes.</div>`;

  setTimeout(() => {
    closeLinkModal();
    loadPresencaForMeeting(linkMeetingId);
  }, 1200);
}

async function executeLinkStaff(staffName) {
  document.getElementById('link-feedback').innerHTML = '<div style="font-size:12px;color:#a5b4fc;padding:8px">Vinculando como equipe...</div>';

  const staffMember = (staffMembers || []).find(s => s.name === staffName);
  if (!staffMember) {
    document.getElementById('link-feedback').innerHTML = '<div style="color:#f87171;font-size:12px;padding:8px">Membro não encontrado.</div>';
    return;
  }

  const currentAliases = staffMember.aliases || [];
  if (!currentAliases.includes(linkZoomName)) {
    const newAliases = [...currentAliases, linkZoomName];
    await sb.from('mentors').update({ aliases: newAliases }).eq('name', staffName);
    if (staffMember.phone) {
      const { data: mentor } = await sb.from('mentors').select('id').eq('phone', staffMember.phone.replace(/\D/g,'')).single();
      if (mentor) await sb.from('mentors').update({ aliases: newAliases }).eq('id', mentor.id);
    }
    staffMember.aliases = newAliases;
  }

  document.getElementById('link-feedback').innerHTML = `<div class="link-success">Vinculado como equipe! "${linkZoomName}" agora é alias de "${staffName}".</div>`;

  setTimeout(() => {
    closeLinkModal();
    loadPresencaForMeeting(linkMeetingId);
  }, 1200);
}

// ── WA LINK ──
let waLinkName = '';
let waLinkPhone = '';

function openWaLinkModal(waName, waPhone) {
  waLinkName = waName;
  waLinkPhone = waPhone;
  document.getElementById('link-title').textContent = `Vincular WA: "${waName}"`;
  document.getElementById('link-sub').textContent = `Escolha o aluno (CSV) ou membro da equipe que usa "${waName}" no WhatsApp`;
  document.getElementById('link-search').value = '';
  document.getElementById('link-results').innerHTML = '';
  document.getElementById('link-feedback').innerHTML = '';
  document.querySelector('.link-actions').innerHTML = `
    <button class="link-btn" onclick="closeLinkModal()">Cancelar</button>
  `;
  document.getElementById('link-search').placeholder = 'Filtrar alunos ou equipe...';
  document.getElementById('link-search').oninput = searchWaForLink;
  document.getElementById('link-modal').classList.remove('hidden');
  document.getElementById('link-search').focus();
  if (waName) {
    document.getElementById('link-search').value = waName.split(' ')[0];
    searchWaForLink();
  }
}

function searchWaForLink() {
  const q = document.getElementById('link-search').value.toLowerCase().trim();

  const csvResults = (allStudents || []).filter(s => {
    if (q.length < 2) return true;
    const name = (s.name || '').toLowerCase();
    const email = (s.email || '').toLowerCase();
    const phone = (s.phone || '').replace(/\D/g, '');
    return name.includes(q) || email.includes(q) || phone.includes(q);
  }).slice(0, 15);

  const staffResults = (staffMembers || []).filter(s => {
    if (q.length < 2) return true;
    const name = (s.name || '').toLowerCase();
    const aliases = (s.aliases || []).join(' ').toLowerCase();
    return name.includes(q) || aliases.includes(q);
  });

  let html = '';

  if (csvResults.length) {
    html += '<div style="font-size:10px;color:#4ade80;font-weight:700;text-transform:uppercase;letter-spacing:.05em;padding:6px 8px;margin-top:4px">Alunos CSV</div>';
    html += csvResults.map(s => {
      const phone = s.phone && !s.phone.startsWith('pending_') ? formatPhoneShort(s.phone) : 'Sem telefone';
      return `<div class="link-result" onclick="executeWaLinkCSV('${s.id}', '${escHtml(s.name || '').replace(/'/g,"\\'")}')">
        <div style="flex:1">
          <div class="lr-name">${escHtml(s.name || 'Sem nome')}</div>
          <div class="lr-meta">${phone}</div>
        </div>
        <div style="font-size:11px;color:#4ade80;font-weight:600">Aluno</div>
      </div>`;
    }).join('');
  }

  if (staffResults.length) {
    html += '<div style="font-size:10px;color:#a5b4fc;font-weight:700;text-transform:uppercase;letter-spacing:.05em;padding:6px 8px;margin-top:8px">Equipe</div>';
    html += staffResults.map(s => {
      return `<div class="link-result" onclick="executeWaLinkStaff('${escHtml(s.name).replace(/'/g,"\\'")}')">
        <div style="flex:1">
          <div class="lr-name">${escHtml(s.name)}</div>
          <div class="lr-meta">${s.category || 'Equipe'}</div>
        </div>
        <div style="font-size:11px;color:#a5b4fc;font-weight:600">Equipe</div>
      </div>`;
    }).join('');
  }

  if (!html) html = '<div style="font-size:12px;color:#555;padding:8px">Nenhum resultado encontrado.</div>';
  document.getElementById('link-results').innerHTML = html;
}

async function executeWaLinkCSV(csvId, csvName) {
  document.getElementById('link-feedback').innerHTML = '<div style="font-size:12px;color:#a5b4fc;padding:8px">Vinculando...</div>';

  const csvStudent = (allStudents || []).find(s => s.id === csvId);
  if (csvStudent && waLinkPhone) {
    const cleanPhone = waLinkPhone.replace(/\D/g, '');
    if (!csvStudent.phone || csvStudent.phone.startsWith('pending_')) {
      const { error } = await sb.from('student_imports').update({ phone: cleanPhone }).eq('id', csvId);
      if (error) {
        document.getElementById('link-feedback').innerHTML = `<div style="color:#f87171;font-size:12px;padding:8px">Erro: ${error.message}</div>`;
        return;
      }
      csvStudent.phone = cleanPhone;
    }
  }

  document.getElementById('link-feedback').innerHTML = `<div class="link-success">Vinculado! "${waLinkName}" (WA) agora vinculado a "${csvName}" (CSV).</div>`;
  setTimeout(() => { closeLinkModal(); renderWaTab(); }, 1200);
}

async function executeWaLinkStaff(staffName) {
  document.getElementById('link-feedback').innerHTML = '<div style="font-size:12px;color:#a5b4fc;padding:8px">Vinculando como equipe...</div>';

  const staffMember = (staffMembers || []).find(s => s.name === staffName);
  if (staffMember && waLinkPhone) {
    const cleanPhone = waLinkPhone.replace(/\D/g, '');
    if (!staffMember.phone) {
      await sb.from('mentors').update({ phone: cleanPhone }).eq('name', staffName);
      staffMember.phone = cleanPhone;
    }
  }

  document.getElementById('link-feedback').innerHTML = `<div class="link-success">Vinculado como equipe! "${waLinkName}" (WA) = "${staffName}".</div>`;
  setTimeout(() => { closeLinkModal(); renderWaTab(); }, 1200);
}

// ── RE-LINK ──
function openRelinkModal(csvName, currentZoomName) {
  const meetingId = document.getElementById('presenca-date-select').value;
  if (!meetingId) return;
  const meeting = turmaMeetings.find(m => m.id === meetingId);
  if (!meeting) return;

  document.getElementById('link-title').textContent = `Editar vínculo: "${csvName}"`;
  document.getElementById('link-sub').textContent = `Atualmente vinculado a "${currentZoomName}". Escolha outro participante ou desvincule.`;
  document.getElementById('link-search').value = '';
  document.getElementById('link-feedback').innerHTML = '';

  const allParts = meeting.participants.sort((a, b) => (a.name || '').localeCompare(b.name || ''));
  const partsHtml = allParts.map(p => {
    const durStr = p.dur >= 60 ? `${Math.floor(p.dur/60)}h${String(p.dur%60).padStart(2,'0')}` : `${p.dur}min`;
    const isCurrent = p.name === currentZoomName;
    const borderStyle = isCurrent ? 'border-color:#4ade80' : '';
    const currentBadge = isCurrent ? '<span style="font-size:9px;color:#4ade80;margin-left:6px">ATUAL</span>' : '';
    return `<div class="link-result" style="${borderStyle}" onclick="executeRelink('${escHtml(csvName).replace(/'/g,"\\'")}', '${escHtml(currentZoomName).replace(/'/g,"\\'")}', '${escHtml(p.name).replace(/'/g,"\\'")}')">
      <div style="flex:1">
        <div class="lr-name">${escHtml(p.name)}${currentBadge}</div>
        <div class="lr-meta">${durStr}</div>
      </div>
      <div style="font-size:11px;color:#6366f1;font-weight:600">${isCurrent ? '' : 'Selecionar'}</div>
    </div>`;
  }).join('');

  document.getElementById('link-results').innerHTML = partsHtml;
  document.getElementById('link-modal').classList.remove('hidden');

  const actionsEl = document.querySelector('.link-actions');
  actionsEl.innerHTML = `
    <button class="link-btn" onclick="closeLinkModal()">Cancelar</button>
    <button class="link-btn" style="border-color:#ef4444;color:#f87171;background:rgba(239,68,68,.06)" onclick="executeUnlink('${escHtml(csvName).replace(/'/g,"\\'")}', '${escHtml(currentZoomName).replace(/'/g,"\\'")}')">Desvincular</button>
  `;

  document.getElementById('link-search').placeholder = 'Filtrar participantes...';
  document.getElementById('link-search').oninput = function() {
    const q = this.value.toLowerCase().trim();
    const filtered = q.length < 1 ? allParts : allParts.filter(p => p.name.toLowerCase().includes(q));
    document.getElementById('link-results').innerHTML = filtered.map(p => {
      const durStr = p.dur >= 60 ? `${Math.floor(p.dur/60)}h${String(p.dur%60).padStart(2,'0')}` : `${p.dur}min`;
      const isCurrent = p.name === currentZoomName;
      const borderStyle = isCurrent ? 'border-color:#4ade80' : '';
      const currentBadge = isCurrent ? '<span style="font-size:9px;color:#4ade80;margin-left:6px">ATUAL</span>' : '';
      return `<div class="link-result" style="${borderStyle}" onclick="executeRelink('${escHtml(csvName).replace(/'/g,"\\'")}', '${escHtml(currentZoomName).replace(/'/g,"\\'")}', '${escHtml(p.name).replace(/'/g,"\\'")}')">
        <div style="flex:1">
          <div class="lr-name">${escHtml(p.name)}${currentBadge}</div>
          <div class="lr-meta">${durStr}</div>
        </div>
        <div style="font-size:11px;color:#6366f1;font-weight:600">${isCurrent ? '' : 'Selecionar'}</div>
      </div>`;
    }).join('');
  };
}

async function executeRelink(csvName, oldZoomName, newZoomName) {
  if (oldZoomName === newZoomName) { closeLinkModal(); return; }
  const meetingId = document.getElementById('presenca-date-select').value;

  const student = (allStudents || []).find(s => s.name === csvName);
  if (student && student.id) {
    const currentAliases = student.aliases || [];
    const normNew = newZoomName.toLowerCase().trim();
    if (!currentAliases.some(a => a.toLowerCase().trim() === normNew)) {
      const updated = [...currentAliases, newZoomName];
      await sb.from('student_imports').update({ aliases: updated }).eq('id', student.id);
      student.aliases = updated;
    }
  }

  closeLinkModal();
  loadPresencaForMeeting(meetingId);
  showToast(`Vínculo salvo: "${csvName}" → "${newZoomName}" (alias persistente)`);
}

async function executeUnlink(csvName, zoomName) {
  const meetingId = document.getElementById('presenca-date-select').value;

  const student = (allStudents || []).find(s => s.name === csvName);
  if (student && student.id) {
    const currentAliases = student.aliases || [];
    const normZoom = zoomName.toLowerCase().trim();
    const updated = currentAliases.filter(a => a.toLowerCase().trim() !== normZoom);
    if (updated.length !== currentAliases.length) {
      await sb.from('student_imports').update({ aliases: updated }).eq('id', student.id);
      student.aliases = updated;
    }
  }

  closeLinkModal();
  loadPresencaForMeeting(meetingId);
  showToast(`"${csvName}" desvinculado de "${zoomName}"`);
}

// ── MANUAL LINK ──
function openManualLinkModal(csvName) {
  const meetingId = document.getElementById('presenca-date-select').value;
  if (!meetingId) return;
  const meeting = turmaMeetings.find(m => m.id === meetingId);
  if (!meeting) return;

  document.getElementById('link-title').textContent = `Vincular: "${csvName}"`;
  document.getElementById('link-sub').textContent = `Escolha o participante Zoom correspondente a este aluno.`;
  document.getElementById('link-search').value = '';
  document.getElementById('link-feedback').innerHTML = '';

  const unmatched = window._currentUnmatchedZoom || [];
  const allParts = meeting.participants.sort((a, b) => (a.name || '').localeCompare(b.name || ''));

  function renderParts(list) {
    return list.map(p => {
      const durStr = p.dur >= 60 ? `${Math.floor(p.dur/60)}h${String(p.dur%60).padStart(2,'0')}` : `${p.dur}min`;
      const isUnmatched = unmatched.some(u => u.name === p.name);
      const label = isUnmatched ? '<span style="font-size:9px;color:#f59e0b;margin-left:4px">NÃO VINCULADO</span>' : '';
      return `<div class="link-result" onclick="executeRelink('${escHtml(csvName).replace(/'/g,"\\'")}', '', '${escHtml(p.name).replace(/'/g,"\\'")}')">
        <div style="flex:1">
          <div class="lr-name">${escHtml(p.name)}${label}</div>
          <div class="lr-meta">${durStr}</div>
        </div>
        <div style="font-size:11px;color:#6366f1;font-weight:600">Vincular</div>
      </div>`;
    }).join('');
  }

  const sortedParts = [...unmatched.sort((a,b) => (a.name||'').localeCompare(b.name||'')), ...allParts.filter(p => !unmatched.some(u => u.name === p.name))];
  document.getElementById('link-results').innerHTML = renderParts(sortedParts);
  document.getElementById('link-modal').classList.remove('hidden');

  const actionsEl = document.querySelector('.link-actions');
  actionsEl.innerHTML = `<button class="link-btn" onclick="closeLinkModal()">Cancelar</button>`;

  document.getElementById('link-search').placeholder = 'Filtrar participantes...';
  document.getElementById('link-search').oninput = function() {
    const q = this.value.toLowerCase().trim();
    const filtered = q.length < 1 ? sortedParts : sortedParts.filter(p => p.name.toLowerCase().includes(q));
    document.getElementById('link-results').innerHTML = renderParts(filtered);
  };
}

function showToast(msg) {
  const t = document.createElement('div');
  t.style.cssText = 'position:fixed;bottom:24px;left:50%;transform:translateX(-50%);background:#1e1e2e;border:1px solid #333;color:#ddd;padding:10px 20px;border-radius:10px;font-size:13px;z-index:9999;transition:opacity .3s';
  t.textContent = msg;
  document.body.appendChild(t);
  setTimeout(() => { t.style.opacity = '0'; setTimeout(() => t.remove(), 300); }, 2500);
}
