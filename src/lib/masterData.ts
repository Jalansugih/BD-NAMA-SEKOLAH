import { getSupabaseClient } from './supabase';
import { MasterSumberDana } from '../types';

/**
 * src/lib/masterData.ts
 * Menjawab poin 8 panduan: Kelas, Sumber Dana, dan Kategori Pengeluaran
 * disimpan & diubah lewat Supabase, bukan lagi hanya array di React State.
 */

// ---------- MASTER KELAS ----------

export async function fetchMasterKelas(): Promise<string[] | null> {
  const client = getSupabaseClient();
  if (!client) return null;
  const { data, error } = await client.from('master_kelas').select('nama').order('urutan', { ascending: true });
  if (error || !data) return null;
  return data.map((r: any) => r.nama as string);
}

export async function insertMasterKelas(nama: string): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };
  const { error } = await client.from('master_kelas').insert([{ nama }]);
  if (error) return { success: false, message: error.message };
  return { success: true };
}

export async function deleteMasterKelas(nama: string): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };
  const { error } = await client.from('master_kelas').delete().eq('nama', nama);
  if (error) return { success: false, message: error.message };
  return { success: true };
}

// ---------- MASTER SUMBER DANA ----------

export async function fetchMasterSumberDana(): Promise<MasterSumberDana[] | null> {
  const client = getSupabaseClient();
  if (!client) return null;
  const { data, error } = await client.from('master_sumber_dana').select('*').order('created_at', { ascending: true });
  if (error || !data) return null;
  return data.map((r: any) => ({ id: r.id, name: r.name, subs: r.subs || [] }));
}

export async function insertMasterSumberDana(item: MasterSumberDana): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };
  const { error } = await client.from('master_sumber_dana').insert([{ id: item.id, name: item.name, subs: item.subs }]);
  if (error) return { success: false, message: error.message };
  return { success: true };
}

export async function deleteMasterSumberDana(id: string): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };
  const { error } = await client.from('master_sumber_dana').delete().eq('id', id);
  if (error) return { success: false, message: error.message };
  return { success: true };
}

// ---------- MASTER KATEGORI PENGELUARAN ----------

export async function fetchMasterKategori(): Promise<string[] | null> {
  const client = getSupabaseClient();
  if (!client) return null;
  const { data, error } = await client.from('master_kategori').select('nama').order('created_at', { ascending: true });
  if (error || !data) return null;
  return data.map((r: any) => r.nama as string);
}

export async function insertMasterKategori(nama: string): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };
  const { error } = await client.from('master_kategori').insert([{ nama }]);
  if (error) return { success: false, message: error.message };
  return { success: true };
}

export async function deleteMasterKategori(nama: string): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };
  const { error } = await client.from('master_kategori').delete().eq('nama', nama);
  if (error) return { success: false, message: error.message };
  return { success: true };
}
