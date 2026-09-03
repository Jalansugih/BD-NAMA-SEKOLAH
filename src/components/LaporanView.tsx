import React, { useState } from 'react';
import { Printer, RefreshCw, Upload, Download, FileSpreadsheet } from 'lucide-react';
import { Pemasukan, Pengeluaran, SiswaTagihan } from '../types';

interface LaporanViewProps {
  pemasukanList: Pemasukan[];
  pengeluaranList: Pengeluaran[];
  currentLembaga: string;
  logoDataUrl: string | null;
  saldoAwal: number;
  formatRupiah: (val: number) => string;
  onLogoUpload: (e: React.ChangeEvent<HTMLInputElement>) => void;
  masterKelas: string[];
  siswaTagihanList: SiswaTagihan[];
}

export const LaporanView: React.FC<LaporanViewProps> = ({
  pemasukanList,
  pengeluaranList,
  currentLembaga,
  logoDataUrl,
  saldoAwal,
  formatRupiah,
  onLogoUpload,
  masterKelas,
  siswaTagihanList
}) => {
  const [selectedReportType, setSelectedReportType] = useState('Buku Kas Umum (BKU)');
  const [customReportType, setCustomReportType] = useState('');
  const [reportMonth, setReportMonth] = useState('Agustus 2026');
  const [selectedKelas, setSelectedKelas] = useState('Semua Kelas');
  const printDate = new Date().toLocaleDateString('id-ID', { day: 'numeric', month: 'long', year: 'numeric' });

  const reportType = selectedReportType === 'Lainnya' 
    ? (customReportType.trim() || 'Laporan Custom') 
    : selectedReportType;

  // Month mapping to prefix YYYY-MM
  const getMonthPrefix = (label: string) => {
    if (label.includes('Agustus')) return '2026-08';
    if (label.includes('Juli')) return '2026-07';
    if (label.includes('Juni')) return '2026-06';
    return '2026-08';
  };

  const periodPrefix = getMonthPrefix(reportMonth);

  // Setiap Jenis Laporan Administrasi punya "mode" tampilan & filter data yang berbeda.
  const isBKU = selectedReportType === 'Buku Kas Umum (BKU)';
  const isRekapPemasukan = selectedReportType === 'Rekapitulasi Pemasukan';
  const isRekapPengeluaran = selectedReportType === 'Rekapitulasi Pengeluaran';
  const isSaldoPosisi = selectedReportType === 'Saldo & Posisi Kas';
  const isPertanggungjawaban = selectedReportType === 'Pertanggungjawaban Bulanan';
  const isStudentPaymentReport = selectedReportType === 'Infaq / Pembayaran Siswa';

  const getTransactionKelas = (tx: Pemasukan) => {
    if (tx.siswaId) return siswaTagihanList.find(s => s.id === tx.siswaId)?.kelas || '';
    if (tx.sumber === 'Infak') return masterKelas.includes(tx.sub) ? tx.sub : '';
    return '';
  };

  // Uang masuk yang benar-benar berasal dari menu Pembayaran Siswa (Infak per-siswa / SPP / dsb),
  // bukan sekadar semua jenis pemasukan (BOS, Donasi, dsb).
  const isSiswaPayment = (tx: Pemasukan) => !!tx.siswaId || tx.sumber === 'Pembayaran';

  // All transactions sorted chronologically for BKU
  const allTxSorted = [
    ...pemasukanList.map(x => ({ ...x, type: 'IN' as const })),
    ...pengeluaranList.map(x => ({ ...x, type: 'OUT' as const }))
  ].sort((a, b) => new Date(a.tanggal).getTime() - new Date(b.tanggal).getTime());

  let saldoAwalPeriode = saldoAwal;
  const txDalamPeriode: typeof allTxSorted = [];

  allTxSorted.forEach(tx => {
    const txPrefix = (tx.tanggal || '').slice(0, 7);
    if (txPrefix === periodPrefix) {
      txDalamPeriode.push(tx);
    } else if (txPrefix < periodPrefix) {
      saldoAwalPeriode += (tx.type === 'IN' ? tx.nominal : -tx.nominal);
    }
  });

  let totalIn = 0;
  let totalOut = 0;
  txDalamPeriode.forEach(tx => {
    if (tx.type === 'IN') totalIn += tx.nominal;
    if (tx.type === 'OUT') totalOut += tx.nominal;
  });

  const finalBalance = saldoAwalPeriode + totalIn - totalOut;

  // Rekapitulasi Pemasukan: seluruh transaksi pemasukan pada periode (semua sumber dana).
  const pemasukanDalamPeriode = txDalamPeriode.filter(tx => tx.type === 'IN') as Array<Pemasukan & { type: 'IN' }>;
  // Rekapitulasi Pengeluaran: seluruh transaksi pengeluaran pada periode (semua kategori).
  const pengeluaranDalamPeriode = txDalamPeriode.filter(tx => tx.type === 'OUT') as Array<Pengeluaran & { type: 'OUT' }>;

  // Infaq / Pembayaran Siswa: hanya uang masuk dari menu Pembayaran Siswa, difilter per kelas.
  const laporanSiswaDalamPeriode = pemasukanDalamPeriode.filter(tx => {
    if (!isSiswaPayment(tx)) return false;
    const kelas = getTransactionKelas(tx);
    return selectedKelas === 'Semua Kelas' || kelas === selectedKelas;
  });

  const displayedTransactions = isStudentPaymentReport
    ? laporanSiswaDalamPeriode
    : isRekapPemasukan
    ? pemasukanDalamPeriode
    : isRekapPengeluaran
    ? pengeluaranDalamPeriode
    : isSaldoPosisi
    ? [] // Saldo & Posisi Kas hanya menampilkan ringkasan, bukan daftar transaksi
    : txDalamPeriode; // BKU, Pertanggungjawaban Bulanan, Lainnya

  const displayedTotalIn = isStudentPaymentReport
    ? laporanSiswaDalamPeriode.reduce((sum, tx) => sum + tx.nominal, 0)
    : isRekapPemasukan
    ? pemasukanDalamPeriode.reduce((sum, tx) => sum + tx.nominal, 0)
    : isRekapPengeluaran
    ? 0
    : totalIn; // BKU, Saldo & Posisi Kas, Pertanggungjawaban, Lainnya

  const displayedTotalOut = isStudentPaymentReport || isRekapPemasukan
    ? 0
    : isRekapPengeluaran
    ? pengeluaranDalamPeriode.reduce((sum, tx) => sum + tx.nominal, 0)
    : totalOut; // BKU, Saldo & Posisi Kas, Pertanggungjawaban, Lainnya

  // Baris "Saldo Kas Akhir Periode" hanya relevan untuk laporan yang mencampur arus masuk & keluar.
  const showSaldoAkhir = isBKU || isPertanggungjawaban || isSaldoPosisi || selectedReportType === 'Lainnya';
  // Kolom tabel: laporan rekap pemasukan/pengeluaran/siswa hanya butuh satu kolom nominal, bukan 2 kolom (masuk & keluar).
  const showTwoColumnNominal = isBKU || isPertanggungjawaban || selectedReportType === 'Lainnya';

  // Export report to Excel / CSV format
  const handleExportExcel = () => {
    let csvContent = `\uFEFF`; // UTF-8 BOM for Microsoft Excel
    csvContent += `LAPORAN KEUANGAN ${reportType.toUpperCase()}\n`;
    csvContent += `Lembaga: ${currentLembaga}\n`;
    csvContent += `Periode: ${reportMonth}\n`;
    csvContent += `Tanggal Cetak: ${new Date().toLocaleDateString('id-ID')}\n\n`;

    csvContent += `No;Tanggal;No. Bukti;Tipe Transaksi;Kategori/Sumber;Pemasukan (Rp);Pengeluaran (Rp);Keterangan\n`;

    displayedTransactions.forEach((tx, index) => {
      const typeText = tx.type === 'IN' ? 'Pemasukan' : 'Pengeluaran';
      const category = tx.type === 'IN' ? `${tx.sumber} (${tx.sub})` : (tx as any).kategori || 'Umum';
      const masuk = tx.type === 'IN' ? tx.nominal : 0;
      const keluar = tx.type === 'OUT' ? tx.nominal : 0;
      const cleanKet = (tx.keterangan || '').replace(/;/g, ',');

      csvContent += `${index + 1};"${tx.tanggal}";"${tx.noBukti || tx.id}";"${typeText}";"${category}";${masuk};${keluar};"${cleanKet}"\n`;
    });

    csvContent += `\n;TOTAL PEMASUKAN;;;;${displayedTotalIn};;\n`;
    csvContent += `;TOTAL PENGELUARAN;;;;;${displayedTotalOut};\n`;
    if (showSaldoAkhir) csvContent += `;SALDO AKHIR PERIODE;;;;;${finalBalance};\n`;

    const blob = new Blob([csvContent], { type: 'text/csv;charset=utf-8;' });
    const url = URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    const filename = `Laporan_${reportType.replace(/\s+/g, '_')}_${currentLembaga.replace(/\s+/g, '_')}_${reportMonth.replace(/\s+/g, '_')}.csv`;
    link.setAttribute('download', filename);
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  };

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      {/* Print CSS stylesheet: elemen non-laporan (Sidebar, Navbar, toolbar, panel filter, dst.)
          sudah disembunyikan total lewat class Tailwind `print:hidden` langsung di elemennya
          (bukan sekadar visibility:hidden) supaya TIDAK menyisakan ruang kosong di kertas cetak.
          Blok CSS di bawah ini hanya mengatur tampilan & pagination dokumen itu sendiri, supaya
          data yang lebih panjang dari 1 halaman otomatis lanjut ke halaman berikutnya dengan rapi
          (header tabel berulang, baris tidak terpotong di tengah). */}
      <style>{`
        @media print {
          @page {
            size: A4;
            margin: 12mm;
          }

          html, body {
            height: auto !important;
            overflow: visible !important;
          }

          /* Bebaskan wrapper preview dari overflow/flex agar tidak memotong konten saat dicetak */
          .print-preview-wrapper {
            position: static !important;
            overflow: visible !important;
            display: block !important;
            padding: 0 !important;
            background: transparent !important;
            border: none !important;
          }

          #printable-report {
            position: static !important;
            display: block !important;
            width: 100% !important;
            min-height: 0 !important;
            height: auto !important;
            max-height: none !important;
            padding: 0 !important;
            margin: 0 !important;
            box-shadow: none !important;
            border: none !important;
            background: white !important;
          }

          /* Kop surat & judul laporan jangan sampai terbelah di tengah */
          .print-kop-surat,
          .print-report-title {
            page-break-inside: avoid;
            break-inside: avoid;
          }

          /* Tabel: header ikut tercetak ulang di halaman baru, baris data tidak terpotong di tengah */
          .print-report-table {
            page-break-inside: auto;
          }
          .print-report-table thead {
            display: table-header-group;
          }
          .print-report-table tfoot {
            display: table-footer-group;
          }
          .print-report-table tr {
            page-break-inside: avoid;
            break-inside: avoid;
          }

          /* Blok tanda tangan tetap satu kesatuan, boleh lanjut ke halaman baru jika tidak muat.
             CATATAN: sebelumnya kolom tanda tangan sempat diubah ke display:table/table-cell,
             tapi karena elemennya <div> (bukan <table> asli) tanpa <tr> di antaranya, sebagian
             mesin cetak salah menghitung tingginya jadi jauh lebih besar dari yang sebenarnya --
             akibatnya gap kosong di halaman pertama malah makin lebar. Diganti ke teknik float
             2 kolom (clearfix overflow:hidden) yang jauh lebih tua & konsisten tingginya di semua
             browser untuk kebutuhan cetak seperti ini. */
          .print-signature-block {
            page-break-inside: avoid;
            break-inside: avoid;
            break-inside: avoid-page;
          }
          .print-signature-grid {
            display: block !important;
            width: 100% !important;
            overflow: hidden !important;
          }
          .print-signature-col {
            display: block !important;
            float: left !important;
            width: 46% !important;
          }
          .print-signature-col:first-child {
            margin-right: 8% !important;
          }
          .print-signature-col:last-child {
            margin-right: 0 !important;
          }
        }
      `}</style>

      <div className="print:hidden flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-bold text-slate-900 tracking-tight">Laporan Keuangan Otomatis</h1>
          <p className="text-xs text-slate-500">Dibuat instan dari transaksi harian. Siap cetak A4 atau ekspor Excel/CSV untuk Komite & Yayasan.</p>
        </div>
        <div className="flex items-center gap-2">
          <button 
            onClick={handleExportExcel}
            className="flex items-center gap-2 px-4 py-2.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-[14px] text-xs font-semibold shadow-sm transition-all active:scale-95"
          >
            <FileSpreadsheet className="w-4 h-4" />
            <span>Download Excel / CSV</span>
          </button>
          <button 
            onClick={() => window.print()} 
            className="flex items-center gap-2 px-4 py-2.5 bg-slate-900 hover:bg-slate-800 text-white rounded-[14px] text-xs font-semibold shadow-sm transition-all active:scale-95"
          >
            <Printer className="w-4 h-4" />
            <span>Cetak Dokumen (A4)</span>
          </button>
        </div>
      </div>

      {/* REPORT CONFIGURATION PANEL */}
      <div className="print:hidden bg-white p-6 rounded-[14px] border border-slate-200/90 shadow-sm grid grid-cols-1 md:grid-cols-3 gap-4">
        <div>
          <label className="block text-xs font-semibold text-slate-700 mb-1.5">Jenis Laporan Administrasi</label>
          <select 
            value={selectedReportType}
            onChange={(e) => setSelectedReportType(e.target.value)}
            className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs font-medium text-slate-800 outline-none focus:border-blue-500"
          >
            <option value="Buku Kas Umum (BKU)">Buku Kas Umum (BKU)</option>
            <option value="Rekapitulasi Pemasukan">Rekapitulasi Pemasukan</option>
            <option value="Rekapitulasi Pengeluaran">Rekapitulasi Pengeluaran</option>
            <option value="Saldo & Posisi Kas">Saldo & Posisi Kas</option>
            <option value="Pertanggungjawaban Bulanan">Pertanggungjawaban Bulanan</option>
            <option value="Infaq / Pembayaran Siswa">Infaq / Pembayaran Siswa</option>
            <option value="Lainnya">Lainnya (Ketik Manual)</option>
          </select>

          {selectedReportType === 'Lainnya' && (
            <input
              type="text"
              value={customReportType}
              onChange={(e) => setCustomReportType(e.target.value)}
              placeholder="Ketik nama / jenis laporan manual..."
              className="mt-2 w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs font-medium text-slate-800 outline-none focus:border-blue-500"
            />
          )}
        </div>

        {isStudentPaymentReport && (
          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1.5">Pilih Kelas</label>
            <select value={selectedKelas} onChange={(e) => setSelectedKelas(e.target.value)} className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs font-medium text-slate-800 outline-none focus:border-blue-500">
              <option value="Semua Kelas">Semua Kelas</option>
              {masterKelas.map(kelas => <option key={kelas} value={kelas}>{kelas}</option>)}
            </select>
            {masterKelas.length === 0 && <p className="mt-1 text-[10px] text-amber-600">Belum ada kelas. Tambahkan melalui Pengaturan → Master Kelas & Rombel.</p>}
          </div>
        )}

        <div>
          <label className="block text-xs font-semibold text-slate-700 mb-1.5">Periode Bulan</label>
          <select 
            value={reportMonth}
            onChange={(e) => setReportMonth(e.target.value)}
            className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs font-medium text-slate-800 outline-none focus:border-blue-500"
          >
            <option value="Agustus 2026">Agustus 2026</option>
            <option value="Juli 2026">Juli 2026</option>
            <option value="Juni 2026">Juni 2026</option>
          </select>
        </div>

        <div className="flex items-end">
          <button 
            onClick={() => {}}
            className="w-full py-2 bg-blue-50 hover:bg-blue-100 text-blue-700 rounded-[14px] text-xs font-semibold border border-blue-200 transition-all flex items-center justify-center gap-1.5"
          >
            <RefreshCw className="w-3.5 h-3.5" />
            <span>Perbarui Preview Laporan</span>
          </button>
        </div>
      </div>

      {/* REALTIME A4 PRINT PREVIEW CANVAS */}
      <div className="print-preview-wrapper bg-slate-300/60 p-6 md:p-10 rounded-[14px] border border-slate-300 overflow-x-auto flex justify-center">
        <div id="printable-report" className="bg-white w-[210mm] min-h-[297mm] p-12 shadow-2xl text-slate-900 text-xs font-sans relative flex flex-col justify-between">
          <div>
            {/* Official Header Kop Sekolah */}
            <div className="print-kop-surat flex items-center gap-4 pb-4 border-b-2 border-slate-900 mb-6">
              <label className="w-16 h-16 shrink-0 bg-slate-100 rounded-lg flex items-center justify-center border border-slate-300 font-bold text-slate-400 text-[10px] overflow-hidden cursor-pointer hover:border-blue-400 transition-all relative group" title="Klik untuk mengganti logo lembaga">
                {logoDataUrl ? (
                  <img src={logoDataUrl} className="w-full h-full object-contain p-1" alt="Logo" />
                ) : (
                  <span>LOGO</span>
                )}
                <input type="file" accept="image/*" onChange={onLogoUpload} className="hidden" />
              </label>
              <div className="flex-1 text-center">
                <h2 className="text-base font-bold uppercase tracking-wide text-slate-900">{currentLembaga}</h2>
                <p className="text-[11px] text-slate-600">Kp. Lewibungur Rt/Rw : 03/05 Desa Sukagalih, Kec. Cikalongkulon, Cianjur 43281 Telp. 0263-2324180</p>
                <p className="text-[10px] text-slate-500 font-mono mt-0.5">Email: mts.admin@mtsnb.com | NPSN: 20252330</p>
              </div>
            </div>

            {/* Report Title */}
            <div className="print-report-title text-center mb-6">
              <h3 className="text-sm font-bold uppercase tracking-wider text-slate-900 underline">
                LAPORAN {reportType.toUpperCase()}
              </h3>
              <p className="text-xs text-slate-600 mt-0.5">
                Periode: <span className="font-semibold">{reportMonth}</span>
                {isStudentPaymentReport && <> <span className="mx-1">•</span> Kelas: <span className="font-semibold">{selectedKelas}</span></>}
              </p>
            </div>

            {isSaldoPosisi ? (
              /* SALDO & POSISI KAS: ringkasan saja, tanpa daftar transaksi per-baris */
              <table className="print-report-table w-full text-left border-collapse border border-slate-300 text-[11px] mb-8">
                <tbody className="divide-y divide-slate-200">
                  <tr>
                    <td className="border border-slate-300 p-3 font-semibold w-2/3">Saldo Awal Periode ({reportMonth})</td>
                    <td className="border border-slate-300 p-3 text-right font-mono">{formatRupiah(saldoAwalPeriode)}</td>
                  </tr>
                  <tr>
                    <td className="border border-slate-300 p-3 font-semibold">Total Pemasukan Periode Ini</td>
                    <td className="border border-slate-300 p-3 text-right font-mono text-emerald-700">{formatRupiah(totalIn)}</td>
                  </tr>
                  <tr>
                    <td className="border border-slate-300 p-3 font-semibold">Total Pengeluaran Periode Ini</td>
                    <td className="border border-slate-300 p-3 text-right font-mono text-rose-700">{formatRupiah(totalOut)}</td>
                  </tr>
                  <tr className="bg-slate-100">
                    <td className="border border-slate-300 p-3 font-bold uppercase">Saldo &amp; Posisi Kas Akhir Periode</td>
                    <td className="border border-slate-300 p-3 text-right font-mono font-bold text-blue-700 text-xs">{formatRupiah(finalBalance)}</td>
                  </tr>
                </tbody>
              </table>
            ) : (
              /* Report Table Body */
              <table className="print-report-table w-full text-left border-collapse border border-slate-300 text-[11px] mb-8">
                <thead>
                  <tr className="bg-slate-100 text-slate-800 font-bold">
                    <th className="border border-slate-300 p-2 text-center w-8">No</th>
                    <th className="border border-slate-300 p-2">Tanggal</th>
                    <th className="border border-slate-300 p-2">No. Bukti</th>
                    {isStudentPaymentReport ? (
                      <><th className="border border-slate-300 p-2">Siswa</th><th className="border border-slate-300 p-2">Jenis Pembayaran</th><th className="border border-slate-300 p-2 text-right">Nominal (Rp)</th></>
                    ) : isRekapPemasukan ? (
                      <><th className="border border-slate-300 p-2">Sumber Dana</th><th className="border border-slate-300 p-2">Keterangan</th><th className="border border-slate-300 p-2 text-right">Nominal (Rp)</th></>
                    ) : isRekapPengeluaran ? (
                      <><th className="border border-slate-300 p-2">Kategori</th><th className="border border-slate-300 p-2">Keterangan</th><th className="border border-slate-300 p-2 text-right">Nominal (Rp)</th></>
                    ) : (
                      <><th className="border border-slate-300 p-2">Keterangan</th><th className="border border-slate-300 p-2 text-right">Pemasukan (Rp)</th><th className="border border-slate-300 p-2 text-right">Pengeluaran (Rp)</th></>
                    )}
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-200">
                  {displayedTransactions.length === 0 ? (
                    <tr><td colSpan={6} className="border border-slate-300 p-4 text-center text-slate-400 italic">
                      {isStudentPaymentReport
                        ? `Tidak ada data Infaq / Pembayaran Siswa untuk ${selectedKelas} pada periode ini.`
                        : isRekapPemasukan
                        ? 'Tidak ada transaksi pemasukan pada periode ini.'
                        : isRekapPengeluaran
                        ? 'Tidak ada transaksi pengeluaran pada periode ini.'
                        : 'Tidak ada transaksi pada periode ini.'}
                    </td></tr>
                  ) : (
                    displayedTransactions.map((tx, idx) => {
                      const pemasukan = tx.type === 'IN' ? tx as Pemasukan : null;
                      const pengeluaran = tx.type === 'OUT' ? tx as Pengeluaran : null;
                      const siswa = pemasukan?.siswaId ? siswaTagihanList.find(s => s.id === pemasukan.siswaId) : null;
                      return (<tr key={tx.id}>
                        <td className="border border-slate-300 p-2 text-center font-mono">{idx + 1}</td>
                        <td className="border border-slate-300 p-2 font-mono">{tx.tanggal}</td>
                        <td className="border border-slate-300 p-2 font-mono">{tx.noBukti || tx.id}</td>
                        {isStudentPaymentReport ? (
                          <><td className="border border-slate-300 p-2">{siswa?.nama || '—'}</td><td className="border border-slate-300 p-2">{siswa?.jenis || pemasukan?.sub || 'Infaq'}</td><td className="border border-slate-300 p-2 text-right font-mono">{formatRupiah(tx.nominal)}</td></>
                        ) : isRekapPemasukan ? (
                          <><td className="border border-slate-300 p-2">{pemasukan?.sumber} {pemasukan?.sub ? `— ${pemasukan.sub}` : ''}</td><td className="border border-slate-300 p-2">{tx.keterangan}</td><td className="border border-slate-300 p-2 text-right font-mono">{formatRupiah(tx.nominal)}</td></>
                        ) : isRekapPengeluaran ? (
                          <><td className="border border-slate-300 p-2">{pengeluaran?.kategori || 'Umum'}</td><td className="border border-slate-300 p-2">{tx.keterangan}</td><td className="border border-slate-300 p-2 text-right font-mono">{formatRupiah(tx.nominal)}</td></>
                        ) : (
                          <><td className="border border-slate-300 p-2">{tx.keterangan}</td><td className="border border-slate-300 p-2 text-right font-mono">{tx.type === 'IN' ? formatRupiah(tx.nominal) : '-'}</td><td className="border border-slate-300 p-2 text-right font-mono">{tx.type === 'OUT' ? formatRupiah(tx.nominal) : '-'}</td></>
                        )}
                      </tr>);
                    })
                  )}
                </tbody>
                <tfoot>
                  <tr className="bg-slate-50 font-bold text-slate-900">
                    <td colSpan={showTwoColumnNominal ? 4 : 5} className="border border-slate-300 p-2 text-right uppercase">
                      {isStudentPaymentReport ? 'Total Pembayaran:' : isRekapPemasukan ? 'Total Pemasukan:' : isRekapPengeluaran ? 'Total Pengeluaran:' : 'Total Periode Ini:'}
                    </td>
                    <td className={`border border-slate-300 p-2 text-right ${isRekapPengeluaran ? 'text-rose-700' : 'text-emerald-700'}`}>
                      {formatRupiah(isRekapPengeluaran ? displayedTotalOut : displayedTotalIn)}
                    </td>
                    {showTwoColumnNominal && <td className="border border-slate-300 p-2 text-right text-rose-700">{formatRupiah(displayedTotalOut)}</td>}
                  </tr>
                  {showSaldoAkhir && (<tr className="bg-slate-100 font-bold text-slate-900"><td colSpan={4} className="border border-slate-300 p-2 text-right uppercase">Saldo Kas Akhir Periode:</td><td colSpan={2} className="border border-slate-300 p-2 text-center text-blue-700 font-mono text-xs">{formatRupiah(finalBalance)}</td></tr>)}
                </tfoot>
              </table>
            )}
          </div>

          {/* Formal Signature Block */}
          <div className="print-signature-block mt-12 pt-6">
            <div className="print-signature-grid grid grid-cols-2 gap-8 text-center text-xs">
              <div className="print-signature-col">
                <p className="text-slate-600">Mengetahui,</p>
                <p className="font-bold text-slate-900 mb-16">Kepala Sekolah {currentLembaga}</p>
                <p className="font-bold text-slate-900 underline">H. Fahru Rozi Ramdhan S.S., M.Pd</p>
                <p className="text-[10px] text-slate-500">NIP. .........................................</p>
              </div>
              <div className="print-signature-col">
                <p className="text-slate-600">Cianjur, {printDate}</p>
                <p className="font-bold text-slate-900 mb-16">Bendahara Sekolah</p>
                <p className="font-bold text-slate-900 underline">Rizki Mulyana, S.Pd</p>
                <p className="text-[10px] text-slate-500">NIP. .........................................</p>
              </div>
            </div>
            <div className="mt-8 text-[9px] text-slate-400 text-center border-t border-slate-100 pt-2 font-mono">
              Dokumen ini dicetak secara otomatis dari Portal Bendahara By Rajakas.ID • Yang Terintegrasi
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
