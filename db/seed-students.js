#!/usr/bin/env node
// ═══════════════════════════════════════
// Seed students from WhatsApp groups via Evolution API
// Run: SUPABASE_SERVICE_KEY=xxx node seed-students.js
// Or run on VPS: node seed-students.js (uses env vars)
// ═══════════════════════════════════════

const EVOLUTION_URL = 'http://localhost:8084';
const EVOLUTION_KEY = 'evo_acadlendaria_2026_secure_key';
const EVOLUTION_INSTANCE = 'igor';

const SUPABASE_URL = 'https://gpufcipkajppykmnmdeh.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_KEY || '';

// Known mentors - exclude from student list
const MENTORS = new Set([
  '554399250490',   // Igor
  '5518988119126',  // Fran Martins
  '558881102201',   // Michele
  '554899748298',   // Lucas Rover
  '5515997425595',  // Adriano De Marqui
  '555191882447',   // Lucas Charao
  '5511952961036',  // Feldman
  '5521998628489',  // Douglas Machado
  '555195763576',   // Gabriel Fofonka
  '553599284346',   // Rogerio Travagin
  '559281951096',   // Jose Carlos Amorim
  '555180196127',   // Academia Lendaria
  '5511915634642',  // Marllon Blando
  '555191511178',   // Erica Souza
  '553584239279',   // admin unknown
  '554888740043',   // admin unknown
  '556199496931',   // Sidney Fernandes
  '558386181165',   // Diego Diniz
  '5516996308617',  // Klaus Deor
  '5511978031078',  // Day Cavalcanti
  '558296838800',   // Adavio Tittoni
  '554891642424',   // Alan Nicolas
  '556499425822',   // Talles Souza
  '556199331574',   // Bruno Gentil/SAL
  '558881718135',   // Luh (admin)
  '5521998742430',  // Daniel Viana (admin)
  '5519984119147',  // Lory Cantelli (admin)
  '5521985515119',  // admin
  '554896172481',   // admin
]);

const COHORT_GROUPS = [
  { name: 'Fundamental T1', jid: '120363407322736559@g.us' },
  { name: 'Fundamental T2', jid: '120363406009222289@g.us' },
  { name: 'Fundamental T3', jid: '120363408861350309@g.us' },
  { name: 'Advanced T1',    jid: '120363423250471692@g.us' },
  { name: 'Advanced T2',    jid: '120363423278234924@g.us' },
];

async function supabaseQuery(method, path, body) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    method,
    headers: {
      'apikey': SUPABASE_KEY,
      'Authorization': `Bearer ${SUPABASE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=representation',
    },
    body: body ? JSON.stringify(body) : undefined,
  });
  if (!res.ok) {
    const text = await res.text();
    throw new Error(`Supabase ${method} ${path}: ${res.status} ${text}`);
  }
  return res.json();
}

async function getGroupParticipants(groupJid) {
  const url = `${EVOLUTION_URL}/group/participants/${EVOLUTION_INSTANCE}?groupJid=${groupJid}`;
  const res = await fetch(url, {
    headers: { 'apikey': EVOLUTION_KEY },
  });
  if (!res.ok) throw new Error(`Evolution API: ${res.status}`);
  const data = await res.json();
  return (data.participants || [])
    .filter(p => p.phoneNumber && p.phoneNumber.endsWith('@s.whatsapp.net'))
    .map(p => ({
      phone: p.phoneNumber.replace('@s.whatsapp.net', ''),
      name: (p.name || '').replace(/[♾️🪖]/g, '').trim(),
      isAdmin: !!p.admin,
    }));
}

async function main() {
  if (!SUPABASE_KEY) {
    console.error('Set SUPABASE_SERVICE_KEY env var');
    process.exit(1);
  }

  // Get cohort IDs from Supabase
  const cohorts = await supabaseQuery('GET', 'cohorts?select=id,name');
  const cohortMap = {};
  for (const c of cohorts) cohortMap[c.name] = c.id;

  let totalInserted = 0;
  let totalSkipped = 0;

  for (const group of COHORT_GROUPS) {
    const cohortId = cohortMap[group.name];
    if (!cohortId) {
      console.log(`SKIP: Cohort "${group.name}" not found in DB`);
      continue;
    }

    console.log(`\nFetching ${group.name} (${group.jid})...`);
    const participants = await getGroupParticipants(group.jid);
    console.log(`  Found ${participants.length} participants`);

    const students = participants.filter(p => !MENTORS.has(p.phone));
    console.log(`  ${students.length} students (${participants.length - students.length} mentors/admins excluded)`);

    for (const s of students) {
      try {
        await supabaseQuery('POST', 'students', {
          name: s.name,
          phone: s.phone,
          cohort_id: cohortId,
          is_mentor: false,
        });
        totalInserted++;
      } catch (e) {
        if (e.message.includes('duplicate') || e.message.includes('409')) {
          totalSkipped++;
        } else {
          console.error(`  ERROR inserting ${s.phone}: ${e.message}`);
        }
      }
    }
    console.log(`  Done: ${students.length} processed`);
  }

  console.log(`\n=== SUMMARY ===`);
  console.log(`Inserted: ${totalInserted}`);
  console.log(`Skipped (duplicate): ${totalSkipped}`);
}

main().catch(e => { console.error(e); process.exit(1); });
