import React, { useState } from 'react';
import { Plus, Search, Receipt, Trash2 } from 'lucide-react';
import { Pengeluaran } from '../types';

interface PengeluaranViewProps {
  pengeluaranList: Pengeluaran[];
  masterKategoriPengeluaran: string[];
  onOpenModal: () => void;
  onDeletePengeluaran: (id: string) => void;
  formatRupiah: (val: number) => string;
}

export const PengeluaranView: React.FC<PengeluaranViewProps> = ({
  pengeluaranList,
  masterKategoriPengeluaran,
  onOpenModal,
  onDeletePengeluaran,
  formatRupiah
}) => {
  const [search, setSearch] = useState('');
  const [filterKat, setFilterKat] = useState('ALL');

  const filtered = pengeluaranList.filter(item => {
    const matchSearch = item.keterangan.toLowerCase().includes(search.toLowerCase()) ||
      item.kategori.toLowerCase().includes(search.toLowerCase());
    const matchKat = filterKat === 'ALL' || item.kategori === filterKat;
    return matchSearch && matchKat;
  });

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-xl font-bold text-slate-900 tracking-tight">Catatan Pengeluaran</h1>
          <p className="text-xs text-slate-500">Pencatatan biaya operasional, gaji/honor guru, ATK, pemeliharaan & utilitas</p>
        </div>
        <button 
          onClick={onOpenModal} 
          className="flex items-center gap-2 px-4 py-2.5 bg-rose-600 hover:bg-rose-700 text-white rounded-[14px] text-xs font-semibold shadow-sm transition-all active:scale-95"
        >
          <Plus className="w-4 h-4" />
          <span>+ Tambah Pengeluaran Baru</span>
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
            placeholder="Cari keterangan atau kategori pengeluaran..." 
            className="w-full pl-9 pr-4 py-2 bg-slate-50 border border-slate-200 rounded-[14px] text-xs outline-none focus:bg-white focus:border-blue-500 transition-all"
          />
        </div>

        <div className="flex items-center gap-2 flex-wrap">
          <select 
            value={filterKat}
            onChange={(e) => setFilterKat(e.target.value)}
            className="border border-slate-200 bg-slate-50 text-slate-700 rounded-[14px] px-3 py-2 text-xs font-medium outline-none focus:border-blue-500"
          >
            <option value="ALL">Semua Kategori</option>
            {masterKategoriPengeluaran.map(k => (
              <option key={k} value={k}>{k}</option>
            ))}
          </select>

          <button 
            onClick={() => { setSearch(''); setFilterKat('ALL'); }}
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
                <th className="p-4">Kategori Pengeluaran</th>
                <th className="p-4">Keterangan / Tujuan</th>
                <th className="p-4 text-right">Nominal</th>
                <th className="p-4 text-center">Bukti Nota</th>
                <th className="p-4 text-center">Status</th>
                <th className="p-4 text-center">Aksi</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-slate-100 font-medium">
              {filtered.length === 0 ? (
                <tr>
                  <td colSpan={7} className="p-8 text-center text-slate-400 font-medium">
                    Tidak ada data pengeluaran ditemukan.
                  </td>
                </tr>
              ) : (
                filtered.map(item => (
                  <tr key={item.id} className="hover:bg-slate-50/80 transition-colors">
                    <td className="p-4 font-mono text-slate-500">{item.tanggal}</td>
                    <td className="p-4 font-bold text-slate-800">{item.kategori}</td>
                    <td className="p-4 text-slate-600 max-w-xs truncate">{item.keterangan}</td>
                    <td className="p-4 text-right font-bold text-rose-600 text-sm">
                      {formatRupiah(item.nominal)}
                    </td>
                    <td className="p-4 text-center">
                      <Receipt className="w-4 h-4 text-slate-400 hover:text-blue-600 cursor-pointer inline" />
                    </td>
                    <td className="p-4 text-center">
                      <span className="px-2 py-0.5 rounded text-[10px] bg-emerald-50 text-emerald-700 font-bold">
                        Lunas
                      </span>
                    </td>
                    <td className="p-4 text-center">
                      <button 
                        onClick={() => onDeletePengeluaran(item.id)} 
                        className="text-slate-400 hover:text-rose-600 p-1" 
                        title="Hapus Pengeluaran"
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
      </div>
    </div>
  );
};
