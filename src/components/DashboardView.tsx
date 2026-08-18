import React from 'react';
import { 
  Wallet, ArrowDownCircle, ArrowUpCircle, Scale, 
  TrendingUp, TrendingDown, ShieldCheck, ArrowRight, Lightbulb
} from 'lucide-react';
import { 
  ResponsiveContainer, LineChart, Line, XAxis, YAxis, 
  CartesianGrid, Tooltip, Legend 
} from 'recharts';
import { Pemasukan, Pengeluaran, MasterSumberDana } from '../types';

interface DashboardViewProps {
  pemasukanList: Pemasukan[];
  pengeluaranList: Pengeluaran[];
  masterSumberDana: MasterSumberDana[];
  saldoAwal: number;
  tahunAjaran: string;
  formatRupiah: (val: number) => string;
  onSwitchTab: (tab: string) => void;
}

const NAMA_BULAN = ['Januari','Februari','Maret','April','Mei','Juni','Juli','Agustus','September','Oktober','November','Desember'];

export const DashboardView: React.FC<DashboardViewProps> = ({
  pemasukanList,
  pengeluaranList,
  masterSumberDana,
  saldoAwal,
  tahunAjaran,
  formatRupiah,
  onSwitchTab
}) => {
  const currentPeriod = new Date().toISOString().slice(0, 7); // "YYYY-MM"
  const currentMonthIdx = new Date().getMonth();
  const currentMonthName = NAMA_BULAN[currentMonthIdx];

  // Total Kas overall
  const totalInAll = pemasukanList.reduce((acc, curr) => acc + curr.nominal, 0);
  const totalOutAll = pengeluaranList.reduce((acc, curr) => acc + curr.nominal, 0);
  const totalSaldoKas = saldoAwal + totalInAll - totalOutAll;

  // Monthly breakdown
  const totalInBulan = pemasukanList
    .filter(x => x.tanggal && x.tanggal.startsWith(currentPeriod))
    .reduce((acc, curr) => acc + curr.nominal, 0);

  const totalOutBulan = pengeluaranList
    .filter(x => x.tanggal && x.tanggal.startsWith(currentPeriod))
    .reduce((acc, curr) => acc + curr.nominal, 0);

  const surplusBulan = totalInBulan - totalOutBulan;

  // Trend
  const saldoAwalBulanIni = totalSaldoKas - surplusBulan;
  let trendPct = 0;
  if (saldoAwalBulanIni > 0) {
    trendPct = (surplusBulan / saldoAwalBulanIni) * 100;
  }

  // Chart 6 months data
  const chartData = [];
  const now = new Date();
  for (let i = 5; i >= 0; i--) {
    const d = new Date(now.getFullYear(), now.getMonth() - i, 1);
    const key = `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}`;
    const label = NAMA_BULAN[d.getMonth()];

    const inVal = pemasukanList
      .filter(x => x.tanggal && x.tanggal.startsWith(key))
      .reduce((acc, curr) => acc + curr.nominal, 0);

    const outVal = pengeluaranList
      .filter(x => x.tanggal && x.tanggal.startsWith(key))
      .reduce((acc, curr) => acc + curr.nominal, 0);

    chartData.push({
      bulan: label,
      pemasukan: inVal,
      pengeluaran: outVal
    });
  }

  // Source Composition
  const perSumber: Record<string, number> = {};
  pemasukanList
    .filter(x => x.tanggal && x.tanggal.startsWith(currentPeriod))
    .forEach(x => {
      perSumber[x.sumber] = (perSumber[x.sumber] || 0) + x.nominal;
    });

  const getSumberName = (id: string) => {
    const found = masterSumberDana.find(s => s.id === id);
    return found ? found.name : id;
  };

  let compositionEntries = Object.keys(perSumber).map(id => ({
    name: getSumberName(id),
    nominal: perSumber[id]
  })).sort((a, b) => b.nominal - a.nominal);

  const palette = ['bg-blue-600', 'bg-emerald-500', 'bg-amber-500', 'bg-rose-500', 'bg-slate-400'];

  // 5 Recent Transactions
  const recentTransactions = [
    ...pemasukanList.map(x => ({ ...x, type: 'IN' as const })),
    ...pengeluaranList.map(x => ({ ...x, type: 'OUT' as const }))
  ].sort((a, b) => new Date(b.tanggal).getTime() - new Date(a.tanggal).getTime()).slice(0, 5);

  return (
    <div className="space-y-8 max-w-7xl mx-auto">
      {/* Welcome Hero Banner */}
      <div className="flex flex-col md:flex-row md:items-center justify-between gap-4 bg-gradient-to-r from-blue-600 to-blue-800 p-6 rounded-[14px] text-white shadow-md relative overflow-hidden">
        <div className="absolute -right-10 -bottom-10 w-48 h-48 bg-white/10 rounded-full blur-2xl pointer-events-none" />
        <div className="space-y-1 z-10">
          <h1 className="text-2xl font-bold tracking-tight">Selamat Datang, Bendahara!</h1>
          <p className="text-blue-100 text-xs max-w-xl">
            Kelola keuangan sekolah tanpa kerumitan debit-kredit. Cukup catat transaksi hari ini, sistem otomatis menyusun Laporan Kas & Rekapitulasi secara real-time.
          </p>
        </div>
        <div className="flex items-center gap-2 z-10">
          <span className="inline-flex items-center gap-1.5 px-3 py-1.5 rounded-full bg-white/10 backdrop-blur-md text-xs font-medium text-white border border-white/20">
            <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
            Kas Terbuku Hari Ini
          </span>
        </div>
      </div>

      {/* 4 Financial Summary Cards */}
      <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-5">
        {/* Card 1: Saldo Kas */}
        <div className="bg-white p-5 rounded-[14px] border border-slate-200/90 shadow-sm hover:shadow-md transition-all group">
          <div className="flex items-center justify-between text-slate-500 mb-3">
            <span className="text-xs font-semibold uppercase tracking-wider">Total Saldo Kas</span>
            <div className="w-8 h-8 rounded-lg bg-blue-50 text-blue-600 flex items-center justify-center group-hover:scale-110 transition-transform">
              <Wallet className="w-4 h-4" />
            </div>
          </div>
          <div className="text-2xl font-bold text-slate-900 tracking-tight">
            {formatRupiah(totalSaldoKas)}
          </div>
          <div className={`mt-3 flex items-center text-[11px] font-medium ${trendPct >= 0 ? 'text-emerald-600' : 'text-rose-600'}`}>
            {trendPct >= 0 ? <TrendingUp className="w-3.5 h-3.5 mr-1" /> : <TrendingDown className="w-3.5 h-3.5 mr-1" />}
            <span>{trendPct >= 0 ? '+' : ''}{trendPct.toFixed(1)}% dari saldo awal bulan</span>
          </div>
        </div>

        {/* Card 2: Pemasukan Bulan Ini */}
        <div className="bg-white p-5 rounded-[14px] border border-slate-200/90 shadow-sm hover:shadow-md transition-all group">
          <div className="flex items-center justify-between text-slate-500 mb-3">
            <span className="text-xs font-semibold uppercase tracking-wider">Pemasukan ({currentMonthName})</span>
            <div className="w-8 h-8 rounded-lg bg-emerald-50 text-emerald-600 flex items-center justify-center group-hover:scale-110 transition-transform">
              <ArrowDownCircle className="w-4 h-4" />
            </div>
          </div>
          <div className="text-2xl font-bold text-emerald-600 tracking-tight">
            {formatRupiah(totalInBulan)}
          </div>
          <div className="mt-3 flex items-center text-[11px] text-slate-500">
            <span>Dari BOS, SPP, & Infak</span>
          </div>
        </div>

        {/* Card 3: Pengeluaran Bulan Ini */}
        <div className="bg-white p-5 rounded-[14px] border border-slate-200/90 shadow-sm hover:shadow-md transition-all group">
          <div className="flex items-center justify-between text-slate-500 mb-3">
            <span className="text-xs font-semibold uppercase tracking-wider">Pengeluaran ({currentMonthName})</span>
            <div className="w-8 h-8 rounded-lg bg-rose-50 text-rose-600 flex items-center justify-center group-hover:scale-110 transition-transform">
              <ArrowUpCircle className="w-4 h-4" />
            </div>
          </div>
          <div className="text-2xl font-bold text-rose-600 tracking-tight">
            {formatRupiah(totalOutBulan)}
          </div>
          <div className="mt-3 flex items-center text-[11px] text-slate-500">
            <span>Honor, Operasional & ATK</span>
          </div>
        </div>

        {/* Card 4: Surplus Bulan Ini */}
        <div className="bg-white p-5 rounded-[14px] border border-slate-200/90 shadow-sm hover:shadow-md transition-all group">
          <div className="flex items-center justify-between text-slate-500 mb-3">
            <span className="text-xs font-semibold uppercase tracking-wider">Surplus Bulan Ini</span>
            <div className="w-8 h-8 rounded-lg bg-slate-100 text-slate-700 flex items-center justify-center group-hover:scale-110 transition-transform">
              <Scale className="w-4 h-4" />
            </div>
          </div>
          <div className="text-2xl font-bold text-slate-900 tracking-tight">
            {surplusBulan >= 0 ? '+ ' : '- '}{formatRupiah(Math.abs(surplusBulan))}
          </div>
          <div className="mt-3 flex items-center text-[11px] text-emerald-600 font-medium">
            <ShieldCheck className="w-3.5 h-3.5 mr-1" />
            <span>Arus Kas Sehat</span>
          </div>
        </div>
      </div>

      {/* Graph & Composition Section */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        {/* Cash Flow Line Chart */}
        <div className="lg:col-span-2 bg-white p-6 rounded-[14px] border border-slate-200/90 shadow-sm">
          <div className="flex items-center justify-between mb-6">
            <div>
              <h3 className="font-bold text-slate-900 text-base">Grafik Arus Kas (Cash Flow)</h3>
              <p className="text-xs text-slate-500">Perbandingan pemasukan vs pengeluaran 6 bulan terakhir</p>
            </div>
            <span className="text-xs font-medium bg-slate-100 text-slate-700 px-3 py-1 rounded-lg">
              T.A {tahunAjaran}
            </span>
          </div>

          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <LineChart data={chartData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#f1f5f9" />
                <XAxis dataKey="bulan" tick={{ fontSize: 11 }} />
                <YAxis 
                  tick={{ fontSize: 10 }} 
                  tickFormatter={(val) => `Rp ${(val / 1000000).toFixed(0)}Jt`} 
                />
                <Tooltip 
                  formatter={(val: any) => [formatRupiah(Number(val)), '']} 
                  contentStyle={{ borderRadius: '10px', fontSize: '12px' }}
                />
                <Legend wrapperStyle={{ fontSize: '12px' }} />
                <Line 
                  type="monotone" 
                  dataKey="pemasukan" 
                  name="Pemasukan (Rp)" 
                  stroke="#10b981" 
                  strokeWidth={2.5} 
                  dot={{ r: 4 }} 
                />
                <Line 
                  type="monotone" 
                  dataKey="pengeluaran" 
                  name="Pengeluaran (Rp)" 
                  stroke="#f43f5e" 
                  strokeWidth={2.5} 
                  dot={{ r: 4 }} 
                />
              </LineChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Source Composition */}
        <div className="bg-white p-6 rounded-[14px] border border-slate-200/90 shadow-sm flex flex-col justify-between">
          <div>
            <h3 className="font-bold text-slate-900 text-base mb-1">Sumber Pemasukan Utama</h3>
            <p className="text-xs text-slate-500 mb-6">Komposisi penerimaan dana bulan {currentMonthName}</p>

            {compositionEntries.length === 0 ? (
              <p className="text-xs text-slate-400 italic">Belum ada pemasukan tercatat bulan ini.</p>
            ) : (
              <div className="space-y-4">
                {compositionEntries.map((e, idx) => {
                  const pct = totalInBulan > 0 ? Math.round((e.nominal / totalInBulan) * 100) : 0;
                  return (
                    <div key={e.name}>
                      <div className="flex justify-between text-xs font-semibold mb-1">
                        <span className="text-slate-700">{e.name}</span>
                        <span className="text-slate-900">{formatRupiah(e.nominal)} ({pct}%)</span>
                      </div>
                      <div className="w-full h-2 bg-slate-100 rounded-full overflow-hidden">
                        <div 
                          className={`${palette[idx % palette.length]} h-full rounded-full transition-all duration-500`} 
                          style={{ width: `${pct}%` }} 
                        />
                      </div>
                    </div>
                  );
                })}
              </div>
            )}
          </div>

          <div className="pt-6 border-t border-slate-100 mt-6">
            <div className="p-3 bg-blue-50/70 rounded-[14px] flex items-start gap-3">
              <Lightbulb className="w-4 h-4 text-blue-600 shrink-0 mt-0.5" />
              <p className="text-xs text-blue-900 leading-relaxed">
                <strong>Tips Bendahara:</strong> Seluruh pemasukan dari SPP akan tercatat otomatis dalam Laporan Rekap Bulanan tanpa perlu membuat jurnal akuntansi manual.
              </p>
            </div>
          </div>
        </div>
      </div>

      {/* 5 Recent Transactions Table */}
      <div className="bg-white rounded-[14px] border border-slate-200/90 shadow-sm overflow-hidden">
        <div className="p-6 border-b border-slate-100 flex items-center justify-between">
          <div>
            <h3 className="font-bold text-slate-900 text-base">5 Transaksi Terakhir</h3>
            <p className="text-xs text-slate-500">Catatan pencatatan terbaru dari Bendahara</p>
          </div>
          <button 
            onClick={() => onSwitchTab('pemasukan')} 
            className="text-xs font-semibold text-blue-600 hover:text-blue-700 flex items-center gap-1"
          >
            Lihat Semua Transaksi <ArrowRight className="w-3.5 h-3.5" />
          </button>
        </div>

        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs text-slate-600">
            <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-100">
              <tr>
                <th className="p-4">Tanggal</th>
                <th className="p-4">Tipe</th>
                <th className="p-4">Kategori / Sumber</th>
                <th className="p-4">Detail Sub Kategori</th>
                <th className="p-4">Keterangan</th>
                <th className="p-4 text-right">Nominal</th>
                <th className="p-4 text-center">Status</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 font-medium">
              {recentTransactions.map(tx => (
                <tr key={tx.id} className="hover:bg-slate-50/80 transition-colors">
                  <td className="p-4 font-mono text-slate-500">{tx.tanggal}</td>
                  <td className="p-4">
                    <span className={`inline-flex items-center gap-1 px-2.5 py-1 rounded-full text-[10px] font-bold ${
                      tx.type === 'IN' ? 'bg-emerald-50 text-emerald-700' : 'bg-rose-50 text-rose-700'
                    }`}>
                      {tx.type === 'IN' ? 'Pemasukan' : 'Pengeluaran'}
                    </span>
                  </td>
                  <td className="p-4 font-semibold text-slate-800">
                    {'sumber' in tx ? tx.sumber : tx.kategori}
                  </td>
                  <td className="p-4 text-slate-600">{'sub' in tx ? tx.sub : '-'}</td>
                  <td className="p-4 text-slate-600 max-w-xs truncate">{tx.keterangan}</td>
                  <td className={`p-4 text-right font-bold text-sm ${
                    tx.type === 'IN' ? 'text-emerald-600' : 'text-rose-600'
                  }`}>
                    {tx.type === 'IN' ? '+' : '-'} {formatRupiah(tx.nominal)}
                  </td>
                  <td className="p-4 text-center">
                    <span className="px-2 py-0.5 rounded text-[10px] bg-slate-100 text-slate-600 font-semibold">Tercatat</span>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  );
};
