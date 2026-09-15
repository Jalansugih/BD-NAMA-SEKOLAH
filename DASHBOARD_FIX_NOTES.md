# Dashboard Financial Logic Fix — 2026-09-15

Perbaikan utama:

1. Dashboard tidak lagi memfilter kartu pemasukan/pengeluaran berdasarkan bulan kalender saat ini.
2. Kartu Total Pemasukan dan Total Pengeluaran memakai seluruh transaksi yang sudah disaring App.tsx berdasarkan periode pembukuan aktif.
3. Surplus/Defisit = Total Pemasukan - Total Pengeluaran.
4. Total Saldo Kas = Saldo Awal Periode + Total Pemasukan - Total Pengeluaran.
5. Grafik Cash Flow memakai bulan yang benar-benar terdapat pada data transaksi aktif, bukan hanya Juni–Agustus atau bulan sekarang.
6. Grafik menampilkan Pemasukan, Pengeluaran, dan Surplus/Defisit.
7. Sumber Pemasukan dihitung dari seluruh periode aktif, bukan bulan kalender sekarang.
8. Filter tanggal periode di App.tsx dinormalisasi agar YYYY-MM-DD dan ISO timestamp konsisten.
9. Transaksi terakhir di Dashboard menggunakan tanggal kalender yang dinormalisasi.

File yang berubah:
- src/components/DashboardView.tsx
- src/App.tsx

Catatan validasi:
- Source sudah diperiksa secara statis.
- Build Vite tidak dapat dijalankan di environment pemeriksaan karena executable `vite` tidak tersedia di node_modules hasil environment sementara. Jalankan `npm ci` lalu `npm run build` di mesin project.
