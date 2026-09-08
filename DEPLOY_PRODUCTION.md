# RajaKas Bendahara — Production Deployment

## Supabase

Untuk database yang sudah memiliki schema/transaksi lama:

1. Backup database.
2. Jangan jalankan migration_v6_multi_tenant.sql lagi.
3. Jangan jalankan migration_v7_multi_tenant.sql lagi.
4. Jalankan `supabase/FINAL_PRODUCTION_FIX_V8.sql` sebagai satu script di Supabase SQL Editor.
5. Pastikan hasilnya `Success` tanpa error.

Migration V8 memperbaiki dependency view `saldo_kas`, backfill tanpa auth.uid(), tenant RLS, periode per tenant, dan kompatibilitas RPC buka_kembali_buku.

## Vercel

Environment Variables:

- `VITE_SUPABASE_URL`
- `VITE_SUPABASE_ANON_KEY`

Jangan commit `.env.local`.

Build:

```bash
npm install
npm run build
```

Deploy folder hasil build Vite: `dist`.
