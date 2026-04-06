// ═══════════════════════════════════════
// CLASSES MANAGEMENT (Turmas)
// ═══════════════════════════════════════
async function loadClasses() {
  const [{ data: classes }, { data: mentors }, { data: cmData }, { data: cohortsData }, { data: accessData }, { data: ccData }] = await Promise.all([
    sb.from('classes').select('*').order('name'),
    sb.from('mentors').select('id, name, role, active').eq('active', true).order('name'),
    sb.from('class_mentors').select('*').order('weekday'),
    sb.from('cohorts').select('id, name, start_date, end_date').order('name'),
    sb.from('class_cohort_access').select('*'),
    sb.from('class_cohorts').select('class_id, cohort_id'),
  ]);
  classesList = classes || [];
  mentorsList = mentors || [];
  cohortsList = cohortsData || [];

  for (const cohort of cohortsList) {
    const linkedClassIds = (ccData || []).filter(cc => cc.cohort_id === cohort.id).map(cc => cc.class_id);
    const linkedClasses = (classes || []).filter(c => linkedClassIds.includes(c.id));
    let lastDate = null;
    for (const cls of linkedClasses) {
      if (!cls.start_date || !cls.end_date) continue;
      const classMentors = (cmData || []).filter(cm => cm.class_id === cls.id);
      const weekdays = classMentors.length > 0
        ? [...new Set(classMentors.map(cm => cm.weekday ?? cls.weekday).filter(w => w !== null))]
        : cls.weekday !== null ? [cls.weekday] : [];
      for (const wd of weekdays) {
        const dates = generateDates(cls.start_date, cls.end_date, wd);
        if (dates.length > 0) {
          const maxDate = dates[dates.length - 1];
          if (!lastDate || maxDate > lastDate) lastDate = maxDate;
        }
      }
    }
    if (!lastDate && cohort.end_date) lastDate = new Date(cohort.end_date + 'T00:00:00');
    cohort._lastClassDate = lastDate;
  }
  classSchedules = [];
  linkedCohorts = [];
  if (!staffList.length) await loadStaff();

  for (const c of classesList) {
    c._mentors = (cmData || []).filter(cm => cm.class_id === c.id);
    c._linkedCohorts = (accessData || []).filter(a => a.class_id === c.id);
  }

  EVENTS = buildEventsFromDB();
  renderClassesList();
}

function renderClassesList() {
  if (!classesList.length) {
    document.getElementById('classes-list').innerHTML = '<div style="text-align:center;color:#333;padding:40px">Nenhuma turma cadastrada</div>';
    return;
  }

  const cards = classesList.map(c => {
    const startFmt = new Date(c.start_date + 'T00:00:00').toLocaleDateString('pt-BR');
    const endFmt = new Date(c.end_date + 'T00:00:00').toLocaleDateString('pt-BR');
    const typeBadge = c.type ? `<span style="font-size:10px;padding:2px 8px;border-radius:999px;background:rgba(99,102,241,0.12);color:#a5b4fc;font-weight:700">${c.type}</span>` : '';

    const byDay = {};
    for (const cm of (c._mentors || [])) {
      if (cm.valid_until !== null && cm.valid_until !== undefined) continue;
      const wd = cm.weekday ?? c.weekday ?? 0;
      if (!byDay[wd]) byDay[wd] = [];
      byDay[wd].push({ name: getMentorName(cm.mentor_id), role: cm.role });
    }

    if (Object.keys(byDay).length === 0 && (c.professor || c.host)) {
      const wd = c.weekday || 0;
      byDay[wd] = [];
      if (c.professor) byDay[wd].push({ name: c.professor, role: 'Professor' });
      if (c.host) byDay[wd].push({ name: c.host, role: 'Host' });
    }

    const closedDates = [...new Set((c._mentors || [])
      .filter(cm => cm.valid_until)
      .map(cm => cm.valid_until)
    )].sort();
    const cyclesBadge = closedDates.length > 0
      ? `<div style="margin-top:6px;display:flex;flex-wrap:wrap;gap:4px">${closedDates.map(d => {
          const fmt = new Date(d + 'T00:00:00').toLocaleDateString('pt-BR');
          return `<span style="display:inline-flex;align-items:center;gap:4px;font-size:9px;padding:2px 7px;border-radius:4px;background:rgba(99,102,241,0.12);color:#a5b4fc;font-weight:700">🔒 Ciclo fechado ${fmt}<button onclick="event.stopPropagation();reopenClassCycle('${c.id}','${d}')" style="font-size:9px;padding:1px 5px;border-radius:3px;border:1px solid #6366f150;background:rgba(99,102,241,0.2);color:#a5b4fc;cursor:pointer;font-family:var(--font-sans);line-height:1">↩ Reabrir</button></span>`;
        }).join('')}</div>`
      : '';

    const daysHtml = Object.entries(byDay).sort((a,b) => a[0]-b[0]).map(([wd, members]) => {
      const people = members.map(m => {
        const color = m.role === 'Professor' ? '#a5b4fc' : m.role === 'Host' ? '#555' : '#facc15';
        return `<span style="font-size:11px;color:${color}">${m.name} <span style="font-size:9px;color:#333">(${m.role})</span></span>`;
      }).join(', ');
      return `<div style="font-size:12px;margin-bottom:4px"><span style="color:#555;font-weight:600">${WEEKDAY_FULL[wd] || 'Dia '+wd}:</span> ${people}</div>`;
    }).join('');

    const allDates = [];
    const weekdays = Object.keys(byDay).length > 0 ? Object.keys(byDay).map(Number) : (c.weekday !== null ? [c.weekday] : []);
    for (const wd of weekdays) {
      allDates.push(...generateDates(c.start_date, c.end_date, wd));
    }
    allDates.sort((a,b) => a-b);

    return `<div class="report-card" style="border-left:3px solid ${c.color || '#666'}">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:8px">
        <div style="display:flex;align-items:center;gap:8px">
          <div style="font-size:16px;font-weight:800;color:#fff">${c.name}</div>
          ${typeBadge}
        </div>
        <div style="display:flex;gap:6px">
          <button class="att-btn" style="padding:6px 10px;font-size:11px" onclick="event.stopPropagation();editClass('${c.id}')">Editar</button>
          <button class="att-btn" style="padding:6px 10px;font-size:11px;background:rgba(34,197,94,0.12);color:#4ade80;border-color:#22c55e30" onclick="event.stopPropagation();openNewCycle('${c.id}','${c.name}')">+ Novo Ciclo</button>
          <button class="att-btn" style="padding:6px 10px;font-size:11px;background:rgba(239,68,68,0.1);color:#f87171;border-color:#ef444430" onclick="event.stopPropagation();finalizeClass('${c.id}','${c.name}')">Encerrar Turma</button>
          <button class="att-btn delete" style="padding:6px 8px" onclick="event.stopPropagation();deleteClass('${c.id}','${c.name}')">🗑</button>
        </div>
      </div>
      <div style="font-size:12px;color:#555;margin-bottom:10px">
        ${c.time_start || ''}–${c.time_end || ''} | ${startFmt} a ${endFmt} | ${allDates.length} aulas
      </div>
      ${daysHtml}
      ${cyclesBadge}
      ${(c._linkedCohorts || []).length > 0 ? `
      <div style="margin-top:8px;padding-top:8px;border-top:1px solid #141414">
        <div style="font-size:10px;font-weight:700;color:#555;text-transform:uppercase;letter-spacing:0.05em;margin-bottom:4px">Turmas vinculadas</div>
        ${(c._linkedCohorts || []).map(lc => {
          const cohort = cohortsList.find(x => x.id === lc.cohort_id);
          const name = cohort ? cohort.name : '?';
          const until = lc.access_until ? new Date(lc.access_until + 'T00:00:00').toLocaleDateString('pt-BR') : '?';
          const isExpired = lc.access_until && new Date(lc.access_until) < new Date();
          const daysLeft = lc.access_until ? Math.ceil((new Date(lc.access_until) - new Date()) / 86400000) : null;
          const badge = isExpired
            ? '<span style="font-size:9px;padding:2px 6px;border-radius:4px;background:rgba(239,68,68,0.12);color:#f87171;font-weight:700">Encerrado</span>'
            : daysLeft <= 15
              ? '<span style="font-size:9px;padding:2px 6px;border-radius:4px;background:rgba(245,158,11,0.12);color:#fbbf24;font-weight:700">' + daysLeft + ' dias</span>'
              : '<span style="font-size:9px;padding:2px 6px;border-radius:4px;background:rgba(34,197,94,0.12);color:#4ade80;font-weight:700">' + daysLeft + ' dias</span>';
          return '<div style="font-size:11px;color:#888;margin-bottom:2px">' + name + ' — até ' + until + ' ' + badge + '</div>';
        }).join('')}
      </div>` : ''}
      <div style="display:flex;flex-wrap:wrap;gap:3px;margin-top:8px">
        ${allDates.slice(0,30).map(d => `<span style="font-size:9px;padding:2px 5px;border-radius:3px;background:${(c.color||'#666')}15;border:1px solid ${(c.color||'#666')}30;color:${c.color||'#666'}">${fmtDate(d)}</span>`).join('')}
        ${allDates.length > 30 ? `<span style="font-size:9px;color:#333">+${allDates.length-30}</span>` : ''}
      </div>
    </div>`;
  }).join('');

  document.getElementById('classes-list').innerHTML = cards;
}

// Schedule day builder
function addScheduleDay() {
  const idx = classSchedules.length;
  classSchedules.push({ weekday: 1, professors: [], mentors: [], hosts: [] });
  renderScheduleDays();
}

function removeScheduleDay(idx) {
  classSchedules.splice(idx, 1);
  renderScheduleDays();
}

function addMemberToDay(idx, role) {
  classSchedules[idx][role].push('');
  renderScheduleDays();
}

function removeMemberFromDay(idx, role, mIdx) {
  classSchedules[idx][role].splice(mIdx, 1);
  renderScheduleDays();
}

function updateDayWeekday(idx, val) {
  classSchedules[idx].weekday = parseInt(val);
}

function updateMember(idx, role, mIdx, val) {
  classSchedules[idx][role][mIdx] = val;
}

function renderScheduleDays() {
  const container = document.getElementById('schedule-days-container');
  if (!container) return;
  const mentorOpts = (mentorsList || []).map(m => `<option value="${m.id}">${m.name}</option>`).join('');

  container.innerHTML = classSchedules.map((day, idx) => `
    <div style="background:#0d0d0d;border:1px solid #1e1e1e;border-radius:10px;padding:14px;margin-bottom:10px">
      <div style="display:flex;align-items:center;gap:10px;margin-bottom:10px">
        <select class="substitute-select" style="padding:8px 10px;flex:0 0 160px" onchange="updateDayWeekday(${idx},this.value)">
          <option value="1" ${day.weekday===1?'selected':''}>Segunda-feira</option>
          <option value="2" ${day.weekday===2?'selected':''}>Terça-feira</option>
          <option value="3" ${day.weekday===3?'selected':''}>Quarta-feira</option>
          <option value="4" ${day.weekday===4?'selected':''}>Quinta-feira</option>
          <option value="5" ${day.weekday===5?'selected':''}>Sexta-feira</option>
          <option value="6" ${day.weekday===6?'selected':''}>Sábado</option>
          <option value="0" ${day.weekday===0?'selected':''}>Domingo</option>
        </select>
        <span style="flex:1"></span>
        <button class="att-btn delete" style="padding:4px 8px;font-size:10px" onclick="removeScheduleDay(${idx})">Remover dia</button>
      </div>
      ${renderMemberSection(idx, 'professors', 'Professor', mentorOpts, '#a5b4fc')}
      ${renderMemberSection(idx, 'mentors', 'Mentor', mentorOpts, '#facc15')}
      ${renderMemberSection(idx, 'hosts', 'Host', mentorOpts, '#888')}
    </div>
  `).join('');
}

function renderMemberSection(dayIdx, role, label, mentorOptsUnused, color) {
  const members = classSchedules[dayIdx][role];
  return `
    <div style="margin-bottom:8px">
      <div style="display:flex;align-items:center;gap:6px;margin-bottom:4px">
        <span style="font-size:11px;font-weight:700;color:${color}">${label}</span>
        <button style="font-size:10px;padding:2px 8px;border-radius:4px;border:1px solid ${color}40;background:${color}15;color:${color};cursor:pointer;font-family:var(--font-sans)" onclick="addMemberToDay(${dayIdx},'${role}')">+</button>
      </div>
      ${members.map((mId, mIdx) => {
        const opts = (mentorsList || []).map(m =>
          `<option value="${m.id}"${m.id === mId ? ' selected' : ''}>${m.name}</option>`
        ).join('');
        return `
        <div style="display:flex;gap:4px;margin-bottom:4px">
          <select class="substitute-select" style="flex:1;padding:6px 8px;font-size:12px" onchange="updateMember(${dayIdx},'${role}',${mIdx},this.value)">
            <option value="">— Selecione —</option>
            ${opts}
          </select>
          <button class="att-btn delete" style="padding:4px 6px;font-size:10px" onclick="removeMemberFromDay(${dayIdx},'${role}',${mIdx})">✕</button>
        </div>`;
      }).join('')}
    </div>`;
}

// Linked cohorts builder
function addLinkedCohort() {
  linkedCohorts.push({ cohort_id: '', access_until: '' });
  renderLinkedCohorts();
}

function removeLinkedCohort(idx) {
  linkedCohorts.splice(idx, 1);
  renderLinkedCohorts();
}

function updateLinkedCohort(idx, field, val) {
  linkedCohorts[idx][field] = val;
  if (field === 'cohort_id' && val) {
    const cohort = cohortsList.find(c => c.id === val);
    const refDate = cohort?._lastClassDate || (cohort?.end_date ? new Date(cohort.end_date + 'T00:00:00') : null);
    if (refDate) {
      const until = new Date(refDate);
      until.setDate(until.getDate() + 30);
      linkedCohorts[idx].access_until = until.toISOString().split('T')[0];
      renderLinkedCohorts();
    }
  }
}

function renderLinkedCohorts() {
  const container = document.getElementById('linked-cohorts-container');
  if (!container) return;
  const cohortOpts = (cohortsList || []).map(c => `<option value="${c.id}">${c.name}</option>`).join('');

  container.innerHTML = linkedCohorts.map((lc, idx) => {
    const isExpired = lc.access_until && new Date(lc.access_until) < new Date();
    const daysLeft = lc.access_until ? Math.ceil((new Date(lc.access_until) - new Date()) / 86400000) : null;
    const statusBadge = isExpired
      ? '<span style="font-size:10px;padding:2px 6px;border-radius:4px;background:rgba(239,68,68,0.12);color:#f87171;font-weight:700">Encerrado</span>'
      : daysLeft !== null && daysLeft <= 15
        ? `<span style="font-size:10px;padding:2px 6px;border-radius:4px;background:rgba(245,158,11,0.12);color:#fbbf24;font-weight:700">${daysLeft} dias</span>`
        : daysLeft !== null
          ? `<span style="font-size:10px;padding:2px 6px;border-radius:4px;background:rgba(34,197,94,0.12);color:#4ade80;font-weight:700">${daysLeft} dias</span>`
          : '';

    return `<div style="display:flex;gap:8px;align-items:center;margin-bottom:6px">
      <select class="substitute-select" style="flex:1;padding:8px 10px" onchange="updateLinkedCohort(${idx},'cohort_id',this.value)">
        <option value="">— Selecione turma —</option>
        ${cohortOpts.replace(`value="${lc.cohort_id}"`, `value="${lc.cohort_id}" selected`)}
      </select>
      <div style="display:flex;align-items:center;gap:4px">
        <label style="font-size:10px;color:#555;white-space:nowrap">Acesso até:</label>
        <input type="date" class="login-field" style="margin:0;padding:6px 8px;width:150px;font-size:12px" value="${lc.access_until || ''}" onchange="updateLinkedCohort(${idx},'access_until',this.value)">
      </div>
      ${statusBadge}
      <button class="att-btn delete" style="padding:4px 6px;font-size:10px" onclick="removeLinkedCohort(${idx})">✕</button>
    </div>`;
  }).join('') || '<div style="font-size:11px;color:#333;padding:8px">Nenhuma turma vinculada. Clique "+ Turma" para vincular.</div>';
}

function openClassForm() {
  const form = document.getElementById('class-form-container');
  form.setAttribute('style', 'display:block !important;background:#111;border:1px solid #1e1e1e;border-radius:12px;padding:20px;margin-bottom:16px');
  document.getElementById('class-edit-id').value = '';
  document.getElementById('class-name').value = '';
  document.getElementById('class-type').value = 'PS';
  document.getElementById('class-start').value = '2026-02-01';
  document.getElementById('class-end').value = '2026-05-31';
  document.getElementById('class-time-start').value = '18:00';
  document.getElementById('class-time-end').value = '20:00';
  document.getElementById('class-color').value = '#6366f1';
  classSchedules = [];
  linkedCohorts = [];
  renderScheduleDays();
  renderLinkedCohorts();
  document.getElementById('class-name').focus();
}

function closeClassForm() {
  document.getElementById('class-form-container').setAttribute('style', 'display:none');
  classSchedules = [];
  linkedCohorts = [];
}

function editClass(id) {
  const c = classesList.find(x => x.id === id);
  if (!c) { alert('Turma não encontrada: ' + id); return; }

  const form = document.getElementById('class-form-container');
  form.setAttribute('style', 'display:block !important;background:#111;border:1px solid #1e1e1e;border-radius:12px;padding:20px;margin-bottom:16px');

  document.getElementById('class-edit-id').value = c.id;
  document.getElementById('class-name').value = c.name || '';
  document.getElementById('class-type').value = c.type || 'PS';
  document.getElementById('class-start').value = c.start_date || '';
  document.getElementById('class-end').value = c.end_date || '';
  document.getElementById('class-time-start').value = c.time_start || '18:00';
  document.getElementById('class-time-end').value = c.time_end || '20:00';
  document.getElementById('class-color').value = c.color || '#6366f1';

  const byDay = {};
  for (const cm of (c._mentors || [])) {
    if (cm.valid_until !== null && cm.valid_until !== undefined) continue;
    const wd = cm.weekday !== null ? cm.weekday : (c.weekday !== null ? c.weekday : 1);
    if (!byDay[wd]) byDay[wd] = { weekday: wd, professors: [], mentors: [], hosts: [] };
    const roleKey = cm.role === 'Professor' ? 'professors' : cm.role === 'Host' ? 'hosts' : 'mentors';
    byDay[wd][roleKey].push(cm.mentor_id);
  }

  if (Object.keys(byDay).length === 0 && c.weekday !== null) {
    byDay[c.weekday] = { weekday: c.weekday, professors: [], mentors: [], hosts: [] };
  }

  classSchedules = Object.values(byDay);
  renderScheduleDays();

  linkedCohorts = (c._linkedCohorts || []).map(lc => ({
    cohort_id: lc.cohort_id,
    access_until: lc.access_until || '',
  }));
  renderLinkedCohorts();

  form.scrollIntoView({ behavior: 'smooth', block: 'start' });
}

async function saveClassV2() {
  const id = document.getElementById('class-edit-id').value;
  const name = document.getElementById('class-name').value.trim();
  const type = document.getElementById('class-type').value;
  const start_date = document.getElementById('class-start').value;
  const end_date = document.getElementById('class-end').value;
  const time_start = document.getElementById('class-time-start').value;
  const time_end = document.getElementById('class-time-end').value;
  const color = document.getElementById('class-color').value;

  if (!name || !start_date || !end_date) { showToast('Preencha nome e datas', 'error'); return; }

  const saveBtn = document.getElementById('save-class-btn');
  saveBtn.disabled = true;
  saveBtn.textContent = 'Salvando...';

  const weekday = classSchedules.length > 0 ? classSchedules[0].weekday : 1;
  const record = { name, type, start_date, end_date, weekday, time_start, time_end, color, active: true };

  let classId = id;
  if (id) {
    const { error } = await sb.from('classes').update(record).eq('id', id);
    if (error) { showToast('Erro: ' + error.message, 'error'); saveBtn.disabled = false; saveBtn.textContent = 'Salvar Turma'; return; }
  } else {
    const { data, error } = await sb.from('classes').insert(record).select().single();
    if (error) { showToast('Erro: ' + error.message, 'error'); saveBtn.disabled = false; saveBtn.textContent = 'Salvar Turma'; return; }
    classId = data.id;
  }

  const { data: activeRecords } = await sb.from('class_mentors')
    .select('valid_from').eq('class_id', classId).is('valid_until', null).limit(1);
  const today = new Date().toISOString().split('T')[0];
  const activeValidFrom = activeRecords && activeRecords.length > 0 ? activeRecords[0].valid_from : today;
  await sb.from('class_mentors').delete().eq('class_id', classId).is('valid_until', null);

  const mentorRows = [];
  for (const day of classSchedules) {
    for (const mId of day.professors) {
      if (mId) mentorRows.push({ class_id: classId, mentor_id: mId, role: 'Professor', weekday: day.weekday, valid_from: activeValidFrom });
    }
    for (const mId of day.mentors) {
      if (mId) mentorRows.push({ class_id: classId, mentor_id: mId, role: 'Mentor', weekday: day.weekday, valid_from: activeValidFrom });
    }
    for (const mId of day.hosts) {
      if (mId) mentorRows.push({ class_id: classId, mentor_id: mId, role: 'Host', weekday: day.weekday, valid_from: activeValidFrom });
    }
  }

  if (mentorRows.length > 0) {
    const { error } = await sb.from('class_mentors').insert(mentorRows);
    if (error) { showToast('Erro ao salvar equipe: ' + error.message, 'error'); }
  }

  await sb.from('class_cohort_access').delete().eq('class_id', classId);
  const cohortRows = linkedCohorts
    .filter(lc => lc.cohort_id && lc.access_until)
    .map(lc => ({ class_id: classId, cohort_id: lc.cohort_id, access_until: lc.access_until }));
  if (cohortRows.length > 0) {
    const { error } = await sb.from('class_cohort_access').insert(cohortRows);
    if (error) { showToast('Erro ao salvar turmas vinculadas: ' + error.message, 'error'); saveBtn.disabled = false; saveBtn.textContent = 'Salvar Turma'; return; }
  }

  showToast(id ? 'Turma atualizada!' : 'Turma criada!', 'success');
  saveBtn.disabled = false;
  saveBtn.textContent = 'Salvar Turma';
  closeClassForm();
  await loadClasses();
  renderAll();
}

async function finalizeClass(classId, className) {
  if (!confirm(`Encerrar a turma "${className}"?\n\nA equipe atual será encerrada e não haverá novo ciclo.\nA turma continuará aparecendo no calendário como histórico.\n\nUse "↩ Reabrir" no badge se precisar desfazer.`)) return;

  const today = new Date().toISOString().split('T')[0];

  const { error } = await sb.from('class_mentors')
    .update({ valid_until: today }).eq('class_id', classId).is('valid_until', null);
  if (error) { showToast('Erro ao encerrar turma: ' + error.message, 'error'); return; }

  const fmt = new Date(today + 'T00:00:00').toLocaleDateString('pt-BR');
  showToast(`Turma "${className}" encerrada em ${fmt}. Histórico preservado no calendário.`, 'success');
  await loadClasses();
  renderAll();
}

async function openNewCycle(classId, className) {
  if (!confirm(`Iniciar novo ciclo de presenças para "${className}"?\n\nO ciclo atual será fechado (histórico preservado) e um novo ciclo começará com a mesma equipe.\n\nUse o botão "↩ Reabrir" no badge do ciclo para voltar e editar um ciclo anterior.`)) return;

  await closeClassCycle(classId, className, true);
}

async function closeClassCycle(classId, className, skipConfirm = false) {
  if (!skipConfirm && !confirm(`Fechar ciclo atual de "${className}"?\n\nA equipe atual será congelada. Você poderá editar livremente sem afetar o histórico.`)) return;

  const today = new Date().toISOString().split('T')[0];
  const tomorrow = new Date(Date.now() + 86400000).toISOString().split('T')[0];

  const { data: activeRows, error: fetchErr } = await sb.from('class_mentors')
    .select('*').eq('class_id', classId).is('valid_until', null);
  if (fetchErr) { showToast('Erro: ' + fetchErr.message, 'error'); return; }

  const { error: closeErr } = await sb.from('class_mentors')
    .update({ valid_until: today }).eq('class_id', classId).is('valid_until', null);
  if (closeErr) { showToast('Erro ao fechar ciclo: ' + closeErr.message, 'error'); return; }

  const newRows = (activeRows || []).map(r => ({
    class_id: r.class_id, mentor_id: r.mentor_id, role: r.role,
    weekday: r.weekday, valid_from: tomorrow, valid_until: null,
  }));
  const { error: insertErr } = await sb.from('class_mentors').insert(newRows);
  if (insertErr) { showToast('Erro ao criar novo ciclo: ' + insertErr.message, 'error'); return; }

  const closedDate = new Date(today + 'T00:00:00').toLocaleDateString('pt-BR');
  showToast(`Ciclo fechado em ${closedDate}. Equipe pode ser editada livremente.`, 'success');
  await loadClasses();
  renderAll();
}

async function reopenClassCycle(classId, closedDate) {
  const fmt = new Date(closedDate + 'T00:00:00').toLocaleDateString('pt-BR');
  if (!confirm(`Reabrir ciclo fechado em ${fmt}?\n\nOs registros novos criados após o fechamento serão removidos e o ciclo anterior será restaurado.`)) return;

  const dayAfter = new Date(new Date(closedDate + 'T00:00:00').getTime() + 86400000).toISOString().split('T')[0];

  const { error: deleteErr } = await sb.from('class_mentors')
    .delete()
    .eq('class_id', classId)
    .eq('valid_from', dayAfter)
    .is('valid_until', null);
  if (deleteErr) { showToast('Erro ao remover registros novos: ' + deleteErr.message, 'error'); return; }

  const { error: reopenErr } = await sb.from('class_mentors')
    .update({ valid_until: null })
    .eq('class_id', classId)
    .eq('valid_until', closedDate);
  if (reopenErr) { showToast('Erro ao reabrir ciclo: ' + reopenErr.message, 'error'); return; }

  showToast(`Ciclo de ${fmt} reaberto com sucesso.`, 'success');
  await loadClasses();
  renderAll();
}

async function deleteClass(id, name) {
  if (!confirm(`Excluir a turma "${name}"?\n\nIsso vai remover todos os mentores e vínculos de cohort associados.\nEsta ação não pode ser desfeita.`)) return;
  await sb.from('class_mentors').delete().eq('class_id', id);
  const { error } = await sb.from('classes').delete().eq('id', id);
  if (error) { showToast('Erro: ' + error.message, 'error'); return; }
  showToast(`Turma "${name}" removida`, 'success');
  await loadClasses();
  renderAll();
}
