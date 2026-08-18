import { createClient, SupabaseClient, Session } from '@supabase/supabase-js';

const STORAGE_KEY_URL = 'rajasch_supabase_url';
const STORAGE_KEY_KEY = 'rajasch_supabase_anon_key';

// PRIORITAS KREDENSIAL: environment variable (VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY)
// yang diset di server deploy (Vercel/Netlify/dst) SELALU didahulukan. localStorage hanya
// dipakai sebagai jalan pintas saat development lokal lewat modal "Pengaturan Supabase".
// (Poin 24 panduan: localStorage HANYA untuk preferensi ini, bukan untuk saldo/transaksi/
// pembayaran/profil lembaga/tagihan/master data -- semua itu sekarang ada di file terpisah
// yang membaca & menulis langsung ke Supabase.)
export function getSavedSupabaseCredentials(): { url: string; key: string } {
  const envUrl = (import.meta as any).env?.VITE_SUPABASE_URL || '';
  const envKey = (import.meta as any).env?.VITE_SUPABASE_ANON_KEY || '';

  const localUrl = envUrl || localStorage.getItem(STORAGE_KEY_URL) || '';
  const localKey = envKey || localStorage.getItem(STORAGE_KEY_KEY) || '';

  const finalUrl = localUrl || 'https://xyzcompany.supabase.co';
  const finalKey = localKey || 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.dummy_anon_key_for_demo';

  return { url: finalUrl, key: finalKey };
}

let supabaseInstance: SupabaseClient | null = null;

export function getSupabaseClient(): SupabaseClient | null {
  const { url, key } = getSavedSupabaseCredentials();
  if (!url || !key || url.includes('xyzcompany.supabase.co')) {
    return null;
  }
  if (!supabaseInstance) {
    try {
      supabaseInstance = createClient(url, key);
    } catch (err) {
      console.warn('Failed to initialize Supabase client:', err);
      return null;
    }
  }
  return supabaseInstance;
}

export function resetSupabaseClient(url: string, key: string) {
  localStorage.setItem(STORAGE_KEY_URL, url);
  localStorage.setItem(STORAGE_KEY_KEY, key);
  if (url && key) {
    try {
      supabaseInstance = createClient(url, key);
    } catch (err) {
      supabaseInstance = null;
    }
  } else {
    supabaseInstance = null;
  }
}

export async function testSupabaseConnection(urlInput?: string, keyInput?: string): Promise<{ success: boolean; message: string }> {
  const creds = getSavedSupabaseCredentials();
  const url = urlInput || creds.url;
  const key = keyInput || creds.key;

  if (!url || !key || url.includes('xyzcompany')) {
    return { success: false, message: 'Kredensial Supabase belum diatur. Sediakan URL & Anon Key valid.' };
  }

  try {
    const testClient = createClient(url, key);
    const { error } = await testClient.from('konfigurasi_lembaga').select('id').limit(1);
    if (error) {
      if (error.code === 'PGRST116' || error.message.includes('relation') && error.message.includes('does not exist')) {
        return { success: false, message: 'Koneksi Berhasil, tetapi skema tabel belum dibuat! Silakan jalankan SQL Script Migration (supabase/migration.sql).' };
      }
      return { success: false, message: `Error Supabase: ${error.message}` };
    }
    return { success: true, message: 'Koneksi Supabase Aktif & Terverifikasi!' };
  } catch (err: any) {
    return { success: false, message: `Gagal terkoneksi: ${err.message || 'Error jaringan'}` };
  }
}

// =========================================================================
// AUTH SESSION HELPERS
// =========================================================================

/** Ambil sesi login saat ini dari Supabase (null jika belum login / belum terhubung). */
export async function getCurrentSession(): Promise<Session | null> {
  const client = getSupabaseClient();
  if (!client) return null;
  const { data, error } = await client.auth.getSession();
  if (error) return null;
  return data.session;
}

/** Daftarkan listener perubahan status login (login/logout/token refresh). */
export function onAuthStateChange(callback: (session: Session | null) => void) {
  const client = getSupabaseClient();
  if (!client) return () => {};
  const { data } = client.auth.onAuthStateChange((_event, session) => {
    callback(session);
  });
  return () => data.subscription.unsubscribe();
}

/** Login dengan email & password. TIDAK ada fallback sesi palsu -- jika gagal, gagal. */
export async function signInWithPassword(email: string, password: string): Promise<{ success: boolean; session?: Session; message?: string }> {
  const client = getSupabaseClient();
  if (!client) {
    return { success: false, message: 'Supabase belum dikonfigurasi. Hubungi admin untuk mengatur koneksi database.' };
  }
  const { data, error } = await client.auth.signInWithPassword({ email, password });
  if (error || !data.session) {
    return { success: false, message: error?.message || 'Email atau kata sandi salah.' };
  }
  return { success: true, session: data.session };
}

export async function signOutSupabase(): Promise<void> {
  const client = getSupabaseClient();
  if (!client) return;
  await client.auth.signOut();
}
