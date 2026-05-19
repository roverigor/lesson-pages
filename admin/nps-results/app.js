// ═══════════════════════════════════════════════════════════════════════════
// admin/nps-results — NPS Results Dashboard (P.3)
// Multi-stakeholder consumer: profs, CS, equipe educacional
// ═══════════════════════════════════════════════════════════════════════════

const SUPABASE_URL = window.SUPABASE_CONFIG?.url;
const SUPABASE_ANON_KEY = window.SUPABASE_CONFIG?.anonKey;
const MOCK = new URLSearchParams(location.search).get("mock") === "1";

const sb = !MOCK && window.supabase
  ? window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
      auth: { persistSession: true, autoRefreshToken: true },
    })
  : null;

const $ = (id) => document.getElementById(id);
const show = (el) => el.classList.remove("hidden");
const hide = (el) => el.classList.add("hidden");

const state = {
  filters: {},
  bucket: "",
  onlyWithComment: true,
  summary: null,
  trend: [],
  cohortBreak: [],
  classBreak: [],
  comments: [],
  filterOpts: { cohorts: [], classes: [] },
  trendChart: null,
};

function escapeHtml(s) {
  if (s == null) return "";
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function fmtDateTime(iso) {
  if (!iso) return "—";
  return new Date(iso).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
}

function fmtDate(iso) {
  if (!iso) return "—";
  return new Date(iso).toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" });
}

function toast(msg, kind = "info") {
  const el = document.createElement("div");
  el.className = `toast ${kind}`;
  el.textContent = msg;
  $("toast-container").appendChild(el);
  setTimeout(() => el.remove(), 4000);
}

async function rpc(name, args = {}) {
  if (MOCK) return mockRpc(name, args);
  const { data, error } = await sb.rpc(name, args);
  if (error) throw error;
  return data;
}

async function ensureAdmin() {
  if (MOCK) return true;
  const { data: { session } } = await sb.auth.getSession();
  if (!session) return null;
  const role = session.user?.user_metadata?.role;
  return role === "admin";
}

async function login() {
  const email = $("login-email").value.trim();
  const password = $("login-password").value;
  if (!email || !password) { showLoginError("Preencha email e senha."); return; }
  try {
    const { error } = await sb.auth.signInWithPassword({ email, password });
    if (error) throw error;
    const ok = await ensureAdmin();
    if (!ok) { showLoginError("Sem permissão de admin."); await sb.auth.signOut(); return; }
    enterApp();
  } catch (e) { showLoginError(e?.message ?? "Erro."); }
}

function showLoginError(m) { const el = $("login-error"); el.textContent = m; show(el); }
function enterApp() { hide($("login-overlay")); show($("app")); init(); }

async function logout() {
  if (!MOCK) await sb.auth.signOut();
  location.reload();
}

// ─── Init ─────────────────────────────────────────────────────────────
async function init() {
  // default date range: last 90 days
  const today = new Date();
  const since = new Date(today); since.setDate(since.getDate() - 90);
  $("filter-date-from").value = since.toISOString().slice(0, 10);
  $("filter-date-to").value = today.toISOString().slice(0, 10);

  try {
    const opts = await rpc("nps_results_filter_options");
    state.filterOpts = opts ?? { cohorts: [], classes: [] };
    populateFilters();
  } catch (e) {
    showError(`Erro carregando filtros: ${e?.message ?? e}`);
  }

  state.filters = readFilters();
  await refreshAll();
}

function readFilters() {
  const from = $("filter-date-from").value;
  const to = $("filter-date-to").value;
  const cohort = $("filter-cohort").value || null;
  const klass = $("filter-class").value || null;
  const mode = $("filter-mode").value || null;
  const source = $("filter-source")?.value || null;
  const surveyRaw = $("filter-survey")?.value || null;
  const f = {};
  if (from) f.date_from = new Date(from + "T00:00:00").toISOString();
  if (to) {
    const toEnd = new Date(to + "T00:00:00");
    toEnd.setDate(toEnd.getDate() + 1);
    f.date_to = toEnd.toISOString();
  }
  if (cohort) f.cohort_id = cohort;
  if (klass) f.class_id = klass;
  if (mode) f.mode = mode;
  if (source) f.source = source;
  // surveyRaw may be either:
  //   - real survey UUID (legacy "manual_survey" type)
  //   - synthetic "session:{class_id}:{YYYY-MM-DD}" representing a NPS post-class session
  if (surveyRaw) {
    if (surveyRaw.startsWith("session:")) {
      const [, classId, dateStr] = surveyRaw.split(":");
      if (classId) f.class_id = classId;
      if (dateStr) {
        const d0 = new Date(dateStr + "T00:00:00").toISOString();
        const d1 = new Date(dateStr + "T00:00:00");
        d1.setDate(d1.getDate() + 1);
        f.date_from = d0;
        f.date_to = d1.toISOString();
      }
      f.source = "auto_class";
    } else {
      f.survey_id = surveyRaw;
      f.source = "manual_survey";
    }
  }
  return f;
}

function populateFilters() {
  const sCohort = $("filter-cohort");
  const sClass = $("filter-class");
  const sSurvey = $("filter-survey");
  sCohort.innerHTML = '<option value="">— todos —</option>' + (state.filterOpts.cohorts ?? [])
    .map((c) => `<option value="${escapeHtml(c.id)}">${escapeHtml(c.name)}</option>`).join("");
  sClass.innerHTML = '<option value="">— todas —</option>' + (state.filterOpts.classes ?? [])
    .map((c) => `<option value="${escapeHtml(c.id)}">${escapeHtml(c.name)}</option>`).join("");
  if (sSurvey) {
    const surveyOpts = (state.filterOpts.surveys ?? [])
      .map((s) => `<option value="${escapeHtml(s.id)}">📋 ${escapeHtml(s.name)}</option>`).join("");
    const sessionOpts = (state.filterOpts.auto_sessions ?? [])
      .map((s) => `<option value="session:${escapeHtml(s.class_id)}:${escapeHtml(s.date)}">⚡ ${escapeHtml(s.label || (s.class_name + ' — ' + s.date))}</option>`).join("");
    sSurvey.innerHTML = '<option value="">— todos —</option>' +
      (surveyOpts ? `<optgroup label="Formulários manuais">${surveyOpts}</optgroup>` : '') +
      (sessionOpts ? `<optgroup label="NPS Pós-aula automático">${sessionOpts}</optgroup>` : '');
  }
}

async function refreshAll() {
  try {
    const [summary, trend, cohortBreak, classBreak, comments] = await Promise.all([
      rpc("nps_results_summary", { p_filters: state.filters }),
      rpc("nps_results_trend", { p_weeks: 12, p_filters: state.filters }),
      rpc("nps_results_by_cohort", { p_filters: state.filters }),
      rpc("nps_results_by_class", { p_filters: state.filters }),
      fetchComments(),
    ]);
    state.summary = summary;
    state.trend = trend || [];
    state.cohortBreak = cohortBreak || [];
    state.classBreak = classBreak || [];
    state.comments = comments || [];
    renderAll();
    hideError();
  } catch (e) {
    showError(`Erro: ${e?.message ?? e}`);
  }
}

async function fetchComments() {
  const f = { ...state.filters };
  if (state.bucket) f.bucket = state.bucket;
  if (state.onlyWithComment) f.only_with_comment = true;
  return await rpc("nps_results_comments", { p_filters: f, p_limit: 100 });
}

async function fetchAllResponses() {
  // Don't filter by bucket/comment — show all matching the global filters
  return await rpc("nps_results_comments", { p_filters: state.filters, p_limit: 1000 });
}

function renderAll() {
  renderHero();
  renderTrend();
  renderCohortBreak();
  renderClassBreak();
  renderComments();
  renderAllResponses();
}

async function renderAllResponses() {
  const tb = $("all-responses-body");
  if (!tb) return;
  try {
    const rows = await fetchAllResponses();
    if (!rows || rows.length === 0) {
      tb.innerHTML = `<tr><td colspan="8" style="padding:20px;color:#444;text-align:center">Nenhuma resposta com filtros atuais.</td></tr>`;
      return;
    }
    tb.innerHTML = rows.map((r) => {
      const when = r.submitted_at ? new Date(r.submitted_at).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", year: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—";
      const who = r.student_name || r.name_provided || "Anônimo";
      const bucketCol = r.bucket === "promoter" ? "#4ade80" : r.bucket === "passive" ? "#f59e0b" : "#f87171";
      const scoreCol = r.nps_score >= 9 ? "#4ade80" : r.nps_score >= 7 ? "#f59e0b" : "#f87171";
      return `<tr>
        <td style="font-size:11px;color:#666">${escapeHtml(when)}</td>
        <td>${escapeHtml(who)}</td>
        <td style="color:#888">${escapeHtml(r.cohort_name || "—")}</td>
        <td style="color:#888">${escapeHtml(r.class_name || "—")}</td>
        <td style="font-weight:700;color:${scoreCol}">${r.nps_score ?? "—"}</td>
        <td style="color:${bucketCol}">${escapeHtml(r.bucket || "—")}</td>
        <td style="color:#888;font-size:11px">${escapeHtml(r.mode || "—")}</td>
        <td style="font-size:12px;color:#ccc;max-width:380px">${escapeHtml(r.comment || "")}</td>
      </tr>`;
    }).join("");
  } catch (e) {
    tb.innerHTML = `<tr><td colspan="8" style="padding:20px;color:#f87171">Erro: ${escapeHtml(e?.message ?? String(e))}</td></tr>`;
  }
}

// ─── Hero NPS ────────────────────────────────────────────────────────
function renderHero() {
  const s = state.summary ?? {};
  $("hero-nps-value").textContent = s.nps_score == null ? "—" : s.nps_score;
  $("hero-avg").textContent = s.avg_score == null ? "—" : s.avg_score;
  $("hero-total").textContent = s.total ?? 0;

  const p = s.promoter_pct ?? 0;
  const ps = s.passive_pct ?? 0;
  const d = s.detractor_pct ?? 0;
  $("bar-promoter").style.width = `${p}%`;
  $("bar-passive").style.width = `${ps}%`;
  $("bar-detractor").style.width = `${d}%`;
  $("leg-promoter").textContent = s.promoters ?? 0;
  $("leg-passive").textContent = s.passives ?? 0;
  $("leg-detractor").textContent = s.detractors ?? 0;
  $("leg-promoter-pct").textContent = p;
  $("leg-passive-pct").textContent = ps;
  $("leg-detractor-pct").textContent = d;
}

// ─── Trend chart ─────────────────────────────────────────────────────
function renderTrend() {
  const ctx = $("trend-chart").getContext("2d");
  if (state.trendChart) state.trendChart.destroy();
  const labels = state.trend.map((r) => fmtDate(r.week_start));
  const npsData = state.trend.map((r) => r.nps);
  const totalData = state.trend.map((r) => r.total);

  state.trendChart = new Chart(ctx, {
    type: "line",
    data: {
      labels,
      datasets: [
        { label: "NPS", data: npsData, borderColor: "#4ade80", backgroundColor: "rgba(74,222,128,0.1)", tension: 0.3, yAxisID: "y" },
        { label: "Respostas (volume)", data: totalData, borderColor: "#888", borderDash: [4, 4], tension: 0.3, yAxisID: "y1" },
      ],
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      plugins: { legend: { labels: { color: "#aaa" } } },
      scales: {
        x: { ticks: { color: "#888" }, grid: { color: "#1e1e26" } },
        y: { ticks: { color: "#888" }, grid: { color: "#1e1e26" }, suggestedMin: -100, suggestedMax: 100, title: { display: true, text: "NPS", color: "#888" } },
        y1: { ticks: { color: "#666" }, grid: { display: false }, position: "right", title: { display: true, text: "Respostas", color: "#666" } },
      },
    },
  });
}

// ─── Breakdowns ──────────────────────────────────────────────────────
function renderCohortBreak() {
  const body = $("cohort-body");
  if (!state.cohortBreak.length) {
    body.innerHTML = `<tr><td colspan="5" class="loading">Sem dados.</td></tr>`;
    return;
  }
  body.innerHTML = state.cohortBreak.map((r) => `
    <tr>
      <td>${escapeHtml(r.cohort_name ?? "—")}</td>
      <td>${r.total}</td>
      <td><strong style="color:${npsColor(r.nps)}">${r.nps ?? "—"}</strong></td>
      <td>${r.avg_score ?? "—"}</td>
      <td style="color:${r.detractors > 0 ? "#f87171" : "#666"}">${r.detractors}</td>
    </tr>
  `).join("");
}

function renderClassBreak() {
  const body = $("class-body");
  if (!state.classBreak.length) {
    body.innerHTML = `<tr><td colspan="4" class="loading">Sem dados.</td></tr>`;
    return;
  }
  body.innerHTML = state.classBreak.map((r) => `
    <tr>
      <td>${escapeHtml(r.class_name ?? "—")}</td>
      <td>${r.total}</td>
      <td><strong style="color:${npsColor(r.nps)}">${r.nps ?? "—"}</strong></td>
      <td>${r.avg_score ?? "—"}</td>
    </tr>
  `).join("");
}

function npsColor(nps) {
  if (nps == null) return "#888";
  if (nps >= 70) return "#4ade80";
  if (nps >= 40) return "#fbbf24";
  return "#f87171";
}

// ─── Comments ────────────────────────────────────────────────────────
function renderComments() {
  const body = $("comments-list");
  if (!state.comments.length) {
    body.innerHTML = `<div class="loading">Sem comentários no filtro atual.</div>`;
    return;
  }
  body.innerHTML = state.comments.map((c) => {
    const sourceTag = c.source === "manual_survey"
      ? '<span style="color:#666;font-size:10px;background:#1a1a20;padding:1px 6px;border-radius:4px">📋 survey antigo</span>'
      : '<span style="color:#4ade80;font-size:10px;background:#07332a;padding:1px 6px;border-radius:4px">⚡ auto pós-aula</span>';
    return `
    <div class="comment-card ${c.bucket}">
      <div class="comment-header">
        <span><span class="comment-score">${c.nps_score}</span>/10 · ${escapeHtml(c.bucket)} ${sourceTag}</span>
        <span>${fmtDateTime(c.submitted_at)}</span>
      </div>
      ${c.comment ? `<div class="comment-body">${escapeHtml(c.comment)}</div>` : '<div class="comment-body" style="font-style:italic;color:#666">(sem comentário)</div>'}
      <div class="comment-meta">
        <span>${escapeHtml(c.cohort_name ?? "—")} · ${escapeHtml(c.class_name ?? "—")}</span>
        <span>${c.mode === "dm" ? `👤 ${escapeHtml(c.student_name ?? "—")} · ${escapeHtml(c.student_phone ?? "—")}` : `📢 grupo (${escapeHtml(c.name_provided ?? "anônimo")})`}</span>
      </div>
    </div>
  `;
  }).join("");
}

// ─── Export CSV ──────────────────────────────────────────────────────
async function exportCsv() {
  const f = { ...state.filters, bucket: "detractor", only_with_comment: false };
  try {
    const rows = await rpc("nps_results_comments", { p_filters: f, p_limit: 500 });
    if (!rows?.length) { toast("Sem detractors no filtro.", "info"); return; }
    const header = ["submitted_at","nps_score","mode","cohort","class","student_name","student_phone","name_provided","comment"];
    const lines = rows.map((r) => header.map((h) => {
      const val = {
        submitted_at: r.submitted_at, nps_score: r.nps_score, mode: r.mode,
        cohort: r.cohort_name, class: r.class_name,
        student_name: r.student_name, student_phone: r.student_phone,
        name_provided: r.name_provided, comment: r.comment,
      }[h];
      return `"${String(val ?? "").replace(/"/g, '""')}"`;
    }).join(","));
    const csv = [header.join(","), ...lines].join("\n");
    const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `nps-detractors-${new Date().toISOString().slice(0,10)}.csv`;
    a.click();
    URL.revokeObjectURL(url);
    toast(`Exportado ${rows.length} detractors.`, "success");
  } catch (e) {
    toast(`Erro: ${e?.message ?? e}`, "error");
  }
}

async function exportCsvAll() {
  const f = { ...state.filters, only_with_comment: false };
  try {
    const rows = await rpc("nps_results_comments", { p_filters: f, p_limit: 1000 });
    if (!rows?.length) { toast("Sem respostas no filtro.", "info"); return; }
    const header = ["submitted_at","nps_score","bucket","mode","source","cohort","class","student_name","student_phone","name_provided","comment"];
    const lines = rows.map((r) => header.map((h) => {
      const val = {
        submitted_at: r.submitted_at, nps_score: r.nps_score, bucket: r.bucket, mode: r.mode, source: r.source,
        cohort: r.cohort_name, class: r.class_name,
        student_name: r.student_name, student_phone: r.student_phone,
        name_provided: r.name_provided, comment: r.comment,
      }[h];
      return `"${String(val ?? "").replace(/"/g, '""')}"`;
    }).join(","));
    const csv = [header.join(","), ...lines].join("\n");
    const blob = new Blob(["﻿" + csv], { type: "text/csv;charset=utf-8" });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url; a.download = `nps-todas-respostas-${new Date().toISOString().slice(0,10)}.csv`;
    a.click(); URL.revokeObjectURL(url);
    toast(`Exportadas ${rows.length} respostas.`, "success");
  } catch (e) { toast(`Erro: ${e?.message ?? e}`, "error"); }
}

function showError(m) { $("error-banner-text").textContent = m; show($("error-banner")); }
function hideError() { hide($("error-banner")); }

// ─── Wire events ─────────────────────────────────────────────────────
function wireEvents() {
  $("logout-btn").addEventListener("click", logout);
  $("refresh-btn").addEventListener("click", refreshAll);
  $("export-csv-btn").addEventListener("click", exportCsv);
  $("export-csv-all-btn")?.addEventListener("click", exportCsvAll);
  $("print-btn")?.addEventListener("click", () => window.print());
  $("error-banner-dismiss").addEventListener("click", hideError);

  $("apply-filters").addEventListener("click", async () => {
    state.filters = readFilters();
    await refreshAll();
  });
  $("reset-filters").addEventListener("click", () => {
    $("filter-cohort").value = "";
    $("filter-class").value = "";
    $("filter-mode").value = "";
    if ($("filter-source")) $("filter-source").value = "";
    init();
  });

  document.querySelectorAll(".chip[data-bucket]").forEach((btn) => {
    btn.addEventListener("click", async () => {
      document.querySelectorAll(".chip[data-bucket]").forEach((b) => b.classList.remove("active"));
      btn.classList.add("active");
      state.bucket = btn.dataset.bucket;
      state.comments = await fetchComments();
      renderComments();
    });
  });

  $("only-with-comment").addEventListener("change", async (e) => {
    state.onlyWithComment = e.target.checked;
    state.comments = await fetchComments();
    renderComments();
  });

  $("login-btn").addEventListener("click", login);
  ["login-email", "login-password"].forEach((id) => {
    $(id).addEventListener("keydown", (e) => { if (e.key === "Enter") login(); });
  });
}

// ─── MOCK ────────────────────────────────────────────────────────────
function mockRpc(name, args) {
  return new Promise((resolve) => setTimeout(() => resolve(_mockRpc(name, args)), 100));
}
function _mockRpc(name, args) {
  if (name === "nps_results_filter_options") {
    return {
      cohorts: [
        { id: "bbb", name: "PS Advanced T3" },
        { id: "ddd", name: "Fundamentals T4" },
        { id: "fff", name: "PS Fundamentals T2" },
      ],
      classes: [
        { id: "aaa", name: "PS Advanced" },
        { id: "ccc", name: "Aula 12 — Casos clínicos" },
        { id: "eee", name: "PS Fundamentals" },
      ],
    };
  }
  if (name === "nps_results_summary") {
    return {
      total: 142, promoters: 87, passives: 32, detractors: 23,
      avg_score: 8.4, nps_score: 45.1,
      promoter_pct: 61.3, passive_pct: 22.5, detractor_pct: 16.2,
    };
  }
  if (name === "nps_results_trend") {
    const weeks = [];
    const base = new Date(); base.setDate(base.getDate() - 84);
    for (let i = 0; i < 12; i++) {
      const wk = new Date(base); wk.setDate(base.getDate() + i * 7);
      weeks.push({
        week_start: wk.toISOString().slice(0, 10),
        total: 8 + Math.floor(Math.random() * 18),
        promoters: 5 + Math.floor(Math.random() * 8),
        detractors: Math.floor(Math.random() * 4),
        nps: 30 + Math.floor(Math.random() * 50),
        avg_score: (7.5 + Math.random() * 1.8).toFixed(2),
      });
    }
    return weeks;
  }
  if (name === "nps_results_by_cohort") {
    return [
      { cohort_id: "bbb", cohort_name: "PS Advanced T3", total: 58, nps: 52.1, avg_score: 8.6, detractors: 8, promoters: 38 },
      { cohort_id: "ddd", cohort_name: "Fundamentals T4", total: 48, nps: 41.7, avg_score: 8.2, detractors: 9, promoters: 29 },
      { cohort_id: "fff", cohort_name: "PS Fundamentals T2", total: 36, nps: 38.9, avg_score: 8.0, detractors: 6, promoters: 20 },
    ];
  }
  if (name === "nps_results_by_class") {
    return [
      { class_id: "aaa", class_name: "PS Advanced", total: 58, nps: 52.1, avg_score: 8.6 },
      { class_id: "ccc", class_name: "Aula 12 — Casos clínicos", total: 32, nps: 56.3, avg_score: 8.8 },
      { class_id: "eee", class_name: "PS Fundamentals", total: 36, nps: 38.9, avg_score: 8.0 },
      { class_id: "fff", class_name: "Aula 11 — Análise estrutural", total: 16, nps: 31.3, avg_score: 7.8 },
    ];
  }
  if (name === "nps_results_comments") {
    const all = [
      { response_id: "1", source: "auto_class", submitted_at: "2026-05-16T22:18:00Z", nps_score: 9, bucket: "promoter", comment: "Aula sensacional, conteúdo bem amarrado e ritmo perfeito.", mode: "dm", name_provided: null, cohort_name: "Fundamentals T4", class_name: "Aula 11 — Análise estrutural", student_name: "Ana Silva", student_phone: "+5511920000001" },
      { response_id: "2", source: "auto_class", submitted_at: "2026-05-16T21:50:00Z", nps_score: 5, bucket: "detractor", comment: "Ritmo muito acelerado, perdi o fio. Esperava mais exemplos.", mode: "dm", name_provided: null, cohort_name: "PS Advanced T3", class_name: "PS Advanced", student_name: "Bruno Costa", student_phone: "+5511920000002" },
      { response_id: "3", source: "auto_class", submitted_at: "2026-05-16T19:30:00Z", nps_score: 10, bucket: "promoter", comment: "Melhor aula do módulo. Já indiquei pra dois colegas.", mode: "group", name_provided: "Carla M.", cohort_name: "Fundamentals T4", class_name: "Aula 11 — Análise estrutural", student_name: null, student_phone: null },
      { response_id: "4", source: "manual_survey", submitted_at: "2026-05-15T22:00:00Z", nps_score: 3, bucket: "detractor", comment: "Áudio com problemas durante 40% da aula. Frustrante.", mode: "dm", name_provided: null, cohort_name: "PS Fundamentals T2", class_name: null, student_name: "Daniel Lima", student_phone: "+5511920000003" },
      { response_id: "5", source: "auto_class", submitted_at: "2026-05-15T21:30:00Z", nps_score: 8, bucket: "passive", comment: "Bom, mas senti falta de feedback no exercício final.", mode: "dm", name_provided: null, cohort_name: "Fundamentals T4", class_name: "Aula 11 — Análise estrutural", student_name: "Eduarda Souza", student_phone: "+5511920000004" },
      { response_id: "6", source: "manual_survey", submitted_at: "2026-05-14T22:00:00Z", nps_score: 9, bucket: "promoter", comment: "Conteúdo sólido, mentor preparado.", mode: "dm", name_provided: null, cohort_name: "PS Advanced T3", class_name: null, student_name: "Fernando Alves", student_phone: "+5511920000005" },
    ];
    let filtered = [...all];
    const bucket = args.p_filters?.bucket;
    if (bucket) filtered = filtered.filter((r) => r.bucket === bucket);
    if (args.p_filters?.only_with_comment) filtered = filtered.filter((r) => r.comment);
    const source = args.p_filters?.source;
    if (source) filtered = filtered.filter((r) => r.source === source);
    return filtered;
  }
  return null;
}

// ─── Boot ────────────────────────────────────────────────────────────
async function boot() {
  wireEvents();
  if (MOCK) {
    hide($("login-overlay"));
    show($("app"));
    init();
    return;
  }
  const ok = await ensureAdmin();
  if (ok === true) enterApp();
  else if (ok === false) { hide($("login-overlay")); show($("app")); show($("forbidden")); }
  else { show($("login-overlay")); hide($("app")); }
}

boot();
