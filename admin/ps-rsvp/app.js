// admin/ps-rsvp — Pre-PS RSVP responses dashboard
// Tables: ps_rsvp_responses, ps_rsvp_links
// VIEW: ps_rsvp_today

const SUPABASE_URL = window.SUPABASE_CONFIG?.url;
const SUPABASE_ANON_KEY = window.SUPABASE_CONFIG?.anonKey;

if (!SUPABASE_URL || !SUPABASE_ANON_KEY) {
  console.error("Missing SUPABASE_CONFIG.");
}

const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true },
});

const $ = (id) => document.getElementById(id);
const show = (el) => el.classList.remove("hidden");
const hide = (el) => el.classList.add("hidden");

const state = { responses: [], pending: [], classes: [] };

function escapeHtml(s) {
  if (s == null) return "";
  return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function fmtTime(ts) {
  if (!ts) return "—";
  const d = new Date(ts);
  return d.toLocaleString("pt-BR", { day: "2-digit", month: "2-digit", hour: "2-digit", minute: "2-digit" });
}

function attendChip(v) {
  if (v === "yes") return `<span class="attend-chip yes">✓ Vai</span>`;
  if (v === "no") return `<span class="attend-chip no">✗ Não</span>`;
  if (v === "maybe") return `<span class="attend-chip maybe">~ Talvez</span>`;
  return `<span class="attend-chip">—</span>`;
}

async function loadResponses() {
  const dateFilter = $("filter-date").value;
  const today = new Date().toISOString().slice(0, 10);

  let q = sb.from("ps_rsvp_responses")
    .select("id, class_id, session_date, will_attend, doubts_text, project_phase, submitted_at, student_id, classes(name), students(name, phone)")
    .order("submitted_at", { ascending: false });

  if (dateFilter === "today") q = q.eq("session_date", today);
  else q = q.gte("session_date", today);

  const { data, error } = await q;
  if (error) {
    console.error(error);
    $("responses-body").innerHTML = `<tr><td colspan="6" class="empty">Erro: ${escapeHtml(error.message)}</td></tr>`;
    return;
  }
  state.responses = data || [];
  renderResponses();
  renderKpis();
}

async function loadPending() {
  const today = new Date().toISOString().slice(0, 10);
  const { data, error } = await sb.from("ps_rsvp_links")
    .select("id, class_id, session_date, send_status, sent_at, student_id, classes(name), students(name, phone)")
    .eq("session_date", today)
    .order("sent_at", { ascending: false });
  if (error) {
    console.error(error);
    $("pending-body").innerHTML = `<tr><td colspan="5" class="empty">Erro: ${escapeHtml(error.message)}</td></tr>`;
    return;
  }
  // Filter: links with no response yet
  const responsesByLink = new Set(state.responses.map((r) => r.id));
  const allLinks = data || [];
  const respondedStudentIds = new Set(state.responses.map((r) => `${r.class_id}::${r.student_id}`));
  state.pending = allLinks.filter((l) => !respondedStudentIds.has(`${l.class_id}::${l.student_id}`));
  renderPending();
}

function renderResponses() {
  const classFilter = $("filter-class").value;
  const attendFilter = $("filter-attend").value;
  const onlyDoubts = $("only-with-doubts").checked;

  let rows = state.responses;
  if (classFilter) rows = rows.filter((r) => r.class_id === classFilter);
  if (attendFilter) rows = rows.filter((r) => r.will_attend === attendFilter);
  if (onlyDoubts) rows = rows.filter((r) => r.doubts_text && r.doubts_text.trim());

  if (rows.length === 0) {
    $("responses-body").innerHTML = `<tr><td colspan="6" class="empty">Nenhuma resposta com os filtros atuais.</td></tr>`;
    return;
  }
  $("responses-body").innerHTML = rows.map((r) => `
    <tr>
      <td>${attendChip(r.will_attend)}</td>
      <td>
        <div class="name-cell">${escapeHtml(r.students?.name || "—")}</div>
        <div class="phone-cell">${escapeHtml(r.students?.phone || "—")}</div>
      </td>
      <td>${escapeHtml(r.classes?.name || "—")}</td>
      <td class="doubts-cell">${escapeHtml(r.doubts_text || "—")}</td>
      <td class="phase-cell">${escapeHtml(r.project_phase || "—")}</td>
      <td class="time-cell">${fmtTime(r.submitted_at)}</td>
    </tr>
  `).join("");
}

function renderPending() {
  const rows = state.pending;
  $("pending-count").textContent = `${rows.length} alunos sem responder ainda (data: hoje)`;
  if (rows.length === 0) {
    $("pending-body").innerHTML = `<tr><td colspan="5" class="empty">Todos responderam ou nada enviado ainda.</td></tr>`;
    return;
  }
  $("pending-body").innerHTML = rows.slice(0, 200).map((l) => `
    <tr>
      <td class="name-cell">${escapeHtml(l.students?.name || "—")}</td>
      <td>${escapeHtml(l.classes?.name || "—")}</td>
      <td class="phone-cell">${escapeHtml(l.students?.phone || "—")}</td>
      <td><span class="attend-chip ${l.send_status === "sent" ? "yes" : l.send_status === "failed" ? "no" : "maybe"}">${escapeHtml(l.send_status)}</span></td>
      <td class="time-cell">${fmtTime(l.sent_at)}</td>
    </tr>
  `).join("") + (rows.length > 200 ? `<tr><td colspan="5" class="empty">+${rows.length - 200} mais (não exibidos)</td></tr>` : "");
}

function renderKpis() {
  const rows = state.responses;
  $("kpi-total").textContent = rows.length;
  $("kpi-yes").textContent = rows.filter((r) => r.will_attend === "yes").length;
  $("kpi-maybe").textContent = rows.filter((r) => r.will_attend === "maybe").length;
  $("kpi-no").textContent = rows.filter((r) => r.will_attend === "no").length;
  $("kpi-doubts").textContent = rows.filter((r) => r.doubts_text && r.doubts_text.trim()).length;
}

async function loadClasses() {
  const { data } = await sb.from("classes")
    .select("id, name")
    .eq("kind", "ps")
    .eq("active", true)
    .order("name");
  state.classes = data || [];
  const sel = $("filter-class");
  state.classes.forEach((c) => {
    const opt = document.createElement("option");
    opt.value = c.id; opt.textContent = c.name;
    sel.appendChild(opt);
  });
}

function exportCSV() {
  const rows = state.responses;
  if (rows.length === 0) { alert("Nada pra exportar."); return; }
  const header = "data,classe,aluno,telefone,status,duvidas,fase,quando";
  const csv = rows.map((r) => [
    r.session_date,
    csvCell(r.classes?.name),
    csvCell(r.students?.name),
    csvCell(r.students?.phone),
    r.will_attend,
    csvCell(r.doubts_text),
    csvCell(r.project_phase),
    r.submitted_at,
  ].join(",")).join("\n");
  download(`ps-rsvp-${new Date().toISOString().slice(0, 10)}.csv`, header + "\n" + csv, "text/csv");
}

function exportMD() {
  const rows = state.responses;
  if (rows.length === 0) { alert("Nada pra exportar."); return; }
  // Group by class, show only attending + maybe with doubts
  const relevant = rows.filter((r) => (r.will_attend === "yes" || r.will_attend === "maybe") && r.doubts_text && r.doubts_text.trim());
  const byClass = {};
  for (const r of relevant) {
    const cn = r.classes?.name || "—";
    (byClass[cn] = byClass[cn] || []).push(r);
  }
  let md = `# Briefing PS — ${new Date().toLocaleDateString("pt-BR")}\n\n`;
  md += `**Total respostas:** ${rows.length} · **Vão participar:** ${rows.filter(r=>r.will_attend==="yes").length} · **Talvez:** ${rows.filter(r=>r.will_attend==="maybe").length} · **Com dúvidas:** ${relevant.length}\n\n---\n\n`;
  if (relevant.length === 0) {
    md += "_Nenhuma dúvida coletada ainda._\n";
  } else {
    for (const cn of Object.keys(byClass).sort()) {
      md += `## ${cn}\n\n`;
      for (const r of byClass[cn]) {
        md += `### ${r.students?.name || "Aluno"}${r.will_attend === "maybe" ? " *(talvez)*" : ""}\n`;
        if (r.project_phase) md += `**Fase:** ${r.project_phase}\n`;
        md += `${r.doubts_text}\n\n`;
      }
    }
  }
  download(`briefing-ps-${new Date().toISOString().slice(0, 10)}.md`, md, "text/markdown");
}

function csvCell(v) { const s = String(v ?? "").replace(/"/g, '""'); return /[,"\n]/.test(s) ? `"${s}"` : s; }
function download(name, content, mime) {
  const a = Object.assign(document.createElement("a"), {
    href: URL.createObjectURL(new Blob(["﻿" + content], { type: mime })),
    download: name,
  });
  a.click();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

async function refresh() {
  await loadResponses();
  await loadPending();
}

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
  if (!email || !password) { showLoginError("Preencha email e senha."); return; }
  $("login-btn").disabled = true;
  try {
    const { error } = await sb.auth.signInWithPassword({ email, password });
    if (error) throw error;
    const ok = await ensureAdmin();
    if (ok === false) { showLoginError("Sua conta não tem permissão de admin."); await sb.auth.signOut(); return; }
    enterApp();
  } catch (e) { showLoginError(e?.message ?? "Erro ao logar."); }
  finally { $("login-btn").disabled = false; }
}

function showLoginError(msg) { const el = $("login-error"); el.textContent = msg; el.classList.remove("hidden"); }

async function enterApp() {
  hide($("login-overlay"));
  show($("app"));
  await loadClasses();
  await refresh();
}

async function logout() { await sb.auth.signOut(); location.reload(); }

(async function bootstrap() {
  const ok = await ensureAdmin();
  if (ok) { enterApp(); }
  else { show($("login-overlay")); }

  $("login-btn").addEventListener("click", login);
  $("login-password").addEventListener("keydown", (e) => { if (e.key === "Enter") login(); });
  $("logout-btn").addEventListener("click", logout);
  $("refresh-btn").addEventListener("click", refresh);
  $("filter-date").addEventListener("change", refresh);
  $("filter-class").addEventListener("change", renderResponses);
  $("filter-attend").addEventListener("change", renderResponses);
  $("only-with-doubts").addEventListener("change", renderResponses);
  $("export-csv-btn").addEventListener("click", exportCSV);
  $("export-md-btn").addEventListener("click", exportMD);
})();
