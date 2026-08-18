import React, { useState } from 'react';
import { Plus, Search, Paperclip, Trash2, GraduationCap } from 'lucide-react';
import { Pemasukan, MasterSumberDana } from '../types';

interface PemasukanViewProps {
  pemasukanList: Pemasukan[];
  masterSumberDana: MasterSumberDana[];
  onOpenModal: () => void;
  onDeletePemasukan: (id: string) => void;
  formatRupiah: (val: number) => string;
  onSwitchTab: (tab: string) => void;
}

export const PemasukanView: React.FC<PemasukanViewProps> = ({
  pemasukanList,
  masterSumberDana,
  onOpenModal,
  onDeletePemasukan,
  formatRupiah,
  onSwitchTab
}) => {
  const [search, setSearch] = useState('');
  const [filterSumber, setFilterSumber] = useState('ALL');
  const [filterBulan, setFilterBulan] = useState('ALL');

  const getSumberName = (id: string) => {
    const s = masterSumberDana.find(x => x.id === id);
    return s ? s.name : id;
  };

  const filtered = pemasukanList.filter(item => {
    const matchSearch = item.keterangan.toLowerCase().includes(search.toLowerCase()) ||
      (item.sub || '').toLowerCase().includes(search.toLowerCase()) ||
      getSumberName(item.sumber).toLowerCase().includes(search.toLowerCase());
    
    const matchSumber = filterSumber === 'ALL' || item.sumber === filterSumber;
    const matchBulan = filterBulan === 'ALL' || (item.tanggal && item.tanggal.slice(5, 7) === filterBulan);

    return matchSearch && matchSumber && matchBulan;
  });

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-bold text-slate-900 tracking-tight">Catatan Pemasukan</h1>
          <p className="text-xs text-slate-500">Kelola dana masuk dari Dana BOS, SPP, Infak, Donasi, dan Kegiatan</p>
        </div>
        <button 
          onClick={onOpenModal} 
          className="flex items-center gap-2 px-4 py-2.5 bg-emerald-600 hover:bg-emerald-700 text-white rounded-[14px] text-xs font-semibold shadow-sm transition-all active:scale-95"
        >
          <Plus className="w-4 h-4" />
          <span>+ Tambah Pemasukan Baru</span>
        </button>
      </div>

      {/* SEARCH & FILTERS */}
      <div className="bg-white p-4 rounded-[14px] border border-slate-200/90 shadow-sm flex flex-wrap gap-3 items-center justify-between">
        <div className="relative flex-1 min-w-[240px]">
          <Search className="w-4 h-4 absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400" />
          <input 
            type="text" 
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Cari keterangan, sumber dana, atau sub kategori..." 
            className="w-full pl-9 pr-4 py-2 bg-slate-50 border border-slate-200 rounded-[14px] text-xs outline-none focus:bg-white focus:border-blue-500 transition-all"
          />
        </div>

        <div className="flex items-center gap-2 flex-wrap">
          <select 
            value={filterSumber}
            onChange={(e) => setFilterSumber(e.target.value)}
            className="border border-slate-200 bg-slate-50 text-slate-700 rounded-[14px] px-3 py-2 text-xs font-medium outline-none focus:border-blue-500"
          >
            <option value="ALL">Semua Sumber Dana</option>
            {masterSumberDana.map(s => (
              <option key={s.id} value={s.id}>{s.name}</option>
            ))}
          </select>

          <select 
            value={filterBulan}
            onChange={(e) => setFilterBulan(e.target.value)}
            className="border border-slate-200 bg-slate-50 text-slate-700 rounded-[14px] px-3 py-2 text-xs font-medium outline-none focus:border-blue-500"
          >
            <option value="ALL">Semua Bulan</option>
            <option value="08">Agustus 2026</option>
            <option value="07">Juli 2026</option>
            <option value="06">Juni 2026</option>
          </select>

          <button 
            onClick={() => { setSearch(''); setFilterSumber('ALL'); setFilterBulan('ALL'); }}
            className="px-3 py-2 text-xs font-medium text-slate-500 hover:text-slate-800"
          >
            Reset Filter
          </button>
        </div>
      </div>

      {/* DATA TABLE */}
      <div className="bg-white rounded-[14px] border border-slate-200/90 shadow-sm overflow-hidden">
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs text-slate-600">
            <thead className="bg-slate-50 text-slate-500 font-semibold border-b border-slate-200/80">
              <tr>
                <th className="p-4">Tanggal</th>
                <th className="p-4">Sumber Dana</th>
                <th className="p-4">Sub Kategori / Detil</th>
                <th className="p-4">Keterangan</th>
                <th className="p-4 text-right">Nominal</th>
                <th className="p-4 text-center">Bukti</th>
                <th className="p-4 text-center">Aksi</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 font-medium">
              {filtered.length === 0 ? (
                <tr>
                  <td colSpan={7} className="p-8 text-center text-slate-400 font-medium">
                    Tidak ada data pemasukan ditemukan.
                  </td>
                </tr>
              ) : (
                filtered.map(item => (
                  <tr key={item.id} className="hover:bg-slate-50/80 transition-colors">
                    <td className="p-4 font-mono text-slate-500">{item.tanggal}</td>
                    <td className="p-4 font-bold text-slate-800">{getSumberName(item.sumber)}</td>
                    <td className="p-4">
                      <span className="px-2 py-0.5 rounded bg-blue-50 text-blue-700 font-medium text-[11px]">
                        {item.sub}
                      </span>
                    </td>
                    <td className="p-4 text-slate-600 max-w-xs truncate">
                      {item.keterangan}
                      {item.siswaId && (
                        <button 
                          onClick={() => onSwitchTab('siswa')} 
                          className="ml-1.5 inline-flex items-center gap-1 px-1.5 py-0.5 rounded bg-amber-50 text-amber-700 text-[10px] font-semibold hover:bg-amber-100" 
                          title="Terhubung ke Monitoring Siswa"
                        >
                          <GraduationCap className="w-3 h-3" />
                        </button>
                      )}
                    </td>
                    <td className="p-4 text-right font-bold text-emerald-600 text-sm">
                      {formatRupiah(item.nominal)}
                    </td>
                    <td className="p-4 text-center">
                      <Paperclip className="w-4 h-4 text-slate-400 hover:text-blue-600 cursor-pointer inline" />
                    </td>
                    <td className="p-4 text-center">
                      <button 
                        onClick={() => onDeletePemasukan(item.id)} 
                        className="text-slate-400 hover:text-rose-600 p-1" 
                        title="Hapus Transaksi"
                      >
                        <Trash2 className="w-4 h-4" />
                      </button>
                    </td>
                  </tr>
                ))
              )}
            </tbody>
          </table>
        </div>
        <div className="p-4 border-t border-slate-100 flex items-center justify-between text-xs text-slate-500">
          <span>Menampilkan <strong>{filtered.length}</strong> transaksi</span>
        </div>
      </div>
    </div>
  );
};
