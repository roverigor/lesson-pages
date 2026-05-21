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
  psRsvpLinks: [],
  psRsvpResponses: [],
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
    const [summary, trend, cohortBreak, classBreak, surveyBreak, comments] = await Promise.all([
      rpc("nps_results_summary", { p_filters: state.filters }),
      rpc("nps_results_trend", { p_weeks: 12, p_filters: state.filters }),
      rpc("nps_results_by_cohort", { p_filters: state.filters }),
      rpc("nps_results_by_class", { p_filters: state.filters }),
      rpc("nps_results_by_survey", { p_filters: state.filters }).catch(() => []),
      fetchComments(),
    ]);
    state.summary = summary;
    state.trend = trend || [];
    state.cohortBreak = cohortBreak || [];
    state.classBreak = classBreak || [];
    state.surveyBreak = surveyBreak || [];
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
  renderSurveyBreak();
  renderComments();
  renderAllResponses();
  renderPsRsvp();
}

// ─── PS RSVP ─────────────────────────────────────────────────────────
async function fetchPsRsvp() {
  if (MOCK || !sb) return { links: [], responses: [] };
  const from = $("filter-date-from").value;
  const to = $("filter-date-to").value;
  const dateFrom = from || new Date(Date.now() - 90 * 86400000).toISOString().slice(0, 10);
  const dateTo = to || new Date().toISOString().slice(0, 10);

  // Fetch só links com send_status sent/failed (skip 'pending' que pode ter milhares stale)
  const [linksRes, respsRes] = await Promise.all([
    sb.from("ps_rsvp_links")
      .select("id, session_date, send_status, sent_at, created_at, class_id, student_id")
      .gte("session_date", dateFrom)
      .lte("session_date", dateTo)
      .in("send_status", ["sent", "failed"]),
    sb.from("ps_rsvp_responses")
      .select("id, link_id, class_id, student_id, session_date, will_attend, doubts_text, project_phase, submitted_at")
      .gte("session_date", dateFrom)
      .lte("session_date", dateTo)
      .order("submitted_at", { ascending: false }),
  ]);
  if (linksRes.error) throw linksRes.error;
  if (respsRes.error) throw respsRes.error;

  // Hydrate class+student via separate queries (chunked pra evitar URL length overflow)
  const classIds = [...new Set([...(linksRes.data || []), ...(respsRes.data || [])].map((r) => r.class_id).filter(Boolean))];
  const studentIds = [...new Set([...(linksRes.data || []), ...(respsRes.data || [])].map((r) => r.student_id).filter(Boolean))];

  async function chunkedIn(table, columns, ids, chunkSize = 80) {
    const out = [];
    for (let i = 0; i < ids.length; i += chunkSize) {
      const chunk = ids.slice(i, i + chunkSize);
      const r = await sb.from(table).select(columns).in("id", chunk);
      if (r.error) throw r.error;
      out.push(...(r.data || []));
    }
    return out;
  }

  const [classesData, studentsData] = await Promise.all([
    classIds.length ? chunkedIn("classes", "id, name", classIds) : Promise.resolve([]),
    studentIds.length ? chunkedIn("students", "id, name, phone", studentIds) : Promise.resolve([]),
  ]);
  const classMap = new Map(classesData.map((c) => [c.id, c]));
  const studentMap = new Map(studentsData.map((s) => [s.id, s]));

  const responses = (respsRes.data || []).map((r) => ({ ...r, class: classMap.get(r.class_id), student: studentMap.get(r.student_id) }));
  const links = (linksRes.data || []).map((l) => ({ ...l, class: classMap.get(l.class_id), student: studentMap.get(l.student_id) }));
  return { links, responses };
}

function mergePsRsvpIntoSurveyBreak() {
  const links = state.psRsvpLinks || [];
  const responses = state.psRsvpResponses || [];
  const groups = new Map();
  for (const l of links) {
    const k = `${l.class_id || "null"}|${l.session_date}`;
    if (!groups.has(k)) groups.set(k, { class_id: l.class_id, class_name: l.class?.name, session_date: l.session_date, links: [], responses: [] });
    groups.get(k).links.push(l);
  }
  for (const r of responses) {
    const k = `${r.class_id || "null"}|${r.session_date}`;
    if (!groups.has(k)) groups.set(k, { class_id: r.class_id, class_name: r.class?.name, session_date: r.session_date, links: [], responses: [] });
    groups.get(k).responses.push(r);
  }
  // Remove old PS RSVP entries to avoid duplication on re-render
  state.surveyBreak = (state.surveyBreak || []).filter((s) => s.kind !== "ps_rsvp");
  const psEntries = [];
  for (const [k, g] of groups) {
    const sent = g.links.filter((l) => l.send_status === "sent").length;
    const total = g.responses.length;
    const yes = g.responses.filter((r) => r.will_attend === "yes").length;
    const no = g.responses.filter((r) => r.will_attend === "no").length;
    const maybe = g.responses.filter((r) => r.will_attend === "maybe").length;
    const rate = sent > 0 ? Math.round((total / sent) * 100) : 0;
    psEntries.push({
      group_key: `psrsvp:${k}`,
      kind: "ps_rsvp",
      label: `📋 Pré PS — ${g.class_name || "Aula PS"} · ${g.session_date}`,
      class_name: g.class_name,
      class_id: g.class_id,
      cohort_name: null,
      session_date: g.session_date,
      first_at: g.session_date + "T00:00:00",
      last_at: g.session_date + "T23:59:59",
      total,
      nps: rate,        // reaproveita NPS slot pra mostrar taxa resposta
      avg_score: null,
      dm_total: sent,
      dm_nps: null,
      group_total: 0,
      group_nps: null,
      ps_yes: yes,
      ps_no: no,
      ps_maybe: maybe,
    });
  }
  state.surveyBreak = state.surveyBreak.concat(psEntries);
}

async function renderPsRsvp() {
  const body = $("ps-rsvp-body");
  if (!body) return;
  try {
    const { links, responses } = await fetchPsRsvp();
    state.psRsvpLinks = links;
    state.psRsvpResponses = responses;
    mergePsRsvpIntoSurveyBreak();
    renderSurveyBreak();
    const sent = links.filter((l) => l.send_status === "sent").length;
    const resp = responses.length;
    const rate = sent > 0 ? Math.round((resp / sent) * 100) : 0;
    const yes = responses.filter((r) => r.will_attend === "yes").length;
    const no = responses.filter((r) => r.will_attend === "no").length;
    const maybe = responses.filter((r) => r.will_attend === "maybe").length;

    $("ps-kpi-sent").textContent = sent;
    $("ps-kpi-resp").textContent = resp;
    $("ps-kpi-rate").textContent = `${rate}%`;
    $("ps-kpi-yes").textContent = yes;
    $("ps-kpi-no").textContent = no;
    $("ps-kpi-maybe").textContent = maybe;

    if (!responses.length) {
      body.innerHTML = `<tr><td colspan="8" style="padding:20px;color:#444;text-align:center">Nenhuma resposta no período. Total envios: ${sent}.</td></tr>`;
      return;
    }

    body.innerHTML = responses.map((r) => {
      const respLbl = r.will_attend === "yes" ? '<span class="ps-resp-yes">✅ Vai</span>'
        : r.will_attend === "no" ? '<span class="ps-resp-no">❌ Não vai</span>'
        : r.will_attend === "maybe" ? '<span class="ps-resp-maybe">⚠️ Dúvida</span>'
        : '<span class="ps-resp-pending">—</span>';
      const when = r.submitted_at ? new Date(r.submitted_at).toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", year: "2-digit", hour: "2-digit", minute: "2-digit" }) : "—";
      const session = r.session_date ? new Date(r.session_date + "T00:00:00").toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit" }) : "—";
      return `<tr>
        <td style="font-size:12px;color:#aaa">${escapeHtml(session)}</td>
        <td>${escapeHtml(r.student?.name || "—")}</td>
        <td style="font-size:11px;color:#888">${escapeHtml(r.student?.phone || "—")}</td>
        <td style="color:#888">${escapeHtml(r.class?.name || "—")}</td>
        <td>${respLbl}</td>
        <td style="font-size:12px;color:#ccc;max-width:340px">${escapeHtml(r.doubts_text || "")}</td>
        <td style="font-size:11px;color:#888">${escapeHtml(r.project_phase || "—")}</td>
        <td style="font-size:11px;color:#666">${escapeHtml(when)}</td>
      </tr>`;
    }).join("");
  } catch (e) {
    body.innerHTML = `<tr><td colspan="8" style="padding:20px;color:#f87171">Erro: ${escapeHtml(e?.message ?? String(e))}</td></tr>`;
  }
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

// ─── By survey / session ─────────────────────────────────────────────
function renderSurveyBreak() {
  const list = $("survey-list");
  if (!list) return;
  const kindFilter = $("survey-kind-filter")?.value || "";
  let rows = state.surveyBreak || [];
  if (kindFilter) rows = rows.filter((r) => r.kind === kindFilter);

  if (rows.length === 0) {
    list.innerHTML = `<div class="loading">Nenhum formulário com filtros atuais.</div>`;
    return;
  }

  list.innerHTML = rows.map((r) => {
    const isPs = r.kind === "ps_rsvp";
    const icon = isPs ? "📋" : r.kind === "manual" ? "📋" : "⚡";
    const kindLbl = isPs ? "Pré PS RSVP" : r.kind === "manual" ? "Formulário manual" : (r.class_kind === "ps" ? "PS pós-aula" : "Aula pós-aula");
    const dateRange = (r.first_at && r.last_at && r.first_at !== r.last_at)
      ? `${fmtDate(r.first_at)} – ${fmtDate(r.last_at)}`
      : fmtDate(r.first_at || r.last_at);
    const cohortTag = r.cohort_name ? `<span style="background:#1a1a20;padding:2px 8px;border-radius:12px;font-size:11px;color:#aaa">👥 ${escapeHtml(r.cohort_name)}</span>` : "";

    let modeSplitTxt = "";
    let stats = "";
    if (isPs) {
      modeSplitTxt = `<span style="color:#888;font-size:11px">📩 Enviados ${r.dm_total ?? 0} · ✅ ${r.ps_yes ?? 0} vão · ❌ ${r.ps_no ?? 0} não · ⚠️ ${r.ps_maybe ?? 0} dúvida</span>`;
      const rateCol = r.nps >= 50 ? "#4ade80" : r.nps >= 20 ? "#fbbf24" : "#f87171";
      stats = `
        <div class="stat-block"><div class="stat-num">${r.total}</div><div class="stat-lbl">respostas</div></div>
        <div class="stat-block"><div class="stat-num" style="color:${rateCol}">${r.nps}%</div><div class="stat-lbl">taxa</div></div>
        <div class="stat-block"><div class="stat-num">${r.dm_total ?? 0}</div><div class="stat-lbl">enviados</div></div>`;
    } else {
      modeSplitTxt = (r.dm_total > 0 || r.group_total > 0)
        ? `<span style="color:#888;font-size:11px">📩 DM ${r.dm_total ?? 0}${r.dm_nps != null ? ` (NPS ${r.dm_nps})` : ""} · 📢 Grupo ${r.group_total ?? 0}${r.group_nps != null ? ` (NPS ${r.group_nps})` : ""}</span>`
        : "";
      const npsCol = npsColor(r.nps);
      stats = `
        <div class="stat-block"><div class="stat-num">${r.total}</div><div class="stat-lbl">respostas</div></div>
        <div class="stat-block"><div class="stat-num" style="color:${npsCol}">${r.nps ?? "—"}</div><div class="stat-lbl">NPS geral</div></div>
        <div class="stat-block"><div class="stat-num">${r.avg_score ?? "—"}</div><div class="stat-lbl">média</div></div>`;
    }
    return `
      <div class="survey-item" data-key="${escapeHtml(r.group_key)}">
        <div class="survey-row">
          <div class="survey-main">
            <div class="survey-label">${icon} ${escapeHtml(r.label)}</div>
            <div class="survey-meta" style="display:flex;gap:8px;align-items:center;flex-wrap:wrap;margin-top:4px">
              ${cohortTag}
              <span>${escapeHtml(kindLbl)} · ${escapeHtml(dateRange)}</span>
            </div>
            ${modeSplitTxt ? `<div style="margin-top:4px">${modeSplitTxt}</div>` : ""}
          </div>
          <div class="survey-stats">
            ${stats}
            <button class="btn-expand" data-key="${escapeHtml(r.group_key)}">Ver detalhe</button>
          </div>
        </div>
        <div class="survey-detail hidden" id="detail-${cssId(r.group_key)}"></div>
      </div>
    `;
  }).join("");

  list.querySelectorAll(".btn-expand").forEach((btn) => {
    btn.addEventListener("click", () => toggleSurveyDetail(btn.dataset.key));
  });
}

function cssId(str) { return String(str).replace(/[^a-zA-Z0-9_-]/g, "_"); }

async function toggleSurveyDetail(key) {
  const elId = `detail-${cssId(key)}`;
  const el = document.getElementById(elId);
  if (!el) return;
  if (!el.classList.contains("hidden")) {
    el.classList.add("hidden");
    el.innerHTML = "";
    return;
  }
  el.classList.remove("hidden");
  el.innerHTML = `<div class="loading">Carregando respostas...</div>`;

  const row = (state.surveyBreak || []).find((r) => r.group_key === key);
  if (!row) { el.innerHTML = `<div class="loading">Dados não encontrados.</div>`; return; }

  // PS RSVP detail — render direto do state.psRsvpResponses (não RPC)
  if (row.kind === "ps_rsvp") {
    const matches = (state.psRsvpResponses || []).filter((r) => r.session_date === row.session_date && r.class_id === row.class_id);
    if (!matches.length) { el.innerHTML = `<div class="loading">Sem respostas PS RSVP.</div>`; return; }
    el.innerHTML = `<table class="data-table" style="margin-top:6px">
      <thead><tr><th>Quando</th><th>Aluno</th><th>Telefone</th><th>Resposta</th><th>Dúvida/Comentário</th><th>Fase</th></tr></thead>
      <tbody>${matches.map((r) => {
        const respLbl = r.will_attend === "yes" ? '<span style="color:#4ade80;font-weight:700">✅ Vai</span>'
          : r.will_attend === "no" ? '<span style="color:#f87171;font-weight:700">❌ Não</span>'
          : r.will_attend === "maybe" ? '<span style="color:#fbbf24;font-weight:700">⚠️ Dúvida</span>' : "—";
        return `<tr>
          <td style="font-size:11px;color:#666">${escapeHtml(fmtDateTime(r.submitted_at))}</td>
          <td>${escapeHtml(r.student?.name || "—")}</td>
          <td style="font-size:11px;color:#888">${escapeHtml(r.student?.phone || "—")}</td>
          <td>${respLbl}</td>
          <td style="font-size:12px;color:#ccc;max-width:380px">${escapeHtml(r.doubts_text || "")}</td>
          <td style="font-size:11px;color:#888">${escapeHtml(r.project_phase || "—")}</td>
        </tr>`;
      }).join("")}</tbody></table>`;
    return;
  }

  // Build filter for detail query
  const f = { ...state.filters };
  if (row.kind === "manual") {
    f.survey_id = row.survey_id;
    f.source = "manual_survey";
  } else {
    f.class_id = row.class_id;
    f.source = "auto_class";
    if (row.session_date) {
      const d0 = new Date(row.session_date + "T00:00:00").toISOString();
      const d1 = new Date(row.session_date + "T00:00:00");
      d1.setDate(d1.getDate() + 1);
      f.date_from = d0;
      f.date_to = d1.toISOString();
    }
  }

  try {
    const rows = await rpc("nps_results_comments", { p_filters: f, p_limit: 500 });
    renderSurveyDetail(el, row, rows || []);
  } catch (e) {
    el.innerHTML = `<div class="loading" style="color:#f87171">Erro: ${escapeHtml(e?.message ?? String(e))}</div>`;
  }
}

function renderSurveyDetail(el, row, responses) {
  if (!responses.length) {
    el.innerHTML = `<div class="loading">Sem respostas para mostrar.</div>`;
    return;
  }

  // Build per-mode summary helper
  const summarize = (arr) => {
    if (!arr.length) return null;
    const promoters = arr.filter((r) => r.nps_score >= 9).length;
    const passives = arr.filter((r) => r.nps_score >= 7 && r.nps_score <= 8).length;
    const detractors = arr.filter((r) => r.nps_score <= 6).length;
    const total = arr.length;
    const nps = Math.round((promoters - detractors) * 100 / total);
    const avg = (arr.reduce((s, r) => s + (r.nps_score ?? 0), 0) / total).toFixed(1);
    return {
      total, promoters, passives, detractors, nps, avg,
      pp: Math.round(promoters * 100 / total),
      ps: Math.round(passives * 100 / total),
      pd: Math.round(detractors * 100 / total),
    };
  };

  const all = summarize(responses);
  const dm = summarize(responses.filter((r) => r.mode === "dm"));
  const grp = summarize(responses.filter((r) => r.mode === "group"));
  const withComment = responses.filter((r) => r.comment && r.comment.trim());

  const buildBar = (s, title) => s ? `
    <div class="detail-mode-block">
      <div class="detail-mode-title">${title} · ${s.total} respostas · NPS <strong style="color:${npsColor(s.nps)}">${s.nps}</strong> · média ${s.avg}</div>
      <div class="detail-bar">
        <div class="bar-segment promoter" style="width:${s.pp}%"></div>
        <div class="bar-segment passive" style="width:${s.ps}%"></div>
        <div class="bar-segment detractor" style="width:${s.pd}%"></div>
      </div>
      <div class="detail-legend">
        <span style="color:#4ade80">💚 ${s.promoters} (${s.pp}%)</span>
        <span style="color:#facc15">⚠️ ${s.passives} (${s.ps}%)</span>
        <span style="color:#f87171">🚨 ${s.detractors} (${s.pd}%)</span>
      </div>
    </div>` : "";

  let html = `
    ${buildBar(all, "📊 Geral")}
    ${dm && grp ? `
      <div class="detail-mode-split">
        ${buildBar(dm, "📩 DM (atribuído)")}
        ${buildBar(grp, "📢 Grupo (anônimo)")}
      </div>` : ""}
    ${dm && !grp ? buildBar(dm, "📩 DM (atribuído)") : ""}
    ${grp && !dm ? buildBar(grp, "📢 Grupo (anônimo)") : ""}
    <div class="detail-section">
      <div class="detail-section-title">Respostas (${all.total})${withComment.length ? ` · ${withComment.length} c/ comentário` : ""}</div>
      <table class="data-table" style="margin-top:6px">
        <thead><tr><th>Quando</th><th>Aluno</th><th>Canal</th><th>Nota</th><th>Comentário</th></tr></thead>
        <tbody>
          ${responses.map((r) => {
            const scoreCol = r.nps_score >= 9 ? "#4ade80" : r.nps_score >= 7 ? "#facc15" : "#f87171";
            const who = r.student_name || r.name_provided || "Anônimo";
            const modeLbl = r.mode === "dm" ? "📩 DM" : "📢 Grupo";
            return `<tr>
              <td style="font-size:11px;color:#666">${escapeHtml(fmtDateTime(r.submitted_at))}</td>
              <td>${escapeHtml(who)}</td>
              <td style="color:#888;font-size:11px">${modeLbl}</td>
              <td><strong style="color:${scoreCol}">${r.nps_score ?? "—"}</strong></td>
              <td style="color:#ccc;font-size:12px;max-width:480px">${escapeHtml(r.comment || "")}</td>
            </tr>`;
          }).join("")}
        </tbody>
      </table>
    </div>
  `;
  el.innerHTML = html;
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

function downloadBlob(content, filename, mime) {
  const blob = new Blob(["﻿" + content], { type: `${mime};charset=utf-8` });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  a.click();
  URL.revokeObjectURL(url);
}

function fmtRespLabel(v) {
  return v === "yes" ? "Vai" : v === "no" ? "Não vai" : v === "maybe" ? "Dúvida" : "—";
}

async function exportPsRsvpCsv() {
  const rows = state.psRsvpResponses || [];
  if (!rows.length) { toast("Sem respostas PS RSVP no filtro.", "info"); return; }
  const header = ["session_date","student_name","student_phone","class_name","will_attend","doubts_text","project_phase","submitted_at"];
  const lines = rows.map((r) => header.map((h) => {
    const val = {
      session_date: r.session_date,
      student_name: r.student?.name,
      student_phone: r.student?.phone,
      class_name: r.class?.name,
      will_attend: fmtRespLabel(r.will_attend),
      doubts_text: r.doubts_text,
      project_phase: r.project_phase,
      submitted_at: r.submitted_at,
    }[h];
    return `"${String(val ?? "").replace(/"/g, '""')}"`;
  }).join(","));
  const csv = [header.join(","), ...lines].join("\n");
  downloadBlob(csv, `ps-rsvp-${new Date().toISOString().slice(0,10)}.csv`, "text/csv");
  toast(`Exportado ${rows.length} respostas PS RSVP.`, "success");
}

async function exportPsRsvpMd() {
  const rows = state.psRsvpResponses || [];
  const links = state.psRsvpLinks || [];
  if (!rows.length && !links.length) { toast("Sem dados PS RSVP no filtro.", "info"); return; }
  const sent = links.filter((l) => l.send_status === "sent").length;
  const resp = rows.length;
  const rate = sent > 0 ? Math.round((resp / sent) * 100) : 0;
  const yes = rows.filter((r) => r.will_attend === "yes").length;
  const no = rows.filter((r) => r.will_attend === "no").length;
  const maybe = rows.filter((r) => r.will_attend === "maybe").length;
  const dateFrom = $("filter-date-from").value || "—";
  const dateTo = $("filter-date-to").value || "—";

  let md = `# Pré PS RSVP — Respostas\n\n`;
  md += `**Período:** ${dateFrom} → ${dateTo}\n\n`;
  md += `## Resumo\n\n`;
  md += `- Enviados: **${sent}**\n`;
  md += `- Respostas: **${resp}** (${rate}% taxa)\n`;
  md += `- ✅ Vão: **${yes}**\n`;
  md += `- ❌ Não vão: **${no}**\n`;
  md += `- ⚠️ Dúvida: **${maybe}**\n\n`;

  // Group by session_date
  const grouped = {};
  for (const r of rows) {
    const k = r.session_date || "sem-data";
    if (!grouped[k]) grouped[k] = [];
    grouped[k].push(r);
  }
  const sortedDates = Object.keys(grouped).sort((a, b) => b.localeCompare(a));

  for (const date of sortedDates) {
    const dateLbl = date !== "sem-data" ? new Date(date + "T00:00:00").toLocaleDateString("pt-BR", { day: "2-digit", month: "2-digit", year: "numeric" }) : "Sem data";
    md += `## ${dateLbl}\n\n`;
    md += `| Aluno | Telefone | Aula | Resposta | Fase projeto | Dúvida/Comentário |\n`;
    md += `|---|---|---|---|---|---|\n`;
    for (const r of grouped[date]) {
      const nome = (r.student?.name || "—").replace(/\|/g, "\\|");
      const tel = (r.student?.phone || "—").replace(/\|/g, "\\|");
      const aula = (r.class?.name || "—").replace(/\|/g, "\\|");
      const resp = fmtRespLabel(r.will_attend);
      const fase = (r.project_phase || "—").replace(/\|/g, "\\|").replace(/\n/g, " ");
      const doubts = (r.doubts_text || "").replace(/\|/g, "\\|").replace(/\n/g, " ");
      md += `| ${nome} | ${tel} | ${aula} | ${resp} | ${fase} | ${doubts} |\n`;
    }
    md += `\n`;
  }

  downloadBlob(md, `ps-rsvp-${new Date().toISOString().slice(0,10)}.md`, "text/markdown");
  toast(`Exportado ${rows.length} respostas PS RSVP em MD.`, "success");
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
  $("export-ps-csv-btn")?.addEventListener("click", exportPsRsvpCsv);
  $("export-ps-md-btn")?.addEventListener("click", exportPsRsvpMd);
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

  $("survey-kind-filter")?.addEventListener("change", () => renderSurveyBreak());

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
