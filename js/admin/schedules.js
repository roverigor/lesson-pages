// ═══════════════════════════════════════
// SCHEDULES / AGENDAMENTOS
// ═══════════════════════════════════════
async function loadSchedulesView() {
  if (!schedClasses.length) {
    const [{ data: cls }, { data: coh }] = await Promise.all([
      sb.from('classes').select('id, name, weekday, time_start').order('name'),
      sb.from('cohorts').select('id, name').eq('active', true).order('name'),
    ]);
    schedClasses = cls || [];
    schedCohorts = coh || [];
    document.getElementById('sched-class').innerHTML =
      '<option value="">— Selecione —</option>' +
      schedClasses.map(c => `<option value="${c.id}" data-weekday="${c.weekday}" data-start="${c.time_start}">${c.name}</option>`).join('');
    document.getElementById('sched-cohort').innerHTML =
      '<option value="">— Selecione —</option>' +
      schedCohorts.map(c => `<option value="${c.id}">${c.name}</option>`).join('');
  }
  await renderSchedulesList();
}

async function renderSchedulesList() {
  const { data, error } = await sb
    .from('notification_schedules')
    .select('*, classes(name, weekday, time_start), cohorts(name)')
    .order('created_at', { ascending: false });

  const el = document.getElementById('schedules-list');
  if (error || !data?.length) {
    el.innerHTML = '<div style="text-align:center;color:#333;padding:40px;font-size:13px">Nenhum agendamento configurado</div>';
    return;
  }

  const weekdays = ['Dom','Seg','Ter','Qua','Qui','Sex','Sáb'];
  el.innerHTML = data.map(s => {
    const cls = s.classes?.name || '—';
    const coh = s.cohorts?.name || '—';
    const wd  = s.classes?.weekday != null ? weekdays[s.classes.weekday] : '—';
    const ts  = s.classes?.time_start ? s.classes.time_start.slice(0,5) : '—';
    const nextFire = s.next_fire_at
      ? new Date(s.next_fire_at).toLocaleString('pt-BR', { timeZone:'America/Sao_Paulo', day:'2-digit', month:'2-digit', hour:'2-digit', minute:'2-digit' })
      : 'Não calculado';
    const typeLabel = { class_reminder:'Lembrete de aula', group_announcement:'Aviso grupo', custom:'Livre' }[s.notification_type] || s.notification_type;
    const statusColor = s.active ? '#4ade80' : '#555';
    const statusLabel = s.active ? 'Ativo' : 'Pausado';

    return `<div style="background:#111;border:1px solid #1e1e1e;border-radius:10px;padding:16px;margin-bottom:8px">
      <div style="display:flex;gap:12px;align-items:flex-start;flex-wrap:wrap">
        <div style="flex:1;min-width:200px">
          <div style="display:flex;gap:8px;align-items:center;margin-bottom:6px">
            <span style="font-size:13px;font-weight:700;color:#ddd">${cls}</span>
            <span style="font-size:10px;padding:2px 8px;border-radius:999px;background:rgba(99,102,241,0.1);border:1px solid rgba(99,102,241,0.3);color:#a5b4fc">${typeLabel}</span>
            <span style="font-size:10px;padding:2px 8px;border-radius:999px;border:1px solid #222;color:${statusColor}">${statusLabel}</span>
          </div>
          <div style="font-size:11px;color:#555;margin-bottom:4px">
            ${coh} · ${wd} ${ts} · ${s.hours_before}h antes
          </div>
          <div style="font-size:11px;color:#333">Próximo disparo: <span style="color:#555">${nextFire}</span></div>
          <div style="font-size:11px;color:#333;margin-top:4px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;max-width:400px">${s.message_template.slice(0,80)}${s.message_template.length > 80 ? '…' : ''}</div>
        </div>
        <div style="display:flex;gap:6px;flex-shrink:0">
          <button onclick="toggleSchedule('${s.id}', ${!s.active})" style="padding:6px 12px;border-radius:6px;border:1px solid #222;background:#1a1a1a;color:#888;font-size:11px;font-weight:700;cursor:pointer;font-family:var(--font-sans)">${s.active ? 'Pausar' : 'Ativar'}</button>
          <button onclick="deleteSchedule('${s.id}')" style="padding:6px 10px;border-radius:6px;border:1px solid #44403c;background:rgba(168,162,158,0.08);color:#a8a29e;font-size:13px;cursor:pointer;font-family:var(--font-sans)">✕</button>
        </div>
      </div>
    </div>`;
  }).join('');
}

function openScheduleForm() {
  document.getElementById('sched-edit-id').value = '';
  document.getElementById('sched-class').value = '';
  document.getElementById('sched-cohort').value = '';
  document.getElementById('sched-type').value = 'class_reminder';
  document.getElementById('sched-target').value = 'both';
  document.getElementById('sched-hours').value = '2';
  document.getElementById('sched-template').value = SCHED_TEMPLATES.class_reminder;
  document.getElementById('sched-save-btn').textContent = 'Salvar Agendamento';
  document.getElementById('schedule-form-container').style.display = '';
  document.getElementById('schedule-form-container').scrollIntoView({ behavior:'smooth', block:'nearest' });
}

function closeScheduleForm() {
  document.getElementById('schedule-form-container').style.display = 'none';
}

function onSchedTypeChange() {
  const type = document.getElementById('sched-type').value;
  document.getElementById('sched-template').value = SCHED_TEMPLATES[type] || '';
}

function onSchedClassChange() {
  // Auto-select matching cohort if only one linked — reserved for future use
}

async function saveSchedule() {
  const classId   = document.getElementById('sched-class').value;
  const cohortId  = document.getElementById('sched-cohort').value;
  const type      = document.getElementById('sched-type').value;
  const target    = document.getElementById('sched-target').value;
  const hours     = parseInt(document.getElementById('sched-hours').value, 10);
  const template  = document.getElementById('sched-template').value.trim();

  if (!classId)  { showToast('Selecione a classe', 'error'); return; }
  if (!cohortId) { showToast('Selecione o cohort', 'error'); return; }
  if (!template) { showToast('Escreva o template', 'error'); return; }
  if (!hours || hours < 1) { showToast('Antecedência deve ser ≥ 1 hora', 'error'); return; }

  const btn = document.getElementById('sched-save-btn');
  btn.disabled = true; btn.textContent = 'Salvando...';

  try {
    const { data: { user } } = await sb.auth.getUser();

    const classOpt = document.getElementById('sched-class').options[document.getElementById('sched-class').selectedIndex];
    const { data: nextFire } = await sb.rpc('calculate_next_fire_at', {
      p_weekday: parseInt(classOpt.dataset.weekday, 10),
      p_time_start: classOpt.dataset.start,
      p_hours_before: hours,
    });

    const { error } = await sb.from('notification_schedules').insert({
      class_id: classId,
      cohort_id: cohortId,
      notification_type: type,
      target_type: target,
      hours_before: hours,
      message_template: template,
      next_fire_at: nextFire,
      active: true,
      created_by: user?.id ?? null,
    });

    if (error) throw error;
    showToast('Agendamento criado!', 'success');
    closeScheduleForm();
    await renderSchedulesList();
  } catch (err) {
    showToast('Erro: ' + err.message, 'error');
  } finally {
    btn.disabled = false; btn.textContent = 'Salvar Agendamento';
  }
}

async function toggleSchedule(id, newActive) {
  const { error } = await sb.from('notification_schedules').update({ active: newActive }).eq('id', id);
  if (error) { showToast('Erro ao atualizar', 'error'); return; }
  showToast(newActive ? 'Agendamento ativado' : 'Agendamento pausado', 'success');
  await renderSchedulesList();
}

async function deleteSchedule(id) {
  if (!confirm('Deletar este agendamento? Esta ação não pode ser desfeita.')) return;
  const { error } = await sb.from('notification_schedules').delete().eq('id', id);
  if (error) { showToast('Erro ao deletar', 'error'); return; }
  showToast('Agendamento deletado', 'success');
  await renderSchedulesList();
}
