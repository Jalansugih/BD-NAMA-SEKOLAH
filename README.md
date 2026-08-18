# RajaKas.id — Modul Bendahara

Aplikasi manajemen keuangan sekolah (pemasukan, pengeluaran, tagihan siswa,
laporan) dengan backend Supabase (Postgres + Auth).

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
2. Buka **SQL Editor** di dashboard Supabase, tempel seluruh isi file
   `supabase/migration.sql`, lalu klik **Run**. Ini membuat semua tabel,
   trigger validasi saldo, audit log, dan Row Level Security.
3. Buka **Authentication > Users > Add User**, buat akun untuk bendahara
   (email + password). Akun ini yang dipakai login di aplikasi.
4. Buka **Project Settings > API**, salin **Project URL** dan **anon public
   key**, masukkan ke `VITE_SUPABASE_URL` / `VITE_SUPABASE_ANON_KEY`.

## Deploy ke server gratis

Lihat panduan langkah-demi-langkah di chat (Vercel/Netlify + Supabase).

## Keamanan

- Semua tabel dilindungi Row Level Security: hanya pengguna yang login
  (`auth.role() = 'authenticated'`) yang bisa membaca/menulis data.
- Validasi saldo kas dan audit log berjalan di level database (trigger),
  bukan cuma di frontend, jadi tidak bisa dilewati.
- Jangan pernah commit `.env.local` ke git (sudah ada di `.gitignore`).
