import { getSupabaseClient } from './supabase';

/**
 * Memastikan akun yang sedang login sudah memiliki seluruh fondasi data server:
 * profile -> organization -> konfigurasi lembaga -> periode aktif.
 *
 * RPC ini aman dipanggil berulang kali (idempotent). Tujuannya bukan membuat
 * data transaksi, melainkan memastikan user baru tidak masuk ke dashboard
 * dengan tenant/periode yang belum tersedia.
 */
export async function ensureUserSetup(): Promise<{
  success: boolean;
  organizationId?: string;
  message?: string;
}> {
  const client = getSupabaseClient();
  if (!client) {
    return { success: false, message: 'Supabase belum terhubung.' };
  }

  const { data: sessionData, error: sessionError } = await client.auth.getSession();
  if (sessionError || !sessionData.session?.user) {
    return { success: false, message: sessionError?.message || 'Sesi login tidak ditemukan.' };
  }

  const { data, error } = await client.rpc('ensure_user_setup');
  if (error) {
    return {
      success: false,
      message: error.message || 'Gagal menyiapkan data awal akun.'
    };
  }

  const row = Array.isArray(data) ? data[0] : data;
  if (!row?.organization_id) {
    return {
      success: false,
      message: 'Organisasi belum berhasil dibuat/ditemukan untuk akun ini.'
    };
  }

  return { success: true, organizationId: row.organization_id };
}
