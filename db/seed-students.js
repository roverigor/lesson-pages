#!/usr/bin/env node
// ═══════════════════════════════════════
// Seed students from WhatsApp groups via Evolution API
// Run: SUPABASE_SERVICE_KEY=xxx node seed-students.js
// Or run on VPS: node seed-students.js (uses env vars)
// ═══════════════════════════════════════

// Run: EVOLUTION_KEY=xxx SUPABASE_SERVICE_KEY=xxx node seed-students.js
const EVOLUTION_URL = process.env.EVOLUTION_URL || 'http://localhost:8084';
const EVOLUTION_KEY = process.env.EVOLUTION_KEY || '';
const EVOLUTION_INSTANCE = process.env.EVOLUTION_INSTANCE || 'igor';

const SUPABASE_URL = process.env.SUPABASE_URL || 'https://gpufcipkajppykmnmdeh.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_KEY || '';

if (!EVOLUTION_KEY) { console.error('EVOLUTION_KEY env var required'); process.exit(1); }
if (!SUPABASE_KEY)  { console.error('SUPABASE_SERVICE_KEY env var required'); process.exit(1); }

// Known mentors phone list — loaded from MENTORS_PHONES env var (comma-separated) or from DB
// Do NOT hardcode phone numbers in source (LGPD compliance)
const MENTORS = new Set(
  (process.env.MENTORS_PHONES || '').split(',').map(p => p.trim()).filter(Boolean)
);

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
