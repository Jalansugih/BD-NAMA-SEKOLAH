import { Pemasukan, Pengeluaran, SiswaTagihan, MasterSumberDana, AuditLog } from '../types';

export const INITIAL_MASTER_KELAS = ['Kelas 1', 'Kelas 2', 'Kelas 3', 'Kelas 4', 'Kelas 5', 'Kelas 6'];

export const INITIAL_MASTER_SUMBER: MasterSumberDana[] = [
  { id: 'BOS', name: 'Dana BOS', subs: ['BOS Reguler', 'BOS Kinerja', 'Tahap 1', 'Tahap 2', 'Tahap 3'] },
  { id: 'Infak', name: 'Infak / Donasi Orang Tua', subs: ['Infak Jumat', 'Infak Pembangunan'] },
  { id: 'Pembayaran', name: 'Pembayaran Siswa', subs: ['SPP Bulanan', 'Daftar Ulang', 'Seragam', 'Ujian', 'Study Tour', 'Ekstrakurikuler'] },
  { id: 'Donasi', name: 'Donasi / CSR', subs: ['CSR BUMN', 'Donasi Alumni', 'Hibah Pemda'] }
];

export const INITIAL_MASTER_KATEGORI = [
  'Honor Guru & Staf', 'ATK & Cetak', 'Listrik & Air', 'Internet & Wifi',
  'Pemeliharaan Bangunan', 'BPJS & Kesehatan', 'Operasional Kantor', 'Transport & Perdin'
];

export const INITIAL_PEMASUKAN: Pemasukan[] = [
  { id: 'IN-001', noBukti: 'KW-BOS-0801', tanggal: '2026-08-01', sumber: 'BOS', sub: 'BOS Reguler Tahap 2', nominal: 35000000, keterangan: 'Pencairan Dana BOS Reguler Tahap 2 T.A 2025/2026', status: 'Verifikasi' },
  { id: 'IN-002', noBukti: 'KW-SPP-0803', tanggal: '2026-08-03', sumber: 'Pembayaran', sub: 'SPP Bulanan', nominal: 18500000, keterangan: 'Penerimaan SPP Siswa Kelas 1 - 6 Bulan Agustus', status: 'Selesai' },
  { id: 'IN-003', noBukti: 'KW-INF-0805', tanggal: '2026-08-05', sumber: 'Infak', sub: 'Kelas 1', nominal: 4000000, keterangan: 'Infak Pembangunan Murid Baru Kelas 1A', status: 'Selesai' },
  { id: 'IN-004', noBukti: 'KW-SRG-0810', tanggal: '2026-08-10', sumber: 'Pembayaran', sub: 'Seragam', nominal: 4000000, keterangan: 'Pelunasan Seragam Sekolah Kelas 1', status: 'Selesai' },
  { id: 'IN-005', noBukti: 'KW-CSR-0812', tanggal: '2026-08-12', sumber: 'Donasi', sub: 'CSR BUMN', nominal: 7000000, keterangan: 'Bantuan Digitalisasi Kelas dari Bank Mandiri', status: 'Selesai' },
  { id: 'IN-006', noBukti: 'KW-INF-0620', tanggal: '2026-06-20', sumber: 'Infak', sub: 'Infak Pembangunan', nominal: 2000000, keterangan: 'Cicilan 1 - Infak Pembangunan a.n Ahmad Fauzi', status: 'Selesai', siswaId: 'ST-001' },
  { id: 'IN-007', noBukti: 'KW-INF-0805', tanggal: '2026-08-05', sumber: 'Infak', sub: 'Infak Pembangunan', nominal: 1200000, keterangan: 'Cicilan 2 - Infak Pembangunan a.n Ahmad Fauzi', status: 'Selesai', siswaId: 'ST-001' },
  { id: 'IN-008', noBukti: 'KW-INF-0715', tanggal: '2026-07-15', sumber: 'Infak', sub: 'Infak Pembangunan', nominal: 3000000, keterangan: 'Pelunasan Infak Pembangunan a.n Siti Aisyah', status: 'Selesai', siswaId: 'ST-002' }
];

export const INITIAL_PENGELUARAN: Pengeluaran[] = [
  { id: 'OUT-001', noBukti: 'NT-0802-01', tanggal: '2026-08-02', kategori: 'Honor Guru & Staf', nominal: 15000000, keterangan: 'Honorarium Guru Non-ASN & Staf TU Bulan Juli', status: 'Terbayar' },
  { id: 'OUT-002', noBukti: 'NT-0804-01', tanggal: '2026-08-04', kategori: 'Listrik & Air', nominal: 2400000, keterangan: 'Pembayaran Rekening Listrik PLN & PDAM', status: 'Terbayar' },
  { id: 'OUT-003', noBukti: 'NT-0806-01', tanggal: '2026-08-06', kategori: 'ATK & Cetak', nominal: 3250000, keterangan: 'Pembelian Kertas HVS, Tinta Printer & Buku Raport', status: 'Terbayar' },
  { id: 'OUT-004', noBukti: 'NT-0808-01', tanggal: '2026-08-08', kategori: 'Internet & Wifi', nominal: 1500000, keterangan: 'Langganan Internet IndiHome 100 Mbps', status: 'Terbayar' },
  { id: 'OUT-005', noBukti: 'NT-0811-01', tanggal: '2026-08-11', kategori: 'Pemeliharaan Bangunan', nominal: 3500000, keterangan: 'Perbaikan Atap Ruang Guru & pengecatan pagar', status: 'Terbayar' }
];

export const INITIAL_SISWA_TAGIHAN: SiswaTagihan[] = [
  { id: 'ST-001', nama: 'Ahmad Fauzi', kelas: 'Kelas 3', jenis: 'Infak Pembangunan', target: 4000000, catatan: 'Cicilan disepakati s.d Desember' },
  { id: 'ST-002', nama: 'Siti Aisyah', kelas: 'Kelas 2', jenis: 'Infak Pembangunan', target: 3000000, catatan: 'Lunas' },
  { id: 'ST-003', nama: 'Muhammad Iqbal', kelas: 'Kelas 4', jenis: 'SPP Bulanan', target: 2100000, catatan: 'Cicilan 3 bulan tertunggak' }
];

export const INITIAL_AUDIT_LOGS: AuditLog[] = [
  {
    id: 'a1b2c3d4-0001-4000-8000-000000000001',
    tabel_terkait: 'pemasukan',
    record_id: 'IN-001',
    aksi: 'INSERT',
    data_sebelum: null,
    data_sesudah: { id: 'IN-001', no_bukti: 'KW-BOS-0801', nominal: 35000000, keterangan: 'Pencairan Dana BOS Reguler' },
    user_id: 'bendahara_main',
    waktu: '2026-08-01T08:30:00.000Z'
  },
  {
    id: 'a1b2c3d4-0002-4000-8000-000000000002',
    tabel_terkait: 'pengeluaran',
    record_id: 'OUT-001',
    aksi: 'INSERT',
    data_sebelum: null,
    data_sesudah: { id: 'OUT-001', no_bukti: 'NT-0802-01', nominal: 15000000, keterangan: 'Honorarium Guru Non-ASN' },
    user_id: 'bendahara_main',
    waktu: '2026-08-02T10:15:00.000Z'
  },
  {
    id: 'a1b2c3d4-0003-4000-8000-000000000003',
    tabel_terkait: 'siswa_tagihan',
    record_id: 'ST-001',
    aksi: 'INSERT',
    data_sebelum: null,
    data_sesudah: { id: 'ST-001', nama: 'Ahmad Fauzi', target: 4000000 },
    user_id: 'bendahara_main',
    waktu: '2026-08-03T11:00:00.000Z'
  }
];
