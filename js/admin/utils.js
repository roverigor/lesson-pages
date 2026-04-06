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

function goToMonth(y, m) { renderGrid(y, m); }
