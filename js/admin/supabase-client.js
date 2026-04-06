// Supabase client — loaded after supabase-js CDN and /js/config.js
const SUPABASE_URL = window.SUPABASE_CONFIG.url;
const SUPABASE_KEY = window.SUPABASE_CONFIG.anonKey;
const sb = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
