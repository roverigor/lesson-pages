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
  document.getElementById('app-header').style.display = 'none';
  document.getElementById('app-content').style.display = 'none';
}

function showApp() {
  document.getElementById('login-overlay').classList.add('hidden');
  document.getElementById('app-header').style.display = '';
  document.getElementById('app-content').style.display = '';
}
