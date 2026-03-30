#!/usr/bin/env node
// Enrich student names from group message pushNames
// Uses LID→phone mapping from group participants + pushNames from messages
// Run on VPS: SUPABASE_SERVICE_KEY=xxx node enrich-from-groups.js

const { execSync } = require('child_process');

const EVOLUTION_URL = 'http://localhost:8084';
const EVOLUTION_KEY = 'evo_acadlendaria_2026_secure_key';
const INSTANCE = 'igor';
const SUPABASE_URL = 'https://gpufcipkajppykmnmdeh.supabase.co';
const SUPABASE_KEY = process.env.SUPABASE_SERVICE_KEY || '';

const GROUPS = [
  '120363407322736559@g.us',
  '120363406009222289@g.us',
  '120363408861350309@g.us',
  '120363423250471692@g.us',
  '120363423278234924@g.us',
];

async function getGroupParticipants(jid) {
  const res = await fetch(`${EVOLUTION_URL}/group/participants/${INSTANCE}?groupJid=${jid}`, {
    headers: { 'apikey': EVOLUTION_KEY },
  });
  const data = await res.json();
  return data.participants || [];
}

function getGroupPushNames(groupJids) {
  const jidList = groupJids.map(j => `'${j}'`).join(',');
  const sql = `
    SELECT DISTINCT ON (key->>'participant')
      key->>'participant' as lid,
      "pushName"
    FROM "Message"
    WHERE "instanceId" = (SELECT id FROM "Instance" WHERE name = '${INSTANCE}' LIMIT 1)
      AND key->>'remoteJid' IN (${jidList})
      AND "pushName" IS NOT NULL AND "pushName" != ''
      AND key->>'participant' IS NOT NULL
      AND "pushName" !~ '^[0-9]+$'
    ORDER BY key->>'participant', "messageTimestamp" DESC
  `;
  const raw = execSync(
    `docker exec infra-postgres-portal-1 psql -U portal_user -d evolution_db -t -A -F'|' -c "${sql.replace(/"/g, '\\"')}"`,
    { encoding: 'utf-8', timeout: 60000 }
  );
  const map = {};
  for (const line of raw.trim().split('\n')) {
    if (!line) continue;
    const [lid, name] = line.split('|');
    if (lid && name) map[lid] = name.replace(/[♾️🪖]/g, '').trim();
  }
  return map;
}

async function main() {
  if (!SUPABASE_KEY) { console.error('Set SUPABASE_SERVICE_KEY'); process.exit(1); }

  // Step 1: Build LID → phone mapping from all groups
  console.log('Building LID → phone mapping from groups...');
  const lidToPhone = {};
  for (const jid of GROUPS) {
    const parts = await getGroupParticipants(jid);
    for (const p of parts) {
      if (p.id && p.phoneNumber) {
        const phone = p.phoneNumber.replace('@s.whatsapp.net', '');
        lidToPhone[p.id] = phone;
      }
    }
  }
  console.log(`  ${Object.keys(lidToPhone).length} LID→phone mappings`);

  // Step 2: Get pushNames from group messages (by LID)
  console.log('Getting pushNames from group messages...');
  const lidToName = getGroupPushNames(GROUPS);
  console.log(`  ${Object.keys(lidToName).length} LIDs with pushNames`);

  // Step 3: Build phone → name mapping
  const phoneToName = {};
  for (const [lid, name] of Object.entries(lidToName)) {
    const phone = lidToPhone[lid];
    if (phone && name) {
      phoneToName[phone] = name;
    }
  }
  console.log(`  ${Object.keys(phoneToName).length} phone→name mappings resolved`);

  // Step 4: Load students without names
  const res = await fetch(`${SUPABASE_URL}/rest/v1/students?select=id,name,phone&or=(name.is.null,name.eq.)`, {
    headers: { 'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}` },
  });
  const noName = await res.json();
  console.log(`\n${noName.length} students without name in Supabase`);

  // Step 5: Update
  let updated = 0;
  let notFound = 0;
  for (const s of noName) {
    const name = phoneToName[s.phone];
    if (name) {
      const r = await fetch(`${SUPABASE_URL}/rest/v1/students?id=eq.${s.id}`, {
        method: 'PATCH',
        headers: {
          'apikey': SUPABASE_KEY, 'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Content-Type': 'application/json', 'Prefer': 'return=minimal',
        },
        body: JSON.stringify({ name }),
      });
      if (r.ok) {
        updated++;
        if (updated <= 20) console.log(`  ${s.phone} → ${name}`);
      }
    } else {
      notFound++;
    }
  }

  console.log(`\n=== SUMMARY ===`);
  console.log(`Updated: ${updated}`);
  console.log(`No name found: ${notFound}`);
}

main().catch(e => { console.error(e); process.exit(1); });
