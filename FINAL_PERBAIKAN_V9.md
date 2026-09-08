# RajaKas Bendahara — Final Repair V9

## Tujuan

Versi ini menyelesaikan mismatch multi-tenant yang ditemukan pada database aktual:

- `organizations` dan `profiles.organization_id` sudah ada.
- Data lama masih memiliki `tenant_id`.
- `periode_pembukuan.organization_id` sudah ada.
- `konfigurasi_lembaga` belum memiliki `organization_id`.
- Provisioning lama tidak konsisten dengan kolom `organizations.name`.
- Aplikasi sebelumnya menganggap schema error sebagai "Supabase belum terhubung" lalu masuk Demo Lokal.

## Mapping data lama yang diverifikasi

`f511cf45-58fc-4466-8f35-5985b9c77fbd`
→ `be4c6030-f13b-4f4c-af0c-4ffd16942fe6`

Mapping ini hanya digunakan untuk data legacy yang sudah teridentifikasi.

## Cara menjalankan

1. **Backup database Supabase terlebih dahulu.**
2. Buka **Supabase Dashboard → SQL Editor**.
3. Jalankan hanya:

   `supabase/migration_v9_final_multitenant_repair.sql`

4. Tunggu sampai query selesai tanpa error.
5. Setelah itu buka aplikasi versi ini.
6. Hard refresh browser (`Ctrl+Shift+R`).
7. Login dengan user yang sudah ada.

## Setelah migration berhasil

Aplikasi menggunakan:

`auth.users → profiles → organizations → organization_id`

Untuk isolasi data:

- konfigurasi lembaga
- periode pembukuan
- kelas
- sumber dana
- kategori
- siswa/tagihan
- pemasukan
- pengeluaran
- audit log

`tenant_id` lama **belum dihapus**. Kolom tersebut dipertahankan sementara sebagai jejak legacy agar migrasi dapat diverifikasi terlebih dahulu.

## Perubahan aplikasi penting

Aplikasi **tidak lagi mengubah schema/database error menjadi Demo Lokal**.

Jika Supabase/schema bermasalah, aplikasi menampilkan error sebenarnya dan tidak merender data demo.

## Validasi pasca-migration

Jalankan:

```sql
SELECT table_name, column_name
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name IN (
    'konfigurasi_lembaga','master_kelas','master_kategori',
    'master_sumber_dana','siswa_tagihan','pemasukan',
    'pengeluaran','periode_pembukuan','audit_log'
  )
  AND column_name = 'organization_id'
ORDER BY table_name;
```

Semua tabel tersebut harus memiliki `organization_id`.

Kemudian:

```sql
SELECT
  p.email,
  p.organization_id,
  o.name AS organization_name
FROM public.profiles p
JOIN public.organizations o ON o.id = p.organization_id
ORDER BY p.email;
```

Harus tetap terlihat 4 user → 4 organization yang sudah ada.

## Catatan build

ZIP ini disiapkan berdasarkan source aplikasi yang ada. Validasi build penuh tetap perlu dilakukan di environment lokal karena `node_modules` pada environment pemeriksaan sebelumnya tidak lengkap.


## V9.1 — Perbaikan trigger cutoff sebelum backfill

V9.1 memperbaiki trigger legacy `cegah_update_transaksi_periode_tertutup()` yang sebelumnya memanggil `get_my_tenant_id()`. Pada saat migration/backfill dijalankan, `auth.uid()` tidak tersedia sehingga muncul `TENANT_TIDAK_DITEMUKAN`. Trigger sekarang berbasis `organization_id` dan mengizinkan operasi migration/service-role ketika `auth.uid()` NULL, sementara pengguna authenticated tetap terkena aturan cutoff.
