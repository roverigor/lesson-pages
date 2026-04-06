// ═══════════════════════════════════════
// SURVEYS — NPS/CSAT Management
// ═══════════════════════════════════════

const FUNCTIONS_URL = 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1';

// ─── State ───
let surveysList = [];
let surveysClasses = [];
let surveysDrawerData = null;

// ─── Init ───
async function loadSurveysView() {
  await Promise.all([fetchSurveysList(), fetchSurveysClasses()]);
  renderSurveysList();
}

async function fetchSurveysList() {
  const { data, error } = await sb
    .from('surveys')
    .select('*, cohorts(name), classes(name)')
    .order('created_at', { ascending: false });
  if (!error) surveysList = data ?? [];
}

async function fetchSurveysClasses() {
  const { data } = await sb.from('classes').select('id, name').order('name');
  surveysClasses = data ?? [];
}

// ─── Render List ───
function renderSurveysList() {
  const container = document.getElementById('surveys-list');
  if (!container) return;

  if (surveysList.length === 0) {
    container.innerHTML = `<div class="empty-state" style="text-align:center;color:#444;padding:48px 0">
      <div style="font-size:32px;margin-bottom:12px">📊</div>
      <div style="color:#666">Nenhuma avaliação criada ainda.</div>
    </div>`;
    return;
  }

  container.innerHTML = surveysList.map(s => {
    const typeColor = s.type === 'nps' ? '#6366f1' : '#f59e0b';
    const typeLabel = s.type === 'nps' ? 'NPS 0–10' : 'CSAT ★';
    const statusMap = { draft: { label: 'Rascunho', color: '#555' }, active: { label: 'Ativo', color: '#4ade80' }, closed: { label: 'Encerrado', color: '#f87171' } };
    const st = statusMap[s.status] || statusMap.draft;
    const turmaName = s.cohorts?.name || s.classes?.name || '—';
    const dispatched = s.dispatched_at ? new Date(s.dispatched_at).toLocaleDateString('pt-BR') : null;

    return `<div class="survey-card" data-id="${s.id}">
      <div class="survey-card-header">
        <div style="flex:1;min-width:0">
          <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap">
            <span style="font-size:14px;font-weight:700;color:#fff">${escHtml(s.name)}</span>
            <span style="font-size:10px;padding:2px 8px;border-radius:999px;background:rgba(99,102,241,.15);color:${typeColor};font-weight:700">${typeLabel}</span>
            <span style="font-size:10px;padding:2px 8px;border-radius:999px;border:1px solid #222;color:${st.color};font-weight:600">${st.label}</span>
          </div>
          <div style="font-size:12px;color:#555;margin-top:4px">${escHtml(turmaName)}${dispatched ? ` · Disparado em ${dispatched}` : ''}</div>
          <div style="font-size:11px;color:#444;margin-top:3px;white-space:nowrap;overflow:hidden;text-overflow:ellipsis">${escHtml(s.question)}</div>
        </div>
        <div style="display:flex;gap:6px;flex-shrink:0;flex-wrap:wrap;justify-content:flex-end">
          ${s.status !== 'closed' ? `<button class="btn-xs btn-primary" onclick="openDispatchModal('${s.id}')">Disparar</button>` : ''}
          <button class="btn-xs btn-ghost" onclick="openSurveysDrawer('${s.id}')">Ver Resultados</button>
          <button class="btn-xs btn-ghost" onclick="exportSurveyCSV('${s.id}')" title="Exportar CSV">CSV</button>
          <button class="btn-xs btn-ghost" onclick="exportSurveyMD('${s.id}')" title="Exportar MD">MD</button>
          ${s.status === 'active' ? `<button class="btn-xs btn-danger" onclick="closeSurvey('${s.id}')">Encerrar</button>` : ''}
        </div>
      </div>
    </div>`;
  }).join('');
}

// ─── Create Survey Modal ───
function openCreateSurveyModal() {
  const classOptions = surveysClasses.map(c => `<option value="${c.id}">${escHtml(c.name)}</option>`).join('');
  const html = `<div id="survey-create-modal" class="modal-overlay" onclick="if(event.target===this)closeSurveyModal()">
    <div class="modal-box" style="max-width:520px">
      <div class="modal-header">
        <span>Nova Avaliação</span>
        <button class="modal-close" onclick="closeSurveyModal()">×</button>
      </div>
      <div class="modal-body">
        <div class="form-group">
          <label class="form-label">Nome da avaliação</label>
          <input id="sv-name" class="form-input" type="text" placeholder="Ex: NPS Aula Advanced #7">
        </div>
        <div style="display:grid;grid-template-columns:1fr 1fr;gap:12px">
          <div class="form-group">
            <label class="form-label">Tipo</label>
            <select id="sv-type" class="form-input">
              <option value="nps">NPS (0–10)</option>
              <option value="csat">CSAT (1–5 estrelas)</option>
            </select>
          </div>
          <div class="form-group">
            <label class="form-label">Turma</label>
            <select id="sv-class" class="form-input">
              <option value="">Selecione...</option>
              ${classOptions}
            </select>
          </div>
        </div>
        <div class="form-group">
          <label class="form-label">Pergunta principal</label>
          <textarea id="sv-question" class="form-input" rows="2" placeholder="De 0 a 10, quanto você recomendaria esta aula?"></textarea>
        </div>
        <div class="form-group">
          <label class="form-label">Follow-up aberto <span style="color:#444">(opcional)</span></label>
          <textarea id="sv-followup" class="form-input" rows="2" placeholder="O que motivou sua nota?"></textarea>
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn-secondary" onclick="closeSurveyModal()">Cancelar</button>
        <button class="btn-primary" onclick="saveSurvey()">Criar Avaliação</button>
      </div>
    </div>
  </div>`;
  document.body.insertAdjacentHTML('beforeend', html);
}

function closeSurveyModal() {
  document.getElementById('survey-create-modal')?.remove();
}

async function saveSurvey() {
  const name     = document.getElementById('sv-name')?.value.trim();
  const type     = document.getElementById('sv-type')?.value;
  const classId  = document.getElementById('sv-class')?.value || null;
  const question = document.getElementById('sv-question')?.value.trim();
  const followUp = document.getElementById('sv-followup')?.value.trim() || null;

  if (!name || !question) { alert('Nome e pergunta são obrigatórios.'); return; }

  const { data: session } = await sb.auth.getSession();
  const email = session?.session?.user?.email || null;

  const { error } = await sb.from('surveys').insert({
    name, type, class_id: classId, question, follow_up: followUp,
    status: 'draft', created_by: email,
  });

  if (error) { alert('Erro ao criar: ' + error.message); return; }
  closeSurveyModal();
  await loadSurveysView();
}

// ─── Dispatch Modal ───
async function openDispatchModal(surveyId) {
  const survey = surveysList.find(s => s.id === surveyId);
  if (!survey) return;

  // Count students
  let studentCount = 0;
  if (survey.class_id) {
    const { data: bridges } = await sb.from('class_cohorts').select('cohort_id').eq('class_id', survey.class_id);
    if (bridges?.length) {
      const cohortIds = bridges.map(b => b.cohort_id);
      const { count } = await sb.from('students').select('id', { count: 'exact', head: true })
        .in('cohort_id', cohortIds).eq('active', true).eq('is_mentor', false);
      studentCount = count ?? 0;
    }
  }

  const html = `<div id="survey-dispatch-modal" class="modal-overlay" onclick="if(event.target===this)closeDispatchModal()">
    <div class="modal-box" style="max-width:420px">
      <div class="modal-header">
        <span>Disparar Avaliação</span>
        <button class="modal-close" onclick="closeDispatchModal()">×</button>
      </div>
      <div class="modal-body">
        <p style="color:#ccc;margin-bottom:12px">Isso enviará um link de avaliação via WhatsApp para <strong style="color:#fff">${studentCount} aluno(s)</strong> da turma.</p>
        <div style="background:#111;border:1px solid #1e1e1e;border-radius:8px;padding:12px;font-size:12px;color:#666">
          <strong style="color:#888">Survey:</strong> ${escHtml(survey.name)}<br>
          <strong style="color:#888">Tipo:</strong> ${survey.type.toUpperCase()}<br>
          <strong style="color:#888">Pergunta:</strong> ${escHtml(survey.question)}
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn-secondary" onclick="closeDispatchModal()">Cancelar</button>
        <button class="btn-primary" onclick="confirmDispatch('${surveyId}')" id="dispatch-confirm-btn">Enviar via WhatsApp</button>
      </div>
    </div>
  </div>`;
  document.body.insertAdjacentHTML('beforeend', html);
}

function closeDispatchModal() {
  document.getElementById('survey-dispatch-modal')?.remove();
}

async function confirmDispatch(surveyId) {
  const btn = document.getElementById('dispatch-confirm-btn');
  if (btn) { btn.disabled = true; btn.textContent = 'Enviando...'; }

  const { data: { session } } = await sb.auth.getSession();
  const token = session?.access_token;

  const res = await fetch(`${FUNCTIONS_URL}/dispatch-survey`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${token}` },
    body: JSON.stringify({ survey_id: surveyId }),
  });

  const result = await res.json();
  closeDispatchModal();

  if (result.success) {
    showToast(`✅ Disparado para ${result.dispatched} aluno(s). ${result.skipped > 0 ? `${result.skipped} sem telefone.` : ''}`);
  } else {
    showToast(`❌ Erro: ${result.error || 'falha no disparo'}`, 'error');
  }

  await loadSurveysView();
}

// ─── Close Survey ───
async function closeSurvey(surveyId) {
  if (!confirm('Encerrar esta avaliação? Nenhum novo link poderá ser respondido.')) return;
  const { error } = await sb.from('surveys').update({ status: 'closed' }).eq('id', surveyId);
  if (error) { showToast('❌ Erro ao encerrar', 'error'); return; }
  await loadSurveysView();
}

// ─── Results Drawer ───
async function openSurveysDrawer(surveyId) {
  const survey = surveysList.find(s => s.id === surveyId);
  if (!survey) return;

  // Fetch responses
  const { data: responses } = await sb
    .from('student_nps')
    .select('score, feedback, responded_at, students(name, phone)')
    .eq('survey_id', surveyId)
    .order('responded_at', { ascending: false });

  // Fetch total links
  const { count: totalLinks } = await sb
    .from('survey_links')
    .select('id', { count: 'exact', head: true })
    .eq('survey_id', surveyId);

  surveysDrawerData = { survey, responses: responses ?? [], totalLinks: totalLinks ?? 0 };

  const r = responses ?? [];
  const totalLinks_ = totalLinks ?? 0;
  const typeLabel = survey.type === 'nps' ? 'NPS' : 'CSAT';
  const turmaName = survey.cohorts?.name || survey.classes?.name || '—';

  let scoreHTML = '';
  if (survey.type === 'nps') {
    const promoters   = r.filter(x => x.score >= 9).length;
    const detractors  = r.filter(x => x.score <= 6).length;
    const total       = r.length;
    const npsScore    = total > 0 ? Math.round(((promoters - detractors) / total) * 100) : null;
    const scoreColor  = npsScore === null ? '#444' : npsScore >= 50 ? '#4ade80' : npsScore >= 0 ? '#f59e0b' : '#f87171';

    const distCounts = Array.from({ length: 11 }, (_, i) => r.filter(x => x.score === i).length);
    const maxCount   = Math.max(...distCounts, 1);
    const distBars   = distCounts.map((c, i) => {
      const pct   = Math.round((c / maxCount) * 100);
      const color = i <= 6 ? '#f87171' : i <= 8 ? '#f59e0b' : '#4ade80';
      return `<div style="flex:1;display:flex;flex-direction:column;align-items:center;gap:3px">
        <div style="font-size:9px;color:#555">${c > 0 ? c : ''}</div>
        <div style="height:40px;width:100%;display:flex;align-items:flex-end">
          <div style="width:100%;height:${pct}%;background:${color};border-radius:3px 3px 0 0;min-height:${c>0?'4px':'0'}"></div>
        </div>
        <div style="font-size:9px;color:#444">${i}</div>
      </div>`;
    }).join('');

    scoreHTML = `
      <div style="display:flex;align-items:center;gap:16px;margin-bottom:16px">
        <div>
          <div style="font-size:11px;color:#555;text-transform:uppercase;letter-spacing:.06em">NPS Score</div>
          <div style="font-size:42px;font-weight:800;color:${scoreColor};line-height:1">${npsScore !== null ? npsScore : '—'}</div>
        </div>
        <div style="flex:1;display:grid;grid-template-columns:repeat(3,1fr);gap:8px">
          <div style="text-align:center;background:#0d0d0d;border:1px solid #1e1e1e;border-radius:8px;padding:8px">
            <div style="font-size:18px;font-weight:700;color:#4ade80">${promoters}</div>
            <div style="font-size:10px;color:#555">Promotores<br>9–10</div>
          </div>
          <div style="text-align:center;background:#0d0d0d;border:1px solid #1e1e1e;border-radius:8px;padding:8px">
            <div style="font-size:18px;font-weight:700;color:#f59e0b">${r.filter(x => x.score >= 7 && x.score <= 8).length}</div>
            <div style="font-size:10px;color:#555">Neutros<br>7–8</div>
          </div>
          <div style="text-align:center;background:#0d0d0d;border:1px solid #1e1e1e;border-radius:8px;padding:8px">
            <div style="font-size:18px;font-weight:700;color:#f87171">${detractors}</div>
            <div style="font-size:10px;color:#555">Detratores<br>0–6</div>
          </div>
        </div>
      </div>
      <div style="display:flex;gap:2px;margin-bottom:16px;height:60px;align-items:flex-end">${distBars}</div>`;
  } else {
    const total   = r.length;
    const avg     = total > 0 ? (r.reduce((s, x) => s + x.score, 0) / total).toFixed(1) : null;
    const avgColor = avg === null ? '#444' : avg >= 4 ? '#4ade80' : avg >= 3 ? '#f59e0b' : '#f87171';

    const distBars = [1,2,3,4,5].map(i => {
      const count = r.filter(x => x.score === i).length;
      const pct = total > 0 ? Math.round((count / total) * 100) : 0;
      const stars = '★'.repeat(i) + '☆'.repeat(5 - i);
      return `<div style="display:flex;align-items:center;gap:8px;margin-bottom:6px">
        <div style="font-size:12px;color:#f59e0b;min-width:60px">${stars}</div>
        <div style="flex:1;background:#1a1a1a;border-radius:3px;height:8px;overflow:hidden">
          <div style="width:${pct}%;height:100%;background:#f59e0b;border-radius:3px"></div>
        </div>
        <div style="font-size:11px;color:#555;min-width:30px;text-align:right">${count}</div>
      </div>`;
    }).join('');

    scoreHTML = `
      <div style="display:flex;align-items:center;gap:16px;margin-bottom:16px">
        <div>
          <div style="font-size:11px;color:#555;text-transform:uppercase;letter-spacing:.06em">Média CSAT</div>
          <div style="font-size:42px;font-weight:800;color:${avgColor};line-height:1">${avg ?? '—'}</div>
          <div style="font-size:11px;color:#555">de 5.0</div>
        </div>
        <div style="flex:1">${distBars}</div>
      </div>`;
  }

  const comments = r.filter(x => x.feedback).map(x =>
    `<div style="background:#0d0d0d;border-left:2px solid #222;padding:10px 14px;margin-bottom:8px;border-radius:0 6px 6px 0">
      <div style="font-size:12px;color:#888;line-height:1.6">${escHtml(x.feedback)}</div>
      <div style="font-size:10px;color:#333;margin-top:4px">${x.students?.name ?? 'Anônimo'} · ${new Date(x.responded_at).toLocaleDateString('pt-BR')}</div>
    </div>`
  ).join('') || '<div style="color:#444;font-size:12px">Nenhum comentário ainda.</div>';

  const html = `<div id="surveys-drawer-overlay" style="position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:1000;display:flex;justify-content:flex-end" onclick="if(event.target===this)closeSurveysDrawer()">
    <div style="width:min(560px,100vw);background:#0d0d0d;border-left:1px solid #1e1e1e;overflow-y:auto;padding:24px">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:20px">
        <div>
          <div style="font-size:16px;font-weight:700;color:#fff">${escHtml(survey.name)}</div>
          <div style="font-size:12px;color:#555">${turmaName} · ${typeLabel} · ${r.length}/${totalLinks_} responderam</div>
        </div>
        <div style="display:flex;gap:6px;align-items:center">
          <button class="btn-xs btn-ghost" onclick="exportSurveyCSV('${surveyId}')">⬇ CSV</button>
          <button class="btn-xs btn-ghost" onclick="exportSurveyMD('${surveyId}')">⬇ MD</button>
          <button onclick="closeSurveysDrawer()" style="background:none;border:none;color:#555;font-size:20px;cursor:pointer;line-height:1">×</button>
        </div>
      </div>
      ${scoreHTML}
      <div style="font-size:11px;font-weight:700;color:#444;text-transform:uppercase;letter-spacing:.06em;margin-bottom:10px">Comentários (${r.filter(x=>x.feedback).length})</div>
      ${comments}
    </div>
  </div>`;
  document.body.insertAdjacentHTML('beforeend', html);
}

function closeSurveysDrawer() {
  document.getElementById('surveys-drawer-overlay')?.remove();
}

// ─── Export ───
async function getSurveyExportData(surveyId) {
  const survey = surveysList.find(s => s.id === surveyId);
  if (!survey) return null;

  const { data: responses } = await sb
    .from('student_nps')
    .select('score, feedback, responded_at, students(name, phone)')
    .eq('survey_id', surveyId)
    .order('responded_at', { ascending: false });

  const turmaName = survey.cohorts?.name || survey.classes?.name || '';
  return { survey, responses: responses ?? [], turmaName };
}

async function exportSurveyCSV(surveyId) {
  const data = await getSurveyExportData(surveyId);
  if (!data) return;

  const { survey, responses, turmaName } = data;
  const header = 'data_resposta,nome_aluno,telefone,turma,tipo,nota,comentario';
  const rows = responses.map(r => {
    const date    = r.responded_at ? new Date(r.responded_at).toLocaleDateString('pt-BR') : '';
    const name    = csvCell(r.students?.name ?? '');
    const phone   = csvCell(r.students?.phone ?? '');
    const turma   = csvCell(turmaName);
    const tipo    = survey.type;
    const score   = r.score;
    const comment = csvCell(r.feedback ?? '');
    return `${date},${name},${phone},${turma},${tipo},${score},${comment}`;
  }).join('\n');

  const content = header + '\n' + rows;
  const dateStr = new Date().toISOString().slice(0, 10);
  downloadFile(`avaliacao-${slugify(survey.name)}-${dateStr}.csv`, content, 'text/csv;charset=utf-8;');
}

async function exportSurveyMD(surveyId) {
  const data = await getSurveyExportData(surveyId);
  if (!data) return;

  const { survey, responses, turmaName } = data;
  const dateStr = new Date().toLocaleDateString('pt-BR');

  let score = '—';
  if (responses.length > 0) {
    if (survey.type === 'nps') {
      const promoters  = responses.filter(r => r.score >= 9).length;
      const detractors = responses.filter(r => r.score <= 6).length;
      score = `NPS ${Math.round(((promoters - detractors) / responses.length) * 100)}`;
    } else {
      const avg = responses.reduce((s, r) => s + r.score, 0) / responses.length;
      score = `CSAT ${avg.toFixed(1)}/5`;
    }
  }

  const tableRows = responses.map(r =>
    `| ${r.responded_at ? new Date(r.responded_at).toLocaleDateString('pt-BR') : ''} | ${r.students?.name ?? 'Anônimo'} | ${r.score} | ${(r.feedback ?? '').replace(/\|/g, '\\|').replace(/\n/g, ' ')} |`
  ).join('\n');

  const comments = responses.filter(r => r.feedback).map(r =>
    `- **${r.students?.name ?? 'Anônimo'}** (nota ${r.score}): ${r.feedback}`
  ).join('\n');

  const md = `# ${survey.name}

**Turma:** ${turmaName}
**Tipo:** ${survey.type.toUpperCase()}
**Score:** ${score}
**Respostas:** ${responses.length}
**Exportado em:** ${dateStr}

---

## Pergunta

> ${survey.question}

${survey.follow_up ? `**Follow-up:** ${survey.follow_up}\n` : ''}

---

## Respostas

| Data | Aluno | Nota | Comentário |
|------|-------|------|------------|
${tableRows}

---

## Comentários

${comments || '_Nenhum comentário registrado._'}
`;

  const exportDate = new Date().toISOString().slice(0, 10);
  downloadFile(`avaliacao-${slugify(survey.name)}-${exportDate}.md`, md, 'text/markdown;charset=utf-8;');
}

// ─── Helpers ───
function csvCell(val) {
  if (!val) return '';
  const s = String(val).replace(/"/g, '""');
  return /[,"\n]/.test(s) ? `"${s}"` : s;
}

function slugify(str) {
  return str.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
}

function downloadFile(filename, content, mimeType) {
  const blob = new Blob(['\uFEFF' + content], { type: mimeType });
  const url  = URL.createObjectURL(blob);
  const a    = document.createElement('a');
  a.href = url; a.download = filename; a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

function escHtml(str) {
  return String(str ?? '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function showToast(msg, type = 'success') {
  const el = document.createElement('div');
  el.style.cssText = `position:fixed;bottom:24px;right:24px;background:${type==='error'?'#7f1d1d':'#14532d'};color:#fff;padding:12px 18px;border-radius:8px;font-size:13px;z-index:9999;max-width:320px`;
  el.textContent = msg;
  document.body.appendChild(el);
  setTimeout(() => el.remove(), 4000);
}
