# RajaKas.id — Modul Bendahara · Panduan Deployment Supabase

Semua script dijalankan di **Supabase Dashboard → SQL Editor** sebagai role
`postgres`, satu per satu, **berurutan dari atas ke bawah**. Semua bersifat
idempotent (aman diulang) dan tidak menghapus baris transaksi.

---

## A. Database baru (sekolah / project Supabase baru)

| # | File | Isi |
|---|---|---|
| 1 | `supabase/migration.sql` | Skema dasar: tabel, audit log, RLS awal, bucket Storage |
| 2 | `supabase/migration_periode_pembukuan.sql` | Periode pembukuan / tutup buku |
| 3 | `supabase/cutoff_migration.sql` | Penguncian transaksi periode tertutup |
| 4 | `supabase/migration_v6_multi_tenant.sql` | Fondasi multi-tenant |
| 5 | `supabase/migration_v7_multi_tenant.sql` | Normalisasi ke `organization_id` + RLS tenant-aware |
| 6 | `supabase/migration_v8_user_provisioning.sql` | Provisioning user baru |
| 7 | `supabase/FINAL_REPAIR_2026_09.sql` | Penyelarasan identity chain + RPC + Storage + RLS |
| 8 | **`supabase/PATCH_V28_SALDO_KAS_GUARD.sql`** | **Wajib.** Mengembalikan validasi saldo kas server-side |
| 9 | `supabase/patch_storage_bukti_pengeluaran_multitenant.sql` | Isolasi folder Storage per organisasi |

Langkah 8 **tidak boleh dilewat**. Tanpa itu, `FINAL_REPAIR` meninggalkan
database tanpa view `saldo_kas` dan tanpa pemeriksaan saldo apa pun — saldo
kas bisa menjadi minus, atau setiap pencatatan pengeluaran gagal dengan
`relation "public.saldo_kas" does not exist`.

## B. Database yang sudah dipakai (sudah ada transaksi)

Jalankan hanya langkah **7 → 8 → 9** di atas, sesuai urutan itu.

## C. Setelah semua script selesai

1. **Storage** → pastikan bucket `logos` dan `bukti-pengeluaran` ada.
2. **Authentication → Providers → Google** → isi Client ID & Secret bila
   ingin login Google (lihat README).
3. **Authentication → URL Configuration** → isi Site URL dengan domain produksi.
4. Di aplikasi: logout → hard refresh (`Ctrl+Shift+R`) → login kembali.

## D. Uji terima (wajib sebelum diserahkan ke sekolah)

Jalankan dari aplikasi, bukan dari SQL Editor:

1. Daftar lembaga baru → Pengaturan → isi profil & logo → hapus logo → muat
   ulang halaman, logo harus tetap hilang.
2. Pengaturan Periode → set tahun ajaran, tanggal mulai, kas awal `0`.
3. Catat pemasukan **Rp 1.000.000**.
4. Catat pengeluaran **Rp 2.000.000** → **harus ditolak** `SALDO_TIDAK_CUKUP`.
5. Catat pengeluaran **Rp 1.000.000** dengan lampiran nota → berhasil, dan
   ikon nota di daftar pengeluaran bisa diklik untuk pratinjau.
6. Hapus pemasukan Rp 1.000.000 → **harus ditolak** `SALDO_TIDAK_CUKUP`.
7. Hapus pengeluarannya dulu, baru pemasukannya → berhasil.
8. Tagihan siswa → catat pembayaran → cek Laporan → pilih bulan pada filter
   periode, datanya harus muncul.
9. Tutup Buku → periode baru terbentuk dengan saldo awal = saldo akhir.
10. Buat akun sekolah kedua → pastikan tidak melihat satu pun data sekolah pertama.

---

## Catatan

- Jangan pernah commit `.env.local`. Isi `.env.example` hanyalah placeholder.
- `src/data/initialData.ts` **hanya** dipakai pada Mode Demo Lokal saat
  `npm run dev`. Pada build produksi, kegagalan koneksi database menampilkan
  layar error, bukan data contoh.
- `supabase/archive/` berisi migrasi lama dan migrasi milik project lain
  (BillingFlow). **Jangan dijalankan** di database sekolah.
