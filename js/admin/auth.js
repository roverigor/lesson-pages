// ═══════════════════════════════════════
// AUTH
// ═══════════════════════════════════════
async function checkAuth() {
  const { data: { session } } = await sb.auth.getSession();
  if (session) {
    showApp();
    await loadClasses();
    await loadOverrides();
    await loadAttendance();
    renderAll();
  }
}

async function handleLogin(e) {
  e.preventDefault();
  const btn = document.getElementById('login-btn');
  const errEl = document.getElementById('login-error');
  btn.disabled = true;
  errEl.classList.remove('show');

  const email = document.getElementById('login-email').value.trim();
  const password = document.getElementById('login-password').value;

  try {
    const { data, error } = await sb.auth.signInWithPassword({ email, password });
    if (error) {
      errEl.textContent = error.message || 'Email ou senha incorretos';
      errEl.classList.add('show');
      btn.disabled = false;
      return;
    }

    showApp();
    await loadClasses();
    await loadOverrides();
    await loadAttendance();
    renderAll();
  } catch (err) {
    console.error('Login exception:', err);
    errEl.textContent = 'Erro de conexão: ' + err.message;
    errEl.classList.add('show');
    btn.disabled = false;
  }
}

async function handleLogout() {
  await sb.auth.signOut();
  document.getElementById('login-overlay').classList.remove('hidden');
  const shell = document.getElementById('app-shell');
  if (shell) shell.classList.add('hidden');
  const header = document.getElementById('app-header');
  if (header) header.style.display = 'none';
  const content = document.getElementById('app-content');
  if (content) content.style.display = 'none';
}

function showApp() {
  document.getElementById('login-overlay').classList.add('hidden');
  const shell = document.getElementById('app-shell');
  if (shell) shell.classList.remove('hidden');
  const header = document.getElementById('app-header');
  if (header) header.style.display = '';
  const content = document.getElementById('app-content');
  if (content) content.style.display = '';
}
