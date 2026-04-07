// ═══════════════════════════════════════
// UTILITY FUNCTIONS
// ═══════════════════════════════════════
function todayDate() { const d=new Date(); d.setHours(0,0,0,0); return d; }
function dateStr(d, m) { return `${String(d).padStart(2,'0')}/${String(m).padStart(2,'0')}`; }

function generateDates(startStr, endStr, weekday) {
  const dates = [];
  const start = new Date(startStr + 'T00:00:00');
  const end = new Date(endStr + 'T00:00:00');
  const d = new Date(start);
  while (d.getDay() !== weekday) d.setDate(d.getDate() + 1);
  while (d <= end) { dates.push(new Date(d)); d.setDate(d.getDate() + 7); }
  return dates;
}

function fmtDate(d) {
  return `${String(d.getDate()).padStart(2,'0')}/${String(d.getMonth()+1).padStart(2,'0')}`;
}

function getMentorName(id) {
  const m = mentorsList.find(x => x.id === id);
  return m ? m.name : '?';
}

function showToast(msg, type) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = `toast ${type} show`;
  setTimeout(() => t.classList.remove('show'), 3000);
}

// ═══════════════════════════════════════
// DELETE CONFIRMATION MODAL
// ═══════════════════════════════════════
function showDeleteConfirm(name, onConfirm) {
  // Remove existing modal if any
  const existing = document.getElementById('delete-confirm-overlay');
  if (existing) existing.remove();

  const overlay = document.createElement('div');
  overlay.id = 'delete-confirm-overlay';
  overlay.style.cssText = [
    'position:fixed','inset:0','background:rgba(0,0,0,0.8)',
    'z-index:9000','display:flex','align-items:center','justify-content:center',
    'backdrop-filter:blur(4px)',
  ].join(';');

  overlay.innerHTML = `
    <div style="background:#111;border:1px solid #2e2e2e;border-radius:16px;padding:28px 32px;max-width:420px;width:90%;text-align:center;box-shadow:0 24px 64px rgba(0,0,0,0.6)">
      <div style="width:48px;height:48px;border-radius:12px;background:rgba(239,68,68,0.12);border:1px solid rgba(239,68,68,0.25);display:inline-flex;align-items:center;justify-content:center;font-size:22px;margin-bottom:18px">🗑</div>
      <div style="font-size:16px;font-weight:800;color:#fff;margin-bottom:8px">Confirmar exclusão</div>
      <div style="font-size:13px;color:#666;line-height:1.6;margin-bottom:24px">
        Deletar <strong style="color:#ddd">${name}</strong>?<br>
        <span style="color:#555;font-size:12px">Esta ação não pode ser desfeita.</span>
      </div>
      <div style="display:flex;gap:10px;justify-content:center">
        <button id="del-cancel-btn" style="padding:10px 24px;border-radius:8px;border:1px solid #2a2a2a;background:#1a1a1a;color:#888;font-size:13px;font-weight:600;cursor:pointer;font-family:var(--font-sans);transition:all 0.15s">Cancelar</button>
        <button id="del-confirm-btn" style="padding:10px 24px;border-radius:8px;border:none;background:linear-gradient(135deg,#dc2626,#b91c1c);color:#fff;font-size:13px;font-weight:700;cursor:pointer;font-family:var(--font-sans);transition:opacity 0.15s">Deletar</button>
      </div>
    </div>
  `;

  document.body.appendChild(overlay);

  const close = () => overlay.remove();

  overlay.addEventListener('click', e => { if (e.target === overlay) close(); });
  document.getElementById('del-cancel-btn').addEventListener('click', close);
  document.getElementById('del-confirm-btn').addEventListener('click', () => {
    close();
    onConfirm();
  });

  // Keyboard support
  const onKey = e => {
    if (e.key === 'Escape') { close(); document.removeEventListener('keydown', onKey); }
    if (e.key === 'Enter') { document.getElementById('del-confirm-btn')?.click(); document.removeEventListener('keydown', onKey); }
  };
  document.addEventListener('keydown', onKey);
}

function goToMonth(y, m) { renderGrid(y, m); }
