import { getSupabaseClient } from './supabase';
import { KonfigurasiLembaga } from '../types';

/**
 * src/lib/configuration.ts
 * Menjawab poin 2 & 3 panduan: konfigurasi lembaga (nama, jenis, logo, saldo
 * awal, identitas lain) disimpan di Supabase (tabel konfigurasi_lembaga).
 *
 * PENTING (perbaikan multi-tenant): sejak supabase/migration_v6_multi_tenant.sql,
 * tabel `konfigurasi_lembaga` BUKAN LAGI singleton dengan kolom `id BOOLEAN`.
 * Schema Bendahara sekarang menggunakan `tenant_id` dan RLS tenant-scoped.
 * Fetch tidak perlu memaksakan tenant_id dari browser; database menentukan
 * baris yang boleh dibaca melalui `get_my_tenant_id()`.
 * Save memakai RPC server-side agar tenant_id tidak dapat dipalsukan oleh client.
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
    // Tidak ada filter tenant_id dari browser. RLS pada tabel
    // konfigurasi_lembaga memastikan hanya baris tenant user yang login
    // yang dapat terlihat. Karena konfigurasi adalah singleton per tenant,
    // maybeSingle() menghasilkan maksimal satu baris.
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
 * Nama file menggunakan user id + timestamp agar file antar user
 * (multi-tenant) tidak saling menimpa file logo satu sama lain di bucket
 * Storage yang sama.
 */
export async function uploadLogoToStorage(file: File): Promise<{ success: boolean; url?: string; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  try {
    const { data: userData } = await client.auth.getUser();
    const uid = userData?.user?.id || 'anon';
    const ext = file.name.split('.').pop() || 'png';
    const path = `${uid}/logo-lembaga.${ext}`;

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
