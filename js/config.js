// ═══════════════════════════════════════
// Supabase Public Configuration
// ─────────────────────────────────────
// A anon key é INTENCIONALMENTE pública por design do Supabase.
// Ela é protegida por Row Level Security (RLS) no banco.
// Nunca coloque service_role key aqui.
// Documentação: https://supabase.com/docs/guides/auth/row-level-security
// ═══════════════════════════════════════
window.SUPABASE_CONFIG = {
  url: 'https://gpufcipkajppykmnmdeh.supabase.co',
  anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImdwdWZjaXBrYWpwcHlrbW5tZGVoIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQzNzE1NzgsImV4cCI6MjA4OTk0NzU3OH0.BBmvIGbMtp3bPirWxjMXwdXkpABBV6zD1wgSQ2cB8aU',
};
