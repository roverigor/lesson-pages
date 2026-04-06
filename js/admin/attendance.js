// ═══════════════════════════════════════
// LOAD ATTENDANCE FROM SUPABASE
// ═══════════════════════════════════════
async function loadAttendance() {
  const sixMonthsAgo = new Date();
  sixMonthsAgo.setMonth(sixMonthsAgo.getMonth() - 6);
  const { data, error } = await sb
    .from('attendance')
    .select('*')
    .gte('lesson_date', sixMonthsAgo.toISOString().split('T')[0])
    .limit(2000);

  if (error) { console.error('Load attendance error:', error); return; }

  attendanceCache = {};
  for (const row of (data || [])) {
    const [yyyy, mm, dd] = (row.lesson_date || '').split('-');
    const dateShort = dd && mm ? `${dd}/${mm}` : row.lesson_date;
    const key = `${dateShort}|${row.course}|${row.teacher_name}`;
    attendanceCache[key] = {
      id: row.id,
      status: row.status,
      substitute_name: row.substitute_name,
      substitute_role: row.substitute_role,
      notes: row.notes,
    };
  }
}

// ═══════════════════════════════════════
// SAVE ATTENDANCE
// ═══════════════════════════════════════
async function saveAttendance(records) {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) { showToast('Sessão expirada. Faça login novamente.', 'error'); return false; }

  const upsertRows = records.map(rec => {
    const [dd, mm] = rec.lesson_date.split('/');
    const isoDate = `${currentYear}-${mm.padStart(2,'0')}-${dd.padStart(2,'0')}`;
    return {
      lesson_date: isoDate,
      course: rec.course,
      teacher_name: rec.teacher_name,
      role: rec.role,
      status: rec.status,
      substitute_name: rec.substitute_name || null,
      substitute_role: rec.substitute_role || null,
      notes: rec.notes || null,
      recorded_by: session.user.id,
    };
  });

  const { error: upsertError } = await sb
    .from('attendance')
    .upsert(upsertRows, { onConflict: 'lesson_date,course,teacher_name' });

  if (upsertError) {
    console.error('Upsert error:', upsertError);
    showToast('Erro ao salvar: ' + upsertError.message, 'error');
    return false;
  }

  await loadAttendance();
  return true;
}

// ═══════════════════════════════════════
// RENDER
// ═══════════════════════════════════════
function renderAll() {
  renderStats();
  renderGrid(currentYear, currentMonth);
}

function renderStats() {
  const totalLessons = Object.keys(EVENTS).length;
  let recorded = 0;
  let presents = 0;
  let absents = 0;
  for (const key in attendanceCache) {
    recorded++;
    if (attendanceCache[key].status === 'present') presents++;
    else absents++;
  }

  document.getElementById('stats-bar').innerHTML = `
    <div class="stat-card">
      <span style="font-size:20px">👥</span>
      <div><div class="stat-num">${TEACHERS.length}</div><div class="stat-label">Professores</div></div>
    </div>
    <div class="stat-card">
      <span style="font-size:20px">📆</span>
      <div><div class="stat-num">${totalLessons}</div><div class="stat-label">Dias com aula</div></div>
    </div>
    <div class="stat-card">
      <span style="font-size:20px">✅</span>
      <div><div class="stat-num">${presents}</div><div class="stat-label">Presenças</div></div>
    </div>
    <div class="stat-card">
      <span style="font-size:20px">❌</span>
      <div><div class="stat-num">${absents}</div><div class="stat-label">Faltas</div></div>
    </div>
    <div class="stat-card">
      <span style="font-size:20px">📋</span>
      <div><div class="stat-num">${recorded}</div><div class="stat-label">Registros</div></div>
    </div>
  `;
}

function getDateAttStatus(dateKey) {
  const events = EVENTS[dateKey];
  if (!events) return 'none';
  let total = 0;
  let recorded = 0;
  for (const course in events) {
    for (const m of events[course].mentors) {
      total++;
      const key = `${dateKey}|${course}|${m.name}`;
      if (attendanceCache[key]) recorded++;
    }
  }
  if (recorded === 0) return 'none';
  if (recorded >= total) return 'complete';
  return 'partial';
}

function renderGrid(year, month1) {
  currentYear = year;
  currentMonth = month1;
  document.getElementById('month-name-label').textContent = MONTH_NAMES[month1-1];

  const firstDay = new Date(year, month1-1, 1).getDay();
  const startOffset = (firstDay + 6) % 7;
  const daysInMonth = new Date(year, month1, 0).getDate();
  const t = todayDate();
  const totalCells = Math.ceil((startOffset + daysInMonth) / 7) * 7;

  let html = '';
  for (let i = 0; i < totalCells; i++) {
    const dayNum = i - startOffset + 1;
    if (dayNum < 1 || dayNum > daysInMonth) { html += '<div class="cal-cell empty"></div>'; continue; }

    const key = dateStr(dayNum, month1);
    const events = EVENTS[key] ? Object.values(EVENTS[key]) : [];
    const cellDate = new Date(year, month1-1, dayNum); cellDate.setHours(0,0,0,0);
    const isPast = cellDate < t;
    const isToday = cellDate.getTime() === t.getTime();

    let classes = 'cal-cell';
    if (events.length) classes += ' has-events';
    if (isToday) classes += ' is-today';
    else if (isPast) classes += ' is-past';

    const attStatus = getDateAttStatus(key);
    const indicator = events.length
      ? `<span class="att-indicator att-${attStatus}" title="${attStatus === 'complete' ? 'Completo' : attStatus === 'partial' ? 'Parcial' : 'Sem registro'}"></span>`
      : '';

    const eventsHTML = events.slice(0, 3).map(ev => {
      const cfg = getCfg(ev.course);
      return `<div class="day-event" style="border-color:${cfg.color};color:${cfg.color};background:${cfg.bg}">${ev.course.replace('Aulas ','')}</div>`;
    }).join('') + (events.length > 3 ? `<div style="font-size:10px;color:#444">+${events.length-3} mais</div>` : '');

    html += `<div class="${classes}" onclick="openAttendance('${key}')">
      <div class="day-num ${events.length?'has-events':''}">
        ${dayNum} ${isToday ? '<span class="today-badge">Hoje</span>' : ''} ${indicator}
      </div>
      ${eventsHTML}
    </div>`;
  }

  document.getElementById('cal-grid').innerHTML = html;
  document.querySelectorAll('.month-tab').forEach((btn, i) => {
    btn.classList.toggle('active', MONTHS[i].m === month1);
  });
}

// ═══════════════════════════════════════
// ATTENDANCE MODAL
// ═══════════════════════════════════════
function openAttendance(dateKey) {
  const events = EVENTS[dateKey] ? Object.values(EVENTS[dateKey]) : [];
  const originalEvents = buildOriginalEventsForDate(dateKey);
  const allCourses = new Set([...Object.keys(events.length ? EVENTS[dateKey] : {}), ...Object.keys(originalEvents)]);

  if (!allCourses.size) return;
  modalDateKey = dateKey;

  const [dd, mm] = dateKey.split('/');
  const date = new Date(2026, parseInt(mm)-1, parseInt(dd));
  const weekday = ['Domingo','Segunda-feira','Terça-feira','Quarta-feira','Quinta-feira','Sexta-feira','Sábado'][date.getDay()];

  const allNames = staffList.length > 0
    ? staffList.map(s => s.name)
    : TEACHERS.map(t => t.name);

  const removedForDate = overridesCache.filter(o => o.lesson_date === dateKey && o.action === 'remove');

  const sessionsHTML = events.map(ev => {
    const cfg = getCfg(ev.course);
    const courseId = ev.course.replace(/[^a-zA-Z0-9]/g, '');

    const mentorsHTML = ev.mentors.map(m => {
      const cacheKey = `${dateKey}|${ev.course}|${m.name}`;
      const cached = attendanceCache[cacheKey] || {};
      const isPresent = cached.status === 'present';
      const isAbsent = cached.status === 'absent';
      const isAdded = overridesCache.some(o => o.lesson_date === dateKey && o.course === ev.course && o.teacher_name === m.name && o.action === 'add');

      const nameOptions = allNames
        .filter(n => n !== m.name)
        .map(n => `<option value="${n}" ${cached.substitute_name === n ? 'selected' : ''}>${n}</option>`)
        .join('');

      return `
        <div class="att-row">
          <div class="att-avatar" style="background:${mentorColor(m.name)}">${initials(m.name)}</div>
          <div class="att-info">
            <div class="att-name">${m.name} ${isAdded ? '<span style="font-size:9px;color:#facc15;background:rgba(250,204,21,0.1);padding:1px 5px;border-radius:3px">adicionado</span>' : ''}</div>
            <div class="att-role">${m.role}</div>
          </div>
          <div class="att-actions">
            <button class="att-btn present ${isPresent?'active':''} ${isAbsent?'dimmed':''}"
              data-date="${dateKey}" data-course="${ev.course}" data-teacher="${m.name}" data-role="${m.role}" data-action="present"
              onclick="toggleAtt(this)">Presente</button>
            <button class="att-btn absent ${isAbsent?'active':''} ${isPresent?'dimmed':''}"
              data-date="${dateKey}" data-course="${ev.course}" data-teacher="${m.name}" data-role="${m.role}" data-action="absent"
              onclick="toggleAtt(this)">Falta</button>
            ${cached.status ? `<button class="att-btn delete" title="Excluir registro de presença"
              data-date="${dateKey}" data-course="${ev.course}" data-teacher="${m.name}"
              onclick="deleteAtt(this)">🗑</button>` : ''}
            ${isAdded
              ? `<button class="att-btn delete" title="Desfazer adição" onclick="undoAdd('${dateKey}','${ev.course}','${m.name}')" style="font-size:11px;padding:6px 8px">↩</button>`
              : `<button class="att-btn delete" title="Remover da aula"
                data-date="${dateKey}" data-course="${ev.course}" data-teacher="${m.name}"
                onclick="removeFromLesson(this)" style="font-size:11px;padding:6px 8px">✕</button>`
            }
          </div>
        </div>
        <div class="substitute-row show">
          <span class="substitute-label">Substituto:</span>
          <select class="substitute-select"
            data-date="${dateKey}" data-course="${ev.course}" data-teacher="${m.name}">
            <option value="">— Nenhum —</option>
            ${nameOptions}
          </select>
          <select class="substitute-select" style="max-width:120px"
            data-date="${dateKey}" data-course="${ev.course}" data-teacher="${m.name}" data-field="role">
            <option value="Professor" ${(cached.substitute_role||'Professor')==='Professor'?'selected':''}>Professor</option>
            <option value="Mentor" ${cached.substitute_role==='Mentor'?'selected':''}>Mentor</option>
            <option value="Host" ${cached.substitute_role==='Host'?'selected':''}>Host</option>
          </select>
        </div>`;
    }).join('');

    const removedForCourse = removedForDate.filter(o => o.course === ev.course);
    const removedHTML = removedForCourse.map(o => `
      <div class="att-row" style="opacity:0.4">
        <div class="att-avatar" style="background:#333">${initials(o.teacher_name)}</div>
        <div class="att-info">
          <div class="att-name" style="text-decoration:line-through;color:#555">${o.teacher_name}</div>
          <div class="att-role" style="color:#7f1d1d">Removido</div>
        </div>
        <div class="att-actions">
          <button class="att-btn" onclick="undoRemove('${dateKey}','${ev.course}','${o.teacher_name}')" style="padding:6px 10px;font-size:11px;color:#facc15;border-color:#854d0e">↩ Restaurar</button>
        </div>
      </div>
    `).join('');

    const addOptions = allNames
      .filter(n => !ev.mentors.some(m => m.name === n))
      .map(n => `<option value="${n}">${n}</option>`)
      .join('');

    const addHTML = `
      <div style="display:flex;gap:6px;align-items:center;margin-top:10px;padding-top:10px;border-top:1px solid #1a1a1a">
        <span style="font-size:11px;color:#555;white-space:nowrap">Adicionar:</span>
        <select class="substitute-select" id="add-teacher-name-${courseId}" style="flex:1">
          <option value="">— Selecionar —</option>
          ${addOptions}
        </select>
        <select class="substitute-select" id="add-teacher-role-${courseId}" style="max-width:120px">
          <option value="Professor">Professor</option>
          <option value="Mentor">Mentor</option>
          <option value="Host">Host</option>
        </select>
        <button class="att-btn present" onclick="addToLesson('${dateKey}','${ev.course}')" style="padding:6px 10px;font-size:11px">+ Add</button>
      </div>`;

    return `<div class="att-session" style="border-left-color:${cfg.color}">
      <div class="att-session-course" style="color:${cfg.color}">${ev.course}</div>
      ${mentorsHTML}
      ${removedHTML}
      ${addHTML}
    </div>`;
  }).join('');

  document.getElementById('modal-content').innerHTML = `
    <div class="modal-date">${weekday}, ${dd}/${mm}/2026</div>
    <div class="modal-title">Registrar Presença</div>
    ${sessionsHTML}
    <div class="att-save-bar">
      <span class="saved-badge" id="saved-badge">Salvo!</span>
      <button class="btn-save" id="btn-save" onclick="saveAll()">Salvar Presença</button>
    </div>
  `;
  document.getElementById('modal').classList.add('show');
}

function buildOriginalEventsForDate(dateKey) {
  const map = {};
  for (const teacher of TEACHERS) {
    for (const a of teacher.assignments) {
      if (a.dates.includes(dateKey)) {
        if (!map[a.course]) map[a.course] = { course: a.course, mentors: [] };
        map[a.course].mentors.push({ name: teacher.name, role: a.role });
      }
    }
  }
  return map;
}

function toggleAtt(btn) {
  const row = btn.closest('.att-row');
  const presentBtn = row.querySelector('.att-btn.present');
  const absentBtn = row.querySelector('.att-btn.absent');
  const isActive = btn.classList.contains('active');

  [presentBtn, absentBtn].forEach(b => { if(b) { b.classList.remove('active','dimmed'); } });

  if (!isActive) {
    btn.classList.add('active');
    if (btn === presentBtn && absentBtn) absentBtn.classList.add('dimmed');
    if (btn === absentBtn && presentBtn) presentBtn.classList.add('dimmed');
  }
}

// ═══════════════════════════════════════
// SCHEDULE OVERRIDES (remove/add to lesson)
// ═══════════════════════════════════════
async function removeFromLesson(btn) {
  const dateKey = btn.dataset.date;
  const course = btn.dataset.course;
  const teacher = btn.dataset.teacher;

  if (!confirm(`Remover ${teacher} da aula ${course} em ${dateKey}?`)) return;

  const { error } = await sb.from('schedule_overrides').insert({
    lesson_date: dateKey,
    course: course,
    teacher_name: teacher,
    action: 'remove',
    role: 'Professor',
  });

  if (error) {
    if (error.code === '23505') { showToast('Já removido', 'error'); return; }
    showToast('Erro: ' + error.message, 'error'); return;
  }

  showToast(`${teacher} removido de ${course} em ${dateKey}`, 'success');
  await loadOverrides();
  renderAll();
  openAttendance(dateKey);
}

async function addToLesson(dateKey, course) {
  const nameSelect = document.getElementById('add-teacher-name-' + course.replace(/[^a-zA-Z0-9]/g, ''));
  const roleSelect = document.getElementById('add-teacher-role-' + course.replace(/[^a-zA-Z0-9]/g, ''));
  const name = nameSelect.value;
  const role = roleSelect.value;

  if (!name) { showToast('Selecione um nome', 'error'); return; }

  const { error } = await sb.from('schedule_overrides').insert({
    lesson_date: dateKey,
    course: course,
    teacher_name: name,
    action: 'add',
    role: role,
  });

  if (error) {
    if (error.code === '23505') { showToast('Já adicionado', 'error'); return; }
    showToast('Erro: ' + error.message, 'error'); return;
  }

  showToast(`${name} adicionado como ${role} em ${course}`, 'success');
  await loadOverrides();
  renderAll();
  openAttendance(dateKey);
}

async function undoRemove(dateKey, course, teacher) {
  const { error } = await sb.from('schedule_overrides')
    .delete()
    .eq('lesson_date', dateKey)
    .eq('course', course)
    .eq('teacher_name', teacher)
    .eq('action', 'remove');

  if (error) { showToast('Erro: ' + error.message, 'error'); return; }

  showToast(`${teacher} restaurado`, 'success');
  await loadOverrides();
  renderAll();
  openAttendance(dateKey);
}

async function undoAdd(dateKey, course, teacher) {
  const { error } = await sb.from('schedule_overrides')
    .delete()
    .eq('lesson_date', dateKey)
    .eq('course', course)
    .eq('teacher_name', teacher)
    .eq('action', 'add');

  if (error) { showToast('Erro: ' + error.message, 'error'); return; }

  showToast(`${teacher} removido`, 'success');
  await loadOverrides();
  renderAll();
  openAttendance(dateKey);
}

async function deleteAtt(btn) {
  const dateKey = btn.dataset.date;
  const course = btn.dataset.course;
  const teacher = btn.dataset.teacher;
  const cacheKey = `${dateKey}|${course}|${teacher}`;
  const cached = attendanceCache[cacheKey];

  if (!cached || !cached.id) { showToast('Nenhum registro para excluir', 'error'); return; }

  if (!confirm(`Excluir registro de ${teacher} em ${dateKey}?`)) return;

  const { error } = await sb
    .from('attendance')
    .delete()
    .eq('id', cached.id);

  if (error) {
    showToast('Erro ao excluir: ' + error.message, 'error');
    return;
  }

  delete attendanceCache[cacheKey];
  showToast(`Registro de ${teacher} excluído`, 'success');
  renderAll();
  openAttendance(dateKey);
}

async function saveAll() {
  const btn = document.getElementById('btn-save');
  btn.disabled = true;
  btn.textContent = 'Salvando...';

  const records = [];
  document.querySelectorAll('.att-btn.active').forEach(b => {
    const rec = {
      lesson_date: b.dataset.date,
      course: b.dataset.course,
      teacher_name: b.dataset.teacher,
      role: b.dataset.role,
      status: b.dataset.action,
    };

    const allSelects = document.querySelectorAll('.substitute-select');
    for (const sel of allSelects) {
      if (sel.dataset.date === rec.lesson_date && sel.dataset.course === rec.course && sel.dataset.teacher === rec.teacher_name) {
        if (sel.dataset.field === 'role') {
          rec.substitute_role = sel.value;
        } else if (sel.value) {
          rec.substitute_name = sel.value;
        }
      }
    }

    records.push(rec);
  });

  if (!records.length) {
    showToast('Nenhuma presença marcada', 'error');
    btn.disabled = false;
    btn.textContent = 'Salvar Presença';
    return;
  }

  const ok = await saveAttendance(records);
  btn.disabled = false;
  btn.textContent = 'Salvar Presença';

  if (ok) {
    showToast(`Presença salva! ${records.length} registro${records.length !== 1 ? 's' : ''} salvos`, 'success');
    document.getElementById('saved-badge').classList.add('show');
    renderAll();
  }
}

function closeModal(e) {
  if (!e || e.target === document.getElementById('modal') || e.target.classList.contains('modal-close')) {
    document.getElementById('modal').classList.remove('show');
    modalDateKey = null;
  }
}
