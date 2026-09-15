# Hasil Perbaikan Audit

- Menghapus kredensial Supabase dummy `xyzcompany` dari jalur konfigurasi.
- Kredensial hanya dibaca dari `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`, atau pengaturan lokal yang sengaja disimpan pengguna.
- Mode belum terhubung kini tidak lagi mencoba mengakses endpoint Supabase palsu.
- Operasi database tetap harus melalui `getSupabaseClient()` dan memeriksa hasil `null`.

## Validasi lokal

```bash
npm ci
npm run lint
npm run build
```

Pastikan `.env.local` berisi kredensial Supabase nyata sebelum menguji transaksi produksi.
