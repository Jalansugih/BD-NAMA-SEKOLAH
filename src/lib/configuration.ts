import { getSupabaseClient, getCurrentOrganizationId } from './supabase';
import { KonfigurasiLembaga } from '../types';

/**
 * src/lib/configuration.ts
 * Menjawab poin 2 & 3 panduan: konfigurasi lembaga (nama, jenis, logo, saldo
 * awal, identitas lain) disimpan di Supabase (tabel konfigurasi_lembaga).
 *
 * MULTI-TENANT (lihat supabase/migration_v6_multi_tenant.sql): tabel ini
 * sekarang SATU BARIS PER ORGANISASI (organization_id sebagai PRIMARY KEY),
 * bukan lagi singleton global (id = true). Baca & tulis TIDAK lagi
 * menyebutkan organization_id secara manual -- RLS otomatis membatasi baris
 * yang terlihat ke lembaga milik user yang sedang login, dan RPC
 * save_konfigurasi_lembaga() di sisi server yang menyelesaikan
 * organization_id dari sesi login.
 */

const DEFAULT_CONFIG: KonfigurasiLembaga = {
  namaLembaga: '',
  jenisLembaga: 'SD',
  logoUrl: null,
  saldoAwal: 0,
  tahunAjaran: '2025/2026'
};

export async function fetchKonfigurasiLembaga(): Promise<KonfigurasiLembaga | null> {
  const client = getSupabaseClient();
  if (!client) return null;
  try {
    // Tidak ada filter organization_id di sini -- RLS ("organization_id =
    // get_auth_org_id()") sudah membatasi query ini hanya melihat SATU baris
    // milik lembaga user yang sedang login, bukan seluruh baris di tabel.
    const { data, error } = await client
      .from('konfigurasi_lembaga')
      .select('*')
      .maybeSingle();

    if (error || !data) return null;
    return {
      namaLembaga: data.nama_lembaga || '',
      jenisLembaga: data.jenis_lembaga || 'SD',
      logoUrl: data.logo_url || null,
      saldoAwal: Number(data.saldo_awal) || 0,
      npsn: data.npsn || '',
      alamat: data.alamat || '',
      kontak: data.kontak || '',
      website: data.website || '',
      tahunAjaran: data.tahun_ajaran || '2025/2026'
    };
  } catch {
    return null;
  }
}

/** Konfigurasi default dipakai HANYA untuk mode Demo Lokal (tanpa Supabase). */
export function getDefaultConfiguration(): KonfigurasiLembaga {
  return { ...DEFAULT_CONFIG };
}

export async function saveKonfigurasiLembaga(
  patch: Partial<Pick<KonfigurasiLembaga, 'namaLembaga' | 'jenisLembaga' | 'npsn' | 'alamat' | 'kontak' | 'website' | 'tahunAjaran'>>
): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  // RPC ini (dibuat di migration_v6_multi_tenant.sql) menyelesaikan
  // organization_id dari sesi login di server -- frontend tidak pernah
  // menyimpan/mengirim organization_id sendiri. Semua parameter opsional:
  // hanya field yang dikirim (bukan undefined) yang diperbarui.
  const { error } = await client.rpc('save_konfigurasi_lembaga', {
    p_nama_lembaga: patch.namaLembaga,
    p_jenis_lembaga: patch.jenisLembaga,
    p_npsn: patch.npsn,
    p_alamat: patch.alamat,
    p_kontak: patch.kontak,
    p_website: patch.website,
    p_tahun_ajaran: patch.tahunAjaran
  });

  if (error) return { success: false, message: error.message };
  return { success: true };
}

export async function saveSaldoAwal(nominal: number): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  const { error } = await client.rpc('save_konfigurasi_lembaga', {
    p_saldo_awal: nominal
  });

  if (error) return { success: false, message: error.message };
  return { success: true };
}

export async function saveLogoUrl(url: string | null): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  const { error } = await client.rpc('save_konfigurasi_lembaga', {
    p_logo_url: url,
    p_clear_logo: url === null
  });

  if (error) return { success: false, message: error.message };
  return { success: true };
}

/**
 * Upload logo ke Supabase Storage (bucket "logos") dan simpan URL publiknya
 * ke konfigurasi_lembaga. Poin 10 panduan: produksi TIDAK lagi memakai
 * Base64 di React State sebagai penyimpanan permanen logo.
 *
 * MULTI-TENANT: path file WAJIB diberi prefix organization_id. Bucket
 * "logos" dipakai bersama oleh SEMUA lembaga -- tanpa prefix ini, dua
 * lembaga yang upload logo akan saling MENIMPA file satu sama lain karena
 * sebelumnya nama filenya selalu sama ("logo-lembaga.<ext>").
 */
export async function uploadLogoToStorage(file: File): Promise<{ success: boolean; url?: string; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  try {
    const orgId = await getCurrentOrganizationId();
    if (!orgId) {
      return { success: false, message: 'Tidak dapat menentukan lembaga aktif untuk sesi ini. Silakan login ulang.' };
    }

    const ext = file.name.split('.').pop() || 'png';
    const path = `${orgId}/logo-lembaga.${ext}`;

    const { error: uploadError } = await client.storage
      .from('logos')
      .upload(path, file, { upsert: true, cacheControl: '3600' });

    if (uploadError) {
      return { success: false, message: `Gagal upload ke Storage: ${uploadError.message}. Pastikan bucket "logos" sudah dibuat (lihat supabase/migration.sql).` };
    }

    const { data: publicUrlData } = client.storage.from('logos').getPublicUrl(path);
    const publicUrl = `${publicUrlData.publicUrl}?t=${Date.now()}`;

    const saveRes = await saveLogoUrl(publicUrl);
    if (!saveRes.success) return { success: false, message: saveRes.message };

    return { success: true, url: publicUrl };
  } catch (err: any) {
    return { success: false, message: err.message || 'Gagal upload logo' };
  }
}
