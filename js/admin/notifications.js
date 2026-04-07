// ═══════════════════════════════════════
// NOTIFICATIONS / AVISOS
// ═══════════════════════════════════════
async function loadNotifyView() {
  const [{ data: cohorts }, { data: classes }] = await Promise.all([
    sb.from('cohorts').select('id, name, whatsapp_group_jid, zoom_link').eq('active', true).order('name'),
    sb.from('classes').select('id, name, time_start, time_end, professor, host').order('name'),
  ]);
  notifyCohorts = cohorts || [];
  notifyClasses = classes || [];

  document.getElementById('notify-cohort').innerHTML =
    '<option value="">— Selecione —</option>' +
    notifyCohorts.map(c => `<option value="${c.id}" data-jid="${c.whatsapp_group_jid || ''}" data-zoom="${c.zoom_link || ''}" data-name="${c.name}">${c.name}</option>`).join('');

  document.getElementById('notify-class').innerHTML =
    '<option value="">— Selecione —</option>' +
    notifyClasses.map(c => `<option value="${c.id}" data-name="${c.name}" data-start="${c.time_start || ''}" data-prof="${c.professor || ''}">${c.name}</option>`).join('');

  onNotifyTypeChange();
  await loadNotifyHistory();
}

function onNotifyTypeChange() {
  const type = document.getElementById('notify-type').value;
  const classWrap = document.getElementById('notify-class-wrap');
  const req = document.getElementById('notify-class-req');
  classWrap.style.display = type === 'class_reminder' ? '' : 'none';
  req.style.display = type === 'class_reminder' ? '' : 'none';

  const tpl = NOTIFY_TEMPLATES[type] || '';
  document.getElementById('notify-message').value = tpl;

  if (type === 'class_reminder') document.getElementById('notify-target').value = 'both';
  else if (type === 'individual') document.getElementById('notify-target').value = 'individual';
  else document.getElementById('notify-target').value = 'group';

  updateNotifyPreview();
}

function onNotifyCohortChange() {
  const sel = document.getElementById('notify-cohort');
  const opt = sel.options[sel.selectedIndex];
  const zoom = opt?.dataset?.zoom || '';
  if (zoom) document.getElementById('notify-zoom').value = zoom;
  updateNotifyPreview();
}

function onNotifyClassChange() { updateNotifyPreview(); }

function updateNotifyPreview() {
  const template = document.getElementById('notify-message').value;
  const previewWrap = document.getElementById('notify-preview-wrap');
  const previewEl = document.getElementById('notify-preview');
  if (!template.trim()) { previewWrap.style.display = 'none'; return; }

  const cohortSel = document.getElementById('notify-cohort');
  const cohortOpt = cohortSel.options[cohortSel.selectedIndex];
  const classSel = document.getElementById('notify-class');
  const classOpt = classSel.options[classSel.selectedIndex];
  const zoom = document.getElementById('notify-zoom').value || '';

  const vars = {
    cohort_name:      cohortOpt?.dataset?.name || '',
    zoom_link:        zoom,
    class_name:       classOpt?.dataset?.name || '',
    class_time_start: classOpt?.dataset?.start || '',
    class_professor:  classOpt?.dataset?.prof || '',
    mentor_name:      '(nome do mentor)',
  };

  let rendered = template;
  for (const [k, v] of Object.entries(vars)) {
    rendered = rendered.replaceAll(`{{${k}}}`, v);
  }

  previewWrap.style.display = '';
  previewEl.textContent = rendered;

  const copyBtn = document.getElementById('copy-zoom-btn');
  if (copyBtn) copyBtn.style.display = zoom ? '' : 'none';
}

function copyZoomLink() {
  const zoom = document.getElementById('notify-zoom').value;
  if (!zoom) return;
  navigator.clipboard.writeText(zoom).then(() => {
    const btn = document.getElementById('copy-zoom-btn');
    const original = btn.textContent;
    btn.textContent = '✓ Copiado!';
    btn.style.color = '#4ade80';
    setTimeout(() => { btn.textContent = original; btn.style.color = '#aaa'; }, 2000);
  }).catch(() => {
    showToast('Não foi possível copiar — copie manualmente', 'error');
  });
}

function resetNotifyForm() {
  document.getElementById('notify-type').value = 'custom';
  document.getElementById('notify-cohort').value = '';
  document.getElementById('notify-class').value = '';
  document.getElementById('notify-target').value = 'group';
  document.getElementById('notify-message').value = '';
  document.getElementById('notify-zoom').value = '';
  document.getElementById('notify-preview-wrap').style.display = 'none';
  onNotifyTypeChange();
}

async function loadNotifyHistory() {
  const { data } = await sb.from('notifications')
    .select('id, type, target_type, status, message_rendered, message_template, error_message, created_at, sent_at, retry_count, max_retries, cohort_id, cohorts(name)')
    .order('created_at', { ascending: false })
    .limit(20);

  const el = document.getElementById('notify-history');
  if (!data || !data.length) {
    el.innerHTML = '<div style="text-align:center;color:#333;padding:40px;font-size:13px">Nenhum aviso enviado ainda</div>';
    return;
  }

  el.innerHTML = data.map(n => {
    const statusCfg = {
      pending:    { bg: 'rgba(245,158,11,0.1)', border: '#92400e', color: '#fbbf24', label: 'Pendente',    icon: '⏳' },
      processing: { bg: 'rgba(59,130,246,0.1)', border: '#1e40af', color: '#60a5fa', label: 'Processando', icon: '⏳' },
      sent:       { bg: 'rgba(34,197,94,0.1)',  border: '#166534', color: '#4ade80', label: 'Enviado',     icon: '✓' },
      partial:    { bg: 'rgba(245,158,11,0.1)', border: '#92400e', color: '#fbbf24', label: 'Parcial',     icon: '⚠' },
      failed:     { bg: 'rgba(239,68,68,0.1)',  border: '#7f1d1d', color: '#f87171', label: 'Falhou',      icon: '✕' },
      cancelled:  { bg: 'rgba(102,102,102,0.1)',border: '#333',    color: '#666',    label: 'Cancelado',   icon: '—' },
    };
    const s = statusCfg[n.status] || statusCfg.pending;
    const cohortName = n.cohorts?.name || '—';
    const msg = (n.message_rendered || n.message_template || '').slice(0, 120);
    const date = new Date(n.created_at).toLocaleString('pt-BR', { day: '2-digit', month: '2-digit', hour: '2-digit', minute: '2-digit' });
    const targetLabel = { group: 'Grupo', individual: 'Individual', both: 'Grupo + Individual' }[n.target_type] || n.target_type;
    const canResend = n.status === 'failed' && (n.retry_count ?? 0) < (n.max_retries ?? 3);

    return `<div style="background:#111;border:1px solid #1e1e1e;border-radius:10px;padding:14px;margin-bottom:8px;display:flex;gap:12px;align-items:flex-start">
      <div style="flex:1;min-width:0">
        <div style="display:flex;gap:8px;align-items:center;margin-bottom:6px;flex-wrap:wrap">
          <span style="font-size:12px;font-weight:700;color:#ddd">${cohortName}</span>
          <span style="font-size:10px;padding:2px 8px;border-radius:999px;background:${s.bg};border:1px solid ${s.border};color:${s.color};font-weight:700">${s.icon} ${s.label}</span>
          <span style="font-size:10px;color:#444">${targetLabel}</span>
          <span style="font-size:10px;color:#333;margin-left:auto">${date}</span>
        </div>
        <div style="font-size:12px;color:#666;white-space:pre-wrap;overflow:hidden;text-overflow:ellipsis;max-height:40px">${msg}</div>
        ${n.error_message ? `<div style="font-size:10px;color:#f87171;margin-top:4px">${n.error_message}</div>` : ''}
        ${canResend ? `<button onclick="resendNotification('${n.id}')" style="margin-top:8px;padding:4px 12px;border-radius:6px;border:1px solid #7f1d1d;background:rgba(239,68,68,0.08);color:#f87171;font-size:11px;font-weight:700;cursor:pointer;font-family:var(--font-sans)">↻ Reenviar</button>` : ''}
      </div>
    </div>`;
  }).join('');
}

async function sendNotification() {
  const notifType  = document.getElementById('notify-type').value;
  const cohortId   = document.getElementById('notify-cohort').value;
  const classId    = document.getElementById('notify-class').value || null;
  const targetType = document.getElementById('notify-target').value;
  const message    = document.getElementById('notify-message').value.trim();
  const zoomLink   = document.getElementById('notify-zoom').value.trim();

  if (!cohortId) { showToast('Selecione um cohort', 'error'); return; }
  if (notifType === 'class_reminder' && !classId) { showToast('Selecione a classe para lembrete', 'error'); return; }
  if (!message) { showToast('Escreva a mensagem', 'error'); return; }

  const cohort = notifyCohorts.find(c => c.id === cohortId);
  if (!cohort) { showToast('Cohort não encontrado', 'error'); return; }

  const btn = document.getElementById('notify-send-btn');
  btn.disabled = true;
  btn.textContent = 'Enviando...';

  try {
    const { data: { user } } = await sb.auth.getUser();
    const { data, error } = await sb.from('notifications').insert({
      type: notifType,
      cohort_id: cohortId,
      class_id: classId,
      target_type: targetType,
      target_group_jid: cohort.whatsapp_group_jid,
      message_template: message,
      metadata: zoomLink ? { zoom_link: zoomLink } : {},
      status: 'pending',
      created_by: user?.id ?? null,
    }).select().single();

    if (error) throw error;

    showToast(`Aviso enviado para ${cohort.name}! Aguardando confirmação...`, 'success');
    resetNotifyForm();

    setTimeout(async () => {
      const { data: updated } = await sb.from('notifications').select('status, error_message').eq('id', data.id).single();
      if (updated) {
        if (updated.status === 'sent') showToast(`✓ Entregue para ${cohort.name}`, 'success');
        else if (updated.status === 'delivered') showToast(`✓ Confirmado — recebido no dispositivo (${cohort.name})`, 'success');
        else if (updated.status === 'partial') showToast(`Entrega parcial — ${cohort.name}`, 'error');
        else if (updated.status === 'failed') showToast('Falha: ' + (updated.error_message || 'erro desconhecido'), 'error');
        else if (updated.status === 'processing') showToast('Ainda processando — confira o histórico', 'success');
      }
      await loadNotifyHistory();
    }, 5000);

  } catch (err) {
    showToast('Erro: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = 'Enviar Aviso';
  }
}

async function sendTestNotification() {
  const message = document.getElementById('notify-message').value.trim();
  if (!message) { showToast('Escreva a mensagem antes de testar', 'error'); return; }

  const cohortId = document.getElementById('notify-cohort').value || null;
  const classId  = document.getElementById('notify-class').value  || null;
  const zoomLink = document.getElementById('notify-zoom').value.trim() || null;

  const btn = document.getElementById('notify-test-btn');
  const feedback = document.getElementById('notify-test-feedback');
  btn.disabled = true;
  btn.textContent = 'Enviando teste...';
  feedback.style.display = 'none';

  try {
    const { data: { session } } = await sb.auth.getSession();
    const res = await fetch(`${SUPABASE_URL}/functions/v1/send-whatsapp`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${session?.access_token ?? SUPABASE_KEY}`,
        'apikey': SUPABASE_KEY,
      },
      body: JSON.stringify({
        action: 'test_notification',
        message_template: message,
        cohort_id: cohortId,
        class_id: classId,
        zoom_link: zoomLink,
      }),
    });

    const result = await res.json();
    feedback.style.display = '';

    if (result.ok) {
      feedback.style.background = 'rgba(34,197,94,0.08)';
      feedback.style.border = '1px solid #166534';
      feedback.style.color = '#4ade80';
      feedback.textContent = `✓ Teste enviado para +55 43 99250-490`;
    } else {
      feedback.style.background = 'rgba(239,68,68,0.08)';
      feedback.style.border = '1px solid #7f1d1d';
      feedback.style.color = '#f87171';
      feedback.textContent = `✕ Erro: ${result.error || 'Falha desconhecida'}`;
    }
  } catch (err) {
    feedback.style.display = '';
    feedback.style.background = 'rgba(239,68,68,0.08)';
    feedback.style.border = '1px solid #7f1d1d';
    feedback.style.color = '#f87171';
    feedback.textContent = `✕ Erro: ${err.message}`;
  } finally {
    btn.disabled = false;
    btn.textContent = '🧪 Testar';
  }
}

async function resendNotification(id) {
  const { error } = await sb.from('notifications')
    .update({ status: 'pending' })
    .eq('id', id)
    .eq('status', 'failed');
  if (error) { showToast('Erro ao reenviar: ' + error.message, 'error'); return; }
  showToast('Reenvio solicitado!', 'success');
  setTimeout(loadNotifyHistory, 5000);
}
