import { getSupabaseClient } from './supabase';
import { MasterSumberDana } from '../types';

/**
 * Master data disimpan di Supabase dan dipisahkan berdasarkan tenant user login.
 * tenant_id selalu diambil dari get_my_tenant_id(), bukan dari input UI.
 */

async function getTenantId(client: any): Promise<{ tenantId?: string; error?: string }> {
  const { data, error } = await client.rpc('get_my_tenant_id');
  if (error) return { error: `Gagal mendapatkan tenant: ${error.message}` };
  if (!data) return { error: 'TENANT_TIDAK_DITEMUKAN: User belum memiliki tenant.' };
  return { tenantId: data };
}

// ---------- MASTER KELAS ----------

export async function fetchMasterKelas(): Promise<string[] | null> {
  const client = getSupabaseClient();
  if (!client) return null;
  const { data, error } = await client
    .from('master_kelas')
    .select('nama')
    .order('urutan', { ascending: true });
  if (error || !data) return null;
  return data.map((r: any) => r.nama as string);
}

export async function insertMasterKelas(nama: string): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  const tenant = await getTenantId(client);
  if (!tenant.tenantId) return { success: false, message: tenant.error };

  const { error } = await client.from('master_kelas').insert([{
    nama,
    tenant_id: tenant.tenantId
  }]);
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
  const { data, error } = await client
    .from('master_sumber_dana')
    .select('*')
    .order('created_at', { ascending: true });
  if (error || !data) return null;
  return data.map((r: any) => ({ id: r.id, name: r.name, subs: r.subs || [] }));
}

export async function insertMasterSumberDana(item: MasterSumberDana): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  const tenant = await getTenantId(client);
  if (!tenant.tenantId) return { success: false, message: tenant.error };

  const { error } = await client.from('master_sumber_dana').insert([{
    id: item.id,
    name: item.name,
    subs: item.subs,
    tenant_id: tenant.tenantId
  }]);
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
  const { data, error } = await client
    .from('master_kategori')
    .select('nama')
    .order('created_at', { ascending: true });
  if (error || !data) return null;
  return data.map((r: any) => r.nama as string);
}

export async function insertMasterKategori(nama: string): Promise<{ success: boolean; message?: string }> {
  const client = getSupabaseClient();
  if (!client) return { success: false, message: 'Supabase belum terhubung.' };

  const tenant = await getTenantId(client);
  if (!tenant.tenantId) return { success: false, message: tenant.error };

  const { error } = await client.from('master_kategori').insert([{
    nama,
    tenant_id: tenant.tenantId
  }]);
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
