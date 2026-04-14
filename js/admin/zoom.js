// ═══════════════════════════════════════
// ZOOM MODULE — State
// ═══════════════════════════════════════
let zoomStaffList = [];
let zoomLegacyStudents = [];

// ═══════════════════════════════════════
// FUZZY MATCHING — Jaro-Winkler
// ═══════════════════════════════════════

function jaroWinkler(a, b) {
  if (a === b) return 1;
  const la = a.length, lb = b.length;
  if (!la || !lb) return 0;
  const dist = Math.max(0, Math.floor(Math.max(la, lb) / 2) - 1);
  const ma = new Array(la).fill(false);
  const mb = new Array(lb).fill(false);
  let matches = 0;
  for (let i = 0; i < la; i++) {
    const lo = Math.max(0, i - dist), hi = Math.min(i + dist + 1, lb);
    for (let j = lo; j < hi; j++) {
      if (mb[j] || a[i] !== b[j]) continue;
      ma[i] = mb[j] = true; matches++; break;
    }
  }
  if (!matches) return 0;
  let t = 0, k = 0;
  for (let i = 0; i < la; i++) {
    if (!ma[i]) continue;
    while (!mb[k]) k++;
    if (a[i] !== b[k]) t++;
    k++;
  }
  const jaro = (matches / la + matches / lb + (matches - t / 2) / matches) / 3;
  let p = 0;
  const max4 = Math.min(4, la, lb);
  while (p < max4 && a[p] === b[p]) p++;
  return jaro + p * 0.1 * (1 - jaro);
}

function normName(n) {
  return n.toUpperCase()
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^A-Z\s]/g, ' ')
    .replace(/\s+/g, ' ').trim();
}

function fuzzyScore(zoomName, studentName) {
  const zn = normName(zoomName);
  const sn = normName(studentName);
  const full = jaroWinkler(zn, sn);
  const zt = zn.split(' ').filter(w => w.length > 1);
  const st = sn.split(' ').filter(w => w.length > 1);
  if (!zt.length || !st.length) return full;
  const first = jaroWinkler(zt[0], st[0]);
  let token = first;
  if (zt.length > 1 && st.length > 1) {
    const last = jaroWinkler(zt[zt.length - 1], st[st.length - 1]);
    token = (first * 0.6 + last * 0.4);
  }
  return Math.max(full, token);
}

function bestStudentMatch(participantName, students) {
  let best = null, bestScore = 0;
  for (const s of students) {
    const score = fuzzyScore(participantName, s.name);
    if (score > bestScore) { bestScore = score; best = s; }
  }
  return { student: best, score: bestScore };
}

// ─── Auto-Match ───
const FUZZY_AUTO     = 0.92;
const FUZZY_SUGGEST  = 0.80;

async function autoMatchParticipants() {
  const unmatched = zoomParticipantsData.filter(p => !p.matched && !p._isStaff);
  if (!unmatched.length) { showToast('Nenhum participante sem vínculo', 'success'); return; }

  // Match contra CSV (prioridade) + Staff
  const meetingOpt = document.getElementById('zoom-meeting-select').selectedOptions[0];
  const meetingCohortId = meetingOpt?.dataset?.cohortId || null;
  const csvFiltered = meetingCohortId
    ? zoomAllStudents.filter(s => s.cohort_id === meetingCohortId)
    : zoomAllStudents;

  // Incluir aliases na busca fuzzy
  const expandedCSV = [];
  csvFiltered.forEach(s => {
    expandedCSV.push(s);
    // Adicionar aliases como entradas extras para matching
    (s.aliases || []).forEach(alias => {
      expandedCSV.push({ ...s, _aliasName: alias });
    });
  });

  const suggestions = [];
  for (const p of unmatched) {
    let bestMatch = null, bestScore = 0, bestType = 'csv';

    // Buscar no CSV (incluindo aliases)
    for (const s of expandedCSV) {
      const matchName = s._aliasName || s.name;
      // Check exact alias match first
      if (s._aliasName && normName(s._aliasName) === normName(p.participant_name)) {
        bestMatch = s; bestScore = 1.0; break;
      }
      const score = fuzzyScore(p.participant_name, matchName);
      if (score > bestScore) { bestScore = score; bestMatch = s; }
    }

    // Buscar no Staff (se score CSV não é perfeito)
    if (bestScore < 0.95) {
      for (const s of zoomStaffList) {
        const score = fuzzyScore(p.participant_name, s.name);
        if (score > bestScore) { bestScore = score; bestMatch = s; bestType = 'staff'; }
        for (const alias of (s.aliases || [])) {
          if (normName(alias) === normName(p.participant_name)) { bestMatch = s; bestScore = 1.0; bestType = 'staff'; break; }
          const aScore = fuzzyScore(p.participant_name, alias);
          if (aScore > bestScore) { bestScore = aScore; bestMatch = s; bestType = 'staff'; }
        }
        if (bestScore >= 1.0) break;
      }
    }

    if (bestMatch && bestScore >= FUZZY_SUGGEST) {
      suggestions.push({ p, student: bestMatch, score: bestScore, auto: bestScore >= FUZZY_AUTO, type: bestType });
    }
  }

  if (!suggestions.length) {
    showToast('Nenhuma sugestão com confiança suficiente (≥80%)', 'error');
    return;
  }

  renderMatchModal(suggestions);
}

function renderMatchModal(suggestions) {
  const auto    = suggestions.filter(s => s.auto);
  const manual  = suggestions.filter(s => !s.auto);

  const rowHTML = (s) => {
    const pct  = Math.round(s.score * 100);
    const color = s.auto ? '#4ade80' : '#f59e0b';
    const typeLabel = s.type === 'staff'
      ? `<span style="font-size:9px;color:#a5b4fc;background:rgba(99,102,241,.12);padding:1px 5px;border-radius:3px;margin-left:4px">EQUIPE</span>`
      : `<span style="font-size:9px;color:#4ade80;background:rgba(74,222,128,.12);padding:1px 5px;border-radius:3px;margin-left:4px">CSV</span>`;
    const pIds = (s.p._ids || [s.p.id]).join(',');
    return `<tr data-pid="${pIds}" data-sid="${s.student.id}" data-type="${s.type || 'csv'}" data-zoom-name="${s.p.participant_name}" class="fuzzy-row">
      <td style="padding:8px 6px;font-size:12px;color:#ccc">${s.p.participant_name}</td>
      <td style="padding:8px 6px;font-size:12px;color:#fff;font-weight:600">${s.student._aliasName || s.student.name}${typeLabel}</td>
      <td style="padding:8px 6px;text-align:center">
        <span style="font-size:11px;font-weight:700;color:${color};background:${color}22;padding:2px 8px;border-radius:999px">${pct}%</span>
      </td>
      <td style="padding:8px 6px;text-align:center">
        <input type="checkbox" class="fuzzy-check" ${s.auto ? 'checked' : ''} style="width:16px;height:16px;cursor:pointer">
      </td>
    </tr>`;
  };

  const html = `<div id="fuzzy-modal" style="position:fixed;inset:0;background:rgba(0,0,0,.7);z-index:2000;display:flex;align-items:center;justify-content:center;padding:16px" onclick="if(event.target===this)closeFuzzyModal()">
    <div style="background:#0f0f0f;border:1px solid #222;border-radius:16px;width:100%;max-width:680px;max-height:85vh;display:flex;flex-direction:column">
      <div style="padding:20px 24px;border-bottom:1px solid #1a1a1a;display:flex;align-items:center;justify-content:space-between">
        <div>
          <div style="font-size:15px;font-weight:700;color:#fff">Sugestões de Vínculo</div>
          <div style="font-size:12px;color:#555;margin-top:2px">${auto.length} auto (≥92%) · ${manual.length} sugestões (80–91%) · total ${suggestions.length}</div>
        </div>
        <button onclick="closeFuzzyModal()" style="background:none;border:none;color:#555;font-size:22px;cursor:pointer">×</button>
      </div>
      <div style="overflow-y:auto;flex:1;padding:16px 24px">
        <div style="display:flex;gap:8px;margin-bottom:16px;flex-wrap:wrap">
          <button onclick="selectAllFuzzy(true)"  style="font-size:11px;font-weight:700;padding:5px 12px;border-radius:6px;border:1px solid #333;background:transparent;color:#aaa;cursor:pointer">Marcar tudo</button>
          <button onclick="selectAllFuzzy(false)" style="font-size:11px;font-weight:700;padding:5px 12px;border-radius:6px;border:1px solid #333;background:transparent;color:#aaa;cursor:pointer">Desmarcar tudo</button>
        </div>
        <table style="width:100%;border-collapse:collapse">
          <thead><tr style="color:#444;font-size:11px;text-transform:uppercase;letter-spacing:.04em">
            <th style="padding:6px;text-align:left">Zoom</th>
            <th style="padding:6px;text-align:left">Aluno</th>
            <th style="padding:6px;text-align:center">Confiança</th>
            <th style="padding:6px;text-align:center">Aceitar</th>
          </tr></thead>
          <tbody>
            ${[...auto, ...manual].map(rowHTML).join('')}
          </tbody>
        </table>
      </div>
      <div style="padding:16px 24px;border-top:1px solid #1a1a1a;display:flex;gap:8px;justify-content:flex-end">
        <button onclick="closeFuzzyModal()" style="padding:9px 18px;border-radius:8px;border:1px solid #222;background:transparent;color:#666;font-size:13px;font-weight:600;cursor:pointer">Cancelar</button>
        <button onclick="applyFuzzyMatches()" style="padding:9px 18px;border-radius:8px;border:none;background:#6366f1;color:#fff;font-size:13px;font-weight:700;cursor:pointer">Vincular selecionados</button>
      </div>
    </div>
  </div>`;
  document.body.insertAdjacentHTML('beforeend', html);
}

function closeFuzzyModal() { document.getElementById('fuzzy-modal')?.remove(); }

function selectAllFuzzy(checked) {
  document.querySelectorAll('.fuzzy-check').forEach(cb => { cb.checked = checked; });
}

async function applyFuzzyMatches() {
  const rows = document.querySelectorAll('.fuzzy-row');
  const toLink = [];
  rows.forEach(row => {
    const cb = row.querySelector('.fuzzy-check');
    if (cb && cb.checked) {
      toLink.push({
        pids: row.dataset.pid.split(','),
        sid: row.dataset.sid,
        type: row.dataset.type || 'csv',
        zoomName: row.dataset.zoomName,
      });
    }
  });

  if (!toLink.length) { closeFuzzyModal(); return; }

  let ok = 0, fail = 0;
  for (const { pids, sid, type, zoomName } of toLink) {
    try {
      if (type === 'staff') {
        // Salvar alias no staff
        const staffMember = zoomStaffList.find(s => s.id === sid);
        if (staffMember) {
          const cur = staffMember.aliases || [];
          if (!cur.includes(zoomName)) {
            await sb.from('mentors').update({ aliases: [...cur, zoomName] }).eq('id', sid);
            staffMember.aliases = [...cur, zoomName];
          }
        }
        for (const pid of pids) {
          await sb.from('zoom_participants').update({ matched: true }).eq('id', pid);
        }
      } else {
        // CSV: salvar alias + vincular via legacy
        const csvStudent = zoomAllStudents.find(s => s.id === sid);
        if (csvStudent) {
          const cur = csvStudent.aliases || [];
          if (!cur.includes(zoomName)) {
            await sb.from('student_imports').update({ aliases: [...cur, zoomName] }).eq('id', sid);
            csvStudent.aliases = [...cur, zoomName];
          }
        }
        // Find legacy student for FK
        const legacy = zoomLegacyStudents.find(s =>
          (s.phone && csvStudent?.phone && s.phone.replace(/\D/g,'').slice(-8) === csvStudent.phone.replace(/\D/g,'').slice(-8)) ||
          (s.name && csvStudent?.name && normName(s.name) === normName(csvStudent.name))
        );
        for (const pid of pids) {
          await sb.from('zoom_participants').update({
            student_id: legacy?.id || null,
            matched: true,
          }).eq('id', pid);
        }
      }
      ok++;
    } catch (e) { fail++; }
  }

  closeFuzzyModal();
  showToast(`✅ ${ok} vinculados + aliases salvos${fail ? ` · ❌ ${fail} erros` : ''}`, ok ? 'success' : 'error');
  await loadZoomParticipants();
}

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
    sel.innerHTML += `<option value="${m.id}" data-cohort-id="${m.cohort_id || ''}">${label}</option>`;
  }

  // Carregar CSV (student_imports) + Staff para vinculação
  const [csvRes, staffRes] = await Promise.all([
    sb.from('student_imports').select('id, name, email, phone, cohort_id, aliases').order('name'),
    sb.from('mentors').select('id, name, email, phone, category, aliases').eq('active', true).order('name'),
  ]);
  zoomAllStudents = (csvRes.data || []).filter(s => s.name && s.name.trim());
  zoomStaffList = (staffRes.data || []).filter(s => s.name && s.name.trim());

  // Fallback: carregar students legado para manter compatibilidade com student_id FK
  const { data: legacyStudents } = await sb.from('students').select('id, name, phone').order('name');
  zoomLegacyStudents = (legacyStudents || []).filter(s => s.name && s.name.trim());
}

async function loadZoomParticipants() {
  const meetingId = document.getElementById('zoom-meeting-select').value;
  if (!meetingId) return;

  document.getElementById('zoom-participants-list').innerHTML = '<div style="color:#555;padding:20px">Carregando...</div>';

  const { data: parts, error } = await sb.from('zoom_participants')
    .select('id, participant_name, participant_email, duration_minutes, matched, student_id, students(name)')
    .eq('meeting_id', meetingId)
    .order('duration_minutes', { ascending: false });

  if (error) { showToast('Erro: ' + error.message, 'error'); return; }

  // ── DEDUP: agrupar por nome normalizado, somar duração ──
  const rawParts = parts || [];
  const byName = {};
  rawParts.forEach(p => {
    const key = normName(p.participant_name || '');
    if (!key) return;
    if (!byName[key]) {
      byName[key] = { ...p, _ids: [p.id], _totalDur: p.duration_minutes || 0 };
    } else {
      byName[key]._ids.push(p.id);
      byName[key]._totalDur += (p.duration_minutes || 0);
      // Preservar o match/student_id se algum registro tinha
      if (p.matched && !byName[key].matched) {
        byName[key].matched = true;
        byName[key].student_id = p.student_id;
        byName[key].students = p.students;
      }
      // Preservar email se disponível
      if (p.participant_email && !byName[key].participant_email) {
        byName[key].participant_email = p.participant_email;
      }
    }
  });
  zoomParticipantsData = Object.values(byName).map(p => ({
    ...p, duration_minutes: p._totalDur,
  })).sort((a, b) => b.duration_minutes - a.duration_minutes);

  // ── Auto-classificar equipe ──
  zoomParticipantsData.forEach(p => {
    p._isStaff = false;
    p._staffMatch = null;
    const pName = normName(p.participant_name || '');
    for (const s of zoomStaffList) {
      if (normName(s.name) === pName) { p._isStaff = true; p._staffMatch = s; break; }
      if (s.aliases && s.aliases.length) {
        for (const alias of s.aliases) {
          if (normName(alias) === pName) { p._isStaff = true; p._staffMatch = s; break; }
        }
        if (p._isStaff) break;
      }
      // Fuzzy com threshold alto
      if (fuzzyScore(p.participant_name, s.name) >= 0.90) { p._isStaff = true; p._staffMatch = s; break; }
    }
  });

  const total = zoomParticipantsData.length;
  const rawTotal = rawParts.length;
  const matched = zoomParticipantsData.filter(p => p.matched).length;
  const staffCount = zoomParticipantsData.filter(p => p._isStaff && !p.matched).length;
  const unmatched = total - matched - staffCount;

  document.getElementById('zoom-stats').style.display = 'flex';
  document.getElementById('zoom-stats').innerHTML = `
    <span style="font-size:13px;color:#888"><span style="color:#fff;font-weight:700;font-size:20px">${total}</span> participantes${rawTotal > total ? ` <span style="color:#333;font-size:11px">(${rawTotal} brutos)</span>` : ''}</span>
    <span style="font-size:13px;color:#888"><span style="color:#4ade80;font-weight:700;font-size:20px">${matched}</span> vinculados</span>
    <span style="font-size:13px;color:#888"><span style="color:#a5b4fc;font-weight:700;font-size:20px">${staffCount}</span> equipe</span>
    <span style="font-size:13px;color:#888"><span style="color:#f87171;font-weight:700;font-size:20px">${unmatched}</span> não vinculados</span>
  `;
  document.getElementById('zoom-search-wrap').style.display = 'flex';
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

  // Filtrar reunião por cohort para mostrar CSV da turma certa
  const meetingId = document.getElementById('zoom-meeting-select').value;
  const meetingOpt = document.getElementById('zoom-meeting-select').selectedOptions[0];
  const meetingCohortId = meetingOpt?.dataset?.cohortId || null;

  const csvFiltered = meetingCohortId
    ? zoomAllStudents.filter(s => s.cohort_id === meetingCohortId)
    : zoomAllStudents;

  // Separar em 3 grupos
  const staff     = zoomParticipantsData.filter(p => p._isStaff && !p.matched);
  const unmatched = zoomParticipantsData.filter(p => !p.matched && !p._isStaff);
  const matched   = zoomParticipantsData.filter(p => p.matched);

  // Optgroups: CSV da turma + CSV outros + Equipe + Legado
  const csvOther = meetingCohortId ? zoomAllStudents.filter(s => s.cohort_id !== meetingCohortId) : [];
  const optCSV = csvFiltered.map(s => `<option value="csv::${s.id}" data-type="csv">${s.name}${s.phone ? ' · '+s.phone.slice(-4) : ''}</option>`).join('');
  const optCSVOther = csvOther.length ? csvOther.map(s => `<option value="csv::${s.id}" data-type="csv">${s.name}</option>`).join('') : '';
  const optStaff = zoomStaffList.map(s => `<option value="staff::${s.id}" data-type="staff">${s.name} (${s.category})</option>`).join('');
  // Legado como fallback para manter FK compatível
  const optLegacy = zoomLegacyStudents.map(s => `<option value="legacy::${s.id}" data-type="legacy">${s.name}</option>`).join('');

  const selectHTML = `
    <option value="">— Vincular a... —</option>
    <optgroup label="Alunos CSV${meetingCohortId ? ' (turma)' : ''}">${optCSV}</optgroup>
    ${optCSVOther ? `<optgroup label="Alunos CSV (outras turmas)">${optCSVOther}</optgroup>` : ''}
    <optgroup label="Equipe">${optStaff}</optgroup>
    <optgroup label="Sistema (legado)">${optLegacy}</optgroup>
  `;

  const staffRowHTML = (p) => {
    const dur = p.duration_minutes;
    const cat = p._staffMatch?.category || 'Equipe';
    const catColors = { Professor: '#a5b4fc', Mentor: '#facc15', Host: '#888' };
    const c = catColors[cat] || '#888';
    const matchLabel = p._staffMatch && normName(p._staffMatch.name) !== normName(p.participant_name)
      ? `<span style="font-size:10px;color:#555;margin-left:4px">→ ${p._staffMatch.name}</span>` : '';
    return `<div class="zoom-part-row" data-name="${p.participant_name}" data-id="${p.id}"
      style="display:flex;align-items:center;gap:12px;padding:10px 16px;border-bottom:1px solid #161625">
      <span style="flex:1;font-size:13px;color:#ccc">${p.participant_name}${matchLabel}</span>
      <span style="font-size:11px;font-weight:700;color:${c};background:${c}15;padding:2px 8px;border-radius:4px">${cat}</span>
      <span style="font-size:11px;color:#555;min-width:60px;text-align:right">${dur} min</span>
    </div>`;
  };

  const matchedRowHTML = (p) => {
    const dur = p.duration_minutes;
    return `<div class="zoom-part-row" data-name="${p.participant_name}" data-id="${p.id}"
      style="display:flex;align-items:center;gap:12px;padding:10px 16px;border-bottom:1px solid #161616">
      <span style="flex:1;font-size:13px;color:#555">${p.participant_name}</span>
      <span style="font-size:12px;color:#4ade80;font-weight:600">${p.students?.name || '—'}</span>
      <span style="font-size:11px;color:#555;min-width:60px;text-align:right">${dur} min</span>
      <button onclick="unlinkParticipant('${p._ids ? p._ids[0] : p.id}')"
        style="font-size:10px;padding:3px 8px;border-radius:4px;border:1px solid #333;background:transparent;color:#555;cursor:pointer">✕</button>
    </div>`;
  };

  const unmatchedRowHTML = (p) => {
    const dur = p.duration_minutes;
    const pct = Math.round(dur / 272 * 100);
    const barColor = dur >= 200 ? '#4ade80' : dur >= 100 ? '#facc15' : '#f87171';
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
        <select class="substitute-select" style="padding:6px 8px;font-size:12px;min-width:220px" id="sel-${p._ids ? p._ids[0] : p.id}">
          ${selectHTML}
        </select>
        <button onclick="linkParticipantNew('${p._ids ? p._ids[0] : p.id}', '${p.participant_name.replace(/'/g, "\\'")}')"
          style="padding:6px 14px;border-radius:6px;border:none;background:#6366f1;color:#fff;font-size:12px;font-weight:700;cursor:pointer">Vincular</button>
      </div>
    </div>`;
  };

  container.innerHTML = `
    ${staff.length ? `
      <div style="font-size:12px;font-weight:700;color:#a5b4fc;text-transform:uppercase;letter-spacing:.06em;margin-bottom:8px">
        🎓 Equipe (${staff.length})
      </div>
      <div style="background:#0d1117;border:1px solid #1a2332;border-radius:12px;overflow:hidden;margin-bottom:20px">
        ${staff.map(staffRowHTML).join('')}
      </div>` : ''}
    ${unmatched.length ? `
      <div style="font-size:12px;font-weight:700;color:#f87171;text-transform:uppercase;letter-spacing:.06em;margin-bottom:8px">
        Não vinculados (${unmatched.length})
      </div>
      <div style="background:#111;border:1px solid #1e1e1e;border-radius:12px;overflow:hidden;margin-bottom:20px">
        ${unmatched.map(unmatchedRowHTML).join('')}
      </div>` : ''}
    ${matched.length ? `
      <details>
        <summary style="font-size:12px;font-weight:700;color:#4ade80;text-transform:uppercase;letter-spacing:.06em;cursor:pointer;margin-bottom:8px">
          ✓ Vinculados (${matched.length})
        </summary>
        <div style="background:#111;border:1px solid #1e1e1e;border-radius:12px;overflow:hidden;margin-top:8px">
          ${matched.map(matchedRowHTML).join('')}
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

// Nova função de vinculação com suporte a CSV/Staff/Legacy + alias persistente
async function linkParticipantNew(partId, zoomName) {
  const sel = document.getElementById(`sel-${partId}`);
  const val = sel?.value;
  if (!val) { showToast('Selecione um aluno ou membro da equipe', 'error'); return; }

  const [type, id] = val.split('::');

  // Encontrar o agrupamento dedup para pegar todos os IDs
  const grouped = zoomParticipantsData.find(p => (p._ids || [p.id]).includes(partId));
  const allIds = grouped?._ids || [partId];

  if (type === 'csv') {
    // Vincular ao CSV: salvar alias no student_imports + vincular via students legado
    const csvStudent = zoomAllStudents.find(s => s.id === id);
    if (csvStudent) {
      // Salvar zoom name como alias no student_imports
      const currentAliases = csvStudent.aliases || [];
      if (!currentAliases.includes(zoomName)) {
        await sb.from('student_imports').update({ aliases: [...currentAliases, zoomName] }).eq('id', id);
        csvStudent.aliases = [...currentAliases, zoomName];
      }
      // Encontrar ou criar registro na tabela students para FK
      let legacyId = null;
      const legacy = zoomLegacyStudents.find(s =>
        (s.phone && csvStudent.phone && s.phone.replace(/\D/g,'').slice(-8) === csvStudent.phone.replace(/\D/g,'').slice(-8)) ||
        (s.name && csvStudent.name && normName(s.name) === normName(csvStudent.name))
      );
      legacyId = legacy?.id || null;
      if (legacyId) {
        for (const pid of allIds) {
          await sb.from('zoom_participants').update({ student_id: legacyId, matched: true }).eq('id', pid);
        }
      } else {
        // Marcar como matched sem student_id (nenhum legado correspondente)
        for (const pid of allIds) {
          await sb.from('zoom_participants').update({ matched: true }).eq('id', pid);
        }
      }
    }
    showToast(`Vinculado a ${csvStudent?.name || 'aluno'} + alias salvo!`, 'success');

  } else if (type === 'staff') {
    // Vincular como equipe: salvar alias no staff
    const staffMember = zoomStaffList.find(s => s.id === id);
    if (staffMember) {
      const currentAliases = staffMember.aliases || [];
      if (!currentAliases.includes(zoomName)) {
        await sb.from('mentors').update({ aliases: [...currentAliases, zoomName] }).eq('id', id);
        staffMember.aliases = [...currentAliases, zoomName];
      }
    }
    // Marcar como matched
    for (const pid of allIds) {
      await sb.from('zoom_participants').update({ matched: true }).eq('id', pid);
    }
    showToast(`Vinculado como equipe (${staffMember?.name}) + alias salvo!`, 'success');

  } else {
    // Legacy: comportamento antigo
    for (const pid of allIds) {
      await sb.from('zoom_participants').update({ student_id: id, matched: true }).eq('id', pid);
    }
    showToast('Vinculado!', 'success');
  }

  await loadZoomParticipants();
}

async function unlinkParticipant(partId) {
  // Encontrar agrupamento para desvincular todos os IDs
  const grouped = zoomParticipantsData.find(p => (p._ids || [p.id]).includes(partId));
  const allIds = grouped?._ids || [partId];
  for (const pid of allIds) {
    await sb.from('zoom_participants').update({ student_id: null, matched: false }).eq('id', pid);
  }
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

// ═══════════════════════════════════════
// APLICAR PRESENÇAS DA EQUIPE VIA ZOOM
// ═══════════════════════════════════════
async function applyStaffAttendanceFromZoom() {
  const meetingId = document.getElementById('zoom-meeting-select').value;
  if (!meetingId) { showToast('Selecione uma reunião primeiro', 'error'); return; }

  const { data: meeting } = await sb
    .from('zoom_meetings')
    .select('id, start_time, topic, cohort_id')
    .eq('id', meetingId)
    .single();

  if (!meeting) { showToast('Reunião não encontrada', 'error'); return; }

  // Converte start_time para dd/mm no fuso de Brasília (UTC-3)
  const utc = new Date(meeting.start_time);
  const brt = new Date(utc.getTime() - 3 * 60 * 60 * 1000);
  const dd  = String(brt.getUTCDate()).padStart(2, '0');
  const mm  = String(brt.getUTCMonth() + 1).padStart(2, '0');
  const dateKey = `${dd}/${mm}`;

  const dayEvents = EVENTS[dateKey];
  if (!dayEvents) {
    showToast(`Nenhuma aula configurada para ${dateKey} no calendário`, 'error');
    return;
  }

  const { data: participants } = await sb
    .from('zoom_participants')
    .select('participant_name, duration_minutes')
    .eq('meeting_id', meetingId);

  if (!participants?.length) {
    showToast('Nenhum participante importado para esta reunião', 'error');
    return;
  }

  // Filtra cursos do dia pelo cohort vinculado à reunião
  let filteredCourses = Object.keys(dayEvents);
  if (meeting.cohort_id) {
    const cohort = (cohortsList || []).find(c => c.id === meeting.cohort_id);
    if (cohort) {
      const cn = cohort.name.toLowerCase();
      const filtered = filteredCourses.filter(ck =>
        ck.toLowerCase() === cn ||
        ck.toLowerCase().includes(cn) ||
        cn.includes(ck.toLowerCase())
      );
      if (filtered.length) filteredCourses = filtered;
    }
  }

  // Coleta equipe escalada apenas nos cursos filtrados
  const scheduled = [];
  for (const course of filteredCourses) {
    for (const m of dayEvents[course].mentors) {
      if (!scheduled.find(s => s.name === m.name && s.course === course)) {
        scheduled.push({ name: m.name, role: m.role, course, dateKey });
      }
    }
  }

  if (!scheduled.length) {
    showToast(`Nenhuma equipe escalada para ${filteredCourses.join(', ')} em ${dateKey}`, 'error');
    return;
  }

  // Fuzzy match equipe × participantes Zoom
  const matches = scheduled.map(staff => {
    let bestPart = null, bestScore = 0;
    for (const p of participants) {
      const score = fuzzyScore(p.participant_name, staff.name);
      if (score > bestScore) { bestScore = score; bestPart = p; }
    }
    const found = bestScore >= 0.72;
    const existing = attendanceCache[`${dateKey}|${staff.course}|${staff.name}`] || null;
    return {
      staff,
      zoomName:   found ? bestPart.participant_name : null,
      duration:   found ? bestPart.duration_minutes : null,
      score:      bestScore,
      found,
      auto:       bestScore >= 0.88,
      existing,
      existingId: existing ? existing.id : null,
    };
  });

  renderStaffAttModal(matches, meeting.topic, dateKey);
}

function renderStaffAttModal(matches, topic, dateKey) {
  const found    = matches.filter(m => m.found);
  const notFound = matches.filter(m => !m.found);

  const rowHTML = m => {
    const pct   = Math.round(m.score * 100);
    const color = m.auto ? '#4ade80' : '#f59e0b';
    if (m.existing) {
      const label = m.existing.status === 'present' ? '✅ presente' : '❌ ausente';
      const c     = m.existing.status === 'present' ? '#4ade80' : '#f87171';
      return `<tr class="staff-att-row" data-date="${m.staff.dateKey}" data-course="${m.staff.course}" data-teacher="${m.staff.name}" data-role="${m.staff.role}" data-existing-id="${m.existingId || ''}">
        <td style="padding:8px 6px;font-size:12px;color:#ccc">${m.staff.name}</td>
        <td style="padding:8px 6px;font-size:11px;color:#666">${m.staff.course.replace('Aulas ','')}</td>
        <td style="padding:8px 6px;font-size:11px;color:#555">${m.staff.role}</td>
        <td style="padding:8px 6px;font-size:12px;color:#aaa">${m.zoomName || '—'}${m.duration ? ` <span style="color:#555">(${m.duration}min)</span>` : ''}</td>
        <td style="padding:8px 6px;text-align:center">${m.found ? `<span style="font-size:11px;font-weight:700;color:${color};background:${color}22;padding:2px 8px;border-radius:999px">${pct}%</span>` : '<span style="color:#333;font-size:11px">—</span>'}</td>
        <td style="padding:8px 6px;text-align:center;white-space:nowrap">
          <span style="font-size:11px;color:${c};margin-right:6px">${label}</span>
          <button onclick="removeStaffAttRow(this)" style="font-size:10px;padding:2px 8px;border-radius:5px;border:1px solid #f87171;background:transparent;color:#f87171;cursor:pointer" title="Remover registro">🗑</button>
        </td>
      </tr>`;
    }
    return `<tr class="staff-att-row" data-date="${m.staff.dateKey}" data-course="${m.staff.course}" data-teacher="${m.staff.name}" data-role="${m.staff.role}">
      <td style="padding:8px 6px;font-size:12px;color:#ccc">${m.staff.name}</td>
      <td style="padding:8px 6px;font-size:11px;color:#666">${m.staff.course.replace('Aulas ','')}</td>
      <td style="padding:8px 6px;font-size:11px;color:#555">${m.staff.role}</td>
      <td style="padding:8px 6px;font-size:12px;color:#aaa">${m.zoomName || '—'}${m.duration ? ` <span style="color:#555">(${m.duration}min)</span>` : ''}</td>
      <td style="padding:8px 6px;text-align:center">${m.found ? `<span style="font-size:11px;font-weight:700;color:${color};background:${color}22;padding:2px 8px;border-radius:999px">${pct}%</span>` : '<span style="color:#555;font-size:11px">não encontrado</span>'}</td>
      <td style="padding:8px 6px;text-align:center"><input type="checkbox" class="staff-att-check" ${m.found ? 'checked' : ''} style="width:16px;height:16px;cursor:pointer"></td>
    </tr>`;
  };

  document.body.insertAdjacentHTML('beforeend', `
  <div id="staff-att-modal" style="position:fixed;inset:0;background:rgba(0,0,0,.8);z-index:2000;display:flex;align-items:center;justify-content:center;padding:16px" onclick="if(event.target===this)closeStaffAttModal()">
    <div style="background:#0f0f0f;border:1px solid #222;border-radius:16px;width:100%;max-width:820px;max-height:88vh;display:flex;flex-direction:column">
      <div style="padding:20px 24px;border-bottom:1px solid #1a1a1a">
        <div style="font-size:15px;font-weight:700;color:#fff">Aplicar Presenças da Equipe</div>
        <div style="font-size:12px;color:#555;margin-top:4px">${topic} · ${dateKey} · ${found.length}/${matches.length} encontrados no Zoom</div>
      </div>
      <div style="overflow-y:auto;flex:1;padding:16px 24px">
        <div style="display:flex;gap:8px;margin-bottom:12px">
          <button onclick="selectAllStaffAtt(true)"  style="font-size:11px;font-weight:700;padding:5px 12px;border-radius:6px;border:1px solid #333;background:transparent;color:#aaa;cursor:pointer">Marcar tudo</button>
          <button onclick="selectAllStaffAtt(false)" style="font-size:11px;font-weight:700;padding:5px 12px;border-radius:6px;border:1px solid #333;background:transparent;color:#aaa;cursor:pointer">Desmarcar tudo</button>
        </div>
        <table style="width:100%;border-collapse:collapse">
          <thead><tr style="color:#444;font-size:10px;text-transform:uppercase;letter-spacing:.05em">
            <th style="padding:6px;text-align:left">Equipe</th>
            <th style="padding:6px;text-align:left">Aula</th>
            <th style="padding:6px;text-align:left">Função</th>
            <th style="padding:6px;text-align:left">Nome no Zoom</th>
            <th style="padding:6px;text-align:center">Confiança</th>
            <th style="padding:6px;text-align:center">Marcar Presente</th>
          </tr></thead>
          <tbody>${matches.map(rowHTML).join('')}</tbody>
        </table>
        ${notFound.length ? `<div style="margin-top:14px;font-size:12px;color:#555;padding:10px;background:#111;border-radius:8px;border:1px solid #1a1a1a">⚠️ ${notFound.length} membro(s) não encontrados no relatório Zoom — verifique o nome no Zoom ou marque manualmente no calendário.</div>` : ''}
      </div>
      <div style="padding:16px 24px;border-top:1px solid #1a1a1a;display:flex;gap:8px;justify-content:flex-end">
        <button onclick="closeStaffAttModal()" style="padding:9px 18px;border-radius:8px;border:1px solid #222;background:transparent;color:#666;font-size:13px;font-weight:600;cursor:pointer">Cancelar</button>
        <button onclick="applyStaffAttendance()" style="padding:9px 18px;border-radius:8px;border:none;background:linear-gradient(135deg,#6366f1,#8b5cf6);color:#fff;font-size:13px;font-weight:700;cursor:pointer">✅ Aplicar Presenças</button>
      </div>
    </div>
  </div>`);
}

function closeStaffAttModal() { document.getElementById('staff-att-modal')?.remove(); }

async function removeStaffAttRow(btn) {
  const row        = btn.closest('tr');
  const dateKey    = row.dataset.date;
  const course     = row.dataset.course;
  const teacher    = row.dataset.teacher;
  const existingId = row.dataset.existingId;

  if (!existingId) { showToast('ID do registro não encontrado', 'error'); return; }

  const { error } = await sb.from('attendance').delete().eq('id', existingId);
  if (error) { showToast('Erro ao remover: ' + error.message, 'error'); return; }

  delete attendanceCache[`${dateKey}|${course}|${teacher}`];
  row.removeAttribute('data-existing-id');
  // Converte a célula de status em checkbox marcado para re-aplicação
  row.cells[5].innerHTML = '<input type="checkbox" class="staff-att-check" checked style="width:16px;height:16px;cursor:pointer">';
  showToast(`Registro de ${teacher} removido`, 'success');
}

function selectAllStaffAtt(checked) {
  document.querySelectorAll('.staff-att-check').forEach(cb => { cb.checked = checked; });
}

async function applyStaffAttendance() {
  const rows   = document.querySelectorAll('.staff-att-row');
  const toSave = [];
  rows.forEach(row => {
    const cb = row.querySelector('.staff-att-check');
    if (cb?.checked) {
      toSave.push({
        lesson_date:  row.dataset.date,
        course:       row.dataset.course,
        teacher_name: row.dataset.teacher,
        role:         row.dataset.role,
        status:       'present',
      });
    }
  });
  if (!toSave.length) { closeStaffAttModal(); return; }
  const ok = await saveAttendance(toSave);
  closeStaffAttModal();
  if (ok) {
    showToast(`✅ ${toSave.length} presenças aplicadas`, 'success');
    renderAll();
  }
}
