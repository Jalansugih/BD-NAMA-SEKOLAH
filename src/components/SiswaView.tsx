import React, { useState } from 'react';
import { 
  Plus, Search, GraduationCap, Clock, HandCoins, Check, Trash2, 
  Wallet, Award, AlertCircle, ArrowUpRight, Printer, X, FileText 
} from 'lucide-react';
import { SiswaTagihan, Pemasukan } from '../types';

interface SiswaViewProps {
  siswaTagihanList: SiswaTagihan[];
  pemasukanList: Pemasukan[];
  masterKelas: string[];
  onOpenModalTambahTagihan: () => void;
  onOpenModalBayar: (siswaId: string) => void;
  onOpenRiwayat: (siswaId: string) => void;
  onDeleteTagihan: (siswaId: string) => void;
  formatRupiah: (val: number) => string;
}

export const SiswaView: React.FC<SiswaViewProps> = ({
  siswaTagihanList,
  pemasukanList,
  masterKelas,
  onOpenModalTambahTagihan,
  onOpenModalBayar,
  onOpenRiwayat,
  onDeleteTagihan,
  formatRupiah
}) => {
  const [search, setSearch] = useState('');
  const [filterKelas, setFilterKelas] = useState('ALL');
  const [filterStatus, setFilterStatus] = useState('ALL');
  const [selectedSiswaForRiwayat, setSelectedSiswaForRiwayat] = useState<SiswaTagihan | null>(null);

  // Compute student payment progress
  const getSiswaPaidAmount = (siswaId: string) => {
    return pemasukanList
      .filter(p => p.siswaId === siswaId)
      .reduce((acc, curr) => acc + curr.nominal, 0);
  };

  // Calculate overall Total Pendapatan Siswa from ALL payments connected to students
  const totalPendapatanSiswa = pemasukanList
    .filter(p => p.siswaId || p.sumber === 'Pembayaran' || (p.sub && (p.sub.includes('SPP') || p.sub.includes('Infak') || p.sub.includes('Seragam') || p.sub.includes('Daftar Ulang'))))
    .reduce((acc, curr) => acc + curr.nominal, 0);

  const computeSiswaProgress = (siswa: SiswaTagihan) => {
    const terbayar = getSiswaPaidAmount(siswa.id);
    const sisa = Math.max(siswa.target - terbayar, 0);
    const persen = siswa.target > 0 ? Math.min(100, Math.round((terbayar / siswa.target) * 100)) : 0;
    const lunas = terbayar >= siswa.target;
    return { terbayar, sisa, persen, lunas };
  };

  const listData = siswaTagihanList.map(s => ({
    siswa: s,
    progress: computeSiswaProgress(s)
  }));

  const filtered = listData.filter(({ siswa, progress }) => {
    const matchSearch = siswa.nama.toLowerCase().includes(search.toLowerCase());
    const matchKelas = filterKelas === 'ALL' || siswa.kelas === filterKelas;
    const matchStatus = filterStatus === 'ALL' || 
      (filterStatus === 'LUNAS' && progress.lunas) ||
      (filterStatus === 'BERJALAN' && !progress.lunas);
    return matchSearch && matchKelas && matchStatus;
  });

  // Global summaries
  const totalSiswaCount = siswaTagihanList.length;
  const totalTargetTagihan = listData.reduce((acc, x) => acc + x.siswa.target, 0);
  const totalTerbayarSiswaTerpantau = listData.reduce((acc, x) => acc + x.progress.terbayar, 0);
  const totalSisaTagihan = listData.reduce((acc, x) => acc + x.progress.sisa, 0);
  const totalLunasCount = listData.filter(x => x.progress.lunas).length;
  const totalBerjalanCount = listData.filter(x => !x.progress.lunas).length;

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-bold text-slate-900 tracking-tight">Pembayaran & Pendapatan Siswa</h1>
          <p className="text-xs text-slate-500">Pantau progres tagihan & total penerimaan dana dari siswa (SPP, Infak, Seragam, dll)</p>
        </div>
        <button 
          onClick={onOpenModalTambahTagihan} 
          className="flex items-center gap-2 px-4 py-2.5 bg-amber-600 hover:bg-amber-700 text-white rounded-[14px] text-xs font-semibold shadow-sm transition-all active:scale-95"
        >
          <Plus className="w-4 h-4" />
          <span>+ Tambah Tagihan Siswa</span>
        </button>
      </div>

      {/* 5 SUMMARY CARDS INCLUDING "TOTAL PENDAPATAN SISWA" */}
      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-5 gap-4">
        {/* CARD 1: TOTAL PENDAPATAN SISWA (HIGHLIGHTED) */}
        <div className="bg-gradient-to-br from-emerald-600 to-emerald-700 p-4 rounded-[14px] text-white shadow-md relative overflow-hidden">
          <div className="absolute right-0 top-0 w-20 h-20 bg-white/10 rounded-full blur-xl pointer-events-none" />
          <div className="flex items-center justify-between mb-2">
            <span className="text-[10px] font-bold uppercase tracking-wider text-emerald-100">
              Total Pendapatan Siswa
            </span>
            <Wallet className="w-4 h-4 text-emerald-200" />
          </div>
          <div className="text-lg font-extrabold tracking-tight">
            {formatRupiah(totalPendapatanSiswa)}
          </div>
          <p className="text-[10px] text-emerald-100 mt-1 flex items-center gap-1">
            <ArrowUpRight className="w-3 h-3 text-emerald-300" />
            Realisasi Masuk ke Kas
          </p>
        </div>

        {/* CARD 2: SISWA TERPANTAU */}
        <div className="bg-white p-4 rounded-[14px] border border-slate-200/90 shadow-sm">
          <div className="flex items-center justify-between mb-2 text-slate-500">
            <span className="text-[10px] font-semibold uppercase tracking-wider">Siswa Terpantau</span>
            <GraduationCap className="w-4 h-4 text-amber-500" />
          </div>
          <div className="text-xl font-bold text-slate-900">{totalSiswaCount} Siswa</div>
          <p className="text-[10px] text-slate-400 mt-1">{totalBerjalanCount} Belum Lunas</p>
        </div>

        {/* CARD 3: TARGET TAGIHAN */}
        <div className="bg-white p-4 rounded-[14px] border border-slate-200/90 shadow-sm">
          <div className="flex items-center justify-between mb-2 text-slate-500">
            <span className="text-[10px] font-semibold uppercase tracking-wider">Target Tagihan</span>
            <Award className="w-4 h-4 text-blue-500" />
          </div>
          <div className="text-lg font-bold text-slate-800">{formatRupiah(totalTargetTagihan)}</div>
          <p className="text-[10px] text-slate-400 mt-1">Siswa Terpantau</p>
        </div>

        {/* CARD 4: SUDAH LUNAS */}
        <div className="bg-white p-4 rounded-[14px] border border-slate-200/90 shadow-sm">
          <div className="flex items-center justify-between mb-2 text-slate-500">
            <span className="text-[10px] font-semibold uppercase tracking-wider">Sudah Lunas</span>
            <Check className="w-4 h-4 text-emerald-600" />
          </div>
          <div className="text-xl font-bold text-emerald-600">{totalLunasCount} Siswa</div>
          <p className="text-[10px] text-emerald-600 font-medium mt-1">{formatRupiah(totalTerbayarSiswaTerpantau)}</p>
        </div>

        {/* CARD 5: SISA TAGIHAN */}
        <div className="bg-white p-4 rounded-[14px] border border-slate-200/90 shadow-sm">
          <div className="flex items-center justify-between mb-2 text-slate-500">
            <span className="text-[10px] font-semibold uppercase tracking-wider">Total Sisa Tagihan</span>
            <AlertCircle className="w-4 h-4 text-rose-500" />
          </div>
          <div className="text-lg font-bold text-rose-600">{formatRupiah(totalSisaTagihan)}</div>
          <p className="text-[10px] text-rose-500 font-medium mt-1">{totalBerjalanCount} Belum Lunas</p>
        </div>
      </div>

      {/* SEARCH & FILTERS */}
      <div className="bg-white p-4 rounded-[14px] border border-slate-200/90 shadow-sm flex flex-wrap gap-3 items-center justify-between">
        <div className="relative flex-1 min-w-[240px]">
          <Search className="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
          <input 
            type="text" 
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Cari nama siswa..." 
            className="w-full pl-9 pr-4 py-2 bg-slate-50 border border-slate-200 rounded-[14px] text-xs outline-none focus:bg-white focus:border-blue-500 transition-all"
          />
        </div>
        <div className="flex items-center gap-2 flex-wrap">
          <select 
            value={filterKelas}
            onChange={(e) => setFilterKelas(e.target.value)}
            className="border border-slate-200 bg-slate-50 text-slate-700 rounded-[14px] px-3 py-2 text-xs font-medium outline-none focus:border-blue-500"
          >
            <option value="ALL">Semua Kelas</option>
            {masterKelas.map(k => (
              <option key={k} value={k}>{k}</option>
            ))}
          </select>

          <select 
            value={filterStatus}
            onChange={(e) => setFilterStatus(e.target.value)}
            className="border border-slate-200 bg-slate-50 text-slate-700 rounded-[14px] px-3 py-2 text-xs font-medium outline-none focus:border-blue-500"
          >
            <option value="ALL">Semua Status</option>
            <option value="BERJALAN">Belum Lunas</option>
            <option value="LUNAS">Lunas</option>
          </select>
        </div>
      </div>

      {/* STUDENT PROGRESS GRID */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        {filtered.length === 0 ? (
          <div className="col-span-full text-center py-12 text-slate-400 text-xs bg-white rounded-[14px] border border-dashed border-slate-200">
            Belum ada data tagihan siswa yang cocok dengan filter.
          </div>
        ) : (
          filtered.map(({ siswa, progress }) => (
            <div key={siswa.id} className="bg-white p-5 rounded-[14px] border border-slate-200/90 shadow-sm hover:shadow-md transition-all flex flex-col justify-between">
              <div>
                <div className="flex items-start justify-between gap-3">
                  <div className="flex items-center gap-3 min-w-0">
                    <div className="w-10 h-10 rounded-full bg-amber-100 text-amber-700 font-bold text-xs flex items-center justify-center shrink-0">
                      {siswa.nama.split(' ').map(n => n[0]).join('').substring(0, 2).toUpperCase()}
                    </div>
                    <div className="min-w-0">
                      <h3 className="font-bold text-slate-900 text-sm truncate">{siswa.nama}</h3>
                      <p className="text-[11px] text-slate-500 truncate">{siswa.kelas} • {siswa.jenis}</p>
                    </div>
                  </div>
                  {progress.lunas ? (
                    <span className="shrink-0 px-2.5 py-1 rounded-full text-[10px] font-bold bg-emerald-100 text-emerald-700">
                      Lunas
                    </span>
                  ) : (
                    <span className="shrink-0 px-2.5 py-1 rounded-full text-[10px] font-bold bg-amber-100 text-amber-700">
                      Berjalan
                    </span>
                  )}
                </div>

                <div className="mt-4">
                  <div className="flex justify-between text-[11px] font-semibold mb-1">
                    <span className="text-slate-700">Progres Pembayaran</span>
                    <span className="text-slate-900">{progress.persen}%</span>
                  </div>
                  <div className="w-full h-2 bg-slate-100 rounded-full overflow-hidden">
                    <div 
                      className={`${progress.lunas ? 'bg-emerald-500' : 'bg-amber-500'} h-full rounded-full transition-all duration-500`} 
                      style={{ width: `${progress.persen}%` }} 
                    />
                  </div>
                </div>

                <div className="grid grid-cols-3 gap-2 mt-4 text-center">
                  <div className="bg-slate-50 rounded-lg p-2">
                    <p className="text-[10px] text-slate-400 font-semibold uppercase">Target</p>
                    <p className="text-[11px] font-bold text-slate-800 mt-0.5">{formatRupiah(siswa.target)}</p>
                  </div>
                  <div className="bg-slate-50 rounded-lg p-2">
                    <p className="text-[10px] text-slate-400 font-semibold uppercase">Terbayar</p>
                    <p className="text-[11px] font-bold text-emerald-600 mt-0.5">{formatRupiah(progress.terbayar)}</p>
                  </div>
                  <div className="bg-slate-50 rounded-lg p-2">
                    <p className="text-[10px] text-slate-400 font-semibold uppercase">Sisa</p>
                    <p className={`text-[11px] font-bold ${progress.sisa > 0 ? 'text-rose-600' : 'text-slate-400'} mt-0.5`}>
                      {formatRupiah(progress.sisa)}
                    </p>
                  </div>
                </div>
              </div>

              <div className="flex items-center gap-2 mt-4 pt-3 border-t border-slate-100">
                <button 
                  onClick={() => {
                    setSelectedSiswaForRiwayat(siswa);
                    onOpenRiwayat(siswa.id);
                  }} 
                  className="flex-1 px-3 py-1.5 text-[11px] font-semibold text-slate-600 border border-slate-200 rounded-[14px] hover:bg-slate-50 flex items-center justify-center gap-1"
                >
                  <Clock className="w-3.5 h-3.5 text-blue-600" /> Riwayat
                </button>
                {!progress.lunas ? (
                  <button 
                    onClick={() => onOpenModalBayar(siswa.id)} 
                    className="flex-1 px-3 py-1.5 text-[11px] font-semibold text-white bg-emerald-600 hover:bg-emerald-700 rounded-[14px] flex items-center justify-center gap-1"
                  >
                    <HandCoins className="w-3.5 h-3.5" /> Bayar
                  </button>
                ) : (
                  <button 
                    disabled 
                    className="flex-1 px-3 py-1.5 text-[11px] font-semibold text-emerald-700 bg-emerald-50 rounded-[14px] flex items-center justify-center gap-1 cursor-default"
                  >
                    <Check className="w-3.5 h-3.5" /> Lunas
                  </button>
                )}
                <button 
                  onClick={() => onDeleteTagihan(siswa.id)} 
                  title="Hapus data tagihan" 
                  className="px-2.5 py-1.5 text-[11px] text-slate-400 hover:text-rose-600 border border-slate-200 rounded-[14px] hover:bg-rose-50"
                >
                  <Trash2 className="w-3.5 h-3.5" />
                </button>
              </div>
            </div>
          ))
        )}
      </div>

      {/* MODAL RIWAYAT PEMBAYARAN SISWA / KARTU SPP */}
      {selectedSiswaForRiwayat && (() => {
        const siswa = selectedSiswaForRiwayat;
        const historyList = pemasukanList.filter(p => p.siswaId === siswa.id);
        const terbayar = historyList.reduce((acc, curr) => acc + curr.nominal, 0);
        const sisa = Math.max(siswa.target - terbayar, 0);
        const lunas = terbayar >= siswa.target;

        return (
          <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
            <div className="bg-white rounded-[16px] max-w-2xl w-full shadow-2xl border border-slate-200 overflow-hidden flex flex-col max-h-[90vh] animate-in fade-in zoom-in duration-150">
              {/* Modal Header */}
              <div className="p-5 bg-slate-900 text-white flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <div className="w-10 h-10 rounded-full bg-blue-500/20 text-blue-400 font-bold flex items-center justify-center border border-blue-400/30">
                    <GraduationCap className="w-5 h-5" />
                  </div>
                  <div>
                    <h2 className="text-base font-bold text-white flex items-center gap-2">
                      Kartu SPP & Riwayat Pembayaran Siswa
                    </h2>
                    <p className="text-xs text-slate-300">
                      a.n <strong className="text-white">{siswa.nama}</strong> ({siswa.kelas}) • {siswa.jenis}
                    </p>
                  </div>
                </div>
                <button 
                  onClick={() => setSelectedSiswaForRiwayat(null)} 
                  className="w-8 h-8 flex items-center justify-center rounded-full bg-slate-800 hover:bg-slate-700 text-slate-300 hover:text-white transition-all"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>

              {/* Modal Body */}
              <div className="p-6 overflow-y-auto space-y-5 text-xs text-slate-700 custom-scrollbar">
                {/* Summary Progress Card */}
                <div className="bg-slate-50 border border-slate-200 p-4 rounded-[14px] space-y-3">
                  <div className="flex items-center justify-between">
                    <span className="font-bold text-slate-800">Status Tagihan Siswa</span>
                    {lunas ? (
                      <span className="px-3 py-1 rounded-full text-xs font-bold bg-emerald-100 text-emerald-800 flex items-center gap-1">
                        <Check className="w-3.5 h-3.5" /> Lunas
                      </span>
                    ) : (
                      <span className="px-3 py-1 rounded-full text-xs font-bold bg-amber-100 text-amber-800 flex items-center gap-1">
                        <Clock className="w-3.5 h-3.5" /> Berjalan (Belum Lunas)
                      </span>
                    )}
                  </div>

                  <div className="grid grid-cols-3 gap-3 text-center pt-2 border-t border-slate-200/60">
                    <div className="bg-white p-2.5 rounded-[10px] border border-slate-200/80">
                      <p className="text-[10px] text-slate-400 font-semibold uppercase">Target Nominal</p>
                      <p className="text-xs font-bold text-slate-800 mt-0.5">{formatRupiah(siswa.target)}</p>
                    </div>
                    <div className="bg-white p-2.5 rounded-[10px] border border-slate-200/80">
                      <p className="text-[10px] text-slate-400 font-semibold uppercase">Total Terbayar</p>
                      <p className="text-xs font-bold text-emerald-600 mt-0.5">{formatRupiah(terbayar)}</p>
                    </div>
                    <div className="bg-white p-2.5 rounded-[10px] border border-slate-200/80">
                      <p className="text-[10px] text-slate-400 font-semibold uppercase">Sisa Tagihan</p>
                      <p className={`text-xs font-bold ${sisa > 0 ? 'text-rose-600' : 'text-slate-400'} mt-0.5`}>
                        {formatRupiah(sisa)}
                      </p>
                    </div>
                  </div>
                </div>

                {/* History Table */}
                <div>
                  <h3 className="font-bold text-slate-900 text-xs mb-3 flex items-center gap-1.5">
                    <FileText className="w-4 h-4 text-blue-600" /> Rincian Transaksi Pembayaran ({historyList.length})
                  </h3>

                  {historyList.length === 0 ? (
                    <div className="p-8 text-center bg-slate-50 border border-dashed border-slate-200 rounded-[14px] text-slate-400 text-xs">
                      Belum ada catatan transaksi pembayaran untuk siswa ini.
                    </div>
                  ) : (
                    <div className="border border-slate-200 rounded-[14px] overflow-hidden">
                      <table className="w-full text-left text-xs">
                        <thead className="bg-slate-100 text-slate-700 font-bold border-b border-slate-200">
                          <tr>
                            <th className="p-3">No</th>
                            <th className="p-3">Tanggal</th>
                            <th className="p-3">No. Bukti</th>
                            <th className="p-3">Keterangan</th>
                            <th className="p-3 text-right">Nominal</th>
                          </tr>
                        </thead>
                        <tbody className="divide-y divide-slate-100">
                          {historyList.map((item, idx) => (
                            <tr key={item.id} className="hover:bg-slate-50 transition-colors">
                              <td className="p-3 font-semibold text-slate-500">{idx + 1}</td>
                              <td className="p-3 text-slate-700 whitespace-nowrap">{item.tanggal}</td>
                              <td className="p-3 font-mono text-[11px] font-bold text-blue-600">{item.noBukti}</td>
                              <td className="p-3 text-slate-800">{item.keterangan}</td>
                              <td className="p-3 text-right font-bold text-emerald-600">{formatRupiah(item.nominal)}</td>
                            </tr>
                          ))}
                        </tbody>
                        <tfoot className="bg-emerald-50/80 font-bold text-emerald-900 border-t border-slate-200">
                          <tr>
                            <td colSpan={4} className="p-3 text-right">Total Seluruh Terbayar:</td>
                            <td className="p-3 text-right text-sm text-emerald-700">{formatRupiah(terbayar)}</td>
                          </tr>
                        </tfoot>
                      </table>
                    </div>
                  )}
                </div>
              </div>

              {/* Modal Footer */}
              <div className="p-4 bg-slate-50 border-t border-slate-100 flex items-center justify-between">
                <button
                  onClick={() => window.print()}
                  className="px-4 py-2 bg-slate-800 hover:bg-slate-900 text-white rounded-[12px] text-xs font-semibold transition-all flex items-center gap-1.5"
                >
                  <Printer className="w-3.5 h-3.5" />
                  <span>Cetak Kartu SPP</span>
                </button>

                <div className="flex items-center gap-2">
                  {!lunas && (
                    <button
                      onClick={() => {
                        const siswaId = siswa.id;
                        setSelectedSiswaForRiwayat(null);
                        onOpenModalBayar(siswaId);
                      }}
                      className="px-4 py-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded-[12px] text-xs font-semibold transition-all flex items-center gap-1.5"
                    >
                      <HandCoins className="w-3.5 h-3.5" />
                      <span>Catat Pembayaran Baru</span>
                    </button>
                  )}
                  <button
                    onClick={() => setSelectedSiswaForRiwayat(null)}
                    className="px-4 py-2 bg-slate-200 hover:bg-slate-300 text-slate-700 rounded-[12px] text-xs font-semibold transition-all"
                  >
                    Tutup
                  </button>
                </div>
              </div>
            </div>
          </div>
        );
      })()}
    </div>
  );
};
