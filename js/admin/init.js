// ═══════════════════════════════════════
// INIT
// ═══════════════════════════════════════
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') closeModal({ target: document.getElementById('modal') });
});

checkAuth();
