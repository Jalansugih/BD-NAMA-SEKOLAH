import { getSupabaseClient } from './supabase';
import { ensureUserSetup } from './userProvisioning';
import { Pemasukan } from '../types';

/**
 * src/lib/pemasukan.ts
 * Menjawab poin 5 & 12 panduan: pemasukan benar-benar server-side dan ID
 * dibuat oleh database (UUID default), bukan generateNextId() di frontend.
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

/**
 * Pencatatan pemasukan lewat RPC `catat_pemasukan` (PATCH_V28).
 *
 * Sebelumnya ini adalah `.insert()` polos yang bergantung sepenuhnya pada
 * DEFAULT `get_auth_org_id()` di kolom organization_id. Bila default itu
 * tidak ada di salah satu database, insert gagal dengan NOT NULL violation.
 * RPC menyamakan polanya dengan pengeluaran & pembayaran siswa: organisasi,
 * periode aktif, dan validasi nominal ditentukan server.
 */
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
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  try {
    const setup = await ensureUserSetup();
    if (!setup.success) return { success: false, message: setup.message };

    const { error } = await client.rpc('catat_pemasukan', {
      p_no_bukti: item.noBukti,
      p_tanggal: item.tanggal,
      p_sumber: item.sumber,
      p_sub: item.sub,
      p_nominal: item.nominal,
      p_keterangan: item.keterangan,
      p_status: item.status || 'Selesai'
    });

    if (error) return { success: false, message: error.message };
    return { success: true };
  } catch (err: any) {
    return { success: false, message: err.message || 'Kesalahan koneksi RPC' };
  }
}

export async function deletePemasukanSupabase(id: string): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };
  const { error } = await client.from('pemasukan').delete().eq('id', id);
  if (error) return { success: false, message: error.message };
  return { success: true };
}
