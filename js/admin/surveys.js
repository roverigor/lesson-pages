// ═══════════════════════════════════════
// SURVEYS — Form Builder & Management
// ═══════════════════════════════════════

const FUNCTIONS_URL = 'https://gpufcipkajppykmnmdeh.supabase.co/functions/v1';

// ─── State ───
let surveysList   = [];
let surveysCohorts = [];
let builderSurveyId = null;   // survey being created/edited
let builderQuestions = [];    // local question list during editing

const Q_TYPES = {
  nps:    { label: 'NPS (0–10)',          icon: '📊', color: '#6366f1' },
  csat:   { label: 'CSAT (estrelas)',     icon: '⭐', color: '#f59e0b' },
  text:   { label: 'Texto livre',         icon: '✏️',  color: '#10b981' },
  choice: { label: 'Múltipla escolha',    icon: '🔘', color: '#06b6d4' },
  multi:  { label: 'Caixas de seleção',   icon: '☑️',  color: '#8b5cf6' },
  scale:  { label: 'Escala numérica',     icon: '🔢', color: '#f97316' },
};

// ─── Init ───
async function loadSurveysView() {
  await Promise.all([fetchSurveysList(), fetchSurveysCohorts()]);
  renderSurveysList();
}

async function fetchSurveysList() {
  const { data } = await sb.from('surveys')
    .select('*, cohorts(name), classes(name)')
    .order('created_at', { ascending: false });
  surveysList = data ?? [];
}

async function fetchSurveysCohorts() {
  const { data } = await sb.from('cohorts').select('id, name').eq('active', true).order('name');
  surveysCohorts = data ?? [];
}

// ─── Surveys List ───
function renderSurveysList() {
  const container = document.getElementById('surveys-list');
  if (!container) return;

  if (surveysList.length === 0) {
    container.innerHTML = `<div style="text-align:center;color:#444;padding:60px 0">
      <div style="font-size:40px;margin-bottom:16px">📋</div>
      <div style="color:#666;font-size:14px">Nenhum formulário criado ainda.</div>
      <div style="color:#444;font-size:12px;margin-top:6px">Clique em "+ Novo Formulário" para começar.</div>
    </div>`;
    return;
  }

  container.innerHTML = surveysList.map(s => {
    const statusMap = {
      draft:  { label: 'Rascunho', color: '#666',    bg: '#1a1a1a' },
      active: { label: 'Ativo',    color: '#4ade80', bg: 'rgba(74,222,128,.08)' },
      closed: { label: 'Encerrado',color: '#f87171', bg: 'rgba(248,113,113,.08)' },
    };
    const st = statusMap[s.status] || statusMap.draft;
    const turma = s.cohorts?.name || s.classes?.name || '—';
    const dispatched = s.dispatched_at ? new Date(s.dispatched_at).toLocaleDateString('pt-BR') : null;

    return `<div class="survey-card" data-id="${s.id}">
      <div class="survey-card-header">
        <div style="flex:1;min-width:0">
          <div style="display:flex;align-items:center;gap:8px;flex-wrap:wrap;margin-bottom:4px">
            <span style="font-size:14px;font-weight:700;color:#fff">${escHtml(s.name)}</span>
            <span style="font-size:10px;padding:2px 9px;border-radius:999px;border:1px solid;color:${st.color};border-color:${st.color}40;background:${st.bg};font-weight:700">${st.label}</span>
          </div>
          <div style="font-size:12px;color:#555">${escHtml(turma)}${dispatched ? ` · Disparado ${dispatched}` : ''}</div>
        </div>
        <div style="display:flex;gap:6px;flex-wrap:wrap;justify-content:flex-end;align-items:center">
          ${s.status === 'draft' ? `<button class="btn-xs btn-ghost" onclick="openBuilder('${s.id}')">✏️ Editar</button>` : ''}
          ${s.status !== 'closed' ? `<button class="btn-xs btn-primary" onclick="openDispatchModal('${s.id}')">📤 Disparar</button>` : ''}
          <button class="btn-xs btn-ghost" onclick="openSurveysDrawer('${s.id}')">📈 Resultados</button>
          <button class="btn-xs btn-ghost" onclick="exportSurveyCSV('${s.id}')" title="CSV">CSV</button>
          <button class="btn-xs btn-ghost" onclick="exportSurveyMD('${s.id}')" title="MD">MD</button>
          ${s.status === 'active' ? `<button class="btn-xs btn-danger" onclick="closeSurvey('${s.id}')">Encerrar</button>` : ''}
        </div>
      </div>
    </div>`;
  }).join('');
}

// ═══════════════════════════════════════
// FORM BUILDER
// ═══════════════════════════════════════

function openBuilder(surveyId) {
  builderSurveyId = surveyId || null;
  builderQuestions = [];
  renderBuilder();
  if (surveyId) loadBuilderData(surveyId);
}

async function loadBuilderData(surveyId) {
  const [{ data: survey }, { data: questions }] = await Promise.all([
    sb.from('surveys').select('*').eq('id', surveyId).single(),
    sb.from('survey_questions').select('*').eq('survey_id', surveyId).order('position'),
  ]);

  if (survey) {
    document.getElementById('bld-name').value      = survey.name || '';
    document.getElementById('bld-cohort').value    = survey.cohort_id || '';
    document.getElementById('bld-intro').value     = survey.intro_text || '';
  }
  builderQuestions = (questions || []).map(q => ({
    id: q.id, type: q.type, label: q.label, required: q.required,
    options: q.options || [], scale_max: q.scale_max || 5, placeholder: q.placeholder || '',
    _saved: true,
  }));
  renderQuestionList();
}

function renderBuilder() {
  const cohortOptions = surveysCohorts.map(c =>
    `<option value="${c.id}">${escHtml(c.name)}</option>`
  ).join('');

  const html = `<div id="survey-builder" style="background:#0d0d0d;border:1px solid #1e1e1e;border-radius:16px;padding:28px;margin-bottom:24px">

    <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:24px">
      <div style="font-size:16px;font-weight:800;color:#fff">${builderSurveyId ? 'Editar Formulário' : 'Novo Formulário'}</div>
      <button onclick="closeBuilder()" style="background:none;border:none;color:#555;font-size:22px;cursor:pointer;line-height:1">×</button>
    </div>

    <!-- Step 1: Config -->
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:14px;margin-bottom:20px">
      <div class="form-group" style="margin:0">
        <label class="form-label">Nome do formulário *</label>
        <input id="bld-name" class="form-input" type="text" placeholder="Ex: Avaliação Aula Advanced #8">
      </div>
      <div class="form-group" style="margin:0">
        <label class="form-label">Turma (destinatários)</label>
        <select id="bld-cohort" class="form-input">
          <option value="">— Selecione uma turma —</option>
          ${cohortOptions}
        </select>
      </div>
    </div>
    <div class="form-group">
      <label class="form-label">Mensagem de boas-vindas <span style="color:#444">(opcional)</span></label>
      <textarea id="bld-intro" class="form-input" rows="2" placeholder="Olá! Esta avaliação leva menos de 2 minutos..."></textarea>
    </div>

    <!-- Step 2: Questions -->
    <div style="border-top:1px solid #1a1a1a;padding-top:20px;margin-top:4px">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:14px">
        <div style="font-size:12px;font-weight:700;color:#666;text-transform:uppercase;letter-spacing:.06em">Perguntas</div>
        <button onclick="openQTypePicker()" style="background:rgba(99,102,241,.12);border:1px dashed #6366f1;color:#a5b4fc;font-size:12px;font-weight:700;padding:6px 14px;border-radius:8px;cursor:pointer">+ Adicionar pergunta</button>
      </div>
      <div id="bld-question-list" style="min-height:48px"></div>
    </div>

    <!-- Footer -->
    <div style="display:flex;gap:8px;justify-content:flex-end;margin-top:20px;padding-top:16px;border-top:1px solid #1a1a1a">
      <button onclick="closeBuilder()" class="btn-secondary">Cancelar</button>
      <button onclick="previewBuilder()" class="btn-ghost-outline">👁 Preview</button>
      <button onclick="saveBuilder()" class="btn-primary">💾 Salvar rascunho</button>
    </div>
  </div>`;

  const container = document.getElementById('surveys-list');
  container.insertAdjacentHTML('beforebegin', html);
  renderQuestionList();
}

function closeBuilder() {
  document.getElementById('survey-builder')?.remove();
  builderSurveyId = null;
  builderQuestions = [];
}

// ─── Question List ───
function renderQuestionList() {
  const el = document.getElementById('bld-question-list');
  if (!el) return;

  if (!builderQuestions.length) {
    el.innerHTML = `<div style="text-align:center;color:#333;font-size:12px;padding:24px;border:1px dashed #1e1e1e;border-radius:10px">
      Nenhuma pergunta adicionada. Clique em "+ Adicionar pergunta" acima.
    </div>`;
    return;
  }

  el.innerHTML = builderQuestions.map((q, i) => {
    const qt = Q_TYPES[q.type] || { label: q.type, icon: '?', color: '#666' };
    const hasOptions = q.type === 'choice' || q.type === 'multi';
    const optHTML = hasOptions
      ? `<div style="margin-top:10px">
          <div style="font-size:10px;color:#444;margin-bottom:6px">Opções:</div>
          <div id="opts-${i}" style="display:flex;flex-direction:column;gap:4px">
            ${(q.options || []).map((o, oi) => `
              <div style="display:flex;gap:6px;align-items:center">
                <input class="form-input" style="padding:5px 10px;flex:1" value="${escHtml(o)}"
                  oninput="updateOption(${i},${oi},this.value)" placeholder="Opção ${oi+1}">
                <button onclick="removeOption(${i},${oi})" style="background:none;border:none;color:#555;cursor:pointer;font-size:16px;line-height:1">×</button>
              </div>`).join('')}
          </div>
          <button onclick="addOption(${i})" style="margin-top:6px;background:none;border:1px dashed #333;color:#555;font-size:11px;padding:4px 10px;border-radius:5px;cursor:pointer">+ Opção</button>
        </div>` : '';

    const scaleHTML = q.type === 'scale'
      ? `<div style="margin-top:10px;display:flex;align-items:center;gap:8px">
          <span style="font-size:11px;color:#555">Máximo:</span>
          <select class="form-input" style="width:80px;padding:4px 8px" onchange="updateQuestion(${i},'scale_max',parseInt(this.value))">
            ${[5,7,10].map(n => `<option value="${n}" ${q.scale_max===n?'selected':''}>${n}</option>`).join('')}
          </select>
        </div>` : '';

    const textHTML = q.type === 'text'
      ? `<div style="margin-top:10px">
          <input class="form-input" style="padding:5px 10px" placeholder="Placeholder (opcional)"
            value="${escHtml(q.placeholder||'')}" oninput="updateQuestion(${i},'placeholder',this.value)">
        </div>` : '';

    return `<div class="q-card" style="background:#111;border:1px solid #1e1e1e;border-radius:10px;padding:14px 16px;margin-bottom:8px">
      <div style="display:flex;align-items:flex-start;gap:10px">
        <div style="flex:1;min-width:0">
          <div style="display:flex;align-items:center;gap:6px;margin-bottom:8px;flex-wrap:wrap">
            <span style="font-size:10px;font-weight:700;padding:2px 8px;border-radius:999px;background:${qt.color}22;color:${qt.color}">${qt.icon} ${qt.label}</span>
            <span style="font-size:10px;color:#444">#${i+1}</span>
            <label style="display:flex;align-items:center;gap:4px;font-size:10px;color:#555;cursor:pointer;margin-left:auto">
              <input type="checkbox" ${q.required?'checked':''} onchange="updateQuestion(${i},'required',this.checked)" style="cursor:pointer">
              Obrigatória
            </label>
          </div>
          <textarea class="form-input" rows="2" style="font-size:13px"
            placeholder="Digite a pergunta..."
            oninput="updateQuestion(${i},'label',this.value)">${escHtml(q.label)}</textarea>
          ${optHTML}${scaleHTML}${textHTML}
        </div>
        <div style="display:flex;flex-direction:column;gap:4px;flex-shrink:0">
          <button onclick="moveQuestion(${i},-1)" ${i===0?'disabled':''} style="background:none;border:1px solid #222;color:#555;width:28px;height:28px;border-radius:5px;cursor:pointer;font-size:13px">▲</button>
          <button onclick="moveQuestion(${i},1)"  ${i===builderQuestions.length-1?'disabled':''} style="background:none;border:1px solid #222;color:#555;width:28px;height:28px;border-radius:5px;cursor:pointer;font-size:13px">▼</button>
          <button onclick="removeQuestion(${i})" style="background:none;border:1px solid #3f1212;color:#f87171;width:28px;height:28px;border-radius:5px;cursor:pointer;font-size:13px">✕</button>
        </div>
      </div>
    </div>`;
  }).join('');
}

// ─── Question Type Picker ───
function openQTypePicker() {
  const html = `<div id="qtype-picker" style="position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:2000;display:flex;align-items:center;justify-content:center" onclick="if(event.target===this)closeQTypePicker()">
    <div style="background:#0f0f0f;border:1px solid #222;border-radius:16px;padding:24px;width:min(480px,95vw)">
      <div style="font-size:14px;font-weight:700;color:#fff;margin-bottom:16px">Escolha o tipo de pergunta</div>
      <div style="display:grid;grid-template-columns:1fr 1fr;gap:8px">
        ${Object.entries(Q_TYPES).map(([type, cfg]) => `
          <button onclick="addQuestion('${type}')" style="background:#111;border:1px solid #1e1e1e;border-radius:10px;padding:14px;text-align:left;cursor:pointer;transition:border-color .15s" onmouseover="this.style.borderColor='${cfg.color}'" onmouseout="this.style.borderColor='#1e1e1e'">
            <div style="font-size:18px;margin-bottom:6px">${cfg.icon}</div>
            <div style="font-size:12px;font-weight:700;color:#fff">${cfg.label}</div>
            <div style="font-size:10px;color:#555;margin-top:2px">${typeDesc(type)}</div>
          </button>`).join('')}
      </div>
      <button onclick="closeQTypePicker()" style="margin-top:16px;width:100%;padding:9px;border-radius:8px;border:1px solid #222;background:transparent;color:#666;font-size:13px;cursor:pointer">Cancelar</button>
    </div>
  </div>`;
  document.body.insertAdjacentHTML('beforeend', html);
}

function typeDesc(type) {
  const d = { nps:'Escala 0 a 10', csat:'1 a 5 estrelas', text:'Campo de texto aberto', choice:'Uma opção', multi:'Várias opções', scale:'Escala numérica customizada' };
  return d[type] || '';
}

function closeQTypePicker() { document.getElementById('qtype-picker')?.remove(); }

function addQuestion(type) {
  closeQTypePicker();
  builderQuestions.push({
    id: null, type, label: '', required: true,
    options: type === 'choice' || type === 'multi' ? ['', ''] : [],
    scale_max: 5, placeholder: '', _saved: false,
  });
  renderQuestionList();
  // Scroll to new question
  const cards = document.querySelectorAll('.q-card');
  cards[cards.length - 1]?.scrollIntoView({ behavior: 'smooth', block: 'nearest' });
}

function removeQuestion(i) {
  builderQuestions.splice(i, 1);
  renderQuestionList();
}

function moveQuestion(i, dir) {
  const j = i + dir;
  if (j < 0 || j >= builderQuestions.length) return;
  [builderQuestions[i], builderQuestions[j]] = [builderQuestions[j], builderQuestions[i]];
  renderQuestionList();
}

function updateQuestion(i, field, value) {
  if (builderQuestions[i]) builderQuestions[i][field] = value;
}

function addOption(qi) {
  builderQuestions[qi].options = [...(builderQuestions[qi].options || []), ''];
  renderQuestionList();
}

function removeOption(qi, oi) {
  builderQuestions[qi].options.splice(oi, 1);
  renderQuestionList();
}

function updateOption(qi, oi, value) {
  if (builderQuestions[qi]) builderQuestions[qi].options[oi] = value;
}

// ─── Save Builder ───
async function saveBuilder() {
  const name      = document.getElementById('bld-name')?.value.trim();
  const cohortId  = document.getElementById('bld-cohort')?.value || null;
  const introText = document.getElementById('bld-intro')?.value.trim() || null;

  if (!name) { showToast('Nome do formulário é obrigatório', 'error'); return; }

  // Validate questions
  for (const [i, q] of builderQuestions.entries()) {
    if (!q.label.trim()) { showToast(`Pergunta #${i+1} sem texto`, 'error'); return; }
    if ((q.type === 'choice' || q.type === 'multi') && q.options.filter(o => o.trim()).length < 2) {
      showToast(`Pergunta #${i+1}: adicione ao menos 2 opções`, 'error'); return;
    }
  }

  // Determine survey type
  const types = [...new Set(builderQuestions.map(q => q.type))];
  const surveyType = types.length === 1 && ['nps','csat'].includes(types[0]) ? types[0] : 'mixed';

  const { data: session } = await sb.auth.getSession();
  const email = session?.session?.user?.email || null;

  let surveyId = builderSurveyId;

  if (surveyId) {
    // Update existing
    await sb.from('surveys').update({ name, cohort_id: cohortId, intro_text: introText, type: surveyType }).eq('id', surveyId);
  } else {
    // Create new
    const { data: created } = await sb.from('surveys').insert({
      name, type: surveyType, cohort_id: cohortId, intro_text: introText,
      status: 'draft', created_by: email,
    }).select('id').single();
    if (!created) { showToast('Erro ao criar formulário', 'error'); return; }
    surveyId = created.id;
    builderSurveyId = surveyId;
  }

  // Sync questions: delete all, re-insert in order
  await sb.from('survey_questions').delete().eq('survey_id', surveyId);

  if (builderQuestions.length > 0) {
    const rows = builderQuestions.map((q, i) => ({
      survey_id: surveyId,
      position: i,
      type: q.type,
      label: q.label.trim(),
      required: q.required,
      options: (q.type === 'choice' || q.type === 'multi') ? q.options.filter(o => o.trim()) : null,
      scale_max: q.type === 'scale' ? (q.scale_max || 5) : null,
      placeholder: q.type === 'text' ? (q.placeholder || null) : null,
    }));
    const { error } = await sb.from('survey_questions').insert(rows);
    if (error) { showToast('Erro ao salvar perguntas: ' + error.message, 'error'); return; }
  }

  showToast('✅ Formulário salvo!', 'success');
  closeBuilder();
  await loadSurveysView();
}

// ─── Preview ───
function previewBuilder() {
  const name  = document.getElementById('bld-name')?.value || 'Preview';
  const intro = document.getElementById('bld-intro')?.value || '';

  const screenHTML = (content) =>
    `<div style="background:#0f0f0f;border:1px solid #1e1e1e;border-radius:14px;padding:28px 24px;margin-bottom:10px">${content}</div>`;

  const questionPreviews = builderQuestions.map((q, i) => {
    const qt = Q_TYPES[q.type] || { icon: '?', label: q.type };
    let widget = '';
    if (q.type === 'nps') {
      widget = `<div style="display:flex;gap:4px;flex-wrap:wrap;margin-top:14px">${Array.from({length:11},(_,n)=>`<div style="width:36px;height:36px;display:flex;align-items:center;justify-content:center;border:1px solid #222;border-radius:7px;font-size:12px;font-weight:700;color:#555">${n}</div>`).join('')}</div><div style="display:flex;justify-content:space-between;font-size:10px;color:#444;margin-top:5px"><span>Nada satisfeito</span><span>Muito satisfeito</span></div>`;
    } else if (q.type === 'csat') {
      widget = `<div style="display:flex;gap:10px;margin-top:14px;justify-content:center">${'★★★★★'.split('').map(s=>`<span style="font-size:36px;color:#333">${s}</span>`).join('')}</div>`;
    } else if (q.type === 'text') {
      widget = `<textarea style="width:100%;margin-top:12px;background:#0d0d0d;border:1px solid #1e1e1e;border-radius:8px;padding:10px;color:#555;font-size:13px;resize:none;height:80px" placeholder="${escHtml(q.placeholder||'Sua resposta...')}" disabled></textarea>`;
    } else if (q.type === 'choice' || q.type === 'multi') {
      widget = `<div style="margin-top:12px;display:flex;flex-direction:column;gap:7px">${(q.options||[]).map(o=>`<div style="display:flex;align-items:center;gap:8px;padding:9px 12px;background:#0d0d0d;border:1px solid #1e1e1e;border-radius:8px"><div style="width:14px;height:14px;border:2px solid #333;border-radius:${q.type==='multi'?'3px':'50%'}"></div><span style="font-size:13px;color:#888">${escHtml(o||'Opção')}</span></div>`).join('')}</div>`;
    } else if (q.type === 'scale') {
      const max = q.scale_max || 5;
      widget = `<div style="display:flex;gap:6px;margin-top:14px;flex-wrap:wrap">${Array.from({length:max},(_,n)=>`<div style="flex:1;min-width:36px;height:36px;display:flex;align-items:center;justify-content:center;border:1px solid #222;border-radius:7px;font-size:12px;font-weight:700;color:#555">${n+1}</div>`).join('')}</div>`;
    }

    return screenHTML(`
      <div style="font-size:10px;color:#444;text-transform:uppercase;letter-spacing:.06em;margin-bottom:12px">Pergunta ${i+1} de ${builderQuestions.length}</div>
      <div style="font-size:18px;font-weight:700;color:#fff;line-height:1.4">${escHtml(q.label||'(sem texto)')}</div>
      ${widget}
      <button style="margin-top:20px;width:100%;padding:12px;background:#6366f1;border:none;border-radius:10px;color:#fff;font-size:14px;font-weight:700;cursor:default">Continuar →</button>
    `);
  }).join('');

  const html = `<div id="preview-modal" style="position:fixed;inset:0;background:rgba(0,0,0,.8);z-index:3000;display:flex;align-items:flex-start;justify-content:center;padding:24px;overflow-y:auto" onclick="if(event.target===this)document.getElementById('preview-modal').remove()">
    <div style="width:min(480px,100%);padding-bottom:40px">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:16px">
        <div style="font-size:13px;font-weight:700;color:#6366f1">Preview — ${escHtml(name)}</div>
        <button onclick="document.getElementById('preview-modal').remove()" style="background:#111;border:1px solid #222;color:#aaa;font-size:12px;padding:6px 14px;border-radius:7px;cursor:pointer">Fechar</button>
      </div>
      ${intro ? screenHTML(`<div style="font-size:22px;font-weight:800;color:#fff;margin-bottom:8px">Olá! 👋</div><div style="font-size:14px;color:#888;line-height:1.6">${escHtml(intro)}</div><button style="margin-top:20px;width:100%;padding:12px;background:#6366f1;border:none;border-radius:10px;color:#fff;font-size:14px;font-weight:700;cursor:default">Começar →</button>`) : ''}
      ${questionPreviews || screenHTML('<div style="text-align:center;color:#444;padding:24px">Nenhuma pergunta adicionada</div>')}
      ${screenHTML('<div style="text-align:center"><div style="font-size:48px">✓</div><div style="font-size:20px;font-weight:800;color:#fff;margin:12px 0 6px">Obrigado!</div><div style="font-size:13px;color:#555">Sua resposta foi registrada.</div></div>')}
    </div>
  </div>`;
  document.body.insertAdjacentHTML('beforeend', html);
}

// ─── Dispatch Modal ───
async function openDispatchModal(surveyId) {
  const survey = surveysList.find(s => s.id === surveyId);
  if (!survey) return;

  let studentCount = 0;
  if (survey.cohort_id) {
    const { count } = await sb.from('students').select('id', { count: 'exact', head: true })
      .eq('cohort_id', survey.cohort_id).eq('active', true).eq('is_mentor', false);
    studentCount = count ?? 0;
  }

  const html = `<div id="survey-dispatch-modal" class="modal-overlay" onclick="if(event.target===this)closeDispatchModal()">
    <div class="modal-box" style="max-width:440px">
      <div class="modal-header"><span>Disparar Formulário</span><button class="modal-close" onclick="closeDispatchModal()">×</button></div>
      <div class="modal-body">
        <p style="color:#ccc;margin-bottom:12px">Enviará um link individual via WhatsApp para <strong style="color:#fff">${studentCount} aluno(s)</strong> da turma.</p>
        <div style="background:#111;border:1px solid #1e1e1e;border-radius:8px;padding:12px;font-size:12px;color:#666">
          <strong style="color:#888">Formulário:</strong> ${escHtml(survey.name)}<br>
          <strong style="color:#888">Turma:</strong> ${escHtml(survey.cohorts?.name || '—')}
        </div>
      </div>
      <div class="modal-footer">
        <button class="btn-secondary" onclick="closeDispatchModal()">Cancelar</button>
        <button class="btn-primary" onclick="confirmDispatch('${surveyId}')" id="dispatch-confirm-btn">📤 Enviar via WhatsApp</button>
      </div>
    </div>
  </div>`;
  document.body.insertAdjacentHTML('beforeend', html);
  document.getElementById('survey-dispatch-modal').style.display = 'flex';
}

function closeDispatchModal() { document.getElementById('survey-dispatch-modal')?.remove(); }

async function confirmDispatch(surveyId) {
  const btn = document.getElementById('dispatch-confirm-btn');
  if (btn) { btn.disabled = true; btn.textContent = 'Enviando...'; }
  const { data: { session } } = await sb.auth.getSession();
  const res = await fetch(`${FUNCTIONS_URL}/dispatch-survey`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${session?.access_token}` },
    body: JSON.stringify({ survey_id: surveyId }),
  });
  const result = await res.json();
  closeDispatchModal();
  showToast(result.success
    ? `✅ Enviado para ${result.dispatched} aluno(s).${result.skipped>0?` ${result.skipped} sem telefone.`:''}`
    : `❌ ${result.error || 'Erro no disparo'}`, result.success ? 'success' : 'error');
  await loadSurveysView();
}

// ─── Close Survey ───
async function closeSurvey(surveyId) {
  if (!confirm('Encerrar este formulário?')) return;
  await sb.from('surveys').update({ status: 'closed' }).eq('id', surveyId);
  await loadSurveysView();
}

// ─── Results Drawer ───
async function openSurveysDrawer(surveyId) {
  const survey = surveysList.find(s => s.id === surveyId);
  if (!survey) return;

  const [{ data: questions }, { data: responses }, { count: totalLinks }] = await Promise.all([
    sb.from('survey_questions').select('*').eq('survey_id', surveyId).order('position'),
    sb.from('survey_responses').select('id, submitted_at, students(name), survey_answers(question_id, value_text, value_number, value_options)').eq('survey_id', surveyId).order('submitted_at', { ascending: false }),
    sb.from('survey_links').select('id', { count: 'exact', head: true }).eq('survey_id', surveyId),
  ]);

  const qs = questions || [];
  const rs = responses || [];
  const turma = survey.cohorts?.name || survey.classes?.name || '—';

  const qSummaries = qs.map(q => {
    const answers = rs.flatMap(r => (r.survey_answers || []).filter(a => a.question_id === q.id));
    const qt = Q_TYPES[q.type] || { icon: '?', label: q.type };
    let summaryHTML = '';

    if (q.type === 'nps' && answers.length) {
      const scores = answers.map(a => a.value_number).filter(n => n !== null);
      const prom = scores.filter(n => n >= 9).length;
      const detr = scores.filter(n => n <= 6).length;
      const nps  = Math.round(((prom - detr) / scores.length) * 100);
      const col  = nps >= 50 ? '#4ade80' : nps >= 0 ? '#f59e0b' : '#f87171';
      summaryHTML = `<div style="display:flex;gap:12px;flex-wrap:wrap;margin-top:8px">
        <div style="text-align:center"><div style="font-size:28px;font-weight:800;color:${col}">${nps}</div><div style="font-size:10px;color:#555">NPS Score</div></div>
        <div style="text-align:center"><div style="font-size:18px;font-weight:700;color:#4ade80">${prom}</div><div style="font-size:10px;color:#555">Promotores</div></div>
        <div style="text-align:center"><div style="font-size:18px;font-weight:700;color:#f87171">${detr}</div><div style="font-size:10px;color:#555">Detratores</div></div>
      </div>`;
    } else if (q.type === 'csat' && answers.length) {
      const scores = answers.map(a => a.value_number).filter(n => n !== null);
      const avg = (scores.reduce((a, b) => a + b, 0) / scores.length).toFixed(1);
      summaryHTML = `<div style="margin-top:8px"><span style="font-size:24px;font-weight:800;color:#f59e0b">${avg}</span><span style="font-size:12px;color:#555">/5 · ${scores.length} respostas</span></div>`;
    } else if (q.type === 'text') {
      const texts = answers.map(a => a.value_text).filter(Boolean);
      summaryHTML = texts.slice(0, 5).map(t => `<div style="margin-top:6px;background:#0d0d0d;border-left:2px solid #222;padding:8px 12px;border-radius:0 6px 6px 0;font-size:12px;color:#888">${escHtml(t)}</div>`).join('');
      if (texts.length > 5) summaryHTML += `<div style="font-size:11px;color:#444;margin-top:4px">+${texts.length-5} mais...</div>`;
    } else if (q.type === 'choice' || q.type === 'multi') {
      const allVals = answers.flatMap(a => {
        if (a.value_options) return Array.isArray(a.value_options) ? a.value_options : [a.value_options];
        return a.value_text ? [a.value_text] : [];
      });
      const counts = {};
      allVals.forEach(v => { counts[v] = (counts[v]||0)+1; });
      const total = allVals.length || 1;
      summaryHTML = Object.entries(counts).sort((a,b)=>b[1]-a[1]).map(([k,v])=>`
        <div style="display:flex;align-items:center;gap:8px;margin-top:6px">
          <div style="font-size:12px;color:#ccc;min-width:120px">${escHtml(k)}</div>
          <div style="flex:1;height:6px;background:#1a1a1a;border-radius:3px;overflow:hidden">
            <div style="height:100%;width:${Math.round(v/total*100)}%;background:#6366f1;border-radius:3px"></div>
          </div>
          <div style="font-size:11px;color:#555;min-width:24px">${v}</div>
        </div>`).join('');
    } else if (q.type === 'scale' && answers.length) {
      const scores = answers.map(a => a.value_number).filter(n => n !== null);
      const avg = (scores.reduce((a, b) => a + b, 0) / scores.length).toFixed(1);
      summaryHTML = `<div style="margin-top:8px"><span style="font-size:24px;font-weight:800;color:#f97316">${avg}</span><span style="font-size:12px;color:#555">/${q.scale_max||5} · ${scores.length} respostas</span></div>`;
    }

    return `<div style="background:#111;border:1px solid #1e1e1e;border-radius:10px;padding:14px;margin-bottom:10px">
      <div style="font-size:10px;color:${qt.color};font-weight:700;text-transform:uppercase;letter-spacing:.04em;margin-bottom:6px">${qt.icon} ${qt.label} · ${answers.length} respostas</div>
      <div style="font-size:13px;color:#ccc;font-weight:600">${escHtml(q.label)}</div>
      ${summaryHTML || '<div style="font-size:11px;color:#333;margin-top:6px">Sem respostas</div>'}
    </div>`;
  }).join('');

  const html = `<div id="surveys-drawer-overlay" style="position:fixed;inset:0;background:rgba(0,0,0,.6);z-index:1000;display:flex;justify-content:flex-end" onclick="if(event.target===this)closeSurveysDrawer()">
    <div style="width:min(580px,100vw);background:#0d0d0d;border-left:1px solid #1e1e1e;overflow-y:auto;padding:24px">
      <div style="display:flex;align-items:center;justify-content:space-between;margin-bottom:20px">
        <div>
          <div style="font-size:16px;font-weight:700;color:#fff">${escHtml(survey.name)}</div>
          <div style="font-size:12px;color:#555">${turma} · ${rs.length}/${totalLinks||0} responderam</div>
        </div>
        <div style="display:flex;gap:6px;align-items:center">
          <button class="btn-xs btn-ghost" onclick="exportSurveyCSV('${surveyId}')">⬇ CSV</button>
          <button class="btn-xs btn-ghost" onclick="exportSurveyMD('${surveyId}')">⬇ MD</button>
          <button onclick="closeSurveysDrawer()" style="background:none;border:none;color:#555;font-size:20px;cursor:pointer">×</button>
        </div>
      </div>
      ${qs.length === 0 ? '<div style="color:#444;text-align:center;padding:40px">Formulário sem perguntas.</div>' : qSummaries}
    </div>
  </div>`;
  document.body.insertAdjacentHTML('beforeend', html);
}

function closeSurveysDrawer() { document.getElementById('surveys-drawer-overlay')?.remove(); }

// ─── Export ───
async function getSurveyExportData(surveyId) {
  const survey = surveysList.find(s => s.id === surveyId);
  if (!survey) return null;
  const [{ data: questions }, { data: responses }] = await Promise.all([
    sb.from('survey_questions').select('*').eq('survey_id', surveyId).order('position'),
    sb.from('survey_responses').select('*, students(name, phone), survey_answers(*)').eq('survey_id', surveyId).order('submitted_at', { ascending: false }),
  ]);
  return { survey, questions: questions||[], responses: responses||[], turmaName: survey.cohorts?.name || survey.classes?.name || '' };
}

async function exportSurveyCSV(surveyId) {
  const d = await getSurveyExportData(surveyId);
  if (!d) return;
  const { survey, questions, responses, turmaName } = d;
  const qHeaders = questions.map(q => csvCell(q.label)).join(',');
  const header   = `data,aluno,telefone,turma,${qHeaders}`;
  const rows = responses.map(r => {
    const date  = r.submitted_at ? new Date(r.submitted_at).toLocaleDateString('pt-BR') : '';
    const name  = csvCell(r.students?.name||'');
    const phone = csvCell(r.students?.phone||'');
    const turma = csvCell(turmaName);
    const vals  = questions.map(q => {
      const a = (r.survey_answers||[]).find(a => a.question_id === q.id);
      if (!a) return '';
      if (a.value_options) return csvCell(Array.isArray(a.value_options)?a.value_options.join(';'):String(a.value_options));
      if (a.value_text !== null && a.value_text !== undefined) return csvCell(a.value_text);
      if (a.value_number !== null && a.value_number !== undefined) return a.value_number;
      return '';
    }).join(',');
    return `${date},${name},${phone},${turma},${vals}`;
  }).join('\n');
  downloadFile(`formulario-${slugify(survey.name)}-${new Date().toISOString().slice(0,10)}.csv`, header+'\n'+rows, 'text/csv;charset=utf-8;');
}

async function exportSurveyMD(surveyId) {
  const d = await getSurveyExportData(surveyId);
  if (!d) return;
  const { survey, questions, responses, turmaName } = d;
  const qCols  = questions.map(q => `| ${q.label.replace(/\|/g,'\\|')} `).join('');
  const qSep   = questions.map(() => '|---').join('');
  const tableRows = responses.map(r => {
    const date = r.submitted_at ? new Date(r.submitted_at).toLocaleDateString('pt-BR') : '';
    const vals = questions.map(q => {
      const a = (r.survey_answers||[]).find(a => a.question_id === q.id);
      if (!a) return '| — ';
      if (a.value_options) return `| ${(Array.isArray(a.value_options)?a.value_options.join(', '):a.value_options).replace(/\|/g,'\\|')} `;
      if (a.value_text) return `| ${a.value_text.replace(/\|/g,'\\|').replace(/\n/g,' ')} `;
      if (a.value_number !== null && a.value_number !== undefined) return `| ${a.value_number} `;
      return '| — ';
    }).join('');
    return `| ${date} | ${r.students?.name||'Anônimo'} ${vals}|`;
  }).join('\n');

  const md = `# ${survey.name}\n\n**Turma:** ${turmaName}  \n**Respostas:** ${responses.length}  \n**Exportado:** ${new Date().toLocaleDateString('pt-BR')}\n\n---\n\n| Data | Aluno ${qCols}|\n|---|---${qSep}|\n${tableRows}\n`;
  downloadFile(`formulario-${slugify(survey.name)}-${new Date().toISOString().slice(0,10)}.md`, md, 'text/markdown;charset=utf-8;');
}

// ─── Helpers ───
function csvCell(v) { const s = String(v??'').replace(/"/g,'""'); return /[,"\n]/.test(s)?`"${s}"`:s; }
function slugify(s) { return s.toLowerCase().replace(/[^a-z0-9]+/g,'-').replace(/^-|-$/g,''); }
function downloadFile(name, content, mime) {
  const a = Object.assign(document.createElement('a'), { href: URL.createObjectURL(new Blob(['\uFEFF'+content],{type:mime})), download: name });
  a.click(); setTimeout(()=>URL.revokeObjectURL(a.href),1000);
}
function escHtml(s) { return String(s??'').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function showToast(msg, type='success') {
  const el = document.createElement('div');
  el.style.cssText = `position:fixed;bottom:24px;right:24px;background:${type==='error'?'#7f1d1d':'#14532d'};color:#fff;padding:12px 18px;border-radius:8px;font-size:13px;z-index:9999;max-width:320px`;
  el.textContent = msg; document.body.appendChild(el);
  setTimeout(()=>el.remove(),4000);
}
