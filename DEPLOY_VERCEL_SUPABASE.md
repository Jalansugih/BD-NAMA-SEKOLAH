# RajaKas Bendahara — Deploy Production

## 1. Supabase
Untuk database baru, jalankan SQL **berurutan** di SQL Editor:

1. `supabase/migration.sql` — membuat schema dasar (script ini RESET/DROP tabel; hanya untuk database baru atau setelah backup).
2. `supabase/cutoff_migration.sql` — menambah tahun ajaran + periode pembukuan.
3. `supabase/migration_v6_multi_tenant.sql` — menambah organisasi/profile dan isolasi tenant.
4. `supabase/migration_v7_multi_tenant.sql` — hardening tenant, RPC, RLS, dan Storage.
5. `supabase/patch_siswa_pembayaran_tenant.sql` — RPC pembayaran siswa tenant-aware.

`patch_master_pengaturan_tenant.sql` bersifat tambahan dan tidak wajib bila V7 berhasil dijalankan.

> Jangan menjalankan `migration.sql` pada database produksi yang sudah berisi data, karena file tersebut melakukan DROP tabel.

## 2. Authentication
Aktifkan Email/Password di Supabase Authentication.

Jika memakai Google OAuth, set callback Supabase sesuai project dan redirect URL aplikasi Vercel.

## 3. Storage
V7 membuat bucket otomatis:
- `logos` — public, maksimal 2 MB.
- `bukti-pengeluaran` — private, maksimal 10 MB.

Bukti pengeluaran disimpan di folder `<organization_id>/...` dan URL akses dibuat sementara saat data dimuat.

## 4. Vercel
Import repository ke Vercel dengan:
- Build Command: `npm run build`
- Output Directory: `dist`

Tambahkan Environment Variables:
- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Untuk production, jangan commit `.env.local`.

## 5. Setelah deploy
Uji dengan akun A dan akun B:
1. A membuat pemasukan/pengeluaran/siswa/master.
2. B login dan memastikan data A tidak terlihat.
3. A upload logo dan bukti pengeluaran.
4. Tutup buku dan pastikan periode berikutnya aktif.
5. Coba transaksi tanggal periode tertutup dan pastikan ditolak.
6. Reopen periode hanya boleh berhasil bila periode setelahnya belum memiliki transaksi.


## Final hardening
Setelah semua migration di atas berhasil, jalankan `supabase/FINAL_PRODUCTION_PATCH.sql`. Script ini tidak mereset data.
