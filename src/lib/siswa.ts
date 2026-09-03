import { getSupabaseClient } from './supabase';
import { SiswaTagihan, Pemasukan } from '../types';

/**
 * Data siswa/tagihan dan pembayaran siswa disimpan di Supabase.
 *
 * Multi-tenant:
 * - tenant_id TIDAK berasal dari form/frontend.
 * - tenant_id diambil dari get_my_tenant_id() berdasarkan auth.uid().
 */

export async function fetchSiswaTagihan(): Promise<SiswaTagihan[] | null> {
  const client = getSupabaseClient();
  if (!client) return null;

  try {
    const { data, error } = await client
      .from('siswa_tagihan')
      .select('*')
      .order('created_at', { ascending: false });

    if (error || !data) return null;

    return data.map((item: any) => ({
      id: item.id,
      nama: item.nama,
      kelas: item.kelas,
      jenis: item.jenis,
      target: Number(item.target),
      catatan: item.catatan || '',
      createdAt: item.created_at,
      createdBy: item.created_by
    }));
  } catch {
    return null;
  }
}

export async function insertSiswaTagihan(data: {
  nama: string;
  kelas: string;
  jenis: string;
  target: number;
  catatan?: string;
}): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) {
    return { success: false, message: 'Supabase belum terhubung.' };
  }

  try {
    // Tenant ditentukan server berdasarkan user yang sedang login.
    const { data: tenantId, error: tenantError } = await client.rpc(
      'get_my_tenant_id'
    );

    if (tenantError) {
      return {
        success: false,
        message: `Gagal mendapatkan tenant: ${tenantError.message}`
      };
    }

    if (!tenantId) {
      return {
        success: false,
        message: 'TENANT_TIDAK_DITEMUKAN: User belum memiliki tenant.'
      };
    }

    const { error } = await client.from('siswa_tagihan').insert([{
      nama: data.nama,
      kelas: data.kelas,
      jenis: data.jenis,
      target: data.target,
      catatan: data.catatan || null,
      tenant_id: tenantId
    }]);

    if (error) {
      return { success: false, message: error.message };
    }

    return { success: true };
  } catch (err: any) {
    return {
      success: false,
      message: err?.message || 'Gagal menyimpan tagihan siswa.'
    };
  }
}

export async function deleteSiswaTagihan(
  id: string
): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) {
    return { success: false, message: 'Supabase belum terhubung.' };
  }

  const { error } = await client
    .from('siswa_tagihan')
    .delete()
    .eq('id', id);

  if (error) {
    return { success: false, message: error.message };
  }

  return { success: true };
}

/**
 * Catat pembayaran siswa melalui RPC.
 * Validasi siswa + insert pemasukan dilakukan atomic di database.
 */
export async function rpcCatatPembayaranSiswa(item: {
  siswaId: string;
  noBukti: string;
  tanggal: string;
  nominal: number;
  status?: string;
}): Promise<{ success: boolean; data?: Pemasukan; message?: string }> {
  const client = getSupabaseClient();

  if (!client) {
    return {
      success: false,
      message: 'Supabase client belum dikonfigurasi.'
    };
  }

  try {
    const { data, error } = await client.rpc('catat_pembayaran_siswa', {
      p_siswa_id: item.siswaId,
      p_no_bukti: item.noBukti,
      p_tanggal: item.tanggal,
      p_status: item.status || 'Selesai',
      p_nominal: item.nominal
    });

    if (error) {
      return {
        success: false,
        message: error.message || 'Gagal mencatat pembayaran siswa.'
      };
    }

    return { success: true, data };
  } catch (err: any) {
    return {
      success: false,
      message: err?.message || 'Kesalahan koneksi RPC.'
    };
  }
}
