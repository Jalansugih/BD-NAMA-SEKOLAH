import { createClient, SupabaseClient, Session } from '@supabase/supabase-js';

const STORAGE_KEY_URL = 'rajasch_supabase_url';
const STORAGE_KEY_KEY = 'rajasch_supabase_anon_key';

/**
 * Mengambil kredensial Supabase.
 *
 * Prioritas:
 * 1. Environment variable VITE_SUPABASE_URL
 * 2. Environment variable VITE_SUPABASE_ANON_KEY
 * 3. localStorage (khusus development / konfigurasi lokal)
 *
 * Tidak ada credential dummy/fallback palsu.
 */
export function getSavedSupabaseCredentials(): {
  url: string;
  key: string;
} {
  const envUrl =
    (import.meta as any).env?.VITE_SUPABASE_URL?.trim() || '';

  const envKey =
    (import.meta as any).env?.VITE_SUPABASE_ANON_KEY?.trim() || '';

  const storedUrl =
    typeof window !== 'undefined'
      ? localStorage.getItem(STORAGE_KEY_URL)?.trim() || ''
      : '';

  const storedKey =
    typeof window !== 'undefined'
      ? localStorage.getItem(STORAGE_KEY_KEY)?.trim() || ''
      : '';

  return {
    url: envUrl || storedUrl,
    key: envKey || storedKey,
  };
}

/**
 * Singleton Supabase client.
 */
let supabaseInstance: SupabaseClient | null = null;

/**
 * Membuat / mengambil Supabase client.
 */
export function getSupabaseClient(): SupabaseClient | null {
  const { url, key } = getSavedSupabaseCredentials();

  if (!url || !key) {
    return null;
  }

  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(url)) {
    console.warn('[Supabase] URL tidak valid:', url);
    return null;
  }

  if (!supabaseInstance) {
    try {
      supabaseInstance = createClient(url, key);
    } catch (err) {
      console.error(
        '[Supabase] Gagal membuat client:',
        err
      );

      supabaseInstance = null;
    }
  }

  return supabaseInstance;
}

/**
 * Menyimpan konfigurasi Supabase dari menu konfigurasi lokal.
 *
 * Catatan:
 * Environment variable tetap menjadi prioritas.
 */
export function resetSupabaseClient(
  url: string,
  key: string
): void {
  const cleanUrl = url.trim();
  const cleanKey = key.trim();

  if (cleanUrl && cleanKey) {
    localStorage.setItem(STORAGE_KEY_URL, cleanUrl);
    localStorage.setItem(STORAGE_KEY_KEY, cleanKey);

    try {
      supabaseInstance = createClient(
        cleanUrl,
        cleanKey
      );
    } catch (err) {
      console.error(
        '[Supabase] Gagal membuat client baru:',
        err
      );

      supabaseInstance = null;
    }

    return;
  }

  localStorage.removeItem(STORAGE_KEY_URL);
  localStorage.removeItem(STORAGE_KEY_KEY);

  supabaseInstance = null;
}

/**
 * Menguji koneksi Supabase sekaligus memastikan
 * tabel utama aplikasi dapat diakses.
 */
export async function testSupabaseConnection(
  urlInput?: string,
  keyInput?: string
): Promise<{
  success: boolean;
  message: string;
}> {
  const saved = getSavedSupabaseCredentials();

  const url = urlInput?.trim() || saved.url;
  const key = keyInput?.trim() || saved.key;

  if (!url || !key) {
    return {
      success: false,
      message:
        'Kredensial Supabase belum diatur. Sediakan URL dan Anon Key yang valid.',
    };
  }

  if (!/^https:\/\/[a-z0-9-]+\.supabase\.co\/?$/.test(url)) {
    return {
      success: false,
      message:
        'URL Supabase tidak valid. Pastikan menggunakan URL project Supabase yang benar.',
    };
  }

  try {
    const testClient = createClient(url, key);

    const { error } = await testClient
      .from('konfigurasi_lembaga')
      .select('id')
      .limit(1);

    if (error) {
      const relationMissing =
        error.code === '42P01' ||
        error.message
          ?.toLowerCase()
          .includes('relation') &&
        error.message
          ?.toLowerCase()
          .includes('does not exist');

      if (relationMissing) {
        return {
          success: false,
          message:
            'Koneksi Supabase berhasil, tetapi tabel konfigurasi_lembaga belum tersedia.',
        };
      }

      return {
        success: false,
        message: `Supabase terhubung tetapi akses database gagal: ${error.message}`,
      };
    }

    return {
      success: true,
      message:
        'Koneksi Supabase aktif dan database dapat diakses.',
    };
  } catch (err: any) {
    console.error(
      '[Supabase] Connection test error:',
      err
    );

    return {
      success: false,
      message:
        err?.message ||
        'Gagal terhubung ke Supabase. Periksa koneksi internet dan konfigurasi.',
    };
  }
}

// ============================================================================
// AUTH SESSION
// ============================================================================

/**
 * Mengambil session Supabase yang sedang aktif.
 */
export async function getCurrentSession(): Promise<Session | null> {
  const client = getSupabaseClient();

  if (!client) {
    return null;
  }

  try {
    const { data, error } =
      await client.auth.getSession();

    if (error) {
      console.error(
        '[Auth] Gagal mengambil session:',
        error
      );

      return null;
    }

    return data.session;
  } catch (err) {
    console.error(
      '[Auth] getCurrentSession error:',
      err
    );

    return null;
  }
}

/**
 * Listener perubahan autentikasi:
 *
 * - SIGNED_IN
 * - SIGNED_OUT
 * - TOKEN_REFRESHED
 * - USER_UPDATED
 * - dll.
 */
export function onAuthStateChange(
  callback: (session: Session | null) => void
): () => void {
  const client = getSupabaseClient();

  if (!client) {
    return () => {};
  }

  const {
    data: { subscription },
  } = client.auth.onAuthStateChange(
    (_event, session) => {
      callback(session);
    }
  );

  return () => {
    subscription.unsubscribe();
  };
}

/**
 * Login menggunakan email + password.
 *
 * Tidak ada fallback login lokal.
 */
export async function signInWithPassword(
  email: string,
  password: string
): Promise<{
  success: boolean;
  session?: Session;
  message?: string;
}> {
  const client = getSupabaseClient();

  if (!client) {
    return {
      success: false,
      message:
        'Supabase belum dikonfigurasi. Silakan hubungi administrator.',
    };
  }

  try {
    const cleanEmail = email.trim();

    const { data, error } =
      await client.auth.signInWithPassword({
        email: cleanEmail,
        password,
      });

    if (error) {
      console.error(
        '[Auth] Login gagal:',
        error
      );

      return {
        success: false,
        message:
          'Email atau kata sandi tidak benar.',
      };
    }

    if (!data.session) {
      return {
        success: false,
        message:
          'Login tidak menghasilkan session yang valid.',
      };
    }

    return {
      success: true,
      session: data.session,
    };
  } catch (err) {
    console.error(
      '[Auth] signInWithPassword error:',
      err
    );

    return {
      success: false,
      message:
        'Terjadi kesalahan saat proses login.',
    };
  }
}

/**
 * Reset / logout session.
 */
export async function signOutSupabase(): Promise<{
  success: boolean;
  message?: string;
}> {
  const client = getSupabaseClient();

  if (!client) {
    return {
      success: false,
      message:
        'Supabase belum dikonfigurasi.',
    };
  }

  try {
    const { error } =
      await client.auth.signOut();

    if (error) {
      console.error(
        '[Auth] Logout gagal:',
        error
      );

      return {
        success: false,
        message: error.message,
      };
    }

    return {
      success: true,
    };
  } catch (err: any) {
    console.error(
      '[Auth] signOut error:',
      err
    );

    return {
      success: false,
      message:
        err?.message ||
        'Gagal melakukan logout.',
    };
  }
}

/**
 * Mengirim email reset password melalui Supabase Auth.
 */
export async function resetPasswordForEmail(
  email: string,
  redirectTo?: string
): Promise<{
  success: boolean;
  message?: string;
}> {
  const client = getSupabaseClient();

  if (!client) {
    return {
      success: false,
      message:
        'Supabase belum dikonfigurasi.',
    };
  }

  const cleanEmail = email.trim();

  if (!cleanEmail) {
    return {
      success: false,
      message:
        'Email wajib diisi.',
    };
  }

  try {
    const redirectUrl =
      redirectTo ||
      `${window.location.origin}/reset-password`;

    const { error } =
      await client.auth.resetPasswordForEmail(
        cleanEmail,
        {
          redirectTo: redirectUrl,
        }
      );

    if (error) {
      console.error(
        '[Auth] Reset password gagal:',
        error
      );

      return {
        success: false,
        message: error.message,
      };
    }

    return {
      success: true,
      message:
        'Email reset kata sandi telah dikirim. Silakan periksa email Anda.',
    };
  } catch (err: any) {
    console.error(
      '[Auth] resetPasswordForEmail error:',
      err
    );

    return {
      success: false,
      message:
        err?.message ||
        'Gagal mengirim email reset kata sandi.',
    };
  }
}