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
    // Poin multi-tenant: kolom `id` singleton sudah DIHAPUS oleh
    // migration_v6_multi_tenant.sql (diganti `organization_id` sebagai
    // primary key). Query test koneksi HARUS memakai kolom yang masih ada,
    // kalau tidak setiap load aplikasi akan salah mendeteksi "skema belum
    // dibuat" padahal skema multi-tenant sudah benar.
    const { error } = await testClient.from('konfigurasi_lembaga').select('organization_id').limit(1);
    if (error) {
      if (error.code === 'PGRST116' || (error.message.includes('relation') && error.message.includes('does not exist'))) {
        return { success: false, message: 'Koneksi Berhasil, tetapi skema tabel belum dibuat! Jalankan SQL Migration secara berurutan: migration.sql -> migration_periode_pembukuan.sql -> cutoff_migration.sql -> migration_v6_multi_tenant.sql (folder supabase/).' };
      }
      if (error.message.includes('organization_id') && error.message.includes('does not exist')) {
        return { success: false, message: 'Skema multi-tenant belum lengkap: jalankan supabase/migration_v6_multi_tenant.sql di SQL Editor Supabase.' };
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

/**
 * Daftar (sign up) akun baru dengan email & password.
 * Setiap akun baru otomatis mendapat organisasi (lembaga) sendiri yang
 * terisolasi lewat trigger `on_auth_user_created_multi_tenant` di
 * supabase/migration_v6_multi_tenant.sql -- sama seperti login Google
 * pertama kali. Kalau Supabase project mewajibkan konfirmasi email,
 * `data.session` akan kosong walau `error` juga kosong; kondisi ini
 * ditandai lewat `needsEmailConfirmation`.
 */
export async function signUpWithPassword(email: string, password: string): Promise<{ success: boolean; session?: Session; needsEmailConfirmation?: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) {
    return { success: false, message: 'Supabase belum dikonfigurasi. Hubungi admin untuk mengatur koneksi database.' };
  }
  const { data, error } = await client.auth.signUp({
    email,
    password,
    options: { emailRedirectTo: window.location.origin }
  });
  if (error) {
    return { success: false, message: error.message || 'Gagal membuat akun baru.' };
  }
  if (!data.session) {
    // Project Supabase mewajibkan verifikasi email sebelum sesi aktif.
    return { success: true, needsEmailConfirmation: true, message: 'Akun berhasil dibuat. Silakan cek email Anda untuk verifikasi sebelum masuk.' };
  }
  return { success: true, session: data.session };
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

/**
 * Login dengan Google (OAuth).
 * BEDA dengan signInWithPassword: fungsi ini TIDAK langsung mengembalikan sesi,
 * karena browser akan dialihkan (redirect) ke halaman Google lalu kembali lagi
 * ke aplikasi ini. Setelah kembali, Supabase otomatis mendeteksi token dari URL
 * dan memicu listener `onAuthStateChange` yang sudah berjalan di App.tsx --
 * jadi tidak perlu penanganan sesi tambahan di pemanggil fungsi ini.
 *
 * PRASYARAT (dilakukan di luar kode, oleh admin/Anda sendiri):
 * 1. Buat OAuth Client ID di Google Cloud Console (jenis "Web application").
 * 2. Di Supabase Dashboard > Authentication > Providers > Google, aktifkan
 *    provider dan isi Client ID & Client Secret dari langkah 1.
 * 3. Di Google Cloud Console, tambahkan Authorized redirect URI persis:
 *    https://<project-ref>.supabase.co/auth/v1/callback
 *    (nilai <project-ref> sama dengan yang ada di VITE_SUPABASE_URL).
 */
export async function signInWithGoogle(): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) {
    return { success: false, message: 'Supabase belum dikonfigurasi. Hubungi admin untuk mengatur koneksi database.' };
  }
  const { error } = await client.auth.signInWithOAuth({
    provider: 'google',
    options: {
      // Kembali ke halaman aplikasi yang sedang dibuka setelah login Google selesai.
      redirectTo: window.location.origin
    }
  });
  if (error) {
    return { success: false, message: error.message || 'Gagal memulai login dengan Google.' };
  }
  // Tidak ada `return session` di sini -- browser sudah dialihkan ke Google.
  return { success: true };
}

export async function signOutSupabase(): Promise<void> {
  const client = getSupabaseClient();
  if (!client) return;
  await client.auth.signOut();
}

/**
 * Kirim email pemulihan kata sandi lewat Supabase Auth.
 * Dipakai oleh modal "Lupa Kata Sandi" di LoginPage.tsx.
 */
export async function resetPasswordForEmail(email: string): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) {
    return { success: false, message: 'Supabase belum dikonfigurasi. Hubungi admin untuk mengatur koneksi database.' };
  }
  const { error } = await client.auth.resetPasswordForEmail(email, {
    redirectTo: window.location.origin
  });
  if (error) {
    return { success: false, message: error.message || 'Gagal mengirim tautan pemulihan kata sandi.' };
  }
  return { success: true };
}
