import { getSupabaseClient } from './supabase';
import { Pemasukan } from '../types';

/**
 * Pemasukan server-side.
 *
 * tenant_id tidak diambil dari form/user input.
 * tenant_id selalu diambil dari tenant_members melalui
 * RPC get_my_tenant_id() berdasarkan auth.uid().
 */

export async function fetchPemasukanFromSupabase(): Promise<Pemasukan[] | null> {
  const client = getSupabaseClient();
  if (!client) return null;

  try {
    const { data, error } = await client
      .from('pemasukan')
      .select('*')
      .order('tanggal', { ascending: false });

    if (error || !data) return null;

    return data.map((item: any) => ({
      id: item.id,
      noBukti: item.no_bukti || item.id,
      tanggal: item.tanggal,
      sumber: item.sumber,
      sub: item.sub,
      nominal: Number(item.nominal),
      keterangan: item.keterangan,
      status: item.status || 'Selesai',
      siswaId: item.siswa_id || undefined,
      createdAt: item.created_at,
      createdBy: item.created_by
    }));
  } catch {
    return null;
  }
}

export async function insertPemasukanSupabase(item: {
  noBukti: string;
  tanggal: string;
  sumber: string;
  sub: string;
  nominal: number;
  keterangan: string;
  status?: string;
}): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();

  if (!client) {
    return {
      success: false,
      message: 'Supabase belum terhubung.'
    };
  }

  try {
    /*
     * Ambil tenant berdasarkan user yang sedang login.
     * Tidak menerima tenant_id dari frontend.
     */
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

    /*
     * Insert dengan tenant_id milik user yang sedang login.
     */
    const { error } = await client
      .from('pemasukan')
      .insert([
        {
          no_bukti: item.noBukti,
          tanggal: item.tanggal,
          sumber: item.sumber,
          sub: item.sub,
          nominal: item.nominal,
          keterangan: item.keterangan,
          status: item.status || 'Selesai',
          tenant_id: tenantId
        }
      ]);

    if (error) {
      return {
        success: false,
        message: error.message
      };
    }

    return {
      success: true
    };
  } catch (err: any) {
    return {
      success: false,
      message: err?.message || 'Gagal menyimpan pemasukan.'
    };
  }
}

export async function deletePemasukanSupabase(
  id: string
): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();

  if (!client) {
    return {
      success: false,
      message: 'Supabase belum terhubung.'
    };
  }

  const { error } = await client
    .from('pemasukan')
    .delete()
    .eq('id', id);

  if (error) {
    return {
      success: false,
      message: error.message
    };
  }

  return {
    success: true
  };
}