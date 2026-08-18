import { getSupabaseClient } from './supabase';
import { KonfigurasiLembaga } from '../types';

/**
 * src/lib/configuration.ts
 * Menjawab poin 2 & 3 panduan: konfigurasi lembaga (nama, jenis, logo, saldo
 * awal, identitas lain) disimpan di Supabase (tabel konfigurasi_lembaga,
 * satu baris singleton), bukan lagi murni React State/hardcode.
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
    const { data, error } = await client
      .from('konfigurasi_lembaga')
      .select('*')
      .eq('id', true)
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

  const payload: Record<string, any> = { id: true, updated_at: new Date().toISOString() };
  if (patch.namaLembaga !== undefined) payload.nama_lembaga = patch.namaLembaga;
  if (patch.jenisLembaga !== undefined) payload.jenis_lembaga = patch.jenisLembaga;
  if (patch.npsn !== undefined) payload.npsn = patch.npsn;
  if (patch.alamat !== undefined) payload.alamat = patch.alamat;
  if (patch.kontak !== undefined) payload.kontak = patch.kontak;
  if (patch.website !== undefined) payload.website = patch.website;
  if (patch.tahunAjaran !== undefined) payload.tahun_ajaran = patch.tahunAjaran;

  const { error } = await client.from('konfigurasi_lembaga').upsert(payload, { onConflict: 'id' });
  if (error) return { success: false, message: error.message };
  return { success: true };
}

export async function saveSaldoAwal(nominal: number): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  const { error } = await client
    .from('konfigurasi_lembaga')
    .upsert({ id: true, saldo_awal: nominal, updated_at: new Date().toISOString() }, { onConflict: 'id' });

  if (error) return { success: false, message: error.message };
  return { success: true };
}

export async function saveLogoUrl(url: string | null): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  const { error } = await client
    .from('konfigurasi_lembaga')
    .upsert({ id: true, logo_url: url, updated_at: new Date().toISOString() }, { onConflict: 'id' });

  if (error) return { success: false, message: error.message };
  return { success: true };
}

/**
 * Upload logo ke Supabase Storage (bucket "logos") dan simpan URL publiknya
 * ke konfigurasi_lembaga. Poin 10 panduan: produksi TIDAK lagi memakai
 * Base64 di React State sebagai penyimpanan permanen logo.
 */
export async function uploadLogoToStorage(file: File): Promise<{ success: boolean; url?: string; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  try {
    const ext = file.name.split('.').pop() || 'png';
    const path = `logo-lembaga.${ext}`;

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
