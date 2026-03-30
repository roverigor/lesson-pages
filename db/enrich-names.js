#!/usr/bin/env node
// Enrich student names from Evolution API contacts + Message pushNames
// Run on VPS: SUPABASE_SERVICE_KEY=xxx node enrich-names.js

const { execSync } = require('child_process');

const SUPABASE_URL = 'https://gpufcipkajppykmnmdeh.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_KEY || '';

async function supabaseGet(path) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/${path}`, {
    headers: {
      'apikey': SUPABASE_KEY,
      'Authorization': `Bearer ${SUPABASE_KEY}`,
    },
  });
  return res.json();
}

async function supabaseUpdate(id, data) {
  const res = await fetch(`${SUPABASE_URL}/rest/v1/students?id=eq.${id}`, {
    method: 'PATCH',
    headers: {
      'apikey': SUPABASE_KEY,
      'Authorization': `Bearer ${SUPABASE_KEY}`,
      'Content-Type': 'application/json',
      'Prefer': 'return=minimal',
    },
    body: JSON.stringify(data),
  });
  return res.ok;
}

function getContactNames() {
  // Query evolution_db for all contacts with pushName
  const sql = `SELECT "remoteJid", "pushName" FROM "Contact" WHERE "instanceId" = (SELECT id FROM "Instance" WHERE name = 'igor' LIMIT 1) AND "pushName" IS NOT NULL AND "pushName" != '' AND "remoteJid" LIKE '%@s.whatsapp.net'`;
  const raw = execSync(
    `docker exec infra-postgres-portal-1 psql -U portal_user -d evolution_db -t -A -F'|' -c "${sql.replace(/"/g, '\\"')}"`,
    { encoding: 'utf-8', timeout: 15000 }
  );
  const map = {};
  for (const line of raw.trim().split('\n')) {
    if (!line) continue;
    const [jid, name] = line.split('|');
    const phone = jid.replace('@s.whatsapp.net', '').replace(/:.*/, '');
    if (name && name !== phone && !name.match(/^\d+$/)) {
      map[phone] = name.replace(/[♾️🪖]/g, '').trim();
    }
  }
  return map;
}

function getMessagePushNames() {
  // Get unique pushNames from messages for phones that don't have contact names
  const sql = `SELECT DISTINCT ON (m.key->>'remoteJid') m.key->>'remoteJid' as jid, m."pushName" FROM "Message" m WHERE m."instanceId" = (SELECT id FROM "Instance" WHERE name = 'igor' LIMIT 1) AND m."pushName" IS NOT NULL AND m."pushName" != '' AND m.key->>'remoteJid' LIKE '%@s.whatsapp.net' ORDER BY m.key->>'remoteJid', m."messageTimestamp" DESC`;
  const raw = execSync(
    `docker exec infra-postgres-portal-1 psql -U portal_user -d evolution_db -t -A -F'|' -c "${sql.replace(/"/g, '\\"')}"`,
    { encoding: 'utf-8', timeout: 30000 }
  );
  const map = {};
  for (const line of raw.trim().split('\n')) {
    if (!line) continue;
    const [jid, name] = line.split('|');
    const phone = jid.replace('@s.whatsapp.net', '');
    if (name && name !== phone && !name.match(/^\d+$/)) {
      map[phone] = name.replace(/[♾️🪖]/g, '').trim();
    }
  }
  return map;
}

async function main() {
  if (!SUPABASE_KEY) { console.error('Set SUPABASE_SERVICE_KEY'); process.exit(1); }

  console.log('Loading contacts from evolution_db...');
  const contactNames = getContactNames();
  console.log(`  ${Object.keys(contactNames).length} contacts with names`);

  console.log('Loading pushNames from messages...');
  const msgNames = getMessagePushNames();
  console.log(`  ${Object.keys(msgNames).length} unique pushNames from messages`);

  // Merge: contacts take priority, messages fill gaps
  const nameMap = { ...msgNames, ...contactNames };
  console.log(`  ${Object.keys(nameMap).length} total unique phone->name mappings`);

  console.log('\nLoading students from Supabase...');
  const students = await supabaseGet('students?select=id,name,phone');
  const noName = students.filter(s => !s.name || s.name.trim() === '');
  console.log(`  ${students.length} total, ${noName.length} without name`);

  let updated = 0;
  let notFound = 0;

  for (const s of noName) {
    const name = nameMap[s.phone];
    if (name) {
      const ok = await supabaseUpdate(s.id, { name });
      if (ok) updated++;
    } else {
      notFound++;
    }
  }

  console.log(`\n=== SUMMARY ===`);
  console.log(`Updated: ${updated}`);
  console.log(`No name found: ${notFound}`);
  console.log(`Already had name: ${students.length - noName.length}`);
}

main().catch(e => { console.error(e); process.exit(1); });
