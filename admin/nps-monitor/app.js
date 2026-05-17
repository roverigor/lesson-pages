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

const MOCK = new URLSearchParams(location.search).get("mock") === "1";

if (!MOCK && (!SUPABASE_URL || !SUPABASE_ANON_KEY)) {
  console.error("Missing SUPABASE_CONFIG. Page will not work.");
}

const sb = !MOCK && window.supabase
  ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: true, autoRefreshToken: true },
    })
  : null;

const $ = (id) => document.getElementById(id);
const show = (el) => el.classList.remove("hidden");
const hide = (el) => el.classList.add("hidden");
const REFRESH_MS = 30000;

const state = {
  data: null,
  groups: [],
  autoRefresh: true,
  refreshTimer: null,
  inflight: 0,
  modalOpen: false,
  pendingMasterFlip: null,
  pendingJobAction: null,
  editingVariant: null,
  pendingGroupVerify: null,
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
    if (MOCK) return await mockRpc(name, args);
    const { data, error } = await sb.rpc(name, args);
    if (error) throw error;
    return data;
  } finally {
    state.inflight--;
  }
}

// ─── MOCK LAYER (preview mode via ?mock=1) ──────────────────────────────
const MOCK_DATA = {
  config: {
    nps_dispatch_enabled: "false",
    nps_cohort_cooldown_hours: "12",
    nps_dispatch_delay_minutes: "5",
    nps_dispatch_max_dm_per_run: "50",
    nps_dispatch_dm_throttle_ms: "10000",
  },
  variants: {
    group: [
      {
        id: "group_v1", channel: "group",
        body_template: "Pessoal, obrigado pela presença em *{{class_name}}* hoje! 💜\n\nQueremos saber como foi pra vocês.\nResponde rapidinho aqui (anônimo, opção de colocar nome): {{link}}",
        meta_template_name: null, active: true, weight: 1, created_at: "2026-05-17T12:00:00Z",
      },
      {
        id: "group_v2", channel: "group",
        body_template: "Galera, fechamos *{{class_name}}* agora! 🚀\n\nUma pergunta rápida pra gente continuar evoluindo o conteúdo: {{link}}\n\nLeva 30s, podem responder sem se identificar.",
        meta_template_name: null, active: true, weight: 1, created_at: "2026-05-17T12:00:00Z",
      },
      {
        id: "group_v3", channel: "group",
        body_template: "Time {{cohort_name}}! 👋\n\nFeedback express da aula de hoje (*{{class_name}}*) — sua opinião direciona os próximos encontros:\n{{link}}",
        meta_template_name: null, active: true, weight: 1, created_at: "2026-05-17T12:00:00Z",
      },
    ],
    dm: [
      { id: "dm_v1", channel: "dm", body_template: "NPS pós-aula individual — variant 1", meta_template_name: "nps_post_class_v1", active: false, weight: 1, created_at: "2026-05-17T12:00:00Z" },
      { id: "dm_v2", channel: "dm", body_template: "NPS pós-aula individual — variant 2", meta_template_name: "nps_post_class_v2", active: false, weight: 1, created_at: "2026-05-17T12:00:00Z" },
      { id: "dm_v3", channel: "dm", body_template: "NPS pós-aula individual — variant 3", meta_template_name: "nps_post_class_v3", active: false, weight: 1, created_at: "2026-05-17T12:00:00Z" },
    ],
  },
  rotation: {
    group: { last_variant_id: "group_v2", rotation_count: 47, updated_at: "2026-05-17T20:14:00Z" },
    dm: { last_variant_id: null, rotation_count: 0, updated_at: "2026-05-17T12:00:00Z" },
  },
  pending_jobs: [
    { id: "11111111-1111-1111-1111-111111111111", class_id: "aaa", cohort_id: "bbb", cohort_name: "PS Advanced T3", class_name: "PS Advanced", class_zoom_meeting_id: "85211223344", job_zoom_meeting_id: "85211223344", cohort_group_verified: true, session_date: "2026-05-17", status: "pending", scheduled_at: "2026-05-17T21:35:00Z", started_at: null, total_eligible_students: 42, dm_sent_count: 0, dm_failed_count: 0, group_send_status: null },
    { id: "22222222-2222-2222-2222-222222222222", class_id: "ccc", cohort_id: "ddd", cohort_name: "Fundamentals T4", class_name: "Aula 12 — Casos clínicos", class_zoom_meeting_id: "85299887766", job_zoom_meeting_id: "85299887766", cohort_group_verified: true, session_date: "2026-05-17", status: "pending", scheduled_at: "2026-05-17T22:05:00Z", started_at: null, total_eligible_students: 18, dm_sent_count: 0, dm_failed_count: 0, group_send_status: null },
    { id: "33333333-3333-3333-3333-333333333333", class_id: "eee", cohort_id: "fff", cohort_name: "PS Fundamentals T2", class_name: "PS Fundamentals", class_zoom_meeting_id: "85277665544", job_zoom_meeting_id: "85277665544", cohort_group_verified: false, session_date: "2026-05-17", status: "in_progress", scheduled_at: "2026-05-17T19:30:00Z", started_at: "2026-05-17T19:35:00Z", total_eligible_students: 67, dm_sent_count: 32, dm_failed_count: 1, group_send_status: "skipped" },
  ],
  recent_jobs: [
    { id: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa", cohort_name: "Fundamentals T4", class_name: "Aula 11 — Análise estrutural", session_date: "2026-05-16", status: "sent", finished_at: "2026-05-16T22:18:00Z", dm_sent_count: 18, dm_failed_count: 0, group_send_status: "sent", error_detail: null, variant_group_id: "group_v4", variant_dm_id: "dm_v1" },
    { id: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb", cohort_name: "PS Advanced T3", class_name: "PS Advanced", session_date: "2026-05-16", status: "partial", finished_at: "2026-05-16T21:50:00Z", dm_sent_count: 38, dm_failed_count: 4, group_send_status: "sent", error_detail: "4 DMs failed: meta_template_pending", variant_group_id: "group_v7", variant_dm_id: "dm_v2" },
    { id: "cccccccc-cccc-cccc-cccc-cccccccccccc", cohort_name: "Fundamentals T3", class_name: "Aula 14 — Casos atípicos", session_date: "2026-05-15", status: "failed", finished_at: "2026-05-15T22:30:00Z", dm_sent_count: 0, dm_failed_count: 12, group_send_status: "failed", error_detail: "evolution_http_503: instance disconnected", variant_group_id: "group_v2", variant_dm_id: null },
    { id: "dddddddd-dddd-dddd-dddd-dddddddddddd", cohort_name: "PS Fundamentals T2", class_name: "PS Fundamentals", session_date: "2026-05-15", status: "skipped", finished_at: "2026-05-15T20:00:00Z", dm_sent_count: 0, dm_failed_count: 0, group_send_status: "not_applicable", error_detail: "cooldown_active", variant_group_id: null, variant_dm_id: null },
  ],
  stats: {
    jobs_24h: 7, jobs_sent_24h: 4, jobs_partial_24h: 1, jobs_failed_24h: 1,
    dm_sent_24h: 124, dm_failed_24h: 5, opens_24h: 73, responses_24h: 28,
  },
  fetched_at: new Date().toISOString(),
};

const MOCK_GROUPS = [
  {
    cohort_id: "bbb", cohort_name: "PS Advanced T3",
    whatsapp_group_jid: "120363042000000111@g.us",
    whatsapp_group_link: "https://chat.whatsapp.com/MOCK_INVITE_ADVANCED_T3",
    jid_valid_format: true, verified: true, verified_at: "2026-05-16T14:30:00Z", verified_by: "admin",
    label: "PS Advanced T3 — WA oficial", active_students_count: 42,
    classes_bound: [
      { class_id: "aaa", class_name: "PS Advanced", zoom_meeting_id: "85211223344" },
    ],
  },
  {
    cohort_id: "ddd", cohort_name: "Fundamentals T4",
    whatsapp_group_jid: "120363042000000222@g.us",
    whatsapp_group_link: "https://chat.whatsapp.com/MOCK_INVITE_FUND_T4",
    jid_valid_format: true, verified: true, verified_at: "2026-05-15T18:00:00Z", verified_by: "admin",
    label: null, active_students_count: 18,
    classes_bound: [
      { class_id: "ccc", class_name: "Aula 12 — Casos clínicos", zoom_meeting_id: "85299887766" },
    ],
  },
  {
    cohort_id: "fff", cohort_name: "PS Fundamentals T2",
    whatsapp_group_jid: "120363042000000333@g.us",
    whatsapp_group_link: null,
    jid_valid_format: true, verified: false, verified_at: null, verified_by: null,
    label: null, active_students_count: 67,
    classes_bound: [
      { class_id: "eee", class_name: "PS Fundamentals", zoom_meeting_id: "85277665544" },
    ],
  },
  {
    cohort_id: "ggg", cohort_name: "Fundamentals T3 — legado",
    whatsapp_group_jid: "invalido-sem-sufixo",
    whatsapp_group_link: null,
    jid_valid_format: false, verified: false, verified_at: null, verified_by: null,
    label: null, active_students_count: 8,
    classes_bound: [
      { class_id: "hhh", class_name: "Aula reposição", zoom_meeting_id: null },
    ],
  },
];

async function mockRpc(name, args) {
  await new Promise((r) => setTimeout(r, 200));
  if (name === "nps_admin_dashboard") {
    return { ...MOCK_DATA, fetched_at: new Date().toISOString() };
  }
  if (name === "nps_admin_list_cohort_groups") {
    return MOCK_GROUPS;
  }
  if (name === "nps_admin_refresh_group_invite") {
    const g = MOCK_GROUPS.find((x) => x.cohort_id === args.p_cohort_id);
    if (g && !g.whatsapp_group_link) {
      g.whatsapp_group_link = `https://chat.whatsapp.com/MOCK_FETCHED_${Date.now()}`;
    }
    return { ok: true, queued: true, message: "mock invite refreshed" };
  }
  if (name === "nps_admin_set_cohort_group_verified") {
    const g = MOCK_GROUPS.find((x) => x.cohort_id === args.p_cohort_id);
    if (g) {
      g.verified = args.p_verified;
      g.verified_at = args.p_verified ? new Date().toISOString() : null;
      g.verified_by = args.p_verified ? "you" : null;
      if (args.p_label !== undefined && args.p_label !== null) g.label = args.p_label;
    }
    return { ok: true };
  }
  if (name === "nps_admin_set_config") {
    MOCK_DATA.config[args.p_key] = args.p_value;
    return { ok: true, key: args.p_key, value: args.p_value };
  }
  if (name === "nps_admin_update_variant") {
    const all = [...MOCK_DATA.variants.group, ...MOCK_DATA.variants.dm];
    const v = all.find((x) => x.id === args.p_variant_id);
    if (v) { v.body_template = args.p_body_template; v.active = args.p_active; }
    return { ok: true, variant_id: args.p_variant_id };
  }
  if (name === "nps_admin_skip_job") {
    const j = MOCK_DATA.pending_jobs.find((x) => x.id === args.p_job_id);
    if (j) {
      j.status = "skipped"; j.finished_at = new Date().toISOString();
      j.error_detail = args.p_reason ?? "manual";
      MOCK_DATA.recent_jobs.unshift(j);
      MOCK_DATA.pending_jobs = MOCK_DATA.pending_jobs.filter((x) => x.id !== args.p_job_id);
    }
    return { ok: true };
  }
  if (name === "nps_admin_force_job_now") {
    const j = MOCK_DATA.pending_jobs.find((x) => x.id === args.p_job_id);
    if (j) j.scheduled_at = new Date().toISOString();
    return { ok: true };
  }
  if (name === "nps_admin_reset_stuck_job") {
    const j = MOCK_DATA.pending_jobs.find((x) => x.id === args.p_job_id);
    if (j) { j.status = "pending"; j.started_at = null; }
    return { ok: true };
  }
  throw new Error(`mock: unknown RPC ${name}`);
}

// ─── Auth ──────────────────────────────────────────────────────────────
async function ensureAdmin() {
  if (MOCK) return true;
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
  if (MOCK) { location.reload(); return; }
  await sb.auth.signOut();
  location.reload();
}

// ─── Dashboard fetch + render ──────────────────────────────────────────
async function refreshDashboard() {
  try {
    const [data, groups] = await Promise.all([
      rpc("nps_admin_dashboard"),
      rpc("nps_admin_list_cohort_groups").catch(() => []),
    ]);
    state.data = data;
    state.groups = groups || [];
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
  renderGroups();
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

// ─── Group verification ───────────────────────────────────────────────
function renderGroups() {
  const body = $("groups-body");
  const groups = state.groups ?? [];
  if (!groups.length) {
    body.innerHTML = `<tr><td colspan="7" class="loading-placeholder">Nenhum cohort com WhatsApp JID cadastrado.</td></tr>`;
    return;
  }
  body.innerHTML = groups.map((g) => {
    const validClass = g.jid_valid_format ? "jid-valid" : "jid-invalid";
    const validIcon = g.jid_valid_format ? "✓" : "✕";
    const jidCell = renderJidCell(g);
    const classesCell = renderClassesBound(g.classes_bound ?? []);
    return `
      <tr>
        <td>${escapeHtml(g.cohort_name ?? "—")}</td>
        <td>${jidCell}</td>
        <td>${escapeHtml(g.label ?? "—")}</td>
        <td>${g.active_students_count ?? 0}</td>
        <td>${classesCell}</td>
        <td class="${validClass}">${validIcon} ${g.jid_valid_format ? "ok" : "inválido"}</td>
        <td>
          <button class="toggle-mini" role="switch"
                  aria-checked="${g.verified ? "true" : "false"}"
                  data-group-toggle="${g.cohort_id}"
                  ${!g.jid_valid_format && !g.verified ? "disabled style='opacity:0.4;cursor:not-allowed'" : ""}
                  title="${g.verified ? "Clique pra desverificar" : "Clique pra verificar"}"></button>
          ${g.verified_at ? `<div style="font-size:10px;color:#666;margin-top:4px">${fmtDateTime(g.verified_at)}</div>` : ""}
        </td>
      </tr>
    `;
  }).join("");
}

function renderJidCell(g) {
  const jid = g.whatsapp_group_jid ?? "";
  const link = g.whatsapp_group_link;
  const jidShort = jid.length > 26 ? jid.slice(0, 22) + "…" : jid;

  const linkPart = link
    ? `<a href="${escapeHtml(link)}" target="_blank" rel="noopener noreferrer" class="jid-link" title="Abrir grupo no WhatsApp">↗ Abrir no WhatsApp</a>`
    : `<button class="copy-btn" data-refresh-invite="${escapeHtml(g.cohort_id)}" title="Buscar link de convite via Evolution API">⤒ buscar invite</button>`;

  return `
    <div class="jid-cell">
      <div class="jid-actions">
        <span class="jid-mono" title="${escapeHtml(jid)}">${escapeHtml(jidShort)}</span>
        <button class="copy-btn" data-copy="${escapeHtml(jid)}" title="Copiar JID">⎘ copiar</button>
      </div>
      <div>${linkPart}</div>
    </div>
  `;
}

function renderClassesBound(classes) {
  if (!classes.length) return `<span class="binding-missing">⚠ nenhuma</span>`;
  return classes.map((c) => {
    const hasZoom = !!c.zoom_meeting_id;
    return `
      <div class="binding-cell">
        <span class="${hasZoom ? "binding-match" : "binding-missing"}">
          ${hasZoom ? "✓" : "✕"} ${escapeHtml(c.class_name ?? "—")}
        </span>
        ${hasZoom ? `<span class="binding-zoom-id">zoom: ${escapeHtml(c.zoom_meeting_id)}</span>` : '<span class="binding-zoom-id">sem zoom_meeting_id — trigger não dispara</span>'}
      </div>
    `;
  }).join("");
}

async function copyToClipboard(text) {
  try {
    await navigator.clipboard.writeText(text);
    toast(`Copiado: ${text.slice(0, 40)}`, "info");
  } catch (e) {
    toast("Falha ao copiar.", "error");
  }
}

async function refreshGroupInvite(cohortId) {
  if (MOCK) {
    toast("Mock: fetch invite simulado (nada real).", "info");
    return;
  }
  try {
    await rpc("nps_admin_refresh_group_invite", { p_cohort_id: cohortId });
    toast("Refresh enfileirado. Aguarda ~10s + reload.", "success");
    setTimeout(refreshDashboard, 10000);
  } catch (e) {
    toast(`Erro: ${e?.message ?? e}`, "error");
  }
}

function openGroupVerifyModal(cohortId) {
  const g = state.groups.find((x) => x.cohort_id === cohortId);
  if (!g) return;
  const willVerify = !g.verified;
  state.pendingGroupVerify = { cohort_id: cohortId, verify: willVerify, current: g };

  $("modal-group-title").textContent = willVerify
    ? `Verificar grupo de ${g.cohort_name}`
    : `Desverificar grupo de ${g.cohort_name}`;
  $("modal-group-msg").innerHTML = `
    <strong>Cohort:</strong> ${escapeHtml(g.cohort_name)}<br>
    <strong>JID:</strong> <code>${escapeHtml(g.whatsapp_group_jid)}</code><br>
    <strong>Alunos ativos:</strong> ${g.active_students_count}
  `;
  $("group-label-input").value = g.label ?? "";
  $("group-label-input").disabled = !willVerify;
  $("modal-group-accept").checked = false;
  $("modal-group-confirm-btn").disabled = true;
  $("modal-group-confirm-btn").textContent = willVerify ? "Marcar verificado" : "Desverificar";
  $("modal-group-confirm-btn").className = willVerify ? "btn-primary" : "btn-danger";
  showModal($("modal-group-verify"));
}

async function confirmGroupVerify() {
  if (!state.pendingGroupVerify) return;
  const { cohort_id, verify } = state.pendingGroupVerify;
  const label = verify ? $("group-label-input").value.trim() || null : null;
  try {
    await rpc("nps_admin_set_cohort_group_verified", {
      p_cohort_id: cohort_id,
      p_verified: verify,
      p_label: label,
    });
    toast(verify ? "Grupo verificado." : "Grupo desverificado.", "success");
    closeModals();
    state.pendingGroupVerify = null;
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
    body.innerHTML = `<tr><td colspan="8" class="loading-placeholder">Nenhum job pendente.</td></tr>`;
    return;
  }
  body.innerHTML = jobs.map((j) => {
    const stuck = j.status === "in_progress" && j.started_at &&
      (Date.now() - new Date(j.started_at).getTime()) > 15 * 60 * 1000;

    const bindingCell = renderJobBinding(j);
    const rowClass = j.cohort_group_verified === false ? "row-unverified" : "";

    return `
      <tr class="${rowClass}">
        <td>${escapeHtml(j.cohort_name ?? "—")}${j.cohort_group_verified === false ? ' <span style="color:#fbbf24;font-size:10px">⚠ não verificado</span>' : ""}</td>
        <td>${escapeHtml(j.class_name ?? "—")}</td>
        <td>${bindingCell}</td>
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

function renderJobBinding(j) {
  const cz = j.class_zoom_meeting_id;
  const jz = j.job_zoom_meeting_id;
  if (!cz && !jz) return `<span class="binding-missing">✕ sem binding zoom</span>`;
  const match = cz && jz && cz === jz;
  return `
    <div class="binding-cell">
      <span class="${match ? "binding-match" : "binding-missing"}">
        ${match ? "✓" : "⚠"} ${escapeHtml(cz ?? "—")}
      </span>
      ${jz && jz !== cz ? `<span class="binding-zoom-id">job: ${escapeHtml(jz)}</span>` : ""}
    </div>
  `;
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
    const groupToggle = e.target.closest("[data-group-toggle]");
    if (groupToggle && !groupToggle.disabled) {
      openGroupVerifyModal(groupToggle.dataset.groupToggle);
      return;
    }
    const copyBtn = e.target.closest("[data-copy]");
    if (copyBtn) {
      copyToClipboard(copyBtn.dataset.copy);
      return;
    }
    const refreshBtn = e.target.closest("[data-refresh-invite]");
    if (refreshBtn) {
      refreshGroupInvite(refreshBtn.dataset.refreshInvite);
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

  $("modal-group-cancel").addEventListener("click", () => { state.pendingGroupVerify = null; closeModals(); });
  $("modal-group-accept").addEventListener("change", (e) => {
    $("modal-group-confirm-btn").disabled = !e.target.checked;
  });
  $("modal-group-confirm-btn").addEventListener("click", confirmGroupVerify);

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
  if (MOCK) {
    hide($("login-overlay"));
    show($("app"));
    show($("mock-banner"));
    init();
    return;
  }
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
