/**
 * Smoke Tests — lesson-pages
 * Story 3.5 — EPIC-003
 *
 * Testa os 4 fluxos críticos do sistema:
 *   1. Calendário público: página carrega e retorna HTML válido
 *   2. Supabase DB (anon): classes acessíveis sem autenticação
 *   3. WhatsApp Edge Function: função responde (não quebra)
 *   4. Zoom Edge Function: função responde (não quebra)
 *   5. Admin panel: página carrega
 *
 * Usa Node.js built-in test runner (node:test) + fetch nativo.
 * Não envia mensagens reais nem cria reuniões Zoom.
 */

import { test, describe } from 'node:test';
import assert from 'node:assert/strict';

// ─── Config ───────────────────────────────────────────────────────────────────

const BASE_URL = process.env.APP_URL ?? 'https://calendario.igorrover.com.br';
const SUPABASE_URL = 'https://gpufcipkajppykmnmdeh.supabase.co';
// anon key é pública por design (protegida por RLS)
const ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdwdWZjaXBrYWpwcHlrbW5tZGVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQzNzE1NzgsImV4cCI6MjA4OTk0NzU3OH0.BBmvIGbMtp3bPirWxjMXwdXkpABBV6zD1wgSQ2cB8aU';

const TIMEOUT_MS = 15_000;

// Utilitário: fetch com timeout
async function fetchWithTimeout(url, options = {}) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), TIMEOUT_MS);
  try {
    const res = await fetch(url, { ...options, signal: controller.signal });
    return res;
  } finally {
    clearTimeout(timer);
  }
}

// ─── 1. Calendário Público ────────────────────────────────────────────────────

describe('Calendário Público', () => {
  test('página carrega (HTTP 200)', async () => {
    const res = await fetchWithTimeout(`${BASE_URL}/calendario/`);
    assert.equal(res.status, 200, `Esperado 200, recebido ${res.status}`);
  });

  test('resposta é HTML com doctype', async () => {
    const res = await fetchWithTimeout(`${BASE_URL}/calendario/`);
    const body = await res.text();
    assert.ok(
      body.toLowerCase().includes('<!doctype html') || body.toLowerCase().includes('<html'),
      'Resposta não contém HTML válido'
    );
  });

  test('página referencia Supabase config', async () => {
    const res = await fetchWithTimeout(`${BASE_URL}/calendario/`);
    const body = await res.text();
    assert.ok(
      body.includes('supabase') || body.includes('SUPABASE') || body.includes('config.js'),
      'Página não carrega configuração do Supabase'
    );
  });
});

// ─── 2. Banco de dados via Supabase REST (anon) ───────────────────────────────

describe('Supabase DB — Leitura Anônima', () => {
  test('tabela classes acessível com anon key', async () => {
    const res = await fetchWithTimeout(
      `${SUPABASE_URL}/rest/v1/classes?select=id,name,active&active=eq.true&limit=3`,
      {
        headers: {
          apikey: ANON_KEY,
          Authorization: `Bearer ${ANON_KEY}`,
        },
      }
    );
    assert.equal(res.status, 200, `Supabase REST retornou ${res.status}`);
    const data = await res.json();
    assert.ok(Array.isArray(data), 'Resposta não é um array JSON');
  });

  test('tabela classes retorna ao menos uma turma ativa', async () => {
    const res = await fetchWithTimeout(
      `${SUPABASE_URL}/rest/v1/classes?select=id,name&active=eq.true&limit=10`,
      {
        headers: {
          apikey: ANON_KEY,
          Authorization: `Bearer ${ANON_KEY}`,
        },
      }
    );
    const data = await res.json();
    assert.ok(Array.isArray(data) && data.length > 0, 'Nenhuma turma ativa encontrada no banco');
  });

  test('tabela mentors acessível com anon key', async () => {
    const res = await fetchWithTimeout(
      `${SUPABASE_URL}/rest/v1/mentors?select=id,name,active&active=eq.true&limit=3`,
      {
        headers: {
          apikey: ANON_KEY,
          Authorization: `Bearer ${ANON_KEY}`,
        },
      }
    );
    assert.equal(res.status, 200, `Supabase REST (mentors) retornou ${res.status}`);
  });
});

// ─── 3. Edge Function: send-whatsapp ─────────────────────────────────────────

describe('Edge Function — send-whatsapp', () => {
  test('função está reachable e responde (não 500)', async () => {
    // Envia notification_id inexistente → função roda, não encontra, retorna ok:false
    // Não dispara nenhuma mensagem real
    const res = await fetchWithTimeout(
      `${SUPABASE_URL}/functions/v1/send-whatsapp`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: ANON_KEY,
          Authorization: `Bearer ${ANON_KEY}`,
        },
        body: JSON.stringify({ notification_id: '00000000-0000-0000-0000-000000000000' }),
      }
    );
    assert.notEqual(res.status, 500, `Edge Function retornou 500 — erro interno`);
    assert.ok(
      res.status < 500,
      `Edge Function retornou status inesperado: ${res.status}`
    );
  });

  test('resposta é JSON válido', async () => {
    const res = await fetchWithTimeout(
      `${SUPABASE_URL}/functions/v1/send-whatsapp`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: ANON_KEY,
          Authorization: `Bearer ${ANON_KEY}`,
        },
        body: JSON.stringify({ notification_id: '00000000-0000-0000-0000-000000000000' }),
      }
    );
    const text = await res.text();
    assert.doesNotThrow(() => JSON.parse(text), 'Resposta não é JSON válido');
  });
});

// ─── 4. Edge Function: zoom-attendance ───────────────────────────────────────

describe('Edge Function — zoom-attendance', () => {
  test('função está reachable e responde (não 500)', async () => {
    // POST sem meeting_id → retorna 400 (bad request), não 500 (crash)
    const res = await fetchWithTimeout(
      `${SUPABASE_URL}/functions/v1/zoom-attendance`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: ANON_KEY,
          Authorization: `Bearer ${ANON_KEY}`,
        },
        body: JSON.stringify({}),
      }
    );
    assert.notEqual(res.status, 500, `Edge Function zoom-attendance retornou 500`);
    assert.ok(
      res.status < 500,
      `Status inesperado: ${res.status}`
    );
  });
});

// ─── 5. Admin Panel ───────────────────────────────────────────────────────────

describe('Admin Panel', () => {
  test('página admin carrega (HTTP 200)', async () => {
    const res = await fetchWithTimeout(`${BASE_URL}/calendario/admin.html`);
    assert.equal(res.status, 200, `Admin panel retornou ${res.status}`);
  });

  test('página admin contém estrutura HTML válida', async () => {
    const res = await fetchWithTimeout(`${BASE_URL}/calendario/admin.html`);
    const body = await res.text();
    assert.ok(
      body.toLowerCase().includes('<!doctype html') || body.toLowerCase().includes('<html'),
      'Admin panel não tem HTML válido'
    );
  });

  test('Supabase Auth endpoint responde (não 500)', async () => {
    // Testa com credenciais inválidas → retorna 400, não 500 nem timeout
    const res = await fetchWithTimeout(
      `${SUPABASE_URL}/auth/v1/token?grant_type=password`,
      {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: ANON_KEY,
        },
        body: JSON.stringify({ email: 'smoke-test@invalid.local', password: 'invalid' }),
      }
    );
    assert.notEqual(res.status, 500, 'Supabase Auth retornou 500');
    assert.ok(
      res.status < 500,
      `Auth endpoint retornou status inesperado: ${res.status}`
    );
  });
});
