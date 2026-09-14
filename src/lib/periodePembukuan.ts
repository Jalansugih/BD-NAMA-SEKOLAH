import { getSupabaseClient } from './supabase';
import { ensureUserSetup } from './userProvisioning';
import { PeriodePembukuan } from '../types';

const LOCAL_KEY = 'rajasch_periode_pembukuan_v1';

const mapRow = (row: any): PeriodePembukuan => ({
  id: row.id,
  namaPeriode: row.nama_periode,
  tahunAjaran: row.tahun_ajaran || row.nama_periode || '2025/2026',
  tanggalMulai: row.tanggal_mulai,
  tanggalAkhir: row.tanggal_akhir ?? null,
  saldoAwal: Number(row.saldo_awal || 0),
  saldoAkhir: row.saldo_akhir == null ? null : Number(row.saldo_akhir),
  status: row.status,
  createdAt: row.created_at,
  closedAt: row.closed_at || undefined
});

export function getLocalPeriodePembukuan(): PeriodePembukuan[] {
  try { return JSON.parse(localStorage.getItem(LOCAL_KEY) || '[]'); } catch { return []; }
}

function saveLocal(items: PeriodePembukuan[]) {
  localStorage.setItem(LOCAL_KEY, JSON.stringify(items));
}

export async function fetchPeriodePembukuan(): Promise<PeriodePembukuan[]> {
  const client = getSupabaseClient();
  if (!client) return getLocalPeriodePembukuan();
  const { data, error } = await client
    .from('periode_pembukuan')
    .select('*')
    .order('tanggal_mulai', { ascending: false });
  if (error || !data) return [];
  return data.map(mapRow);
}

export function getActivePeriode(items: PeriodePembukuan[]): PeriodePembukuan | null {
  return items.find(x => x.status === 'AKTIF') || null;
}


export async function updateTahunAjaranAktif(tahunAjaran: string): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) {
    const items = getLocalPeriodePembukuan();
    const idx = items.findIndex(x => x.status === 'AKTIF');
    if (idx >= 0) {
      items[idx] = { ...items[idx], tahunAjaran, namaPeriode: tahunAjaran };
      saveLocal(items);
    }
    return { success: true };
  }

  const setup = await ensureUserSetup();
  if (!setup.success) return { success: false, message: setup.message };

  const { data: active, error: readError } = await client
    .from('periode_pembukuan')
    .select('id, tanggal_mulai, saldo_awal')
    .eq('status', 'AKTIF')
    .order('tanggal_mulai', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (readError) return { success: false, message: readError.message };
  if (!active) return { success: false, message: 'Periode aktif tidak ditemukan di database.' };

  const { error } = await client.rpc('save_periode_aktif', {
    p_periode_id: active.id,
    p_tahun_ajaran: tahunAjaran,
    p_tanggal_mulai: active.tanggal_mulai,
    p_saldo_awal: Number(active.saldo_awal || 0)
  });

  if (error) return { success: false, message: error.message };
  return { success: true };
}

export async function updatePeriodeAktifSettings(
  id: string | null,
  tahunAjaran: string,
  tanggalMulai: string,
  saldoAwal: number
): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();

  if (!client) {
    const items = getLocalPeriodePembukuan();
    const idx = items.findIndex(x =>
      x.status === 'AKTIF' && (!id || x.id === id)
    );
    if (idx < 0) return { success: false, message: 'Periode aktif tidak ditemukan.' };

    items[idx] = {
      ...items[idx],
      namaPeriode: tahunAjaran,
      tahunAjaran,
      tanggalMulai,
      saldoAwal
    };
    saveLocal(items);
    return { success: true };
  }

  const setup = await ensureUserSetup();
  if (!setup.success) return { success: false, message: setup.message };

  const { data: active, error: readError } = await client
    .from('periode_pembukuan')
    .select('id')
    .eq('status', 'AKTIF')
    .order('tanggal_mulai', { ascending: false })
    .limit(1)
    .maybeSingle();

  if (readError) return { success: false, message: `Gagal membaca periode aktif: ${readError.message}` };

  const targetId = id || active?.id || null;
  if (!targetId) return { success: false, message: 'Periode aktif tidak ditemukan di database.' };

  const { error } = await client.rpc('save_periode_aktif', {
    p_periode_id: targetId,
    p_tahun_ajaran: tahunAjaran,
    p_tanggal_mulai: tanggalMulai,
    p_saldo_awal: saldoAwal
  });

  if (error) return { success: false, message: error.message };
  return { success: true };
}

export async function updateSaldoAwalPeriode(id: string, nominal: number): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) {
    const items = getLocalPeriodePembukuan();
    const idx = items.findIndex(x => x.id === id && x.status === 'AKTIF');
    if (idx < 0) return { success: false, message: 'Periode aktif tidak ditemukan.' };
    items[idx] = { ...items[idx], saldoAwal: nominal };
    saveLocal(items);
    return { success: true };
  }
  const setup = await ensureUserSetup();
  if (!setup.success) return { success: false, message: setup.message };

  const { data: active, error: readError } = await client
    .from('periode_pembukuan')
    .select('id, tahun_ajaran, tanggal_mulai')
    .eq('id', id)
    .eq('status', 'AKTIF')
    .maybeSingle();
  if (readError) return { success: false, message: readError.message };
  if (!active) return { success: false, message: 'Periode aktif tidak ditemukan di database.' };

  const { error } = await client.rpc('save_periode_aktif', {
    p_periode_id: active.id,
    p_tahun_ajaran: active.tahun_ajaran,
    p_tanggal_mulai: active.tanggal_mulai,
    p_saldo_awal: nominal
  });
  if (error) return { success: false, message: error.message };
  return { success: true };
}

export async function closePeriodePembukuan(
  id: string,
  tanggalCutoff: string
): Promise<{ success: boolean; data?: { saldoAkhir: number; periodeBerikutnya: PeriodePembukuan }; message?: string }> {
  const client = getSupabaseClient();

  if (!client) {
    const items = getLocalPeriodePembukuan();
    const idx = items.findIndex(x => x.id === id && x.status === 'AKTIF');
    if (idx < 0) return { success: false, message: 'Periode aktif tidak ditemukan.' };

    const current = items[idx];
    if (tanggalCutoff < current.tanggalMulai) {
      return { success: false, message: 'Tanggal cut-off tidak boleh sebelum tanggal mulai periode.' };
    }

    // Mode lokal hanya untuk demo. Produksi menghitung saldo melalui PostgreSQL.
    const saldoAkhir = current.saldoAwal;
    const closed = { ...current, tanggalAkhir: tanggalCutoff, status: 'DITUTUP' as const, saldoAkhir, closedAt: new Date().toISOString() };
    const nextYear = nextTahunAjaran(current.tahunAjaran);
    const next: PeriodePembukuan = {
      id: `PER-${Date.now()}`,
      namaPeriode: nextYear,
      tahunAjaran: nextYear,
      tanggalMulai: addDays(tanggalCutoff, 1),
      tanggalAkhir: null,
      saldoAwal: saldoAkhir,
      saldoAkhir: null,
      status: 'AKTIF',
      createdAt: new Date().toISOString()
    };
    saveLocal([next, closed, ...items.filter(x => x.id !== id)]);
    return { success: true, data: { saldoAkhir, periodeBerikutnya: next } };
  }

  const { data, error } = await client.rpc('tutup_buku', {
    p_periode_id: id,
    p_tanggal_cutoff: tanggalCutoff
  });

  if (error || !data) return { success: false, message: error?.message || 'Gagal melakukan Tutup Buku.' };

  const row = Array.isArray(data) ? data[0] : data;
  return {
    success: true,
    data: {
      saldoAkhir: Number(row.saldo_akhir || 0),
      periodeBerikutnya: mapRow(row.periode_berikutnya)
    }
  };
}

function nextTahunAjaran(value: string): string {
  const match = /^(\d{4})\/(\d{4})$/.exec(value.trim());
  if (!match) return value;
  return `${Number(match[1]) + 1}/${Number(match[2]) + 1}`;
}

function addDays(dateStr: string, days: number): string {
  const d = new Date(`${dateStr}T00:00:00`);
  d.setDate(d.getDate() + days);
  return d.toISOString().slice(0, 10);
}

export function defaultTanggalAkhirTahunAjaran(tahunAjaran: string): string {
  const match = /^(\d{4})\/(\d{4})$/.exec(tahunAjaran.trim());
  return match ? `${match[2]}-06-30` : new Date().toISOString().slice(0, 10);
}

export function defaultTanggalMulaiTahunAjaran(tahunAjaran: string): string {
  const match = /^(\d{4})\/(\d{4})$/.exec(tahunAjaran.trim());
  return match ? `${match[1]}-07-01` : new Date().toISOString().slice(0, 10);
}
