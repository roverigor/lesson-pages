// ═══════════════════════════════════════
// VIEW TOGGLE
// ═══════════════════════════════════════
async function switchView(view) {
  document.querySelectorAll('.view-btn').forEach(b => b.classList.remove('active'));
  document.querySelector(`.view-btn[onclick="switchView('${view}')"]`).classList.add('active');

  document.getElementById('calendar-view').style.display = view === 'calendar' ? '' : 'none';
  document.getElementById('report-view').style.display = view === 'report' ? '' : 'none';
  document.getElementById('staff-view').style.display = view === 'staff' ? '' : 'none';
  document.getElementById('classes-view').style.display = view === 'classes' ? '' : 'none';
  document.getElementById('notify-view').style.display = view === 'notify' ? '' : 'none';
  document.getElementById('schedules-view').style.display = view === 'schedules' ? '' : 'none';
  document.getElementById('zoom-view').style.display = view === 'zoom' ? '' : 'none';
  document.getElementById('abstracts-view').style.display = view === 'abstracts' ? '' : 'none';

  if (view === 'report') renderReport();
  if (view === 'staff') loadStaff();
  if (view === 'classes') loadClasses();
  if (view === 'notify') loadNotifyView();
  if (view === 'schedules') loadSchedulesView();
  if (view === 'zoom') loadZoomMeetings();
  if (view === 'abstracts') loadAbstractsView();
  if (view === 'calendar') {
    await loadClasses();
    await loadOverrides();
    await loadAttendance();
    renderAll();
  }
}

// ═══════════════════════════════════════
// REPORT VIEW
// ═══════════════════════════════════════
function renderReport() {
  const mentorData = {};

  for (const date in EVENTS) {
    for (const course in EVENTS[date]) {
      for (const m of EVENTS[date][course].mentors) {
        if (!mentorData[m.name]) mentorData[m.name] = { courses: {}, asSubstitute: [] };
        const key = `${course}|${m.role}`;
        if (!mentorData[m.name].courses[key]) mentorData[m.name].courses[key] = { course, role: m.role, dates: [] };
        mentorData[m.name].courses[key].dates.push(date);
      }
    }
  }

  for (const key in attendanceCache) {
    const rec = attendanceCache[key];
    if (rec.substitute_name) {
      if (!mentorData[rec.substitute_name]) mentorData[rec.substitute_name] = { courses: {}, asSubstitute: [] };
      const [date, course, teacher] = key.split('|');
      mentorData[rec.substitute_name].asSubstitute.push({ date, course, replacing: teacher, role: rec.substitute_role || 'Substituto' });
    }
  }

  for (const name in mentorData) {
    for (const key in mentorData[name].courses) {
      mentorData[name].courses[key].dates.sort((a, b) => {
        const [da, ma] = a.split('/').map(Number);
        const [db, mb] = b.split('/').map(Number);
        return (ma * 100 + da) - (mb * 100 + db);
      });
    }
  }

  const sortedNames = Object.keys(mentorData).sort();

  const cards = sortedNames.map(name => {
    const data = mentorData[name];
    let presents = 0, absents = 0, pending = 0;

    const courseSections = Object.values(data.courses).map(c => {
      const datesHTML = c.dates.map(date => {
        const cacheKey = `${date}|${c.course}|${name}`;
        const rec = attendanceCache[cacheKey];
        if (rec) {
          if (rec.status === 'present') {
            presents++;
            let label = date;
            if (rec.substitute_name) label += ` <span class="sub-name">sub: ${rec.substitute_name}</span>`;
            return `<span class="report-date present" title="Presente">${label}</span>`;
          } else {
            absents++;
            let label = date;
            if (rec.substitute_name) label += ` <span class="sub-name">sub: ${rec.substitute_name}</span>`;
            return `<span class="report-date absent" title="Falta">${label}</span>`;
          }
        } else {
          pending++;
          return `<span class="report-date" title="Sem registro">${date}</span>`;
        }
      }).join('');

      const cfg = getCfg(c.course);
      const roleBadges = {
        'Professor': '<span class="badge-role-prof">Professor</span>',
        'Mentor': '<span class="badge-substitute">Mentor</span>',
        'Host': '<span class="badge-role-host">Host</span>',
      };
      const roleBadge = roleBadges[c.role] || `<span class="badge-role-host">${c.role}</span>`;

      return `<div class="report-course-section">
        <div class="report-course-title">
          <span style="width:8px;height:8px;border-radius:2px;background:${cfg.color};display:inline-block"></span>
          ${c.course} ${roleBadge}
        </div>
        <div class="report-dates">${datesHTML}</div>
      </div>`;
    }).join('');

    const subs = data.asSubstitute;
    let subSection = '';
    if (subs.length > 0) {
      const subDates = subs.map(s => {
        return `<span class="report-date substitute" title="Substituiu ${s.replacing} como ${s.role}">
          ${s.date} <span class="sub-name">${s.course} (por ${s.replacing})</span>
        </span>`;
      }).join('');
      subSection = `<div class="report-course-section">
        <div class="report-course-title">
          <span style="width:8px;height:8px;border-radius:2px;background:#facc15;display:inline-block"></span>
          Como Substituto <span class="badge-substitute">${subs.length}x</span>
        </div>
        <div class="report-dates">${subDates}</div>
      </div>`;
    }

    const totalDates = Object.values(data.courses).reduce((s, c) => s + c.dates.length, 0);
    const recorded = presents + absents;
    const pct = recorded > 0 ? Math.round((presents / recorded) * 100) : null;
    const pctColor = pct !== null ? (pct >= 80 ? '#4ade80' : pct >= 50 ? '#f59e0b' : '#f87171') : '#444';

    const roles = [...new Set(Object.values(data.courses).map(c => c.role))];
    const rolesLabel = roles.join(', ');

    return `<div class="report-card">
      <div class="report-card-header">
        <div class="report-avatar" style="background:${mentorColor(name)}">${initials(name)}</div>
        <div>
          <div class="report-name">${name}</div>
          <div class="report-summary">${rolesLabel} · ${totalDates} aulas${subs.length > 0 ? ` · ${subs.length} substituições` : ''}</div>
        </div>
        <div class="report-stats-row">
          <div class="report-stat">
            <div class="report-stat-num" style="color:#4ade80">${presents}</div>
            <div class="report-stat-label">Presenças</div>
          </div>
          <div class="report-stat">
            <div class="report-stat-num" style="color:#f87171">${absents}</div>
            <div class="report-stat-label">Faltas</div>
          </div>
          <div class="report-stat">
            <div class="report-stat-num" style="color:#555">${pending}</div>
            <div class="report-stat-label">Pendente</div>
          </div>
          <div class="report-stat">
            <div class="report-stat-num" style="color:${pctColor}">${pct !== null ? pct + '%' : '-'}</div>
            <div class="report-stat-label">Frequência</div>
          </div>
        </div>
      </div>
      ${courseSections}
      ${subSection}
    </div>`;
  }).join('');

  document.getElementById('report-content').innerHTML = cards || '<div style="text-align:center;color:#333;padding:40px">Nenhum dado para exibir</div>';
}
