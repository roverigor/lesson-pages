// ═══════════════════════════════════════
// ABSTRACTS / RESUMO DE AULAS
// ═══════════════════════════════════════
let abstractsList = [];

async function loadAbstractsView() {
  await renderAbstractsList();
}

async function renderAbstractsList() {
  const { data, error } = await sb
    .from('lesson_abstracts')
    .select('id, slug, title, lesson_date, badge_class, badge_label, section_type, sort_order, published, cohort_tag')
    .order('sort_order');

  const el = document.getElementById('abstracts-list');
  if (error) { el.innerHTML = `<div style="color:#f87171;padding:20px;font-size:13px;">Erro: ${error.message}</div>`; return; }

  abstractsList = data || [];
  if (!abstractsList.length) {
    el.innerHTML = '<div style="text-align:center;color:#333;padding:40px;font-size:13px;">Nenhum resumo cadastrado</div>';
    return;
  }

  const months = ['Jan','Fev','Mar','Abr','Mai','Jun','Jul','Ago','Set','Out','Nov','Dez'];
  const fmtDate = iso => {
    const d = new Date(iso + 'T00:00:00');
    return `${String(d.getDate()).padStart(2,'0')} ${months[d.getMonth()]} ${d.getFullYear()}`;
  };

  const badgeColors = { green: '#4ade80', purple: '#a855f7', gray: '#666' };

  el.innerHTML = abstractsList.map(r => {
    const color = badgeColors[r.badge_class] || '#888';
    const date = fmtDate(r.lesson_date);
    const typeLabel = r.section_type === 'kb' ? 'Base de Conhecimento' : 'Aula';
    const pubColor = r.published ? '#4ade80' : '#555';
    const pubLabel = r.published ? 'Publicado' : 'Oculto';

    return `<div style="background:#111;border:1px solid #1e1e1e;border-radius:10px;padding:14px 16px;margin-bottom:8px;display:flex;align-items:center;gap:12px;">
      <div style="width:8px;height:8px;border-radius:50%;background:${color};flex-shrink:0"></div>
      <div style="flex:1;min-width:0">
        <div style="font-size:13px;font-weight:700;color:#ddd;margin-bottom:2px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${r.title}</div>
        <div style="font-size:11px;color:#555">${r.badge_label} · ${date} · <span style="color:#444">${typeLabel}</span> · slug: <span style="color:#333;font-family:monospace">${r.slug}</span></div>
      </div>
      <span style="font-size:10px;padding:2px 8px;border-radius:999px;border:1px solid #222;color:${pubColor};flex-shrink:0">${pubLabel}</span>
      <div style="display:flex;gap:6px;flex-shrink:0">
        <button onclick="editAbstract('${r.id}')" style="padding:5px 10px;border-radius:6px;border:1px solid #222;background:#1a1a1a;color:#aaa;font-size:11px;font-weight:700;cursor:pointer;font-family:var(--font-sans)">Editar</button>
        <button onclick="toggleAbstract('${r.id}', ${!r.published})" style="padding:5px 10px;border-radius:6px;border:1px solid #222;background:#1a1a1a;color:#888;font-size:11px;cursor:pointer;font-family:var(--font-sans)">${r.published ? 'Ocultar' : 'Publicar'}</button>
        <button onclick="deleteAbstract('${r.id}')" style="padding:5px 8px;border-radius:6px;border:1px solid #44403c;background:rgba(168,162,158,0.08);color:#a8a29e;font-size:13px;cursor:pointer;font-family:var(--font-sans)">✕</button>
      </div>
    </div>`;
  }).join('');
}

function openAbstractForm() {
  document.getElementById('abstract-edit-id').value = '';
  document.getElementById('abstract-slug').value = '';
  document.getElementById('abstract-title').value = '';
  document.getElementById('abstract-date').value = '';
  document.getElementById('abstract-badge-class').value = 'green';
  document.getElementById('abstract-badge-label').value = '';
  document.getElementById('abstract-section-type').value = 'lesson';
  document.getElementById('abstract-sort').value = abstractsList.length;
  document.getElementById('abstract-cohort').value = '';
  document.getElementById('abstract-body').value = '';
  document.getElementById('abstract-save-btn').textContent = 'Salvar';
  document.getElementById('abstract-form-container').style.display = '';
  document.getElementById('abstract-form-container').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function closeAbstractForm() {
  document.getElementById('abstract-form-container').style.display = 'none';
}

async function editAbstract(id) {
  const { data, error } = await sb.from('lesson_abstracts').select('*').eq('id', id).single();
  if (error) { showToast('Erro ao carregar: ' + error.message, 'error'); return; }

  document.getElementById('abstract-edit-id').value = data.id;
  document.getElementById('abstract-slug').value = data.slug;
  document.getElementById('abstract-title').value = data.title;
  document.getElementById('abstract-date').value = data.lesson_date;
  document.getElementById('abstract-badge-class').value = data.badge_class;
  document.getElementById('abstract-badge-label').value = data.badge_label;
  document.getElementById('abstract-section-type').value = data.section_type;
  document.getElementById('abstract-sort').value = data.sort_order;
  document.getElementById('abstract-cohort').value = data.cohort_tag || '';
  document.getElementById('abstract-body').value = data.body_html;
  document.getElementById('abstract-save-btn').textContent = 'Atualizar';
  document.getElementById('abstract-form-container').style.display = '';
  document.getElementById('abstract-form-container').scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

async function saveAbstract() {
  const id       = document.getElementById('abstract-edit-id').value;
  const slug     = document.getElementById('abstract-slug').value.trim();
  const title    = document.getElementById('abstract-title').value.trim();
  const date     = document.getElementById('abstract-date').value;
  const badgeCls = document.getElementById('abstract-badge-class').value;
  const badgeLbl = document.getElementById('abstract-badge-label').value.trim();
  const secType  = document.getElementById('abstract-section-type').value;
  const sort     = parseInt(document.getElementById('abstract-sort').value, 10) || 0;
  const cohort   = document.getElementById('abstract-cohort').value.trim();
  const body     = document.getElementById('abstract-body').value.trim();

  if (!slug)    { showToast('Slug é obrigatório', 'error'); return; }
  if (!title)   { showToast('Título é obrigatório', 'error'); return; }
  if (!date)    { showToast('Data é obrigatória', 'error'); return; }
  if (!body)    { showToast('Conteúdo HTML é obrigatório', 'error'); return; }

  const btn = document.getElementById('abstract-save-btn');
  btn.disabled = true; btn.textContent = 'Salvando...';

  try {
    const payload = {
      slug, title,
      lesson_date: date,
      badge_class: badgeCls,
      badge_label: badgeLbl,
      section_type: secType,
      sort_order: sort,
      cohort_tag: cohort || null,
      body_html: body,
    };

    let error;
    if (id) {
      ({ error } = await sb.from('lesson_abstracts').update(payload).eq('id', id));
    } else {
      ({ error } = await sb.from('lesson_abstracts').insert({ ...payload, published: true }));
    }

    if (error) throw error;
    showToast(id ? 'Resumo atualizado!' : 'Resumo criado!', 'success');
    closeAbstractForm();
    await renderAbstractsList();
  } catch (err) {
    showToast('Erro: ' + err.message, 'error');
  } finally {
    btn.disabled = false;
    btn.textContent = id ? 'Atualizar' : 'Salvar';
  }
}

async function toggleAbstract(id, published) {
  const { error } = await sb.from('lesson_abstracts').update({ published }).eq('id', id);
  if (error) { showToast('Erro ao atualizar', 'error'); return; }
  showToast(published ? 'Publicado' : 'Ocultado', 'success');
  await renderAbstractsList();
}

async function deleteAbstract(id) {
  if (!confirm('Deletar este resumo? Esta ação não pode ser desfeita.')) return;
  const { error } = await sb.from('lesson_abstracts').delete().eq('id', id);
  if (error) { showToast('Erro ao deletar', 'error'); return; }
  showToast('Deletado', 'success');
  await renderAbstractsList();
}
