// ═══════════════════════════════════════════════════════════════════════════
// admin/envios — Dispatch History Dashboard
// ═══════════════════════════════════════════════════════════════════════════
//
// Uses:
//   window.SUPABASE_CONFIG (from /js/config.js) — { url, anonKey }
//   window.supabase        (UMD client from @supabase/supabase-js@2)
//   window.Chart           (Chart.js v4)
//
// All data access via PostgreSQL RPCs that enforce is_dashboard_admin().
// Non-admin user gets 403 (PostgREST surfaces as error.code === '42501').
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

// ─── State ────────────────────────────────────────────────────────────
const state = {
  filters: {},
  page: 1,
  pageSize: 50,
  totalCount: 0,
  rows: [],
  trendChart: null,
  funnelChart: null,
  currentDispatch: null, // { source, dispatch_id, status, ... }
  retryToken: null,
  retryExpiresAt: null,
};

// ─── Labels ───────────────────────────────────────────────────────────
const TYPE_LABELS = {
  class_reminder: { icon: "🔔", text: "Lembrete pré-aula", sub: "auto" },
  ps_rsvp: { icon: "📋", text: "Pré PS RSVP", sub: "auto" },
  nps: { icon: "⭐", text: "NPS pós-aula", sub: "auto" },
  survey: { icon: "📝", text: "Survey/Formulário", sub: "manual" },
  mentor_individual: { icon: "👤", text: "Aviso mentor", sub: "manual" },
  group_announcement: { icon: "📢", text: "Anúncio grupo", sub: "manual" },
  custom: { icon: "✍️", text: "Mensagem livre", sub: "manual" },
};

const STATUS_LABELS = {
  pending: { icon: "⏳", text: "Pendente/Agendado", color: "#fbbf24" },
  sent: { icon: "✅", text: "Enviado", color: "#4ade80" },
  delivered: { icon: "📬", text: "Entregue", color: "#22d3ee" },
  read: { icon: "👁", text: "Lido", color: "#a5b4fc" },
  responded: { icon: "💬", text: "Respondido", color: "#a78bfa" },
  failed: { icon: "❌", text: "Falhou", color: "#f87171" },
  cancelled: { icon: "🚫", text: "Cancelado", color: "#666" },
  skipped: { icon: "⏭", text: "Pulado", color: "#666" },
};

function typeLabel(t) {
  const l = TYPE_LABELS[t];
  return l ? `${l.icon} ${l.text} <span class="muted small">(${l.sub})</span>` : (t ?? "—");
}

function statusLabel(s) {
  const l = STATUS_LABELS[s];
  return l ? `${l.icon} ${l.text}` : (s ?? "—");
}

// ─── Helpers ──────────────────────────────────────────────────────────
function fmtDate(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleString("pt-BR", {
    day: "2-digit", month: "2-digit", year: "2-digit",
    hour: "2-digit", minute: "2-digit",
  });
}

function fmtUSD(n) {
  if (n == null) return "—";
  return `$${Number(n).toFixed(4)}`;
}

function escapeHtml(s) {
  if (s == null) return "";
  return String(s)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

function defaultDateRange() {
  const to = new Date();
  const from = new Date();
  from.setDate(from.getDate() - 7);
  return { from: from.toISOString(), to: to.toISOString() };
}

function buildFiltersFromUI() {
  const from = $("filter-date-from").value;
  const to = $("filter-date-to").value;
  const channels = Array.from(document.querySelectorAll('#filter-channels .chip.active'))
    .map(b => b.dataset.value);
  const statuses = Array.from(document.querySelectorAll('#filter-statuses .chip.active'))
    .map(b => b.dataset.value);
  const dispatch_types = Array.from(document.querySelectorAll('#filter-dispatch-types .chip.active'))
    .map(b => b.dataset.value);
  const student = $("filter-student-search").value.trim();
  const tpl = $("filter-template-name").value.trim();

  const filters = {};
  if (from) filters.date_from = `${from}T00:00:00Z`;
  if (to)   filters.date_to   = `${to}T23:59:59Z`;
  if (channels.length)        filters.channels = channels;
  if (statuses.length)        filters.statuses = statuses;
  if (dispatch_types.length)  filters.dispatch_types = dispatch_types;
  if (student) filters.student_search = student;
  if (tpl)     filters.template_name = tpl;
  return filters;
}

function renderActiveFilters() {
  const target = $("active-filters");
  target.innerHTML = "";
  const f = state.filters;
  const add = (label) => {
    const span = document.createElement("span");
    span.className = "active-filter-chip";
    span.textContent = label;
    target.appendChild(span);
  };
  if (f.date_from || f.date_to) {
    add(`📅 ${f.date_from?.slice(0,10) ?? "..."} → ${f.date_to?.slice(0,10) ?? "..."}`);
  }
  (f.channels ?? []).forEach((c) => add(`📡 ${c}`));
  (f.statuses ?? []).forEach((s) => add(`● ${s}`));
  (f.dispatch_types ?? []).forEach((t) => {
    const l = TYPE_LABELS[t];
    add(l ? `${l.icon} ${l.text}` : `🏷 ${t}`);
  });
  if (f.student_search) add(`👤 ${f.student_search}`);
  if (f.template_name)  add(`📝 ${f.template_name}`);
}

// ─── Auth ─────────────────────────────────────────────────────────────
async function checkAuthAndLoad() {
  const { data: { session } } = await sb.auth.getSession();
  if (session) {
    hide($("login-overlay"));
    show($("app"));
    await loadAll();
  }
}

async function doLogin() {
  const btn = $("login-btn");
  const errEl = $("login-error");
  hide(errEl);
  btn.disabled = true;
  const { error } = await sb.auth.signInWithPassword({
    email: $("login-email").value.trim(),
    password: $("login-password").value,
  });
  if (error) {
    errEl.textContent = "Email ou senha incorretos";
    show(errEl);
    btn.disabled = false;
    return;
  }
  hide($("login-overlay"));
  show($("app"));
  btn.disabled = false;
  await loadAll();
}

async function doLogout() {
  await sb.auth.signOut();
  location.reload();
}

// ─── Load all dashboard data ──────────────────────────────────────────
async function loadAll() {
  if (Object.keys(state.filters).length === 0) {
    const dr = defaultDateRange();
    state.filters = { date_from: dr.from, date_to: dr.to };
    const fromDate = dr.from.slice(0, 10);
    const toDate = dr.to.slice(0, 10);
    $("filter-date-from").value = fromDate;
    $("filter-date-to").value = toDate;
  }
  renderActiveFilters();

  const [kpisErr] = await Promise.all([
    loadKpis(),
    loadTrend(),
    loadFunnel(),
    loadTopClasses(),
    loadFailures(),
    loadChannelBreakdown(),
    loadDispatchTable(),
  ]);

  if (kpisErr === "forbidden") {
    hide($("kpi-grid"));
    show($("forbidden"));
  }
}

// ─── KPIs ─────────────────────────────────────────────────────────────
async function loadKpis() {
  const { data, error } = await sb.rpc("dispatch_summary_kpis", { p_filters: state.filters });
  if (error) {
    if (error.code === "42501" || /forbidden/i.test(error.message)) {
      console.warn("forbidden — not admin");
      return "forbidden";
    }
    console.error("kpis error", error);
    return;
  }
  const row = data?.[0] ?? {};
  $("kpi-grid").querySelector('[data-kpi="total_sent"] .kpi-value').textContent = row.total_sent ?? 0;
  $("kpi-grid").querySelector('[data-kpi="delivered_pct"] .kpi-value').textContent = (row.delivered_pct ?? 0) + "%";
  $("kpi-grid").querySelector('[data-kpi="read_pct"] .kpi-value').textContent = (row.read_pct ?? 0) + "%";
  $("kpi-grid").querySelector('[data-kpi="total_cost_usd"] .kpi-value').textContent = fmtUSD(row.total_cost_usd);
}

// ─── Trend chart ──────────────────────────────────────────────────────
async function loadTrend() {
  const { data, error } = await sb.rpc("dispatch_trend_daily", { p_filters: state.filters, p_days: 30 });
  if (error) { console.error("trend error", error); return; }
  const labels = (data ?? []).map(r => r.day);
  const sent = (data ?? []).map(r => Number(r.total_sent ?? 0));
  const delivered = (data ?? []).map(r => Number(r.total_delivered ?? 0));
  const failed = (data ?? []).map(r => Number(r.total_failed ?? 0));
  const cost = (data ?? []).map(r => Number(r.total_cost_usd ?? 0));

  const ctx = $("trend-chart");
  if (state.trendChart) state.trendChart.destroy();
  state.trendChart = new Chart(ctx, {
    type: "line",
    data: {
      labels,
      datasets: [
        { label: "Envios", data: sent, borderColor: "#6366f1", backgroundColor: "rgba(99,102,241,0.15)", tension: 0.3, fill: true },
        { label: "Entregues", data: delivered, borderColor: "#10b981", tension: 0.3 },
        { label: "Falhas", data: failed, borderColor: "#ef4444", tension: 0.3 },
        { label: "Custo USD", data: cost, borderColor: "#fbbf24", yAxisID: "y1", tension: 0.3 },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      interaction: { mode: "index", intersect: false },
      plugins: { legend: { labels: { color: "#aaa", font: { size: 11 } } } },
      scales: {
        x: { ticks: { color: "#666", font: { size: 10 } }, grid: { color: "#1a1a1a" } },
        y: { ticks: { color: "#666", font: { size: 10 } }, grid: { color: "#1a1a1a" } },
        y1: { position: "right", ticks: { color: "#fbbf24", font: { size: 10 } }, grid: { display: false } },
      },
    },
  });
}

// ─── Funnel chart ─────────────────────────────────────────────────────
async function loadFunnel() {
  const { data, error } = await sb.rpc("dispatch_funnel", { p_filters: state.filters });
  if (error) { console.error("funnel error", error); return; }
  const labels = (data ?? []).map(r => ({
    sent: "Enviado", delivered: "Entregue", read: "Lido", opened: "Aberto", responded: "Respondeu"
  }[r.stage] ?? r.stage));
  const counts = (data ?? []).map(r => Number(r.count ?? 0));
  const pcts = (data ?? []).map(r => Number(r.pct_of_sent ?? 0));

  const ctx = $("funnel-chart");
  if (state.funnelChart) state.funnelChart.destroy();
  state.funnelChart = new Chart(ctx, {
    type: "bar",
    data: {
      labels,
      datasets: [{
        label: "Quantidade",
        data: counts,
        backgroundColor: ["#6366f1", "#10b981", "#22c55e", "#fbbf24", "#a855f7"],
      }],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      indexAxis: "y",
      plugins: {
        legend: { display: false },
        tooltip: {
          callbacks: {
            label: (ctx) => `${ctx.parsed.x} (${pcts[ctx.dataIndex]}% do enviado)`,
          },
        },
      },
      scales: {
        x: { ticks: { color: "#666", font: { size: 10 } }, grid: { color: "#1a1a1a" } },
        y: { ticks: { color: "#aaa", font: { size: 11 } }, grid: { display: false } },
      },
    },
  });
}

// ─── Top classes ──────────────────────────────────────────────────────
async function loadTopClasses() {
  const { data, error } = await sb.rpc("dispatch_top_classes", { p_filters: state.filters, p_limit: 5 });
  if (error) { console.error("top_classes error", error); return; }
  const tbody = $("top-classes-table").querySelector("tbody");
  if (!data?.length) { tbody.innerHTML = '<tr><td class="muted">Sem dados</td></tr>'; return; }
  tbody.innerHTML = data.map(r => `
    <tr>
      <td>${escapeHtml(r.class_title ?? "?")}</td>
      <td>${r.total_sent}</td>
    </tr>`).join("");
}

async function loadFailures() {
  const { data, error } = await sb.rpc("dispatch_recent_failures", { p_hours: 24, p_limit: 20 });
  if (error) { console.error("failures error", error); return; }
  const tbody = $("failures-table").querySelector("tbody");
  if (!data?.length) { tbody.innerHTML = '<tr><td class="muted">Nenhuma falha últimas 24h ✓</td></tr>'; return; }
  tbody.innerHTML = data.map(r => `
    <tr>
      <td>${escapeHtml(r.recipient_label ?? "—")}</td>
      <td>${escapeHtml(r.channel ?? "—")}</td>
    </tr>`).join("");
}

async function loadChannelBreakdown() {
  const { data, error } = await sb.rpc("dispatch_channel_breakdown", { p_filters: state.filters });
  if (error) { console.error("channel error", error); return; }
  const tbody = $("channel-breakdown-table").querySelector("tbody");
  if (!data?.length) { tbody.innerHTML = '<tr><td class="muted">Sem dados</td></tr>'; return; }
  tbody.innerHTML = data.map(r => `
    <tr>
      <td>${escapeHtml(r.channel ?? "?")}</td>
      <td>${r.total} (${r.failed} falhas)</td>
    </tr>`).join("");
}

// ─── Dispatch table ───────────────────────────────────────────────────
async function loadDispatchTable() {
  const { data, error } = await sb.rpc("list_dispatch_history", {
    p_filters: state.filters,
    p_page: state.page,
    p_size: state.pageSize,
  });
  if (error) { console.error("list error", error); return; }
  state.rows = data ?? [];
  state.totalCount = state.rows[0]?.total_count ?? 0;
  renderDispatchTable();
  renderPagination();
}

function shortId(id) {
  if (!id) return "";
  return String(id).replace(/-/g, "").slice(0, 8);
}

function formLabel(r) {
  // Map row to "qual formulário" string + form ID (when applicable).
  const meta = r.metadata || {};
  if (r.source === "survey_link") {
    const name = meta.survey_name || "Survey";
    const id = meta.survey_id || r.metadata?.survey_id;
    return { text: name, idLabel: "Forms", id };
  }
  if (r.source === "nps_class_link") {
    const id = meta.dispatch_job_id;
    const mode = meta.mode === "group" ? "Grupo" : "DM";
    return { text: `NPS pós-aula (${mode})`, idLabel: "Disparo", id };
  }
  if (r.source === "class_reminder") {
    const t = meta.reminder_type;
    const labels = { "60min": "Lembrete 60min", "15min": "Lembrete 15min", "now": "Lembrete na hora" };
    return { text: labels[t] || "Lembrete pré-aula", idLabel: "Batch", id: meta.batch_id };
  }
  if (r.source === "ps_rsvp_link") {
    return { text: "Pré PS RSVP", idLabel: "Disparo", id: meta.dispatch_id || r.dispatch_id };
  }
  if (r.source === "notification") {
    return { text: r.template_name || r.dispatch_type || "Notificação", idLabel: "Tmpl", id: r.template_name };
  }
  return { text: r.template_name || r.dispatch_type || "—", idLabel: "", id: null };
}

function classLabel(r) {
  const parts = [];
  if (r.class_title) parts.push(escapeHtml(r.class_title));
  if (r.cohort_name) parts.push(`<span class="muted small">${escapeHtml(r.cohort_name)}</span>`);
  return parts.length ? parts.join("<br>") : '<span class="muted">—</span>';
}

function formCell(r) {
  const f = formLabel(r);
  const txt = escapeHtml(f.text);
  if (!f.id) return txt;
  const sid = shortId(f.id);
  const fullId = escapeHtml(String(f.id));
  return `${txt}<br><span class="muted small" title="${escapeHtml(f.idLabel)} ID: ${fullId}" style="cursor:copy" data-copy="${fullId}">🆔 ${escapeHtml(f.idLabel)}: ${escapeHtml(sid)}</span>`;
}

function renderDispatchTable() {
  const tbody = $("envios-tbody");
  $("envios-count").textContent = `(${state.totalCount} total)`;
  if (!state.rows.length) {
    tbody.innerHTML = '<tr><td colspan="8" class="muted center">Nenhum envio com os filtros atuais</td></tr>';
    return;
  }
  tbody.innerHTML = state.rows.map(r => {
    const recipient = r.student_name ?? r.recipient_identifier ?? "—";
    const dispatchSid = shortId(r.dispatch_id);
    return `
    <tr data-source="${escapeHtml(r.source)}" data-id="${escapeHtml(r.dispatch_id)}">
      <td>${fmtDate(r.sent_at)}<br><span class="muted small" title="Envio ID: ${escapeHtml(r.dispatch_id)}" style="cursor:copy" data-copy="${escapeHtml(r.dispatch_id)}">🆔 ${escapeHtml(dispatchSid)}</span></td>
      <td><span class="channel-pill ${escapeHtml(r.channel)}">${escapeHtml(r.channel)}</span></td>
      <td>${escapeHtml(recipient)}</td>
      <td>${typeLabel(r.dispatch_type)}</td>
      <td>${classLabel(r)}</td>
      <td>${formCell(r)}</td>
      <td class="row-link" data-source="${escapeHtml(r.source)}" data-id="${escapeHtml(r.dispatch_id)}"><span class="muted small">—</span></td>
      <td><span class="status-pill status-${escapeHtml(r.status)}">${statusLabel(r.status)}</span></td>
      <td class="right">${r.cost_usd > 0 ? fmtUSD(r.cost_usd) : "—"}</td>
    </tr>`;
  }).join("");
  hydrateLinkColumn(state.rows);
  tbody.querySelectorAll("tr").forEach(tr => {
    tr.addEventListener("click", (e) => {
      // Copy on small-ID click; otherwise open modal
      const copyEl = e.target.closest("[data-copy]");
      if (copyEl) {
        e.stopPropagation();
        navigator.clipboard?.writeText(copyEl.dataset.copy);
        const original = copyEl.textContent;
        copyEl.textContent = "✓ copiado";
        setTimeout(() => { copyEl.textContent = original; }, 1500);
        return;
      }
      openDispatchModal(tr.dataset.source, tr.dataset.id);
    });
  });
}

// JIT batch fetch tokens pra coluna "Link" (1 query por source)
async function hydrateLinkColumn(rows) {
  const psIds = rows.filter(r => r.source === "ps_rsvp_link").map(r => r.dispatch_id);
  const npsIds = rows.filter(r => r.source === "nps_class_link").map(r => r.dispatch_id);

  const tokenMap = new Map();
  if (psIds.length > 0) {
    const { data } = await sb.from("ps_rsvp_links").select("id, token").in("id", psIds);
    (data ?? []).forEach(d => tokenMap.set("ps_rsvp_link:" + d.id, "https://painel.academialendaria.ai/ps-rsvp/?token=" + d.token));
  }
  if (npsIds.length > 0) {
    const { data } = await sb.from("nps_class_links").select("id, token").in("id", npsIds);
    (data ?? []).forEach(d => tokenMap.set("nps_class_link:" + d.id, "https://painel.academialendaria.ai/survey/?token=" + d.token));
  }

  document.querySelectorAll("td.row-link").forEach(td => {
    const key = td.dataset.source + ":" + td.dataset.id;
    const url = tokenMap.get(key);
    if (!url) { td.innerHTML = '<span class="muted small">—</span>'; return; }
    td.innerHTML = `<a href="${url}" target="_blank" rel="noopener" style="word-break:break-all;font-size:11px" title="${url}">🔗 ${url.slice(0, 50)}…</a>`;
  });
}

function renderPagination() {
  const totalPages = Math.max(1, Math.ceil(state.totalCount / state.pageSize));
  const c = $("pagination-controls");
  c.innerHTML = `
    <button id="pg-prev" ${state.page <= 1 ? "disabled" : ""}>‹ Anterior</button>
    <span class="page-info">Pg ${state.page} de ${totalPages}</span>
    <button id="pg-next" ${state.page >= totalPages ? "disabled" : ""}>Próxima ›</button>`;
  $("pg-prev").onclick = () => { state.page = Math.max(1, state.page - 1); loadDispatchTable(); };
  $("pg-next").onclick = () => { state.page = Math.min(totalPages, state.page + 1); loadDispatchTable(); };
}

// ─── Dispatch modal (drilldown) ───────────────────────────────────────
async function openDispatchModal(source, dispatchId) {
  const row = state.rows.find(r => r.source === source && r.dispatch_id === dispatchId);
  if (!row) return;
  state.currentDispatch = row;

  const tL = TYPE_LABELS[row.dispatch_type];
  $("dm-title").textContent = `${tL ? tL.icon + " " + tL.text : row.dispatch_type ?? "envio"} · ${row.channel}`;
  show($("dispatch-modal-backdrop"));
  show($("dispatch-modal"));

  // Render timeline
  const tl = $("dm-timeline");
  tl.innerHTML = [
    { label: "Enviado", ts: row.sent_at, active: !!row.sent_at },
    { label: "Entregue", ts: row.delivered_at, active: !!row.delivered_at },
    { label: "Lido", ts: row.read_at, active: !!row.read_at },
    { label: "Link aberto", ts: row.last_opened_at, active: row.open_count > 0 },
    { label: "Respondeu", ts: row.response_count > 0 ? "✓" : null, active: row.response_count > 0 },
  ].map(e => `
    <li class="timeline-entry ${e.active ? "active" : ""}">
      ${escapeHtml(e.label)}${e.ts && e.ts !== "✓" ? `<span class="ts">${fmtDate(e.ts)}</span>` : (e.ts === "✓" ? " ✓" : "")}
    </li>`).join("");

  // Render metadata
  const meta = $("dm-metadata").querySelector("tbody");
  meta.innerHTML = `
    <tr><td>Source</td><td>${escapeHtml(row.source)}</td></tr>
    <tr><td>Dispatch ID</td><td>${escapeHtml(row.dispatch_id)}</td></tr>
    <tr><td>Status</td><td>${escapeHtml(row.status)}</td></tr>
    <tr><td>Template</td><td>${escapeHtml(row.template_name ?? "—")}</td></tr>
    <tr><td>Categoria</td><td>${escapeHtml(row.template_category ?? "—")}</td></tr>
    <tr><td>Custo</td><td>${row.cost_usd > 0 ? fmtUSD(row.cost_usd) : "—"}</td></tr>
    <tr><td>Provider msg ID</td><td>${escapeHtml(row.recipient_identifier ?? "—")}</td></tr>
    <tr><td>Erro</td><td>${escapeHtml(row.error_detail ?? "—")}</td></tr>
    <tr><td>Aberturas</td><td>${row.open_count ?? 0}</td></tr>
    <tr><td>Respostas</td><td>${row.response_count ?? 0}</td></tr>
    <tr id="dm-link-row"><td>Link</td><td class="muted small">carregando…</td></tr>
  `;

  // JIT: buscar token via ps_rsvp_links/nps_class_links pra renderizar URL clicável
  (async () => {
    let url = null;
    try {
      if (row.source === "ps_rsvp_link") {
        const { data } = await sb.from("ps_rsvp_links").select("token").eq("id", row.dispatch_id).maybeSingle();
        if (data?.token) url = `https://painel.academialendaria.ai/ps-rsvp/?token=${data.token}`;
      } else if (row.source === "nps_class_link") {
        const { data } = await sb.from("nps_class_links").select("token").eq("id", row.dispatch_id).maybeSingle();
        if (data?.token) url = `https://painel.academialendaria.ai/survey/?token=${data.token}`;
      }
    } catch (e) { /* ignora, mantém — */ }
    const cell = document.querySelector("#dm-link-row td:last-child");
    if (!cell) return;
    if (url) {
      cell.innerHTML = `<a href="${url}" target="_blank" style="word-break:break-all" data-copy="${url}">${escapeHtml(url)}</a> <button class="btn-icon" data-copy-btn="${url}" title="Copiar">📋</button>`;
    } else {
      cell.textContent = "—";
      cell.className = "muted small";
    }
  })();

  // Render preview (JIT via RPC)
  const previewEl = $("dm-preview");
  previewEl.innerHTML = '<p class="muted small center">Carregando preview…</p>';
  const { data: previewData, error: previewErr } = await sb.rpc("render_message_preview", {
    p_source: row.source, p_dispatch_id: row.dispatch_id,
  });
  if (previewErr || !previewData || previewData.error) {
    // Fall back to inline rendered_message from VIEW
    const msg = row.rendered_message ?? "(sem preview disponível)";
    previewEl.innerHTML = renderWhatsappBubble(msg, row.sent_at, row.delivered_at, row.read_at);
  } else {
    const msg = previewData.message ?? row.rendered_message ?? "(sem preview)";
    previewEl.innerHTML = renderWhatsappBubble(msg, row.sent_at, row.delivered_at, row.read_at);
  }

  // Retry button state
  const retryBtn = $("dm-retry-btn");
  const retryHint = $("dm-retry-hint");
  if (row.status === "failed") {
    retryBtn.disabled = false;
    retryHint.textContent = "Reenviar este envio falhado. Você confirmará antes de enviar.";
  } else {
    retryBtn.disabled = true;
    retryHint.textContent = "Reenvio só permitido pra envios com status=failed.";
  }
}

function renderWhatsappBubble(message, sent, delivered, read) {
  const time = sent ? new Date(sent).toLocaleTimeString("pt-BR", { hour: "2-digit", minute: "2-digit" }) : "";
  const check = read ? '<span class="bubble-check">✓✓</span>' : (delivered ? '<span class="bubble-check">✓✓</span>' : (sent ? '<span class="bubble-check">✓</span>' : ""));
  return `
    <div class="whatsapp-bubble">${escapeHtml(message)}<span class="bubble-time">${time}${check}</span></div>
  `;
}

function closeDispatchModal() {
  hide($("dispatch-modal"));
  hide($("dispatch-modal-backdrop"));
  state.currentDispatch = null;
}

// ─── Retry flow ───────────────────────────────────────────────────────
async function startRetry() {
  const row = state.currentDispatch;
  if (!row || row.status !== "failed") return;

  const { data, error } = await sb.rpc("get_retry_confirm_token", {
    p_source: row.source, p_dispatch_id: row.dispatch_id,
  });
  if (error) {
    alert("Erro ao gerar token: " + error.message);
    return;
  }
  const tokenRow = data?.[0];
  if (!tokenRow?.token) {
    alert("Sem token retornado.");
    return;
  }
  state.retryToken = tokenRow.token;
  state.retryExpiresAt = tokenRow.expires_at;

  // Populate confirm modal
  const recipientLabel = row.student_name ?? row.recipient_identifier ?? "—";
  $("rc-recipient").textContent = recipientLabel;
  $("rc-message").textContent = row.rendered_message ?? "(sem texto)";
  $("rc-expires").textContent = fmtDate(tokenRow.expires_at);

  show($("retry-confirm-modal"));
}

async function confirmRetry() {
  const row = state.currentDispatch;
  if (!row || !state.retryToken) return;

  const btn = $("rc-confirm");
  btn.disabled = true;
  btn.textContent = "Reenviando…";

  const { data, error } = await sb.rpc("retry_dispatch", {
    p_source: row.source,
    p_dispatch_id: row.dispatch_id,
    p_confirm_token: state.retryToken,
  });

  btn.disabled = false;
  btn.textContent = "Sim, reenviar";

  if (error) {
    alert("Falha no reenvio: " + error.message);
    return;
  }
  hide($("retry-confirm-modal"));
  state.retryToken = null;
  alert(data?.success ? "Reenvio enfileirado. Status atualiza em alguns segundos." : "Sem confirmação: " + JSON.stringify(data));
  closeDispatchModal();
  setTimeout(() => loadAll(), 4000);
}

// ─── CSV export ───────────────────────────────────────────────────────
async function exportCsv() {
  const totalToFetch = Math.min(state.totalCount, 5000);
  if (state.totalCount > 5000) {
    if (!confirm(`${state.totalCount} envios — export limitado a 5000. Continuar?`)) return;
  }

  const all = [];
  const pageSize = 200;
  const totalPages = Math.ceil(totalToFetch / pageSize);
  for (let p = 1; p <= totalPages; p++) {
    const { data, error } = await sb.rpc("list_dispatch_history", {
      p_filters: state.filters, p_page: p, p_size: pageSize,
    });
    if (error) { alert("Erro export: " + error.message); return; }
    all.push(...(data ?? []));
    if (all.length >= totalToFetch) break;
  }

  const cols = [
    ["dispatch_id", "Envio ID"],
    ["source", "Source"],
    ["sent_at", "Data"],
    ["channel", "Canal"],
    ["student_name", "Aluno"],
    ["recipient_identifier", "Destinatário"],
    ["dispatch_type", "Tipo"],
    ["class_title", "Aula"],
    ["cohort_name", "Turma"],
    ["template_name", "Template"],
    ["status", "Status"],
    ["cost_usd", "Custo USD"],
    ["open_count", "Aberturas"],
    ["response_count", "Respostas"],
    ["error_detail", "Erro"],
  ];

  const header = cols.map(c => csvEscape(c[1])).join(",");
  const lines = all.map(row => cols.map(c => csvEscape(row[c[0]])).join(","));
  const csv = [header, ...lines].join("\n");

  const blob = new Blob([csv], { type: "text/csv;charset=utf-8" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  const dateTag = (state.filters.date_from ?? "").slice(0, 10);
  a.download = `envios-${dateTag}.csv`;
  a.click();
  URL.revokeObjectURL(url);
}

function csvEscape(v) {
  if (v == null) return "";
  const s = String(v);
  if (/[",\n]/.test(s)) return `"${s.replace(/"/g, '""')}"`;
  return s;
}

// ─── Wire up events ───────────────────────────────────────────────────
function wire() {
  $("login-btn").addEventListener("click", doLogin);
  $("logout-btn").addEventListener("click", doLogout);

  document.querySelectorAll("#login-email, #login-password").forEach(el => {
    el.addEventListener("keypress", (e) => { if (e.key === "Enter") doLogin(); });
  });

  $("refresh-btn").addEventListener("click", () => loadAll());

  // Filter drawer
  $("filter-toggle").addEventListener("click", () => {
    show($("drawer-backdrop"));
    show($("filters-drawer"));
  });
  $("filter-close").addEventListener("click", closeDrawer);
  $("drawer-backdrop").addEventListener("click", closeDrawer);

  function closeDrawer() {
    hide($("filters-drawer"));
    hide($("drawer-backdrop"));
  }

  document.querySelectorAll(".chip.toggle").forEach(b => {
    b.addEventListener("click", () => b.classList.toggle("active"));
  });

  document.querySelectorAll(".chip.preset").forEach(b => {
    b.addEventListener("click", () => {
      const days = parseInt(b.dataset.preset, 10);
      const to = new Date();
      const from = new Date();
      from.setDate(from.getDate() - days);
      $("filter-date-from").value = from.toISOString().slice(0, 10);
      $("filter-date-to").value = to.toISOString().slice(0, 10);
    });
  });

  $("filter-apply").addEventListener("click", () => {
    state.filters = buildFiltersFromUI();
    state.page = 1;
    closeDrawer();
    loadAll();
  });

  $("filter-clear").addEventListener("click", () => {
    document.querySelectorAll(".chip.toggle").forEach(c => c.classList.remove("active"));
    $("filter-student-search").value = "";
    $("filter-template-name").value = "";
    const dr = defaultDateRange();
    $("filter-date-from").value = dr.from.slice(0, 10);
    $("filter-date-to").value = dr.to.slice(0, 10);
  });

  // Dispatch modal
  $("dm-close").addEventListener("click", closeDispatchModal);
  $("dispatch-modal-backdrop").addEventListener("click", closeDispatchModal);
  $("dm-retry-btn").addEventListener("click", startRetry);

  // Retry confirm modal
  $("rc-cancel").addEventListener("click", () => {
    hide($("retry-confirm-modal"));
    state.retryToken = null;
  });
  $("rc-confirm").addEventListener("click", confirmRetry);

  // Export
  $("export-csv-btn").addEventListener("click", exportCsv);
}

// ─── Bootstrap ────────────────────────────────────────────────────────
wire();
checkAuthAndLoad();
