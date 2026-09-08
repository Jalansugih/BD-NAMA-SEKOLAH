import { getSupabaseClient } from './supabase';
import { Pemasukan } from '../types';

/**
 * Pemasukan server-side.
 *
 * organization_id tidak diambil dari form/user input.
 * Database mengisi organization_id otomatis melalui
 * DEFAULT public.get_auth_org_id() dan RLS memvalidasi tenant.
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
     * organization_id ditentukan oleh database melalui DEFAULT
     * public.get_auth_org_id(). Frontend tidak boleh mengirim tenant id.
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
          status: item.status || 'Selesai'
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