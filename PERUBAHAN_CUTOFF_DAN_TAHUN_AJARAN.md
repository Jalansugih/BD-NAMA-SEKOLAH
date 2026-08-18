# RajaKas — Perubahan Terbatas: Tutup Buku & Tahun Ajaran

Baseline yang digunakan: `perbaikan ke 19.zip`.

## File yang berubah
Hanya 8 file:
- `src/App.tsx`
- `src/types.ts`
- `src/components/DashboardView.tsx`
- `src/components/Navbar.tsx`
- `src/components/PengaturanView.tsx`
- `src/lib/configuration.ts`
- `src/lib/periodePembukuan.ts`
- `supabase/cutoff_migration.sql`

## Perubahan yang disengaja

### 1. Reset → Tutup Buku (Cut-Off)
- Tombol Reset massal dihapus dari UI.
- Diganti dengan `Tutup Buku (Cut-Off)`.
- Tidak ada DELETE massal.
- PostgreSQL menghitung saldo akhir berdasarkan transaksi di database.
- Periode lama menjadi `DITUTUP`.
- Sistem membuat periode berikutnya `AKTIF`.
- `saldo_akhir` periode lama menjadi `saldo_awal` periode baru.
- Transaksi lama tetap ada.
- Database menolak penghapusan/perubahan transaksi dari periode yang sudah ditutup.
- Mekanisme buka kembali periode terakhir tersedia di database untuk kebutuhan koreksi berikutnya, tetapi tombol Edit transaksi belum dibuat sesuai instruksi pengguna.

### 2. Tahun Ajaran Aktif custom
- `2025/2026` tidak lagi readonly.
- Format yang diterima: `YYYY/YYYY`.
- Nilai disimpan di `konfigurasi_lembaga.tahun_ajaran`.
- Nilai periode aktif ikut disinkronkan.
- Navbar dan label Dashboard mengikuti Tahun Ajaran aktif.

### 3. Perbaikan khusus data yang ditemukan
Database saat ini menunjukkan `tanggal_mulai = 1900-01-01`.
Migration baru memperbaikinya menjadi 1 Juli tahun pertama pada `tahun_ajaran` (untuk `2025/2026` → `2025-07-01`), tanpa mengubah atau menghapus transaksi.

## Yang TIDAK dilakukan
- Tidak membuat fitur Edit transaksi.
- Tidak mengubah desain UI utama.
- Tidak mengubah modul Pemasukan/Pengeluaran/Siswa/Master/Audit selain integrasi yang diperlukan untuk cut-off.
- Tidak menghapus data transaksi.
- Tidak menjalankan DROP tabel.

## Penting
`supabase/cutoff_migration.sql` adalah migration tambahan baru. Jangan menjalankan file migration lama lagi. Jalankan file ini satu kali setelah source baru dipasang/siap diuji.


### Update lanjutan — Pengaturan Periode Aktif

Pengaturan periode sekarang menggunakan tiga nilai yang dapat diatur user:
- Tahun Ajaran Aktif (`YYYY/YYYY`)
- Tanggal Mulai Periode (date picker)
- Saldo Awal

Ketiganya disimpan melalui tombol `Simpan`. Untuk mode Supabase, nilai periode aktif disimpan ke `periode_pembukuan`, sementara Tahun Ajaran dan Saldo Awal juga disinkronkan ke `konfigurasi_lembaga`. Tidak ada transaksi yang dihapus.


## Perbaikan v2.1

Penyimpanan periode aktif sekarang memverifikasi/mencari row `status = AKTIF` langsung dari Supabase bila ID periode di React state belum tersedia atau stale. Setelah penyimpanan, daftar periode dimuat ulang dari database.


## v2.2 fix
- Menghapus penyimpanan `tahun_ajaran` ke `konfigurasi_lembaga`. Sumber utama Tahun Ajaran adalah `periode_pembukuan`, sesuai schema database RajaKas yang tersedia.
