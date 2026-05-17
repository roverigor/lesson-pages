// ═══════════════════════════════════════════════════════════════════════════
// admin/nps-monitor — NPS Dispatcher Monitor (P3-UI)
// ═══════════════════════════════════════════════════════════════════════════
//
// Backend RPCs (all gated by is_dashboard_admin()):
//   nps_admin_dashboard()                 → returns full state
//   nps_admin_set_config(key, value)
//   nps_admin_update_variant(id, body, active)
//   nps_admin_skip_job(job_id, reason)
//   nps_admin_force_job_now(job_id)
//   nps_admin_reset_stuck_job(job_id)
// ═══════════════════════════════════════════════════════════════════════════

const SUPABASE_URL = window.SUPABASE_CONFIG?.url;
const SUPABASE_ANON_KEY = window.SUPABASE_CONFIG?.anonKey;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error("Missing SUPABASE_CONFIG. Page will not work.");
}

const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true },
});

const $ = (id) => document.getElementById(id);
const show = (el) => el.classList.remove("hidden");
const hide = (el) => el.classList.add("hidden");
const REFRESH_MS = 30000;

const state = {
  data: null,
  autoRefresh: true,
  refreshTimer: null,
  inflight: 0,
  modalOpen: false,
  pendingMasterFlip: null,
  pendingJobAction: null,
  editingVariant: null,
};

// ─── Utilities ─────────────────────────────────────────────────────────
function escapeHtml(s) {
  if (s == null) return "";
  return String(s)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

function fmtDateTime(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleString("pt-BR", {
    day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit",
  });
}

function fmtDate(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "2-digit" });
}

function toast(msg, kind = "info") {
  const container = $("toast-container");
  const el = document.createElement("div");
  el.className = `toast ${kind}`;
  el.textContent = msg;
  container.appendChild(el);
  setTimeout(() => el.remove(), 4500);
}

async function rpc(name, args = {}) {
  state.inflight++;
  try {
    const { data, error } = await sb.rpc(name, args);
    if (error) throw error;
    return data;
  } finally {
    state.inflight--;
  }
}

// ─── Auth ──────────────────────────────────────────────────────────────
async function ensureAdmin() {
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return null;
  const role = session.user?.user_metadata?.role;
  if (role !== "admin") return false;
  return true;
}

async function login() {
  const email = $("login-email").value.trim();
  const password = $("login-password").value;
  if (!email || !password) {
    showLoginError("Preencha email e senha.");
    return;
  }
  $("login-btn").disabled = true;
  try {
    const { error } = await sb.auth.signInWithPassword({ email, password });
    if (error) throw error;
    const ok = await ensureAdmin();
    if (ok === false) {
      showLoginError("Sua conta não tem permissão de admin.");
      await sb.auth.signOut();
      return;
    }
    enterApp();
  } catch (e) {
    showLoginError(e?.message ?? "Erro ao logar.");
  } finally {
    $("login-btn").disabled = false;
  }
}

function showLoginError(msg) {
  const el = $("login-error");
  el.textContent = msg;
  el.classList.remove("hidden");
}

function enterApp() {
  hide($("login-overlay"));
  show($("app"));
  init();
}

async function logout() {
  await sb.auth.signOut();
  location.reload();
}

// ─── Dashboard fetch + render ──────────────────────────────────────────
async function refreshDashboard() {
  try {
    const data = await rpc("nps_admin_dashboard");
    state.data = data;
    renderAll();
    hideError();
    $("last-fetched").textContent = `atualizado ${fmtDateTime(data?.fetched_at)}`;
  } catch (e) {
    const msg = e?.message ?? String(e);
    if (e?.code === "42501") {
      hide($("app"));
      show($("forbidden"));
      return;
    }
    showError(`Erro ao carregar: ${msg}`);
  }
}

function showError(msg) {
  $("error-banner-text").textContent = msg;
  show($("error-banner"));
}
function hideError() { hide($("error-banner")); }

function renderAll() {
  if (!state.data) return;
  renderMasterSwitch();
  renderKpis();
  renderConfig();
  renderVariants();
  renderPendingJobs();
  renderRecentJobs();
}

// ─── Master Switch ─────────────────────────────────────────────────────
function renderMasterSwitch() {
  const cfg = state.data.config ?? {};
  const enabled = cfg.nps_dispatch_enabled === "true";
  const label = $("master-state-label");
  const toggle = $("master-toggle");
  label.textContent = enabled ? "Ligado" : "Desligado";
  label.className = `master-state-label ${enabled ? "on" : "off"}`;
  toggle.setAttribute("aria-checked", String(enabled));
}

function openMasterConfirm() {
  const cfg = state.data?.config ?? {};
  const currentlyOn = cfg.nps_dispatch_enabled === "true";
  const nextValue = currentlyOn ? "false" : "true";

  $("modal-master-title").textContent = currentlyOn
    ? "Desabilitar dispatcher?"
    : "Habilitar dispatcher?";
  $("modal-master-msg").textContent = currentlyOn
    ? "Jobs pendentes ficam congelados. Jobs em andamento finalizam normalmente. Nenhuma nova mensagem será enviada até reativar."
    : "Após confirmar, o dispatcher começa a processar jobs pendentes. Mensagens reais serão enviadas a alunos via WhatsApp.";

  $("modal-master-accept").checked = false;
  $("modal-master-confirm-btn").disabled = true;
  state.pendingMasterFlip = nextValue;
  showModal($("modal-master-confirm"));
}

async function confirmMasterFlip() {
  if (!state.pendingMasterFlip) return;
  try {
    await rpc("nps_admin_set_config", { p_key: "nps_dispatch_enabled", p_value: state.pendingMasterFlip });
    toast(`Dispatcher ${state.pendingMasterFlip === "true" ? "habilitado" : "desabilitado"}.`, "success");
    closeModals();
    state.pendingMasterFlip = null;
    await refreshDashboard();
  } catch (e) {
    toast(`Erro: ${e?.message ?? e}`, "error");
  }
}

// ─── KPIs ──────────────────────────────────────────────────────────────
function renderKpis() {
  const s = state.data.stats ?? {};
  const $$ = (k) => document.querySelector(`[data-kpi="${k}"]`);
  const $$sub = (k) => document.querySelector(`[data-kpi-sub="${k}"]`);

  $$("jobs_24h").textContent = s.jobs_24h ?? 0;
  $$("dm_sent_24h").textContent = s.dm_sent_24h ?? 0;
  $$("opens_24h").textContent = s.opens_24h ?? 0;
  $$("responses_24h").textContent = s.responses_24h ?? 0;

  $$sub("jobs_split").textContent =
    `✓ ${s.jobs_sent_24h ?? 0}  ✕ ${s.jobs_failed_24h ?? 0}  ◐ ${s.jobs_partial_24h ?? 0}`;
  $$sub("dm_failed").textContent =
    `falhas: ${s.dm_failed_24h ?? 0}`;
}

// ─── Config ────────────────────────────────────────────────────────────
function renderConfig() {
  const cfg = state.data.config ?? {};
  $("cfg-cooldown").value = cfg.nps_cohort_cooldown_hours ?? "";
  $("cfg-delay").value = cfg.nps_dispatch_delay_minutes ?? "";
  $("cfg-maxdm").value = cfg.nps_dispatch_max_dm_per_run ?? "";
  $("cfg-throttle").value = cfg.nps_dispatch_dm_throttle_ms ?? "";
}

async function saveConfig(key) {
  const input = document.querySelector(`input[data-key="${key}"]`);
  const value = input.value.trim();
  if (value === "") {
    toast("Valor vazio.", "error");
    return;
  }
  try {
    await rpc("nps_admin_set_config", { p_key: key, p_value: value });
    toast(`${key} salvo: ${value}`, "success");
    await refreshDashboard();
  } catch (e) {
    toast(`Erro: ${e?.message ?? e}`, "error");
  }
}

// ─── Variants ──────────────────────────────────────────────────────────
function renderVariants() {
  const v = state.data.variants ?? { group: [], dm: [] };
  const rot = state.data.rotation ?? {};
  $("variants-group").innerHTML = renderVariantList(v.group, rot.group?.last_variant_id);
  $("variants-dm").innerHTML = renderVariantList(v.dm, rot.dm?.last_variant_id);
}

function renderVariantList(list, lastVariantId) {
  if (!list?.length) return `<div class="loading-placeholder">Sem variantes cadastradas.</div>`;
  return list.map((v) => {
    const rotated = v.id === lastVariantId;
    const isDM = v.channel === "dm";
    return `
      <div class="variant-card ${v.active ? "active" : "inactive"}">
        <div class="variant-row-top">
          <span class="variant-id">
            ${escapeHtml(v.id)}
            ${rotated ? '<span class="badge-rotated">🔄 última</span>' : ""}
          </span>
          <div class="variant-actions">
            <span class="variant-status-pill ${v.active ? "active" : "inactive"}">
              ${v.active ? "ativa" : "inativa"}
            </span>
            <button class="btn-secondary btn-sm" data-edit-variant="${escapeHtml(v.id)}">
              Editar
            </button>
          </div>
        </div>
        <pre class="variant-body">${escapeHtml(v.body_template)}</pre>
        <div class="variant-meta">
          ${isDM ? `<span>tpl: ${escapeHtml(v.meta_template_name ?? "—")}</span>` : ""}
          <span>peso: ${v.weight}</span>
        </div>
      </div>
    `;
  }).join("");
}

function openVariantEdit(variantId) {
  const all = [...(state.data.variants?.group ?? []), ...(state.data.variants?.dm ?? [])];
  const v = all.find((x) => x.id === variantId);
  if (!v) return;
  state.editingVariant = v;
  $("modal-variant-title").textContent = `Editar ${v.id} (${v.channel})`;
  const textarea = $("variant-body-textarea");
  textarea.value = v.body_template ?? "";
  textarea.disabled = v.channel === "dm"; // DM body controlled by Meta template, only toggle active
  $("variant-active-toggle").checked = !!v.active;
  showModal($("modal-variant-edit"));
}

async function saveVariant() {
  if (!state.editingVariant) return;
  const v = state.editingVariant;
  const newBody = $("variant-body-textarea").value;
  const newActive = $("variant-active-toggle").checked;

  // For DM, don't change body
  const bodyToSend = v.channel === "dm" ? v.body_template : newBody;

  if (v.channel === "group" && bodyToSend.trim().length < 10) {
    toast("Body muito curto (min 10 chars).", "error");
    return;
  }

  try {
    await rpc("nps_admin_update_variant", {
      p_variant_id: v.id,
      p_body_template: bodyToSend,
      p_active: newActive,
    });
    toast(`Variant ${v.id} atualizada.`, "success");
    closeModals();
    state.editingVariant = null;
    await refreshDashboard();
  } catch (e) {
    toast(`Erro: ${e?.message ?? e}`, "error");
  }
}

// ─── Pending Jobs ──────────────────────────────────────────────────────
function renderPendingJobs() {
  const jobs = state.data.pending_jobs ?? [];
  const body = $("pending-jobs-body");
  if (!jobs.length) {
    body.innerHTML = `<tr><td colspan="7" class="loading-placeholder">Nenhum job pendente.</td></tr>`;
    return;
  }
  body.innerHTML = jobs.map((j) => {
    const stuck = j.status === "in_progress" && j.started_at &&
      (Date.now() - new Date(j.started_at).getTime()) > 15 * 60 * 1000;
    return `
      <tr>
        <td>${escapeHtml(j.cohort_name ?? "—")}</td>
        <td>${escapeHtml(j.class_name ?? "—")}</td>
        <td>${fmtDate(j.session_date)}</td>
        <td><span class="status-pill ${j.status}">${j.status}</span></td>
        <td>${fmtDateTime(j.scheduled_at)}</td>
        <td>${j.total_eligible_students ?? "—"}</td>
        <td>
          <div class="row-actions">
            ${j.status === "pending" ? `<button class="btn-primary btn-sm" data-action="force" data-job="${j.id}">▶ Disparar</button>` : ""}
            ${j.status === "pending" || j.status === "in_progress" ? `<button class="btn-secondary btn-sm" data-action="skip" data-job="${j.id}">✕ Cancelar</button>` : ""}
            ${stuck ? `<button class="btn-secondary btn-sm" data-action="reset" data-job="${j.id}">↻ Reset</button>` : ""}
          </div>
        </td>
      </tr>
    `;
  }).join("");
}

function openJobActionConfirm(action, jobId) {
  const messages = {
    force: ["Disparar job agora?", "Job sai no próximo tick do cron (≤5 min) ou imediato se você invocar dispatch-class-nps manualmente."],
    skip: ["Cancelar job?", "Status muda pra 'skipped'. Não envia nada. Irreversível por essa UI."],
    reset: ["Reset job stuck?", "Status volta pra 'pending'. Próximo tick re-tenta. Use só se job ficou 'in_progress' por >15min."],
  };
  const [title, msg] = messages[action] ?? ["Confirmar", "Executar ação?"];
  $("modal-job-title").textContent = title;
  $("modal-job-msg").textContent = msg;
  state.pendingJobAction = { action, jobId };
  showModal($("modal-job-confirm"));
}

async function confirmJobAction() {
  if (!state.pendingJobAction) return;
  const { action, jobId } = state.pendingJobAction;
  const rpcMap = {
    force: "nps_admin_force_job_now",
    skip: "nps_admin_skip_job",
    reset: "nps_admin_reset_stuck_job",
  };
  const args = { p_job_id: jobId };
  if (action === "skip") args.p_reason = "manual_via_ui";

  try {
    await rpc(rpcMap[action], args);
    toast(`Ação '${action}' OK.`, "success");
    closeModals();
    state.pendingJobAction = null;
    await refreshDashboard();
  } catch (e) {
    toast(`Erro: ${e?.message ?? e}`, "error");
  }
}

// ─── Recent Jobs ───────────────────────────────────────────────────────
function renderRecentJobs() {
  const jobs = state.data.recent_jobs ?? [];
  const body = $("recent-jobs-body");
  if (!jobs.length) {
    body.innerHTML = `<tr><td colspan="8" class="loading-placeholder">Sem jobs finalizados.</td></tr>`;
    return;
  }
  body.innerHTML = jobs.map((j) => `
    <tr>
      <td>${escapeHtml(j.cohort_name ?? "—")}</td>
      <td>${escapeHtml(j.class_name ?? "—")}</td>
      <td>${fmtDate(j.session_date)}</td>
      <td><span class="status-pill ${j.status}">${j.status}</span></td>
      <td>${fmtDateTime(j.finished_at)}</td>
      <td>${j.dm_sent_count ?? 0}/${(j.dm_sent_count ?? 0) + (j.dm_failed_count ?? 0)}</td>
      <td>${escapeHtml(j.group_send_status ?? "—")}</td>
      <td><button class="btn-secondary btn-sm" data-action="detail" data-job="${j.id}">Ver</button></td>
    </tr>
  `).join("");
}

function openJobDetail(jobId) {
  const all = [...(state.data.pending_jobs ?? []), ...(state.data.recent_jobs ?? [])];
  const j = all.find((x) => x.id === jobId);
  if (!j) return;
  $("modal-job-detail-title").textContent = `Job ${j.id.slice(0, 8)}…`;
  $("modal-job-detail-body").textContent = JSON.stringify(j, null, 2);
  showModal($("modal-job-detail"));
}

// ─── Modal helpers ─────────────────────────────────────────────────────
function showModal(el) {
  state.modalOpen = true;
  show(el);
  pauseAutoRefresh();
}

function closeModals() {
  state.modalOpen = false;
  document.querySelectorAll(".modal-overlay").forEach(hide);
  if (state.autoRefresh) startAutoRefresh();
}

// ─── Auto-refresh ──────────────────────────────────────────────────────
function startAutoRefresh() {
  stopAutoRefresh();
  state.refreshTimer = setInterval(() => {
    if (!state.modalOpen && state.inflight === 0) refreshDashboard();
  }, REFRESH_MS);
}

function stopAutoRefresh() {
  if (state.refreshTimer) clearInterval(state.refreshTimer);
  state.refreshTimer = null;
}

function pauseAutoRefresh() {
  stopAutoRefresh();
}

function toggleAutoRefresh() {
  state.autoRefresh = !state.autoRefresh;
  if (state.autoRefresh) {
    startAutoRefresh();
    $("auto-refresh-btn").textContent = "⏸️ Pausar";
    toast("Auto-refresh ativo (30s)", "info");
  } else {
    stopAutoRefresh();
    $("auto-refresh-btn").textContent = "▶ Auto-refresh";
    toast("Auto-refresh pausado", "info");
  }
}

// ─── Event wiring ──────────────────────────────────────────────────────
function wireEvents() {
  $("logout-btn").addEventListener("click", logout);
  $("refresh-btn").addEventListener("click", refreshDashboard);
  $("auto-refresh-btn").addEventListener("click", toggleAutoRefresh);
  $("error-banner-dismiss").addEventListener("click", hideError);

  $("master-toggle").addEventListener("click", openMasterConfirm);
  $("modal-master-cancel").addEventListener("click", () => { state.pendingMasterFlip = null; closeModals(); });
  $("modal-master-accept").addEventListener("change", (e) => {
    $("modal-master-confirm-btn").disabled = !e.target.checked;
  });
  $("modal-master-confirm-btn").addEventListener("click", confirmMasterFlip);

  document.querySelectorAll("[data-save-config]").forEach((btn) => {
    btn.addEventListener("click", () => saveConfig(btn.dataset.saveConfig));
  });

  document.addEventListener("click", (e) => {
    const editBtn = e.target.closest("[data-edit-variant]");
    if (editBtn) {
      openVariantEdit(editBtn.dataset.editVariant);
      return;
    }
    const actionBtn = e.target.closest("[data-action]");
    if (actionBtn) {
      const action = actionBtn.dataset.action;
      const jobId = actionBtn.dataset.job;
      if (action === "detail") openJobDetail(jobId);
      else openJobActionConfirm(action, jobId);
      return;
    }
  });

  $("modal-variant-cancel").addEventListener("click", () => { state.editingVariant = null; closeModals(); });
  $("modal-variant-save").addEventListener("click", saveVariant);

  $("modal-job-cancel").addEventListener("click", () => { state.pendingJobAction = null; closeModals(); });
  $("modal-job-confirm-btn").addEventListener("click", confirmJobAction);

  $("modal-job-detail-close").addEventListener("click", closeModals);

  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && state.modalOpen) closeModals();
  });

  $("login-btn").addEventListener("click", login);
  ["login-email", "login-password"].forEach((id) => {
    $(id).addEventListener("keydown", (e) => { if (e.key === "Enter") login(); });
  });
}

// ─── Init ──────────────────────────────────────────────────────────────
async function init() {
  await refreshDashboard();
  if (state.autoRefresh) startAutoRefresh();
}

async function boot() {
  wireEvents();
  const isAdmin = await ensureAdmin();
  if (isAdmin === true) {
    enterApp();
  } else if (isAdmin === false) {
    // logged but not admin
    hide($("login-overlay"));
    show($("app"));
    hide(document.querySelector(".master-switch-card"));
    show($("forbidden"));
  } else {
    // no session
    show($("login-overlay"));
    hide($("app"));
  }
}

boot();
