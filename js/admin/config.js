// ═══════════════════════════════════════
// COURSE CONFIGURATION
// ═══════════════════════════════════════
const COURSE_CFG = {
  'PS Advanced':       {color:'#6366f1', bg:'rgba(99,102,241,0.08)'},
  'PS Advanced T1':    {color:'#6366f1', bg:'rgba(99,102,241,0.08)'},
  'PS Advanced T2':    {color:'#6366f1', bg:'rgba(99,102,241,0.08)'},
  'PS Fundamentals':   {color:'#f59e0b', bg:'rgba(245,158,11,0.08)'},
  'Aulas Advanced T1': {color:'#10b981', bg:'rgba(16,185,129,0.08)'},
  'Aulas Advanced T2': {color:'#34d399', bg:'rgba(52,211,153,0.08)'},
  'Aulas Fund T1':     {color:'#06b6d4', bg:'rgba(6,182,212,0.08)'},
  'Aulas Fund T2':     {color:'#0ea5e9', bg:'rgba(14,165,233,0.08)'},
  'Aulas Fund T3':     {color:'#22d3ee', bg:'rgba(34,211,238,0.08)'},
  'AIOS Fund (Manhã)': {color:'#ec4899', bg:'rgba(236,72,153,0.08)'},
  'AIOS Fund (Tarde)': {color:'#f472b6', bg:'rgba(244,114,182,0.08)'},
};
function getCfg(c) { return COURSE_CFG[c] || {color:'#666', bg:'rgba(102,102,102,0.08)'}; }

const MENTOR_COLORS = ['#6366f1','#10b981','#f59e0b','#ec4899','#06b6d4','#8b5cf6','#ef4444','#14b8a6','#f97316','#a855f7','#22c55e','#3b82f6','#e11d48','#7c3aed','#0891b2'];
function mentorColor(name) { let h=0; for(const c of name) h=(h*31+c.charCodeAt(0))%MENTOR_COLORS.length; return MENTOR_COLORS[h]; }
function initials(name) { return name.split(' ').map(w=>w[0]).slice(0,2).join('').toUpperCase(); }

const NOTIFY_TEMPLATES = {
  custom:             '',
  class_reminder:     'Olá! 👋 Lembrando que hoje tem *{{class_name}}* às {{class_time_start}}.\n\nProfessor(a): {{class_professor}}\nLink: {{zoom_link}}\n\n_Academia Lendária_ 🚀',
  group_announcement: '📢 *Aviso — {{cohort_name}}*\n\n{{zoom_link}}\n\n_Academia Lendária_',
};

const SCHED_TEMPLATES = {
  class_reminder:     'Olá! 👋 Lembrando que hoje tem *{{class_name}}* às {{class_time_start}}.\n\nProfessor(a): {{class_professor}}\nLink: {{zoom_link}}\n\n_Academia Lendária_ 🚀',
  group_announcement: '📢 *Aviso — {{cohort_name}}*\n\n{{zoom_link}}\n\n_Academia Lendária_',
  custom:             '',
};

const FERIADOS_2026 = {
  '2026-01-01': 'Ano Novo',
  '2026-02-16': 'Carnaval',
  '2026-02-17': 'Carnaval',
  '2026-04-03': 'Sexta-feira Santa',
  '2026-04-05': 'Páscoa',
  '2026-04-21': 'Tiradentes',
  '2026-05-01': 'Dia do Trabalho',
  '2026-06-04': 'Corpus Christi',
  '2026-09-07': 'Independência do Brasil',
  '2026-10-12': 'N. Sra. Aparecida',
  '2026-11-02': 'Finados',
  '2026-11-15': 'Proclamação da República',
  '2026-11-20': 'Consciência Negra',
  '2026-12-25': 'Natal',
};

const WEEKDAY_NAMES = ['Domingo','Segunda','Terça','Quarta','Quinta','Sexta','Sábado'];
const WEEKDAY_LABELS = {0:'Dom',1:'Seg',2:'Ter',3:'Qua',4:'Qui',5:'Sex',6:'Sab'};
const WEEKDAY_FULL  = {0:'Domingo',1:'Segunda',2:'Terça',3:'Quarta',4:'Quinta',5:'Sexta',6:'Sábado'};
const MONTHS      = [{y:2026,m:2},{y:2026,m:3},{y:2026,m:4},{y:2026,m:5}];
const MONTH_NAMES = ['Janeiro','Fevereiro','Março','Abril','Maio','Junho','Julho','Agosto','Setembro','Outubro','Novembro','Dezembro'];
