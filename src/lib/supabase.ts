import { createClient, type SupabaseClient } from '@supabase/supabase-js';

const url = import.meta.env.VITE_SUPABASE_URL;
const anonKey = import.meta.env.VITE_SUPABASE_ANON_KEY;

if (!url || !anonKey) {
  throw new Error(
    'Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY. ' +
    'Copy .env.example to .env.local and fill in your Supabase values, ' +
    'or set them as GitHub Actions Variables for the deployed build.'
  );
}

export const supabase: SupabaseClient = createClient(url, anonKey);

if (typeof window !== 'undefined') {
  (window as unknown as { supabase: SupabaseClient }).supabase = supabase;
}
