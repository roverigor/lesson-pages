// ═══════════════════════════════════════
// STAFF MANAGEMENT (reads from mentors table)
// ═══════════════════════════════════════
async function loadStaff() {
  const { data, error } = await sb.from('mentors').select('*').order('name');
  if (error) { console.error('Load staff error:', error); return; }
  staffList = data || [];
  renderStaffList();
}

function renderStaffList() {
  const categoryColors = { Professor: '#a5b4fc', Mentor: '#facc15', Host: '#555' };
  const categoryBg = { Professor: 'rgba(99,102,241,0.12)', Mentor: 'rgba(250,204,21,0.1)', Host: 'rgba(255,255,255,0.05)' };

  const rows = staffList.map(s => {
    const aliasesStr = (s.aliases || []).length ? s.aliases.map(a => `<span style="background:rgba(99,102,241,.08);border:1px solid rgba(99,102,241,.15);color:#a5b4fc;padding:1px 6px;border-radius:4px;font-size:10px">${a}</span>`).join(' ') : '<span style="color:#333">—</span>';
    return `
    <tr>
      <td>
        <span style="display:inline-flex;align-items:center;gap:8px">
          <span style="width:28px;height:28px;border-radius:50%;background:${mentorColor(s.name)};display:inline-flex;align-items:center;justify-content:center;font-size:10px;font-weight:800;color:#fff">${initials(s.name)}</span>
          <span style="color:#ddd;font-weight:600">${s.name}</span>
        </span>
      </td>
      <td>${s.email || '<span style="color:#333">—</span>'}</td>
      <td>${s.phone || '<span style="color:#333">—</span>'}</td>
      <td><span style="color:${categoryColors[s.category]};background:${categoryBg[s.category]};padding:2px 8px;border-radius:4px;font-size:11px;font-weight:700">${s.category}</span></td>
      <td style="font-size:11px">${aliasesStr}</td>
      <td>
        <span style="display:flex;gap:4px">
          <button class="att-btn" style="padding:4px 8px;font-size:11px" onclick="editStaff('${s.id}')">Editar</button>
          <button class="att-btn delete" style="padding:4px 8px" onclick="deleteStaff('${s.id}','${s.name}')">🗑</button>
        </span>
      </td>
    </tr>`;
  }).join('');

  document.getElementById('staff-list').innerHTML = `
    <table class="report-table">
      <thead><tr>
        <th>Nome</th><th>Email</th><th>Telefone</th><th>Categoria</th><th>Aliases Zoom</th><th>Ações</th>
      </tr></thead>
      <tbody>${rows}</tbody>
    </table>
  `;
}

function openStaffForm() {
  document.getElementById('staff-form-container').style.display = '';
  document.getElementById('staff-edit-id').value = '';
  document.getElementById('staff-name').value = '';
  document.getElementById('staff-email').value = '';
  document.getElementById('staff-phone').value = '';
  document.getElementById('staff-category').value = 'Professor';
  document.getElementById('staff-aliases').value = '';
  document.getElementById('staff-name').focus();
}

function closeStaffForm() {
  document.getElementById('staff-form-container').style.display = 'none';
}

function editStaff(id) {
  const s = staffList.find(x => x.id === id);
  if (!s) return;
  document.getElementById('staff-form-container').style.display = '';
  document.getElementById('staff-edit-id').value = s.id;
  document.getElementById('staff-name').value = s.name;
  document.getElementById('staff-email').value = s.email || '';
  document.getElementById('staff-phone').value = s.phone || '';
  document.getElementById('staff-category').value = s.category;
  document.getElementById('staff-aliases').value = (s.aliases || []).join(', ');
  document.getElementById('staff-name').focus();
}

async function saveStaff() {
  const id       = document.getElementById('staff-edit-id').value;
  const name     = document.getElementById('staff-name').value.trim();
  const email    = document.getElementById('staff-email').value.trim();
  const rawPhone = document.getElementById('staff-phone').value.trim().replace(/\D/g, '');
  const category = document.getElementById('staff-category').value;
  const aliasesRaw = document.getElementById('staff-aliases').value.trim();
  const aliases  = aliasesRaw ? aliasesRaw.split(',').map(a => a.trim()).filter(a => a) : [];

  if (!name) { showToast('Nome é obrigatório', 'error'); return; }

  const role = category === 'Host' ? 'Host' : 'Professor';
  const record = { name, email: email || null, phone: rawPhone || null, role, category, aliases };

  if (id) {
    const { error } = await sb.from('mentors').update(record).eq('id', id);
    if (error) { showToast('Erro: ' + error.message, 'error'); return; }
  } else {
    const { error } = await sb.from('mentors').insert(record);
    if (error) { showToast('Erro: ' + error.message, 'error'); return; }
  }

  showToast(id ? 'Cadastro atualizado!' : 'Membro adicionado!', 'success');
  closeStaffForm();
  await loadStaff();
}

async function deleteStaff(id, name) {
  showDeleteConfirm(name, async () => {
    const { error } = await sb.from('mentors').delete().eq('id', id);
    if (error) { showToast('Erro: ' + error.message, 'error'); return; }
    showToast(`${name} removido`, 'success');
    await loadStaff();
  });
}
