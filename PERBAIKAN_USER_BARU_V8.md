# Perbaikan User Baru — V8

## Masalah yang ditemukan

1. Schema aplikasi sudah memakai `organization_id`, tetapi beberapa file frontend masih memakai `tenant_id` dan RPC `get_my_tenant_id()`.
2. `testSupabaseConnection()` masih mengecek `tenant_id` pada `konfigurasi_lembaga`.
3. Provisioning user hanya mengandalkan trigger lama. User yang trigger-nya pernah gagal tidak otomatis diperbaiki saat login.
4. Setelah login, dashboard sebelumnya dapat memuat data sebelum fondasi akun/tenant/periode dipastikan tersedia.
5. Patch lama `patch_master_pengaturan_tenant.sql` dan `patch_siswa_pembayaran_tenant.sql` masih berbasis schema `tenant_id`, sehingga berbahaya jika dijalankan pada V7.

## Perbaikan V8

- Frontend diseragamkan ke `organization_id` + `get_auth_org_id()`.
- Ditambahkan `src/lib/userProvisioning.ts`.
- Ditambahkan RPC `ensure_user_setup()`.
- Ditambahkan helper server-side `provision_user_account(...)`.
- Trigger `on_auth_user_created_multi_tenant` diperbarui agar provisioning tidak bergantung pada `auth.uid()` saat trigger berjalan.
- User lama yang belum memiliki profile/organization/config/periode diperbaiki otomatis oleh repair sekali jalan pada migrasi dan saat login berikutnya.
- Satu periode aktif dijamin unik per organization.
- Default periode user baru mengikuti tahun ajaran berjalan berdasarkan tanggal server (mulai 1 Juli).
- Ditambahkan RPC `catat_pembayaran_siswa()` versi `organization_id`.
- Patch tenant lama diberi status OBSOLETE agar tidak lagi dijalankan.

## Urutan SQL

`migration.sql` → `migration_periode_pembukuan.sql` → `cutoff_migration.sql` → `migration_v6_multi_tenant.sql` → `migration_v7_multi_tenant.sql` → `migration_v8_user_provisioning.sql`.

Jika database sudah sampai V7, cukup jalankan `migration_v8_user_provisioning.sql`.

## Validasi

Source sudah diperiksa secara statis dan tidak lagi memiliki referensi `get_my_tenant_id`, `get_my_organization_id`, atau `tenant_id` di `src/`.
Build/lint lokal belum dapat dinyatakan berhasil karena `node_modules` pada environment pemeriksaan tidak lengkap (`vite` tidak tersedia dan type definitions TypeScript hilang).
