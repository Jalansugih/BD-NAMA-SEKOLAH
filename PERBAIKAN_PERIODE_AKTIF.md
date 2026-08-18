# Perbaikan Pengaturan Periode Aktif

Perubahan utama:
- Penyimpanan periode aktif selalu membaca baris `status = AKTIF` langsung dari Supabase.
- ID periode dari React state tidak lagi dijadikan sumber kebenaran.
- Jika belum ada periode AKTIF, aplikasi membuat periode baru.
- Setelah berhasil, App memuat ulang periode dari database.

Tidak ada penghapusan atau perubahan terhadap transaksi.
