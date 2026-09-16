# Catatan Perbaikan — Versi Final

## 🔴 Blocker yang diperbaiki

### 1. Validasi saldo kas server-side dikembalikan → `supabase/PATCH_V28_SALDO_KAS_GUARD.sql`
`FINAL_REPAIR_2026_09.sql` baris 112 menjalankan `DROP VIEW IF EXISTS public.saldo_kas`
tanpa pernah membuatnya kembali, sementara RPC `catat_pengeluaran` versi FINAL
tidak memeriksa saldo sama sekali. Patch V28:

- Membuat fungsi `hitung_saldo_kas_berjalan(org)` — basisnya
  `periode_pembukuan.saldo_awal` + transaksi **dalam rentang periode aktif**,
  sama persis dengan angka yang ditampilkan aplikasi (sebelumnya database
  memakai `konfigurasi_lembaga.saldo_awal` tanpa batas periode — dua sumber
  kebenaran yang bisa berbeda).
- Membuat ulang view `saldo_kas` sebagai tenant-aware `security_invoker`.
- Mengganti trigger `check_saldo_sebelum_pengeluaran()` dengan versi yang
  memfilter `organization_id` secara eksplisit.
- Menambahkan cek saldo di dalam RPC `catat_pengeluaran` (pesan error yang
  terbaca bendahara, sebelum transaksi dibuat).
- **Trigger baru**: hapus / turunkan nominal pemasukan ditolak bila membuat
  saldo minus. Sebelumnya "catat 5jt → belanja 5jt → hapus pemasukannya"
  menghasilkan saldo −5jt tanpa penolakan.
- RPC baru `catat_pemasukan`, menggantikan `.insert()` polos dari browser.
- Trigger kunci periode (`cutoff_migration.sql`) kini memfilter
  `organization_id`. Sebelumnya, karena dipicu dari RPC `SECURITY DEFINER`
  (RLS di-bypass), trigger melihat periode **seluruh sekolah** dan sekolah A
  bisa tertolak gara-gara periode sekolah B.

### 2. Mode Demo Lokal dikunci ke development
`ALLOW_DEMO_MODE = import.meta.env.DEV`. Pada build produksi, kegagalan
koneksi Supabase menampilkan layar error dengan tombol "Coba Hubungkan Lagi",
bukan sesi palsu `demo_local` berisi data contoh yang bisa disangka nyata.

### 3. Regresi `saveLogoUrl` (layar putih)
`App.tsx` memanggil `saveLogoUrl(null)` tanpa mengimpornya — `vite build`
tetap lolos karena esbuild tidak melakukan typecheck, sehingga bug ini masuk
produksi. Klik "Hapus Logo" = `ReferenceError` = layar putih total.
Impor diperbaiki, dan gerbangnya dipasang (lihat di bawah).

---

## 🟠 Perbaikan lain

- **`npm run build` sekarang menjalankan typecheck lebih dulu**
  (`tsc --noEmit && vite build`). Kesalahan seperti nomor 3 di atas tidak bisa
  lolos ke produksi lagi. Typecheck saat ini **bersih (0 error)**.
- **`prebuild` → `node scripts/check-env.mjs` diaktifkan.** Script ini
  sebelumnya kode mati: `dotenv` tidak ada di dependencies dan tidak pernah
  dipanggil. Sekarang build **gagal** kalau `VITE_SUPABASE_URL` /
  `VITE_SUPABASE_ANON_KEY` belum diisi di Vercel.
- **Error Boundary** (`src/components/ErrorBoundary.tsx`) — error render tidak
  lagi menghasilkan layar putih tanpa pesan.
- **File yatim dihapus**: `lib/actions/invoice-actions.ts` dan
  `types/database.ts` (re-export ke file yang tidak ada, sisa project
  BillingFlow) — penyebab 2 dari 3 error typecheck.
- **13 migrasi BillingFlow dipindah** ke `supabase/archive/billingflow/`
  (`invoices`, `products`, `inventory`, `vendors`, `purchases`). Kalau tidak
  sengaja dijalankan di database sekolah, hasilnya tabel sampah atau error.
- **`.env.example` dijadikan placeholder**; kredensial Supabase asli dihapus,
  `.env.local` tidak lagi ikut dalam paket.
- **Code splitting**: bundle 1 file 1.007 kB → `index` 398 kB + `charts`
  388 kB + `supabase` 219 kB. Chart dan Supabase SDK jarang berubah, jadi
  cache browser awet antar rilis.
- `package.json` `"react-example" 0.0.0` → `"rajakas-bendahara" 1.0.0`;
  `metadata.json` dibersihkan dari sisa AI Studio / Gemini; folder kosong
  `assets/.aistudio/` dihapus.
- `SUPABASE_DEPLOY.md` ditulis ulang: urutan migrasi yang pasti untuk database
  baru maupun lama, plus checklist uji terima 10 langkah.

---

## ⚠️ Yang SENGAJA belum diubah

**Bucket `bukti-pengeluaran` masih publik.** Patch multi-tenant sebelumnya
sudah membereskan isolasi **tulis** (upload hanya ke folder organisasi
sendiri), tapi policy bacanya masih `TO public` tanpa filter organisasi —
siapa pun yang punya URL bisa membuka nota keuangan sekolah mana pun.

Memperbaikinya butuh perubahan yang tidak aman dilakukan tanpa pengujian di
data nyata: bucket diubah PRIVATE, dan kolom `bukti_url` yang selama ini
menyimpan *public URL* harus dimigrasi menjadi *path* saja, lalu frontend
memanggil `createSignedUrl()` setiap kali menampilkan. URL lama yang sudah
tersimpan di database akan mati kalau bucket langsung diprivate.

Saran: kerjakan ini sebagai patch V29 terpisah, dengan backup dulu.

---

## Validasi yang sudah dijalankan pada paket ini

```
npx tsc --noEmit     → 0 error
npm run build        → prebuild env-check jalan, build sukses
```

Uji fungsional terhadap database sungguhan **belum** dilakukan — itu langkah
Anda, mengikuti checklist bagian D di `SUPABASE_DEPLOY.md`.
