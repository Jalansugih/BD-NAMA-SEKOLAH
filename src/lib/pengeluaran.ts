import { getSupabaseClient, getCurrentOrganizationId } from './supabase';
import { Pengeluaran } from '../types';

/**
 * src/lib/pengeluaran.ts
 * Menjawab poin 13 panduan: pengeluaran dicatat lewat RPC
 * catat_pengeluaran() dengan validasi saldo server-side (Postgres trigger),
 * ID selalu dibuat server (UUID default), bukan generateNextId() di frontend.
 *
 * Termasuk dukungan upload "Nota / Kwitansi" (bukti_url) ke Supabase
 * Storage bucket "bukti-pengeluaran" -- lihat supabase/migration.sql.
 */

export async function fetchPengeluaranFromSupabase(): Promise<Pengeluaran[] | null> {
  const client = getSupabaseClient();
  if (!client) return null;
  try {
    const { data, error } = await client
      .from('pengeluaran')
      .select('*')
      .order('tanggal', { ascending: false });

    if (error || !data) return null;
    return data.map((item: any) => ({
      id: item.id,
      noBukti: item.no_bukti || item.id,
      tanggal: item.tanggal,
      kategori: item.kategori,
      nominal: Number(item.nominal),
      keterangan: item.keterangan,
      status: item.status || 'Terbayar',
      buktiUrl: item.bukti_url || undefined,
      createdAt: item.created_at,
      createdBy: item.created_by
    }));
  } catch {
    return null;
  }
}

/**
 * Upload file nota/kwitansi ke Supabase Storage bucket "bukti-pengeluaran"
 * dan kembalikan public URL-nya. Dipanggil SEBELUM rpcCatatPengeluaran,
 * agar bukti_url bisa langsung disertakan saat INSERT.
 *
 * MULTI-TENANT: path diberi prefix organization_id. Nama file lama sudah
 * acak sehingga tidak akan bertabrakan antar lembaga, tapi tanpa prefix ini
 * file nota SEMUA lembaga tetap tercampur rata di root bucket yang sama --
 * prefix ini yang jadi dasar pembatasan akses per-lembaga di Storage RLS
 * (lihat Bagian 9 supabase/migration_v6_multi_tenant.sql).
 */
export async function uploadBuktiPengeluaranToStorage(
  file: File
): Promise<{ success: boolean; url?: string; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  try {
    const orgId = await getCurrentOrganizationId();
    if (!orgId) {
      return { success: false, message: 'Tidak dapat menentukan lembaga aktif untuk sesi ini. Silakan login ulang.' };
    }

    const ext = file.name.split('.').pop() || 'jpg';
    const path = `${orgId}/${Date.now()}-${Math.random().toString(36).slice(2, 8)}.${ext}`;

    const { error: uploadError } = await client.storage
      .from('bukti-pengeluaran')
      .upload(path, file, { upsert: false, cacheControl: '3600' });

    if (uploadError) {
      return {
        success: false,
        message: `Gagal upload nota/kwitansi: ${uploadError.message}. Pastikan bucket "bukti-pengeluaran" sudah dibuat (lihat supabase/migration.sql).`
      };
    }

    const { data: publicUrlData } = client.storage.from('bukti-pengeluaran').getPublicUrl(path);
    return { success: true, url: publicUrlData.publicUrl };
  } catch (err: any) {
    return { success: false, message: err.message || 'Gagal upload nota/kwitansi' };
  }
}

export async function rpcCatatPengeluaran(item: {
  noBukti: string;
  tanggal: string;
  kategori: string;
  nominal: number;
  keterangan: string;
  status?: string;
  buktiUrl?: string;
}): Promise<{ success: boolean; data?: Pengeluaran; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase client belum dikonfigurasi.' };

  try {
    const { data, error } = await client.rpc('catat_pengeluaran', {
      p_no_bukti: item.noBukti,
      p_tanggal: item.tanggal,
      p_kategori: item.kategori,
      p_nominal: item.nominal,
      p_keterangan: item.keterangan,
      p_status: item.status || 'Terbayar',
      p_bukti_url: item.buktiUrl || null
    });

    if (error) return { success: false, message: error.message || 'Gagal mencatat pengeluaran.' };
    return { success: true, data };
  } catch (err: any) {
    return { success: false, message: err.message || 'Kesalahan koneksi RPC' };
  }
}

export async function deletePengeluaranSupabase(id: string): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };
  const { error } = await client.from('pengeluaran').delete().eq('id', id);
  if (error) return { success: false, message: error.message };
  return { success: true };
}
