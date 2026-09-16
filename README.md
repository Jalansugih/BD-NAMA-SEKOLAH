# RajaKas.id — Modul Bendahara

Aplikasi manajemen keuangan sekolah (pemasukan, pengeluaran, tagihan siswa,
laporan) dengan backend Supabase (Postgres + Auth), **multi-tenant**: setiap
lembaga/sekolah yang mendaftar (lewat email/password atau Google) otomatis
mendapat ruang data sendiri yang terisolasi dari lembaga lain.

## Menjalankan secara lokal

**Prasyarat:** Node.js 18+

1. `npm install`
2. Salin `.env.example` menjadi `.env.local`, lalu isi `VITE_SUPABASE_URL`
   dan `VITE_SUPABASE_ANON_KEY` dari project Supabase Anda (lihat bagian
   "Setup Supabase" di bawah). Kalau dikosongkan, aplikasi jalan dalam
   **Mode Demo Lokal** (data hanya tersimpan di browser, tanpa login).
3. `npm run dev`

## Setup Supabase (wajib untuk data yang aman & permanen)

1. Daftar gratis di https://supabase.com dan buat project baru (region
   Singapore paling dekat untuk pengguna Indonesia).
2. Buka **SQL Editor** di dashboard Supabase dan jalankan script pada
   folder `supabase/` **berurutan sesuai tabel di `SUPABASE_DEPLOY.md`**
   (9 langkah untuk database baru, 3 langkah untuk database yang sudah
   dipakai). Jangan menjalankan apa pun dari `supabase/archive/`.

   Langkah `PATCH_V28_SALDO_KAS_GUARD.sql` bersifat **wajib** — tanpa itu
   validasi saldo kas di level database tidak aktif.

3. Buka **Project Settings > API**, salin **Project URL** dan **anon public
   key**, masukkan ke `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`.
4. (Opsional, tapi disarankan) Buat dua bucket di **Storage**: `logos`
   (Public) dan `bukti-pengeluaran` (Public) — lihat bagian akhir
   `supabase/migration.sql` untuk policy-nya.

Dengan langkah di atas, akun bendahara **tidak perlu dibuat manual** lagi
lewat Authentication > Users — cukup daftar sendiri dari halaman login
aplikasi (lihat bagian berikut).

## Login & Daftar (email/password + Google, multi-tenant)

Halaman login (`src/components/LoginPage.tsx`) punya dua mode: **Masuk**
dan **Daftar Lembaga Baru**. Keduanya mendukung email/password maupun
Google:

- **Daftar** (email/password atau tombol Google) → membuat akun
  `auth.users` baru di Supabase. Trigger `on_auth_user_created_multi_tenant`
  (dari `migration_v6_multi_tenant.sql`) otomatis:
  1. Membuat baris baru di `organizations` untuk lembaga ini.
  2. Membuat baris `profiles` yang menghubungkan user ↔ organisasi
     tersebut dengan role `owner`.
  3. Membuat baris awal `konfigurasi_lembaga` (kosong, diisi lewat menu
     Pengaturan) untuk organisasi tersebut.
- **Masuk** (email/password atau Google) untuk akun yang sudah pernah
  daftar → langsung masuk ke organisasi yang sama seperti sebelumnya
  (trigger tidak berjalan lagi karena baris `auth.users` sudah ada).
- Semua tabel data (`pemasukan`, `pengeluaran`, `siswa_tagihan`,
  `master_kelas`, `master_kategori`, `audit_log`, `konfigurasi_lembaga`,
  `periode_pembukuan`) punya kolom `organization_id` dan RLS yang membatasi
  setiap lembaga hanya bisa melihat/mengubah datanya sendiri.

### Mengaktifkan Login Google (wajib agar tombol "Masuk/Daftar dengan
Google" berfungsi)

1. Di **Google Cloud Console**, buat **OAuth Client ID** bertipe
   "Web application".
2. Tambahkan **Authorized redirect URI** persis:
   `https://<project-ref>.supabase.co/auth/v1/callback`
   (`<project-ref>` = bagian depan `VITE_SUPABASE_URL` Anda, sebelum
   `.supabase.co`).
3. Tambahkan juga domain tempat aplikasi ini di-deploy (mis.
   `https://nama-app-anda.vercel.app`) ke **Authorized JavaScript
   origins**.
4. Di **Supabase Dashboard > Authentication > Providers > Google**,
   aktifkan provider dan isi **Client ID** & **Client Secret** dari
   langkah 1.
5. Di **Supabase Dashboard > Authentication > URL Configuration**,
   pastikan **Site URL** diisi dengan domain produksi aplikasi Anda (dan
   tambahkan domain preview/staging ke **Redirect URLs** kalau ada), supaya
   pengguna diarahkan kembali ke aplikasi yang benar setelah login Google.

Kalau provider Google belum diaktifkan di Supabase, tombol Google akan
menampilkan pesan error yang jelas (bukan diam-diam gagal).

## Deploy ke server gratis

Lihat panduan langkah-demi-langkah di chat (Vercel/Netlify + Supabase).

## Keamanan

- Semua tabel dilindungi Row Level Security **per-organisasi**: setiap
  lembaga hanya bisa membaca/menulis datanya sendiri
  (`organization_id = get_auth_org_id()`), bukan sekadar "siapapun yang
  login" seperti pada versi single-tenant awal.
- Validasi saldo kas dan audit log berjalan di level database (trigger +
  RPC), bukan cuma di frontend, jadi tidak bisa dilewati. Ini dipulihkan
  oleh `supabase/PATCH_V28_SALDO_KAS_GUARD.sql` — pastikan sudah dijalankan.
- Fungsi `tutup_buku`/`buka_kembali_periode`/`hitung_saldo_akhir_periode`
  memfilter `organization_id` secara eksplisit di dalam kode SQL-nya
  sendiri (bukan hanya mengandalkan RLS), karena fungsi-fungsi ini berjalan
  sebagai `SECURITY DEFINER`.
- Upload logo lembaga disimpan per-akun (folder `<user_id>/...` di bucket
  Storage `logos`) supaya logo satu lembaga tidak menimpa logo lembaga
  lain.
- Jangan pernah commit `.env.local` ke git (sudah ada di `.gitignore`).


## Supabase — Repair Produksi

Untuk database yang sudah pernah dipakai, gunakan **hanya** `supabase/FINAL_REPAIR_2026_09.sql` sebagai repair/hardening akhir. Script ini menyelaraskan identity chain `auth.users → profiles → organizations → konfigurasi → periode aktif`, RPC transaksi, Storage, dan RLS tanpa menghapus transaksi.

Panduan lengkap ada di `SUPABASE_DEPLOY.md`.


### Perbaikan upload bukti pengeluaran (multi-tenant)
Jika upload nota menghasilkan `new row violates row-level security policy`, jalankan `supabase/patch_storage_bukti_pengeluaran_multitenant.sql` sekali di Supabase SQL Editor. Versi ini menyamakan path Storage dengan `organization_id` yang digunakan RLS.
