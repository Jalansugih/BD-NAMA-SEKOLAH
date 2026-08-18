# RajaKas — Perubahan Tutup Buku & Tahun Ajaran

## Perubahan yang dibuat

1. `Reset Data & Kosongkan Dashboard` dihapus dari alur Pengaturan dan diganti menjadi `Tutup Buku (Cut-Off)`.
2. Tutup Buku tidak menghapus transaksi.
3. Saldo akhir periode dihitung oleh PostgreSQL melalui RPC `hitung_saldo_akhir_periode` / `tutup_buku`.
4. Saldo akhir periode lama otomatis menjadi `saldo_awal` periode berikutnya.
5. Setelah cut-off, transaksi bertanggal sebelum awal periode aktif dikunci di frontend dan database.
6. Tersedia `Buka Kembali` untuk membuka periode terakhir jika perlu koreksi.
7. `Tahun Ajaran Aktif` yang sebelumnya hard-code `2025/2026` sekarang bisa diubah user dengan format `YYYY/YYYY`.
8. Tahun ajaran ditampilkan dinamis di Navbar.
9. Perubahan lain pada nilai bisnis dan tampilan UI tidak disentuh.

## Wajib setelah deploy

Jalankan sekali file:

`supabase/cutoff_migration.sql`

di Supabase SQL Editor.

Migration ini bersifat non-destructive: tidak melakukan DROP tabel dan tidak menghapus transaksi.

## Catatan

Fitur edit transaksi belum ditambahkan karena pada versi sumber yang dikirim memang belum ada fungsi Edit transaksi; yang tersedia sebelumnya hanya Hapus. `Buka Kembali` disediakan agar periode dapat dibuka untuk koreksi tanpa menghapus histori.
