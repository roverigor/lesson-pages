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

const state = { responses: [], pending: [], classes: [], setup: [] };
const _studentsCache = new Map(); // classId → students[]

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
  return `<span class="attend-chip">—</span>`;
}

async function loadResponses() {
  const dateFilter = $("filter-date").value;
  const today = new Date().toISOString().slice(0, 10);

  let q = sb.from("ps_rsvp_responses")
    .select("id, class_id, session_date, will_attend, doubts_text, project_phase, confirmed_name, no_reason, team_message, submitted_at, student_id, classes(name), students(name, phone)")
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
  if (onlyDoubts) rows = rows.filter((r) => (r.doubts_text && r.doubts_text.trim()) || (r.no_reason && r.no_reason.trim()));

  if (rows.length === 0) {
    $("responses-body").innerHTML = `<tr><td colspan="6" class="empty">Nenhuma resposta com os filtros atuais.</td></tr>`;
    return;
  }
  $("responses-body").innerHTML = rows.map((r) => {
    const isYes = r.will_attend === "yes";
    const displayName = isYes
      ? (r.confirmed_name || r.students?.name || "—")
      : (r.students?.name || "—");
    const middleText = isYes
      ? (r.doubts_text || "—")
      : (r.no_reason ? `🗨️ ${r.no_reason}` : "—");
    const rightText = isYes
      ? (r.project_phase || "—")
      : (r.team_message ? `✉️ ${r.team_message}` : "—");
    return `
    <tr>
      <td>${attendChip(r.will_attend)}</td>
      <td>
        <div class="name-cell">${escapeHtml(displayName)}</div>
        <div class="phone-cell">${escapeHtml(r.students?.phone || "—")}</div>
      </td>
      <td>${escapeHtml(r.classes?.name || "—")}</td>
      <td class="doubts-cell">${escapeHtml(middleText)}</td>
      <td class="phase-cell">${escapeHtml(rightText)}</td>
      <td class="time-cell">${fmtTime(r.submitted_at)}</td>
    </tr>`;
  }).join("");
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
  $("kpi-no").textContent = rows.filter((r) => r.will_attend === "no").length;
  $("kpi-doubts").textContent = rows.filter((r) => r.doubts_text && r.doubts_text.trim()).length;
  const feedback = $("kpi-feedback");
  if (feedback) feedback.textContent = rows.filter((r) => (r.no_reason && r.no_reason.trim()) || (r.team_message && r.team_message.trim())).length;
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
  const header = "data,classe,aluno,nome_confirmado,telefone,status,duvidas,fase,motivo_nao,recado_equipe,quando";
  const csv = rows.map((r) => [
    r.session_date,
    csvCell(r.classes?.name),
    csvCell(r.students?.name),
    csvCell(r.confirmed_name),
    csvCell(r.students?.phone),
    r.will_attend,
    csvCell(r.doubts_text),
    csvCell(r.project_phase),
    csvCell(r.no_reason),
    csvCell(r.team_message),
    r.submitted_at,
  ].join(",")).join("\n");
  download(`ps-rsvp-${new Date().toISOString().slice(0, 10)}.csv`, header + "\n" + csv, "text/csv");
}

function exportMD() {
  const rows = state.responses;
  if (rows.length === 0) { alert("Nada pra exportar."); return; }
  // Briefing: yes-with-doubts grouped by class
  const attending = rows.filter((r) => r.will_attend === "yes" && r.doubts_text && r.doubts_text.trim());
  const notComingWithFeedback = rows.filter((r) => r.will_attend === "no" && ((r.no_reason && r.no_reason.trim()) || (r.team_message && r.team_message.trim())));
  const byClass = {};
  for (const r of attending) {
    const cn = r.classes?.name || "—";
    (byClass[cn] = byClass[cn] || []).push(r);
  }
  let md = `# Briefing PS — ${new Date().toLocaleDateString("pt-BR")}\n\n`;
  md += `**Total respostas:** ${rows.length} · **Vão:** ${rows.filter(r=>r.will_attend==="yes").length} · **Não:** ${rows.filter(r=>r.will_attend==="no").length} · **Com dúvidas:** ${attending.length}\n\n---\n\n`;
  md += `## Dúvidas dos que vão\n\n`;
  if (attending.length === 0) {
    md += "_Nenhuma dúvida coletada ainda._\n\n";
  } else {
    for (const cn of Object.keys(byClass).sort()) {
      md += `### ${cn}\n\n`;
      for (const r of byClass[cn]) {
        const nm = r.confirmed_name || r.students?.name || "Aluno";
        md += `#### ${nm}\n`;
        if (r.project_phase) md += `**Fase:** ${r.project_phase}\n`;
        md += `${r.doubts_text}\n\n`;
      }
    }
  }
  if (notComingWithFeedback.length > 0) {
    md += `---\n\n## Quem não vai (com retorno)\n\n`;
    for (const r of notComingWithFeedback) {
      const nm = r.students?.name || "Aluno";
      md += `### ${nm} — ${r.classes?.name || "—"}\n`;
      if (r.no_reason) md += `**Motivo:** ${r.no_reason}\n`;
      if (r.team_message) md += `**Recado:** ${r.team_message}\n`;
      md += `\n`;
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
  await loadSetup();
  await loadResponses();
  await loadPending();
}

// ─── SETUP DASHBOARD ─────────────────────────────────────────────────
async function loadSetup() {
  const container = $("setup-container");
  if (!container) return;
  container.innerHTML = `<div class="empty">Carregando setup...</div>`;

  // 1) PS classes ativas
  const { data: classes, error: classErr } = await sb.from("classes")
    .select("id, name, weekday, time_start")
    .eq("kind", "ps")
    .eq("active", true)
    .order("name");
  if (classErr) {
    container.innerHTML = `<div class="empty" style="color:#f87171">Erro classes: ${escapeHtml(classErr.message)}</div>`;
    return;
  }
  if (!classes || classes.length === 0) {
    container.innerHTML = `<div class="empty">Nenhuma classe PS ativa.</div>`;
    return;
  }

  // 2) class_cohorts + cohorts em batch
  const classIds = classes.map((c) => c.id);
  const { data: bridges } = await sb.from("class_cohorts")
    .select("class_id, cohort_id")
    .in("class_id", classIds);
  const cohortIds = [...new Set((bridges || []).map((b) => b.cohort_id))];
  const cohortMap = new Map();
  if (cohortIds.length > 0) {
    const { data: cohorts } = await sb.from("cohorts")
      .select("id, name, active, whatsapp_group_jid, whatsapp_group_name")
      .in("id", cohortIds);
    (cohorts || []).forEach((co) => cohortMap.set(co.id, co));
  }

  // 3) Count students por cohort
  const { data: students } = await sb.from("students")
    .select("id, cohort_id, active, is_mentor, phone")
    .in("cohort_id", cohortIds.length > 0 ? cohortIds : ["00000000-0000-0000-0000-000000000000"]);
  const studentByCohort = new Map();
  (students || []).forEach((s) => {
    if (!studentByCohort.has(s.cohort_id)) studentByCohort.set(s.cohort_id, []);
    studentByCohort.get(s.cohort_id).push(s);
  });

  // 4) Build setup view
  const setup = classes.map((c) => {
    const classCohorts = (bridges || [])
      .filter((b) => b.class_id === c.id)
      .map((b) => cohortMap.get(b.cohort_id))
      .filter(Boolean);

    const cohortDetails = classCohorts.map((co) => {
      const list = studentByCohort.get(co.id) || [];
      const eligible = list.filter((s) => s.active && !s.is_mentor && s.phone && s.phone.trim());
      const noPhone = list.filter((s) => s.active && !s.is_mentor && (!s.phone || !s.phone.trim()));
      return {
        cohort: co,
        eligible_count: eligible.length,
        no_phone_count: noPhone.length,
        total_active: list.filter((s) => s.active).length,
      };
    });

    const totalEligible = cohortDetails.reduce((s, d) => s + d.eligible_count, 0);
    const missingWA = cohortDetails.filter((d) => !d.cohort.whatsapp_group_jid).length;

    return {
      class: c,
      cohorts: cohortDetails,
      total_eligible: totalEligible,
      missing_wa: missingWA,
      has_issue: missingWA > 0 || cohortDetails.length === 0,
    };
  });

  state.setup = setup;
  renderSetup();
}

const WEEKDAYS = ["Domingo","Segunda","Terça","Quarta","Quinta","Sexta","Sábado"];

function renderSetup() {
  const container = $("setup-container");
  if (!container) return;
  if (!state.setup.length) { container.innerHTML = `<div class="empty">Sem dados de setup.</div>`; return; }

  container.innerHTML = state.setup.map((s) => {
    const c = s.class;
    const wdLabel = WEEKDAYS[c.weekday] || `weekday=${c.weekday}`;
    const timeLabel = c.time_start ? c.time_start.slice(0, 5) : "—";
    const issueClass = s.has_issue ? "has-issue" : "";

    const cohortRows = s.cohorts.length === 0
      ? `<div class="empty" style="padding:14px">⚠️ Nenhum cohort vinculado a esta classe. <code>class_cohorts</code> precisa de INSERT.</div>`
      : s.cohorts.map((d) => {
          const co = d.cohort;
          const inactiveTag = !co.active ? `<span class="inactive-tag">inativo</span>` : "";
          const groupCell = co.whatsapp_group_jid
            ? `<span class="grupo-cell">${escapeHtml(co.whatsapp_group_name || co.whatsapp_group_jid)}</span>`
            : `<span class="grupo-cell missing">⚠️ sem grupo WA</span>`;
          return `
            <div class="cohort-row">
              <div class="cohort-name">${escapeHtml(co.name)}${inactiveTag}</div>
              ${groupCell}
              <div class="count-cell">${d.eligible_count} 👤</div>
              <button class="toggle-students-btn" data-class="${escapeHtml(c.id)}" data-cohort="${escapeHtml(co.id)}">Ver alunos</button>
            </div>
          `;
        }).join("");

    const issueBadge = s.missing_wa > 0
      ? `<span class="stat-pill warn">⚠️ ${s.missing_wa} sem grupo WA</span>`
      : s.cohorts.length > 0 ? `<span class="stat-pill ok">✓ grupos OK</span>` : "";

    return `
      <div class="class-block ${issueClass}">
        <div class="class-header">
          <div>
            <div class="class-name">${escapeHtml(c.name)}</div>
            <div class="class-meta">${wdLabel} · ${timeLabel}</div>
          </div>
          <div class="class-stats">
            <span class="stat-pill">${s.cohorts.length} cohort(s)</span>
            <span class="stat-pill">${s.total_eligible} aluno(s) elegível(s)</span>
            ${issueBadge}
          </div>
        </div>
        ${cohortRows}
        <div class="students-list hidden" id="students-${cssId(c.id)}"></div>
      </div>
    `;
  }).join("");

  container.querySelectorAll(".toggle-students-btn").forEach((btn) => {
    btn.addEventListener("click", () => toggleStudents(btn.dataset.class, btn.dataset.cohort));
  });
}

function cssId(s) { return String(s).replace(/[^a-zA-Z0-9_-]/g, "_"); }

async function toggleStudents(classId, cohortId) {
  const el = document.getElementById(`students-${cssId(classId)}`);
  if (!el) return;
  if (!el.classList.contains("hidden") && el.dataset.cohort === cohortId) {
    el.classList.add("hidden");
    el.innerHTML = "";
    return;
  }
  el.classList.remove("hidden");
  el.dataset.cohort = cohortId;
  el.innerHTML = `<div style="color:#666;font-size:11px">Carregando alunos...</div>`;

  const cacheKey = `${cohortId}`;
  let list = _studentsCache.get(cacheKey);
  if (!list) {
    const { data } = await sb.from("students")
      .select("id, name, phone, is_mentor, active")
      .eq("cohort_id", cohortId)
      .order("name");
    list = data || [];
    _studentsCache.set(cacheKey, list);
  }
  const eligible = list.filter((s) => s.active && !s.is_mentor && s.phone);
  const others = list.filter((s) => !(s.active && !s.is_mentor && s.phone));
  el.innerHTML = `
    <div style="color:#888;font-size:11px;margin-bottom:6px">📋 Cohort: ${escapeHtml(cohortId)} · Elegíveis: ${eligible.length} · Total: ${list.length}</div>
    ${eligible.map((s) => `<div class="student-line">✓ ${escapeHtml(s.name)} — ${escapeHtml(s.phone)}</div>`).join("")}
    ${others.length ? `<div style="color:#666;font-size:11px;margin-top:8px;border-top:1px solid #222;padding-top:6px">Não elegíveis (${others.length}):</div>` : ""}
    ${others.map((s) => {
      const reason = !s.active ? "inativo" : s.is_mentor ? "mentor" : "sem phone";
      return `<div class="student-line" style="color:#666">⊘ ${escapeHtml(s.name)} <span style="color:#444">(${reason})</span></div>`;
    }).join("")}
  `;
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

// ─── PRE-BRIEF GROUP DISPATCH MODAL ──────────────────────────────────
const PREBRIEF_GROUP_VARIANTS = [
  (className, timeStart) => `Bom dia, time.\n\nHoje rola *${className}*, ${timeStart} (Brasília).\n\nQuanto mais a sessão for sobre o que vocês estão construindo, mais valor ela gera. Reserva 30s pra contar o que precisa destravar:\nhttps://painel.academialendaria.ai/ps-rsvp`,
  (className, timeStart) => `Time, bom dia!\n\n*${className}* abre hoje às ${timeStart}. O foco do PS se ajusta às dúvidas que vocês trouxerem — vale separar 30s antes:\nhttps://painel.academialendaria.ai/ps-rsvp`,
  (className, timeStart) => `Bom dia.\n\nPS *${className}* — ${timeStart} (Brasília). Pra mentor chegar com pauta calibrada pro seu caso, conta o que está precisando trabalhar:\nhttps://painel.academialendaria.ai/ps-rsvp`,
  (className, timeStart) => `Time, hoje tem *${className}* às ${timeStart}.\n\nA sessão fica mais cirúrgica quando os pontos chegam antes. 30s pra preencher:\nhttps://painel.academialendaria.ai/ps-rsvp`,
  (className, timeStart) => `Bom dia, Lendários.\n\n*${className}* — ${timeStart} (Brasília). Compartilha o que está te travando hoje pra gente trazer resposta direcionada:\nhttps://painel.academialendaria.ai/ps-rsvp`,
];

const prebriefState = { groups: [] };

function brtWeekday() {
  const now = new Date();
  const brt = new Date(now.getTime() - 3 * 60 * 60 * 1000);
  return brt.getUTCDay();
}

async function openPrebriefModal() {
  const overlay = $("prebrief-modal");
  overlay.classList.remove("hidden");
  $("prebrief-loading").classList.remove("hidden");
  $("prebrief-list").classList.add("hidden");
  $("prebrief-empty").classList.add("hidden");
  $("prebrief-token-row").classList.add("hidden");
  $("prebrief-results").classList.add("hidden");
  $("prebrief-fire").disabled = true;
  $("prebrief-fire").textContent = "Disparar →";
  $("prebrief-results").innerHTML = "";

  const wd = brtWeekday();

  const { data: classes } = await sb.from("classes")
    .select("id, name, weekday, time_start")
    .eq("kind", "ps").eq("active", true).eq("weekday", wd)
    .order("name");

  if (!classes || classes.length === 0) {
    $("prebrief-loading").classList.add("hidden");
    $("prebrief-empty").classList.remove("hidden");
    $("prebrief-empty").textContent = `Nenhuma classe PS ativa para hoje (weekday=${wd}).`;
    return;
  }

  const classIds = classes.map((c) => c.id);
  const { data: bridges } = await sb.from("class_cohorts").select("class_id, cohort_id").in("class_id", classIds);
  const cohortIds = [...new Set((bridges || []).map((b) => b.cohort_id))];
  const { data: cohorts } = await sb.from("cohorts")
    .select("id, name, whatsapp_group_jid, whatsapp_group_name")
    .in("id", cohortIds.length > 0 ? cohortIds : ["00000000-0000-0000-0000-000000000000"])
    .not("whatsapp_group_jid", "is", null);

  const cohortMap = new Map();
  (cohorts || []).forEach((co) => cohortMap.set(co.id, co));

  prebriefState.groups = [];
  for (const c of classes) {
    const myCohortIds = (bridges || []).filter((b) => b.class_id === c.id).map((b) => b.cohort_id);
    for (const coId of myCohortIds) {
      const co = cohortMap.get(coId);
      if (!co || !co.whatsapp_group_jid) continue;
      const variantIdx = Math.floor(Math.random() * PREBRIEF_GROUP_VARIANTS.length);
      const timeStr = c.time_start ? c.time_start.slice(0, 5) : "";
      const text = PREBRIEF_GROUP_VARIANTS[variantIdx](c.name, timeStr);
      prebriefState.groups.push({
        key: `${c.id}__${coId}`,
        class_id: c.id, class_name: c.name, cohort_id: coId, cohort_name: co.name,
        group_jid: co.whatsapp_group_jid, group_name: co.whatsapp_group_name,
        text, selected: true, status: "pending",
      });
    }
  }

  $("prebrief-loading").classList.add("hidden");
  if (prebriefState.groups.length === 0) {
    $("prebrief-empty").classList.remove("hidden");
    $("prebrief-empty").textContent = "Classes PS encontradas mas sem cohorts com whatsapp_group_jid.";
    return;
  }

  $("prebrief-list").classList.remove("hidden");
  $("prebrief-token-row").classList.remove("hidden");
  renderPrebriefList();

  const cachedToken = sessionStorage.getItem("admin_one_shot_token") || "";
  $("prebrief-token").value = cachedToken;
  updatePrebriefFireBtn();
}

function renderPrebriefList() {
  const list = $("prebrief-list");
  list.innerHTML = prebriefState.groups.map((g) => `
    <div class="prebrief-group-card">
      <div class="group-head">
        <label>
          <input type="checkbox" data-key="${escapeHtml(g.key)}" ${g.selected ? "checked" : ""}>
          <div>
            <div class="group-title">${escapeHtml(g.class_name)} — ${escapeHtml(g.cohort_name)}</div>
            <div class="group-jid">${escapeHtml(g.group_name || "")} · ${escapeHtml(g.group_jid)}</div>
          </div>
        </label>
      </div>
      <div class="group-text">${escapeHtml(g.text)}</div>
    </div>
  `).join("");
  list.querySelectorAll('input[type="checkbox"]').forEach((cb) => {
    cb.addEventListener("change", () => {
      const g = prebriefState.groups.find((x) => x.key === cb.dataset.key);
      if (g) g.selected = cb.checked;
      updatePrebriefFireBtn();
    });
  });
}

function updatePrebriefFireBtn() {
  const token = $("prebrief-token").value.trim();
  const selected = prebriefState.groups.filter((g) => g.selected).length;
  $("prebrief-fire").disabled = !token || selected === 0;
  $("prebrief-fire").textContent = selected > 0 ? `Disparar para ${selected} grupo(s) →` : "Disparar →";
}

async function firePrebrief() {
  const token = $("prebrief-token").value.trim();
  if (!token) return;
  sessionStorage.setItem("admin_one_shot_token", token);
  const selected = prebriefState.groups.filter((g) => g.selected);
  if (!selected.length) return;

  $("prebrief-fire").disabled = true;
  $("prebrief-results").classList.remove("hidden");
  const res = $("prebrief-results");
  res.innerHTML = "Disparando...\n";

  for (const g of selected) {
    const start = Date.now();
    try {
      const r = await fetch(`${SUPABASE_URL}/functions/v1/admin-send-group-once`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-admin-token": token,
        },
        body: JSON.stringify({ group_jid: g.group_jid, text: g.text, cohort_id: g.cohort_id }),
      });
      const data = await r.json().catch(() => ({}));
      if (r.ok && data.ok) {
        g.status = "sent";
        res.innerHTML += `✅ ${g.cohort_name} — sent (${Date.now() - start}ms)\n`;
      } else {
        g.status = "failed";
        res.innerHTML += `❌ ${g.cohort_name} — ${r.status} ${JSON.stringify(data)}\n`;
      }
    } catch (e) {
      g.status = "failed";
      res.innerHTML += `❌ ${g.cohort_name} — ${e.message}\n`;
    }
    // 2s sleep between sends
    await new Promise((rsv) => setTimeout(rsv, 2000));
  }
  res.innerHTML += `\nFinalizado. Fechar modal para reset.\n`;
  $("prebrief-fire").disabled = false;
  $("prebrief-fire").textContent = "Fechar";
  $("prebrief-fire").onclick = closePrebriefModal;
}

function closePrebriefModal() {
  $("prebrief-modal").classList.add("hidden");
  $("prebrief-fire").onclick = firePrebrief;
}

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
  $("send-group-prebrief-btn")?.addEventListener("click", openPrebriefModal);
  $("prebrief-modal-close")?.addEventListener("click", closePrebriefModal);
  $("prebrief-cancel")?.addEventListener("click", closePrebriefModal);
  $("prebrief-fire")?.addEventListener("click", firePrebrief);
  $("prebrief-token")?.addEventListener("input", updatePrebriefFireBtn);
})();
