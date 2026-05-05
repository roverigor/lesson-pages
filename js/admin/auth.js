// ═══════════════════════════════════════
// AUTH (EPIC-015 Story 15.1 — role-based redirect)
// ═══════════════════════════════════════

const CS_REDIRECT_URL = '/cs/';
const ADMIN_REDIRECT_URL = '/admin/';

function getUserRole(user) {
  return user?.user_metadata?.role ?? null;
}

async function handleRoleRouting(user) {
  const role = getUserRole(user);

  // CS role → redirect para área CS
  if (role === 'cs') {
    const target = window.location.origin + CS_REDIRECT_URL;
    if (window.location.pathname !== CS_REDIRECT_URL) {
      window.location.replace(target);
      return false;  // não continua admin app
    }
    return false;
  }

  // Admin role → permite acesso painel admin
  if (role === 'admin') {
    return true;
  }

  // Sem role válida — logout + erro
  console.warn('[auth] role não autorizada:', role);
  await sb.auth.signOut();
  showLoginError('Acesso não autorizado. Contate o administrador.');
  return false;
}

function showLoginError(msg) {
  const errEl = document.getElementById('login-error');
  if (errEl) {
    errEl.textContent = msg;
    errEl.classList.add('show');
  }
}

async function checkAuth() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return;

  const ok = await handleRoleRouting(session.user);
  if (!ok) return;

  showApp();
  await loadClasses();
  await loadOverrides();
  await loadAttendance();
  renderAll();
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

    // Story 15.1 — redirect role-based
    const ok = await handleRoleRouting(data.user);
    if (!ok) {
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
