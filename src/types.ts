export interface Pemasukan {
  id: string;
  noBukti: string;
  tanggal: string;
  sumber: string;
  sub: string;
  nominal: number;
  keterangan: string;
  status: string;
  siswaId?: string;
  createdAt?: string;
  createdBy?: string;
}

export interface Pengeluaran {
  id: string;
  noBukti: string;
  tanggal: string;
  kategori: string;
  nominal: number;
  keterangan: string;
  status: string;
  buktiUrl?: string;
  createdAt?: string;
  createdBy?: string;
}

export interface SiswaTagihan {
  id: string;
  nama: string;
  kelas: string;
  jenis: string;
  target: number;
  catatan?: string;
  createdAt?: string;
  createdBy?: string;
}

export interface MasterSumberDana {
  id: string;
  name: string;
  subs: string[];
}

export interface AuditLog {
  id: string;
  tabel_terkait: string;
  record_id: string;
  aksi: 'INSERT' | 'UPDATE' | 'DELETE';
  data_sebelum: any;
  data_sesudah: any;
  user_id: string;
  waktu: string;
}

export interface KonfigurasiLembaga {
  namaLembaga: string;
  jenisLembaga: string;
  logoUrl: string | null;
  saldoAwal: number;
  npsn?: string;
  alamat?: string;
  kontak?: string;
  website?: string;
  tahunAjaran?: string;
}

export interface PeriodePembukuan {
  id: string;
  namaPeriode: string;
  tahunAjaran: string;
  tanggalMulai: string;
  tanggalAkhir: string | null;
  saldoAwal: number;
  saldoAkhir: number | null;
  status: 'AKTIF' | 'DITUTUP';
  createdAt?: string;
  closedAt?: string;

  // Relasi periode sebelumnya
  periodeSebelumnyaId?: string | null;
}

export interface SupabaseConfig {
  url: string;
  anonKey: string;
  isConnected: boolean;
  useLocalStorage: boolean;
}

export interface UserSession {
  id: string;
  email: string;
  role: string;
}
