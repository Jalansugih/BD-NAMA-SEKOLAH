import { getSupabaseClient } from './supabase';
import { AuditLog } from '../types';

/**
 * src/lib/audit.ts
 * Poin 15 panduan: audit tetap dicatat lewat trigger database. Frontend
 * hanya MEMBACA audit_log dari Supabase -- tidak pernah menulis audit log
 * lokal sebagai sumber produksi.
 */

export async function fetchAuditLogsFromSupabase(): Promise<AuditLog[] | null> {
  const client = getSupabaseClient();
  if (!client) return null;
  try {
    const { data, error } = await client
      .from('audit_log')
      .select('*')
      .order('waktu', { ascending: false })
      .limit(50);

    if (error || !data) return null;
    return data as AuditLog[];
  } catch {
    return null;
  }
}
