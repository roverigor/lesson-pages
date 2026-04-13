// ─── Shared utilities — Academia Lendária ───────────────────────────────────
// Inclua com: <script src="/templates/utils.js"></script>
// ────────────────────────────────────────────────────────────────────────────

// ── Toast notification ──────────────────────────────────────────────────────
function showToast(msg, type = 'success', durationMs = 3000) {
  const t = document.getElementById('toast');
  if (!t) return;
  t.textContent = msg;
  t.className = 'toast ' + type + ' show';
  clearTimeout(t._hideTimer);
  t._hideTimer = setTimeout(() => t.classList.remove('show'), durationMs);
}

// ── Deterministic color from name (consistent across all pages) ─────────────
const MENTOR_COLORS = ['#6366f1','#8b5cf6','#ec4899','#f59e0b','#10b981','#3b82f6','#ef4444','#14b8a6'];

function mentorColor(name) {
  let h = 0;
  for (const c of (name || '')) h = (h * 31 + c.charCodeAt(0)) % MENTOR_COLORS.length;
  return MENTOR_COLORS[h];
}

// Alias for pages that use getAvatarColor
const getAvatarColor = mentorColor;

// ── HTML escape ─────────────────────────────────────────────────────────────
function escHtml(s) {
  return (s ?? '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ── Name matching (token-based) ─────────────────────────────────────────────
function nameMatch(a, b) {
  if (!a || !b) return false;
  const norm = s => s.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').trim();
  const ta = norm(a).split(/\s+/).filter(Boolean);
  const tb = norm(b).split(/\s+/).filter(Boolean);
  if (ta.length === 0 || tb.length === 0) return false;
  if (ta[0] !== tb[0]) return false;
  const shared = ta.filter(t => tb.includes(t));
  return shared.length >= Math.min(2, Math.min(ta.length, tb.length));
}

// ── Login handler (requires Supabase client `sb`) ───────────────────────────
function handleLogin(e) {
  e.preventDefault();
  const btn = document.getElementById('login-btn');
  const errEl = document.getElementById('login-error');
  btn.disabled = true;
  errEl.textContent = '';
  errEl.classList.remove('show');
  sb.auth.signInWithPassword({
    email: document.getElementById('login-email').value.trim(),
    password: document.getElementById('login-password').value,
  }).then(({ error }) => {
    if (error) {
      errEl.textContent = 'Email ou senha incorretos';
      errEl.classList.add('show');
      btn.disabled = false;
      return;
    }
    showApp();
  });
}

// ── Date helpers ─────────────────────────────────────────────────────────────
function generateWeeklyDates(startStr, endStr, weekday, format = 'iso') {
  const dates = [];
  const start = new Date(startStr + 'T00:00:00');
  const end   = new Date(endStr   + 'T00:00:00');
  const d = new Date(start);
  while (d.getDay() !== weekday) d.setDate(d.getDate() + 1);
  while (d <= end) {
    if (format === 'iso')    dates.push(d.toISOString().split('T')[0]);
    else if (format === 'br') dates.push(d.toLocaleDateString('pt-BR', { day: '2-digit', month: '2-digit' }));
    else                      dates.push(new Date(d));
    d.setDate(d.getDate() + 7);
  }
  return dates;
}
