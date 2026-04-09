// ═══════════════════════════════════════
// CLASS HUB — Unified class detail view
// ═══════════════════════════════════════
let hubClassId = null;

async function openClassHub(classId) {
  hubClassId = classId;
  const c = classesList.find(x => x.id === classId);
  if (!c) { showToast('Turma não encontrada', 'error'); return; }

  // Show hub view, hide classes view
  document.getElementById('classes-view').style.display = 'none';
  const hub = document.getElementById('class-hub-view');
  hub.style.display = '';
  hub.scrollIntoView({ behavior: 'smooth', block: 'start' });

  // Render header immediately
  const typeBadge = c.type ? `<span class="hub-badge type">${c.type}</span>` : '';
  const statusBadge = c.active !== false
    ? '<span class="hub-badge active">Ativa</span>'
    : '<span class="hub-badge inactive">Inativa</span>';

  document.getElementById('hub-header').innerHTML = `
    <div style="display:flex;align-items:center;gap:12px;flex:1;min-width:0">
      <div style="width:6px;height:48px;border-radius:3px;background:${c.color || '#6366f1'};flex-shrink:0"></div>
      <div style="min-width:0">
        <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
          <div style="font-size:20px;font-weight:800;color:#fff">${escHtml(c.name)}</div>
          ${typeBadge} ${statusBadge}
        </div>
        <div style="font-size:12px;color:#555;margin-top:2px">
          ${c.time_start || ''}–${c.time_end || ''} · ${fmtIso(c.start_date)} a ${fmtIso(c.end_date)}
        </div>
      </div>
    </div>
    <div style="display:flex;gap:6px;flex-shrink:0">
      <button class="att-btn" style="padding:8px 14px;font-size:12px" onclick="editClass('${c.id}');closeClassHub()">Editar</button>
      <button class="att-btn" style="padding:8px 14px;font-size:12px" onclick="closeClassHub()">← Voltar</button>
    </div>`;

  // Show spinners in all sections
  const sections = ['hub-team', 'hub-students', 'hub-attendance', 'hub-zoom', 'hub-abstracts', 'hub-whatsapp', 'hub-surveys'];
  sections.forEach(id => {
    const el = document.getElementById(id);
    if (el) el.innerHTML = '<div style="color:#333;font-size:12px;padding:12px">Carregando...</div>';
  });

  // Load all sections in parallel
  await Promise.all([
    renderHubTeam(c),
    loadHubStudents(c),
    loadHubAttendance(c),
    loadHubZoom(c),
    loadHubAbstracts(c),
    loadHubWhatsApp(c),
    loadHubSurveys(c),
  ]);

  // Re-render Lucide icons for hub section headers
  if (window.lucide) window.lucide.createIcons();
}

function closeClassHub() {
  document.getElementById('class-hub-view').style.display = 'none';
  document.getElementById('classes-view').style.display = '';
  hubClassId = null;
}

function fmtIso(d) {
  if (!d) return '?';
  return new Date(d + 'T00:00:00').toLocaleDateString('pt-BR');
}

// ─── TEAM SECTION ────────────────────────────────────
async function renderHubTeam(c) {
  const byDay = {};
  for (const cm of (c._mentors || [])) {
    if (cm.valid_until) continue;
    const wd = cm.weekday ?? c.weekday ?? 0;
    if (!byDay[wd]) byDay[wd] = [];
    byDay[wd].push({ name: getMentorName(cm.mentor_id), role: cm.role });
  }

  const html = Object.entries(byDay).sort((a, b) => a[0] - b[0]).map(([wd, members]) => {
    const people = members.map(m => {
      const color = m.role === 'Professor' ? '#a5b4fc' : m.role === 'Host' ? '#888' : '#facc15';
      return `<span style="font-size:12px;padding:4px 10px;border-radius:6px;background:${color}15;border:1px solid ${color}30;color:${color}">${m.name} <span style="font-size:10px;opacity:0.7">(${m.role})</span></span>`;
    }).join(' ');
    return `<div style="margin-bottom:6px"><span style="font-size:11px;color:#555;font-weight:600;margin-right:8px">${WEEKDAY_FULL[wd] || 'Dia ' + wd}:</span>${people}</div>`;
  }).join('');

  document.getElementById('hub-team').innerHTML = html || '<div style="color:#333;font-size:12px">Nenhuma equipe configurada</div>';
}

// ─── STUDENTS SECTION ────────────────────────────────
async function loadHubStudents(c) {
  const cohortIds = (c._linkedCohorts || []).map(lc => lc.cohort_id).filter(Boolean);
  if (!cohortIds.length) {
    document.getElementById('hub-students').innerHTML = '<div style="color:#333;font-size:12px">Nenhuma turma vinculada</div>';
    return;
  }

  const { data: students } = await sb
    .from('students')
    .select('id, name, phone, cohort_id, active')
    .in('cohort_id', cohortIds)
    .eq('is_mentor', false)
    .eq('active', true)
    .order('name');

  if (!students || !students.length) {
    document.getElementById('hub-students').innerHTML = '<div style="color:#333;font-size:12px">Nenhum aluno encontrado</div>';
    return;
  }

  const rows = students.map(s => {
    const cohort = cohortsList.find(x => x.id === s.cohort_id);
    const cohortName = cohort ? cohort.name : '';
    const phone = s.phone ? s.phone.replace(/^55/, '').replace(/(\d{2})(\d{5})(\d{4})/, '($1) $2-$3') : '';
    return `<tr>
      <td style="padding:6px 10px;font-size:12px;color:#ddd">${escHtml(s.name)}</td>
      <td style="padding:6px 10px;font-size:11px;color:#555">${phone}</td>
      <td style="padding:6px 10px;font-size:11px;color:#555">${escHtml(cohortName)}</td>
    </tr>`;
  }).join('');

  document.getElementById('hub-students').innerHTML = `
    <div style="font-size:11px;color:#555;margin-bottom:8px">${students.length} aluno${students.length !== 1 ? 's' : ''}</div>
    <div style="max-height:300px;overflow-y:auto;border:1px solid #1a1a1a;border-radius:8px">
      <table style="width:100%;border-collapse:collapse">
        <thead><tr style="background:#0d0d0d;border-bottom:1px solid #1a1a1a">
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Nome</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Telefone</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Turma</th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}

// ─── ATTENDANCE SECTION ──────────────────────────────
async function loadHubAttendance(c) {
  const { data: records } = await sb
    .from('mentor_attendance')
    .select('session_date, status, mentor_id, comment')
    .eq('class_id', c.id)
    .order('session_date', { ascending: false })
    .limit(30);

  if (!records || !records.length) {
    // Fallback: check legacy attendance table by class name
    const { data: legacy } = await sb
      .from('attendance')
      .select('lesson_date, course, teacher_name, status, substitute_name')
      .eq('course', c.name)
      .order('lesson_date', { ascending: false })
      .limit(30);

    if (!legacy || !legacy.length) {
      document.getElementById('hub-attendance').innerHTML = '<div style="color:#333;font-size:12px">Nenhum registro de presença</div>';
      return;
    }

    const byDate = {};
    for (const r of legacy) {
      const d = r.lesson_date;
      if (!byDate[d]) byDate[d] = [];
      byDate[d].push(r);
    }

    const rows = Object.entries(byDate).slice(0, 15).map(([date, recs]) => {
      const presents = recs.filter(r => r.status === 'present').length;
      const absents = recs.filter(r => r.status === 'absent').length;
      const subs = recs.filter(r => r.substitute_name).map(r => r.substitute_name);
      return `<tr>
        <td style="padding:6px 10px;font-size:12px;color:#ddd">${fmtIso(date)}</td>
        <td style="padding:6px 10px;font-size:12px;color:#4ade80">${presents}</td>
        <td style="padding:6px 10px;font-size:12px;color:#f87171">${absents}</td>
        <td style="padding:6px 10px;font-size:11px;color:#555">${subs.length ? subs.join(', ') : '—'}</td>
      </tr>`;
    }).join('');

    document.getElementById('hub-attendance').innerHTML = `
      <div style="max-height:280px;overflow-y:auto;border:1px solid #1a1a1a;border-radius:8px">
        <table style="width:100%;border-collapse:collapse">
          <thead><tr style="background:#0d0d0d;border-bottom:1px solid #1a1a1a">
            <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Data</th>
            <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Presentes</th>
            <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Faltas</th>
            <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Substitutos</th>
          </tr></thead>
          <tbody>${rows}</tbody>
        </table>
      </div>`;
    return;
  }

  // Group by session_date
  const byDate = {};
  for (const r of records) {
    if (!byDate[r.session_date]) byDate[r.session_date] = [];
    byDate[r.session_date].push(r);
  }

  const rows = Object.entries(byDate).slice(0, 15).map(([date, recs]) => {
    const presents = recs.filter(r => r.status === 'present').length;
    const absents = recs.filter(r => r.status === 'absent').length;
    const names = recs.map(r => getMentorName(r.mentor_id)).join(', ');
    return `<tr>
      <td style="padding:6px 10px;font-size:12px;color:#ddd">${fmtIso(date)}</td>
      <td style="padding:6px 10px;font-size:12px;color:#4ade80">${presents}</td>
      <td style="padding:6px 10px;font-size:12px;color:#f87171">${absents}</td>
      <td style="padding:6px 10px;font-size:11px;color:#555;max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${names}</td>
    </tr>`;
  }).join('');

  document.getElementById('hub-attendance').innerHTML = `
    <div style="max-height:280px;overflow-y:auto;border:1px solid #1a1a1a;border-radius:8px">
      <table style="width:100%;border-collapse:collapse">
        <thead><tr style="background:#0d0d0d;border-bottom:1px solid #1a1a1a">
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Data</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Presentes</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Faltas</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Equipe</th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}

// ─── ZOOM SECTION ────────────────────────────────────
async function loadHubZoom(c) {
  const { data: meetings } = await sb
    .from('zoom_meetings')
    .select('id, topic, start_time, duration_minutes, participants_count, zoom_uuid')
    .eq('class_id', c.id)
    .order('start_time', { ascending: false })
    .limit(10);

  if (!meetings || !meetings.length) {
    document.getElementById('hub-zoom').innerHTML = '<div style="color:#333;font-size:12px">Nenhuma reunião Zoom registrada</div>';
    return;
  }

  const rows = meetings.map(m => {
    const date = m.start_time ? new Date(m.start_time).toLocaleDateString('pt-BR') : '?';
    const time = m.start_time ? new Date(m.start_time).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) : '';
    return `<tr>
      <td style="padding:6px 10px;font-size:12px;color:#ddd">${date}</td>
      <td style="padding:6px 10px;font-size:11px;color:#555">${time}</td>
      <td style="padding:6px 10px;font-size:12px;color:#a5b4fc">${m.participants_count || 0}</td>
      <td style="padding:6px 10px;font-size:11px;color:#555">${m.duration_minutes || 0}min</td>
      <td style="padding:6px 10px;font-size:11px;color:#555;max-width:180px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${escHtml(m.topic || '')}</td>
    </tr>`;
  }).join('');

  document.getElementById('hub-zoom').innerHTML = `
    <div style="font-size:11px;color:#555;margin-bottom:8px">${meetings.length} reuniões recentes</div>
    <div style="max-height:260px;overflow-y:auto;border:1px solid #1a1a1a;border-radius:8px">
      <table style="width:100%;border-collapse:collapse">
        <thead><tr style="background:#0d0d0d;border-bottom:1px solid #1a1a1a">
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Data</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Hora</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Particip.</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Duração</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Tópico</th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}

// ─── ABSTRACTS SECTION ───────────────────────────────
async function loadHubAbstracts(c) {
  const { data: abstracts } = await sb
    .from('lesson_abstracts')
    .select('id, title, lesson_date, badge_label')
    .order('lesson_date', { ascending: false })
    .limit(50);

  // Filter by class name match (abstracts don't have class_id FK)
  const nameLC = c.name.toLowerCase();
  const matched = (abstracts || []).filter(a =>
    (a.title || '').toLowerCase().includes(nameLC)
  ).slice(0, 8);

  if (!matched.length) {
    document.getElementById('hub-abstracts').innerHTML = '<div style="color:#333;font-size:12px">Nenhum resumo encontrado para esta turma</div>';
    return;
  }

  const rows = matched.map(a => `
    <div style="display:flex;align-items:center;gap:8px;padding:6px 0;border-bottom:1px solid #111">
      <span style="font-size:10px;padding:2px 8px;border-radius:4px;background:rgba(34,197,94,0.12);color:#4ade80;font-weight:700">${a.badge_label || 'Aula'}</span>
      <span style="font-size:12px;color:#ddd;flex:1;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${escHtml(a.title)}</span>
      <span style="font-size:11px;color:#444;flex-shrink:0">${fmtIso(a.lesson_date)}</span>
    </div>`).join('');

  document.getElementById('hub-abstracts').innerHTML = rows;
}

// ─── WHATSAPP SECTION ────────────────────────────────
async function loadHubWhatsApp(c) {
  const cohortIds = (c._linkedCohorts || []).map(lc => lc.cohort_id).filter(Boolean);

  let notifications = [];
  if (cohortIds.length) {
    const { data } = await sb
      .from('notifications')
      .select('id, cohort_id, message, status, sent_at, total_recipients')
      .in('cohort_id', cohortIds)
      .order('sent_at', { ascending: false })
      .limit(10);
    notifications = data || [];
  }

  if (!notifications.length) {
    document.getElementById('hub-whatsapp').innerHTML = '<div style="color:#333;font-size:12px">Nenhuma notificação enviada</div>';
    return;
  }

  const rows = notifications.map(n => {
    const date = n.sent_at ? new Date(n.sent_at).toLocaleDateString('pt-BR') : '?';
    const time = n.sent_at ? new Date(n.sent_at).toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' }) : '';
    const preview = (n.message || '').substring(0, 60).replace(/\n/g, ' ');
    const statusBadge = n.status === 'sent'
      ? '<span style="font-size:10px;padding:2px 6px;border-radius:4px;background:rgba(34,197,94,0.12);color:#4ade80">Enviado</span>'
      : `<span style="font-size:10px;padding:2px 6px;border-radius:4px;background:rgba(245,158,11,0.12);color:#fbbf24">${n.status || '?'}</span>`;

    return `<tr>
      <td style="padding:6px 10px;font-size:12px;color:#ddd">${date} ${time}</td>
      <td style="padding:6px 10px;font-size:11px;color:#555;max-width:200px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap">${escHtml(preview)}…</td>
      <td style="padding:6px 10px;font-size:12px;color:#a5b4fc;text-align:center">${n.total_recipients || '?'}</td>
      <td style="padding:6px 10px">${statusBadge}</td>
    </tr>`;
  }).join('');

  document.getElementById('hub-whatsapp').innerHTML = `
    <div style="max-height:240px;overflow-y:auto;border:1px solid #1a1a1a;border-radius:8px">
      <table style="width:100%;border-collapse:collapse">
        <thead><tr style="background:#0d0d0d;border-bottom:1px solid #1a1a1a">
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Data</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Mensagem</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:center;font-weight:700;text-transform:uppercase">Dest.</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Status</th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}

// ─── SURVEYS SECTION ─────────────────────────────────
async function loadHubSurveys(c) {
  const cohortIds = (c._linkedCohorts || []).map(lc => lc.cohort_id).filter(Boolean);

  let surveys = [];
  // Surveys can be linked by class_id or cohort_id
  const queries = [
    sb.from('surveys').select('id, name, type, status, dispatched_at, class_id, cohort_id').eq('class_id', c.id).order('created_at', { ascending: false }).limit(10),
  ];
  if (cohortIds.length) {
    queries.push(
      sb.from('surveys').select('id, name, type, status, dispatched_at, class_id, cohort_id').in('cohort_id', cohortIds).order('created_at', { ascending: false }).limit(10)
    );
  }

  const results = await Promise.all(queries);
  const seen = new Set();
  for (const r of results) {
    for (const s of (r.data || [])) {
      if (!seen.has(s.id)) { seen.add(s.id); surveys.push(s); }
    }
  }

  if (!surveys.length) {
    document.getElementById('hub-surveys').innerHTML = '<div style="color:#333;font-size:12px">Nenhuma avaliação encontrada</div>';
    return;
  }

  // Get response counts
  const surveyIds = surveys.map(s => s.id);
  const { data: responses } = await sb
    .from('survey_responses')
    .select('survey_id, score')
    .in('survey_id', surveyIds);

  const byS = {};
  for (const r of (responses || [])) {
    if (!byS[r.survey_id]) byS[r.survey_id] = { count: 0, total: 0 };
    byS[r.survey_id].count++;
    if (r.score !== null && r.score !== undefined) byS[r.survey_id].total += r.score;
  }

  const rows = surveys.map(s => {
    const stats = byS[s.id] || { count: 0, total: 0 };
    const avg = stats.count > 0 ? (stats.total / stats.count).toFixed(1) : '—';
    const date = s.dispatched_at ? new Date(s.dispatched_at).toLocaleDateString('pt-BR') : '—';
    const typeBadge = s.type === 'nps'
      ? '<span style="font-size:10px;padding:2px 6px;border-radius:4px;background:rgba(99,102,241,0.12);color:#a5b4fc">NPS</span>'
      : '<span style="font-size:10px;padding:2px 6px;border-radius:4px;background:rgba(245,158,11,0.12);color:#fbbf24">CSAT</span>';
    const statusColor = s.status === 'active' ? '#4ade80' : s.status === 'closed' ? '#f87171' : '#555';

    return `<tr>
      <td style="padding:6px 10px;font-size:12px;color:#ddd">${escHtml(s.name)}</td>
      <td style="padding:6px 10px">${typeBadge}</td>
      <td style="padding:6px 10px;font-size:12px;color:${statusColor}">${s.status}</td>
      <td style="padding:6px 10px;font-size:12px;color:#a5b4fc;text-align:center">${stats.count}</td>
      <td style="padding:6px 10px;font-size:12px;color:#facc15;text-align:center">${avg}</td>
      <td style="padding:6px 10px;font-size:11px;color:#555">${date}</td>
    </tr>`;
  }).join('');

  document.getElementById('hub-surveys').innerHTML = `
    <div style="max-height:240px;overflow-y:auto;border:1px solid #1a1a1a;border-radius:8px">
      <table style="width:100%;border-collapse:collapse">
        <thead><tr style="background:#0d0d0d;border-bottom:1px solid #1a1a1a">
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Nome</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Tipo</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Status</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:center;font-weight:700;text-transform:uppercase">Respostas</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:center;font-weight:700;text-transform:uppercase">Score</th>
          <th style="padding:8px 10px;font-size:10px;color:#444;text-align:left;font-weight:700;text-transform:uppercase">Enviado</th>
        </tr></thead>
        <tbody>${rows}</tbody>
      </table>
    </div>`;
}
