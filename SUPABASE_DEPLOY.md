# RajaKas Bendahara — Supabase Deployment

## Database yang sudah pernah dipakai
Jalankan **hanya** `supabase/FINAL_REPAIR_2026_09.sql` sekali sebagai role `postgres` di Supabase SQL Editor.

Script ini memperbaiki fondasi `auth.users → profiles → organizations`, periode aktif, RPC profil, periode, pembayaran siswa, pengeluaran, Storage, dan RLS tanpa menghapus transaksi.

Setelah berhasil:
1. Logout dari aplikasi.
2. Hard refresh browser (`Ctrl+Shift+R`).
3. Login kembali.
4. Uji: Profil → Logo → Pengeluaran tanpa bukti → Pengeluaran dengan bukti → Pembayaran Siswa → Pengaturan Periode → Tutup Buku.

## Database baru
Gunakan migration inti secara berurutan sesuai versi yang dibutuhkan aplikasi, lalu jalankan `FINAL_REPAIR_2026_09.sql` sebagai hardening akhir.

## Catatan
- Jangan commit `.env.local` atau kredensial Supabase.
- `src/data/initialData.ts` hanya untuk Demo Lokal ketika Supabase belum dikonfigurasi.
