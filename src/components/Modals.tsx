import React, { useState } from 'react';
import { 
  X, ArrowDownLeft, ArrowUpRight, GraduationCap, HandCoins, 
  Compass, Wand2, ShieldAlert, AlertCircle, UploadCloud, FileText 
} from 'lucide-react';
import { MasterSumberDana, SiswaTagihan, Pemasukan } from '../types';

// =========================================================================
// MODAL 1: FORM PEMASUKAN
// =========================================================================
interface ModalPemasukanProps {
  isOpen: boolean;
  onClose: () => void;
  masterSumberDana: MasterSumberDana[];
  masterKelas: string[];
  onSave: (data: {
    tanggal: string;
    noBukti: string;
    sumber: string;
    sub: string;
    nominal: number;
    keterangan: string;
  }) => void;
}

export const ModalPemasukan: React.FC<ModalPemasukanProps> = ({
  isOpen,
  onClose,
  masterSumberDana,
  masterKelas,
  onSave
}) => {
  const [tanggal, setTanggal] = useState(new Date().toISOString().split('T')[0]);
  const [noBukti, setNoBukti] = useState('');
  const [sumber, setSumber] = useState('');
  const [customSumber, setCustomSumber] = useState('');
  const [sub, setSub] = useState('');
  const [customSub, setCustomSub] = useState('');
  const [nominal, setNominal] = useState('');
  const [keterangan, setKeterangan] = useState('');

  if (!isOpen) return null;

  const currentSumberObj = masterSumberDana.find(s => s.id === sumber);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    const finalSumber = sumber === 'Lainnya' ? (customSumber.trim() || 'Sumber Dana Lainnya') : sumber;
    const finalSub = sumber === 'Lainnya' ? (customSub.trim() || 'Umum') : sub;

    if (!finalSumber || !finalSub || !nominal || !keterangan) return;

    onSave({
      tanggal,
      noBukti,
      sumber: finalSumber,
      sub: finalSub,
      nominal: parseFloat(nominal),
      keterangan
    });

    setNoBukti('');
    setNominal('');
    setKeterangan('');
    setCustomSumber('');
    setCustomSub('');
    onClose();
  };

  return (
    <div className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-[14px] max-w-lg w-full shadow-xl border border-slate-200 overflow-y-auto max-h-[92vh] animate-in fade-in zoom-in duration-150">
        <div className="p-5 bg-slate-50 border-b border-slate-100 flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-full bg-emerald-100 text-emerald-600 flex items-center justify-center">
              <ArrowDownLeft className="w-4 h-4" />
            </div>
            <div>
              <h3 className="font-bold text-slate-900 text-sm">Tambah Pemasukan Kas</h3>
              <p className="text-[11px] text-slate-500">Maksimal 2-3 klik untuk mencatat penerimaan dana</p>
            </div>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600 p-1">
            <X className="w-4 h-4" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">Tanggal Transaksi</label>
              <input 
                type="date" 
                required 
                value={tanggal}
                onChange={(e) => setTanggal(e.target.value)}
                className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs text-slate-800 outline-none focus:bg-white focus:border-blue-500"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">No. Bukti <span className="text-slate-400 font-normal">(Opsional)</span></label>
              <input 
                type="text" 
                value={noBukti}
                onChange={(e) => setNoBukti(e.target.value)}
                placeholder="Otomatis jika kosong" 
                className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs text-slate-800 outline-none focus:bg-white focus:border-blue-500"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">Sumber Dana Utama</label>
            <select 
              required
              value={sumber}
              onChange={(e) => { setSumber(e.target.value); setSub(''); }}
              className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs font-semibold text-slate-800 outline-none focus:bg-white focus:border-blue-500"
            >
              <option value="" disabled>-- Pilih Sumber Dana --</option>
              {masterSumberDana.map(s => (
                <option key={s.id} value={s.id}>{s.name}</option>
              ))}
              <option value="Lainnya">-- Sumber Dana Lainnya (Ketik Manual) --</option>
            </select>
            {sumber === 'Lainnya' && (
              <input 
                type="text"
                required
                value={customSumber}
                onChange={(e) => setCustomSumber(e.target.value)}
                placeholder="Ketik Nama Sumber Dana Manual..."
                className="mt-2 w-full bg-white border border-blue-300 rounded-[14px] px-3 py-2 text-xs font-semibold text-blue-900 outline-none focus:ring-1 focus:ring-blue-500"
              />
            )}
          </div>

          {sumber === 'Lainnya' ? (
            <div className="bg-blue-50/50 p-3.5 rounded-[14px] border border-blue-100">
              <label className="block text-xs font-bold text-blue-900 mb-1">Rincian / Sub Kategori (Ketik Manual)</label>
              <input 
                type="text"
                required
                value={customSub}
                onChange={(e) => setCustomSub(e.target.value)}
                placeholder="Rincian penerimaan / nama instansi / donatur..."
                className="w-full bg-white border border-blue-200 rounded-[14px] px-3 py-2 text-xs font-semibold text-blue-900 outline-none"
              />
            </div>
          ) : sumber && (
            <div className="bg-blue-50/50 p-3.5 rounded-[14px] border border-blue-100">
              <label className="block text-xs font-bold text-blue-900 mb-1">Sub Kategori / Rincian</label>
              {sumber === 'Infak' && masterKelas.length > 0 ? (
                <select 
                  required
                  value={sub}
                  onChange={(e) => setSub(e.target.value)}
                  className="w-full bg-white border border-blue-200 rounded-[14px] px-3 py-2 text-xs font-semibold text-blue-900 outline-none"
                >
                  <option value="" disabled>-- Pilih Sub / Kelas --</option>
                  {(currentSumberObj?.subs || []).map(sb => (
                    <option key={sb} value={sb}>{sb}</option>
                  ))}
                  {masterKelas.map(k => (
                    <option key={k} value={k}>{k}</option>
                  ))}
                </select>
              ) : currentSumberObj?.subs && currentSumberObj.subs.length > 0 ? (
                <select 
                  required
                  value={sub}
                  onChange={(e) => setSub(e.target.value)}
                  className="w-full bg-white border border-blue-200 rounded-[14px] px-3 py-2 text-xs font-semibold text-blue-900 outline-none"
                >
                  <option value="" disabled>-- Pilih Rincian --</option>
                  {currentSumberObj.subs.map(sb => (
                    <option key={sb} value={sb}>{sb}</option>
                  ))}
                </select>
              ) : (
                <input 
                  type="text"
                  required
                  value={sub}
                  onChange={(e) => setSub(e.target.value)}
                  placeholder="Nama Donatur / Instansi / Rincian Pemasukan"
                  className="w-full bg-white border border-blue-200 rounded-[14px] px-3 py-2 text-xs font-semibold text-blue-900 outline-none"
                />
              )}
            </div>
          )}

          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">Nominal (Rp)</label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-slate-400">Rp</span>
              <input 
                type="number" 
                required 
                min="1"
                value={nominal}
                onChange={(e) => setNominal(e.target.value)}
                placeholder="0" 
                className="w-full pl-9 pr-3 py-2 bg-slate-50 border border-slate-200 rounded-[14px] text-sm font-bold text-slate-900 outline-none focus:bg-white focus:border-blue-500"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">Keterangan Catatan</label>
            <input 
              type="text" 
              required
              value={keterangan}
              onChange={(e) => setKeterangan(e.target.value)}
              placeholder="Contoh: Pembayaran SPP bulan Agustus a.n Ahmad" 
              className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs text-slate-800 outline-none focus:bg-white focus:border-blue-500"
            />
          </div>

          <div className="pt-3 flex items-center justify-end gap-2 border-t border-slate-100">
            <button 
              type="button" 
              onClick={onClose} 
              className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-[14px]"
            >
              Batal
            </button>
            <button 
              type="submit" 
              className="px-5 py-2 text-xs font-semibold text-white bg-emerald-600 hover:bg-emerald-700 rounded-[14px] shadow-sm transition-all"
            >
              Simpan Transaksi
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

// =========================================================================
// MODAL 2: FORM PENGELUARAN (WITH RPC SERVER-SIDE VALIDATION CATCHING)
// =========================================================================
interface ModalPengeluaranProps {
  isOpen: boolean;
  onClose: () => void;
  masterKategoriPengeluaran: string[];
  onSave: (data: {
    tanggal: string;
    noBukti: string;
    kategori: string;
    nominal: number;
    keterangan: string;
    buktiFile?: File | null;
  }) => Promise<{ success: boolean; message?: string }>;
}

const MAX_BUKTI_SIZE_BYTES = 5 * 1024 * 1024; // 5MB

export const ModalPengeluaran: React.FC<ModalPengeluaranProps> = ({
  isOpen,
  onClose,
  masterKategoriPengeluaran,
  onSave
}) => {
  const [tanggal, setTanggal] = useState(new Date().toISOString().split('T')[0]);
  const [noBukti, setNoBukti] = useState('');
  const [kategori, setKategori] = useState('');
  const [customKategori, setCustomKategori] = useState('');
  const [nominal, setNominal] = useState('');
  const [keterangan, setKeterangan] = useState('');
  const [buktiFile, setBuktiFile] = useState<File | null>(null);
  const [buktiPreviewUrl, setBuktiPreviewUrl] = useState<string | null>(null);
  const [errorMessage, setErrorMessage] = useState<string | null>(null);
  const [submitting, setSubmitting] = useState(false);

  if (!isOpen) return null;

  const handleBuktiChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0] || null;
    setErrorMessage(null);

    if (!file) {
      setBuktiFile(null);
      setBuktiPreviewUrl(null);
      return;
    }

    if (file.size > MAX_BUKTI_SIZE_BYTES) {
      setErrorMessage('Ukuran file nota/kwitansi maksimal 5MB.');
      e.target.value = '';
      return;
    }

    setBuktiFile(file);
    if (file.type.startsWith('image/')) {
      setBuktiPreviewUrl(URL.createObjectURL(file));
    } else {
      setBuktiPreviewUrl(null);
    }
  };

  const handleRemoveBukti = () => {
    setBuktiFile(null);
    setBuktiPreviewUrl(null);
  };

  const resetForm = () => {
    setNoBukti('');
    setNominal('');
    setKeterangan('');
    setCustomKategori('');
    setBuktiFile(null);
    setBuktiPreviewUrl(null);
  };

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const finalKategori = kategori === 'Lainnya' ? (customKategori.trim() || 'Pengeluaran Lainnya') : kategori;
    if (!finalKategori || !nominal || !keterangan) return;

    setSubmitting(true);
    setErrorMessage(null);

    const res = await onSave({
      tanggal,
      noBukti,
      kategori: finalKategori,
      nominal: parseFloat(nominal),
      keterangan,
      buktiFile
    });

    setSubmitting(false);

    if (res.success) {
      resetForm();
      onClose();
    } else {
      // Show server-side constraint validation error (e.g. Saldo tidak cukup)!
      setErrorMessage(res.message || 'Gagal menyimpan pengeluaran.');
    }
  };

  return (
    <div className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-[14px] max-w-lg w-full shadow-xl border border-slate-200 overflow-y-auto max-h-[92vh] animate-in fade-in zoom-in duration-150">
        <div className="p-5 bg-slate-50 border-b border-slate-100 flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-full bg-rose-100 text-rose-600 flex items-center justify-center">
              <ArrowUpRight className="w-4 h-4" />
            </div>
            <div>
              <h3 className="font-bold text-slate-900 text-sm">Tambah Pengeluaran Kas</h3>
              <p className="text-[11px] text-slate-500">Validasi Saldo Kas Server-Side via Postgres RPC Function</p>
            </div>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600 p-1">
            <X className="w-4 h-4" />
          </button>
        </div>

        <form onSubmit={handleSubmit} className="p-6 space-y-4">
          {errorMessage && (
            <div className="p-3.5 bg-rose-50 border border-rose-200 rounded-[14px] text-xs font-semibold text-rose-800 flex items-start gap-2.5">
              <AlertCircle className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />
              <div>
                <p className="font-bold text-rose-900">Validasi Server Database Gagal:</p>
                <p className="mt-0.5 font-normal text-[11px]">{errorMessage}</p>
              </div>
            </div>
          )}

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">Tanggal Transaksi</label>
              <input 
                type="date" 
                required 
                value={tanggal}
                onChange={(e) => setTanggal(e.target.value)}
                className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs text-slate-800 outline-none focus:bg-white focus:border-blue-500"
              />
            </div>
            <div>
              <label className="block text-xs font-semibold text-slate-700 mb-1">No. Bukti <span className="text-slate-400 font-normal">(Opsional)</span></label>
              <input 
                type="text" 
                value={noBukti}
                onChange={(e) => setNoBukti(e.target.value)}
                placeholder="Otomatis jika kosong" 
                className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs text-slate-800 outline-none focus:bg-white focus:border-blue-500"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">Kategori Pengeluaran</label>
            <select 
              required
              value={kategori}
              onChange={(e) => setKategori(e.target.value)}
              className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs font-semibold text-slate-800 outline-none focus:bg-white focus:border-blue-500"
            >
              <option value="" disabled>-- Pilih Kategori Pengeluaran --</option>
              {masterKategoriPengeluaran.map(k => (
                <option key={k} value={k}>{k}</option>
              ))}
              <option value="Lainnya">-- Kategori Pengeluaran Lainnya (Ketik Manual) --</option>
            </select>
            {kategori === 'Lainnya' && (
              <input 
                type="text"
                required
                value={customKategori}
                onChange={(e) => setCustomKategori(e.target.value)}
                placeholder="Ketik Kategori Pengeluaran Manual..."
                className="mt-2 w-full bg-white border border-rose-300 rounded-[14px] px-3 py-2 text-xs font-semibold text-rose-900 outline-none focus:ring-1 focus:ring-rose-500"
              />
            )}
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">Nominal (Rp)</label>
            <div className="relative">
              <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-slate-400">Rp</span>
              <input 
                type="number" 
                required 
                min="1"
                value={nominal}
                onChange={(e) => setNominal(e.target.value)}
                placeholder="0" 
                className="w-full pl-9 pr-3 py-2 bg-slate-50 border border-slate-200 rounded-[14px] text-sm font-bold text-slate-900 outline-none focus:bg-white focus:border-blue-500"
              />
            </div>
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">Keterangan / Tujuan Pengeluaran</label>
            <input 
              type="text" 
              required
              value={keterangan}
              onChange={(e) => setKeterangan(e.target.value)}
              placeholder="Contoh: Pembelian spidol & kertas HVS A4 untuk ujian" 
              className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3 py-2 text-xs text-slate-800 outline-none focus:bg-white focus:border-blue-500"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1">Upload Nota / Kwitansi</label>
            {!buktiFile ? (
              <label
                htmlFor="bukti-pengeluaran-input"
                className="flex flex-col items-center justify-center gap-1.5 border-2 border-dashed border-slate-200 rounded-[14px] py-6 px-3 text-center cursor-pointer hover:border-blue-400 hover:bg-blue-50/40 transition-colors"
              >
                <UploadCloud className="w-5 h-5 text-slate-400" />
                <span className="text-[11px] text-slate-500">Unggah foto nota tagihan/struk (Opsional)</span>
                <input
                  id="bukti-pengeluaran-input"
                  type="file"
                  accept="image/*,application/pdf"
                  onChange={handleBuktiChange}
                  className="hidden"
                />
              </label>
            ) : (
              <div className="flex items-center gap-3 border border-slate-200 rounded-[14px] p-2.5">
                {buktiPreviewUrl ? (
                  <img src={buktiPreviewUrl} alt="Preview nota" className="w-12 h-12 rounded-[10px] object-cover shrink-0" />
                ) : (
                  <div className="w-12 h-12 rounded-[10px] bg-slate-100 flex items-center justify-center shrink-0">
                    <FileText className="w-5 h-5 text-slate-400" />
                  </div>
                )}
                <div className="min-w-0 flex-1">
                  <p className="text-xs font-semibold text-slate-800 truncate">{buktiFile.name}</p>
                  <p className="text-[11px] text-slate-500">{(buktiFile.size / 1024).toFixed(0)} KB</p>
                </div>
                <button
                  type="button"
                  onClick={handleRemoveBukti}
                  className="text-slate-400 hover:text-rose-600 p-1 shrink-0"
                  aria-label="Hapus file"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>
            )}
          </div>

          <div className="pt-3 flex items-center justify-end gap-2 border-t border-slate-100">
            <button 
              type="button" 
              onClick={onClose} 
              className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-[14px]"
            >
              Batal
            </button>
            <button 
              type="submit" 
              disabled={submitting}
              className="px-5 py-2 text-xs font-semibold text-white bg-rose-600 hover:bg-rose-700 rounded-[14px] shadow-sm transition-all disabled:opacity-50"
            >
              {submitting ? 'Memeriksa Saldo & Saving...' : 'Simpan Pengeluaran'}
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

// =========================================================================
// MODAL 3: TAGIHAN SISWA
// =========================================================================
interface ModalSiswaTagihanProps {
  isOpen: boolean;
  onClose: () => void;
  masterKelas: string[];
  onSave: (data: {
    nama: string;
    kelas: string;
    jenis: string;
    target: number;
    catatan?: string;
  }) => void;
}

export const ModalSiswaTagihanPropsModal: React.FC<ModalSiswaTagihanProps> = ({
  isOpen,
  onClose,
  masterKelas,
  onSave
}) => {
  const [nama, setNama] = useState('');
  const [kelas, setKelas] = useState(masterKelas[0] || 'Kelas 1');
  const [jenis, setJenis] = useState('Infak Pembangunan');
  const [target, setTarget] = useState('');
  const [catatan, setCatatan] = useState('');

  if (!isOpen) return null;

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!nama || !jenis || !target) return;
    onSave({
      nama,
      kelas,
      jenis,
      target: parseFloat(target),
      catatan
    });
    setNama('');
    setTarget('');
    setCatatan('');
    onClose();
  };

  return (
    <div className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-[14px] max-w-lg w-full shadow-xl border border-slate-200 p-6 space-y-4">
        <div className="flex items-center justify-between border-b pb-3">
          <div className="flex items-center gap-2">
            <GraduationCap className="w-5 h-5 text-amber-500" />
            <h3 className="font-bold text-slate-900 text-sm">Tambah Tagihan Siswa Baru</h3>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600">✕</button>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4 text-xs">
          <div>
            <label className="block font-semibold text-slate-700 mb-1">Nama Siswa</label>
            <input 
              type="text" 
              required
              value={nama}
              onChange={(e) => setNama(e.target.value)}
              placeholder="Contoh: Ahmad Fauzi" 
              className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-[14px] outline-none"
            />
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <label className="block font-semibold text-slate-700 mb-1">Kelas</label>
              <select 
                value={kelas}
                onChange={(e) => setKelas(e.target.value)}
                className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-[14px] outline-none"
              >
                {masterKelas.map(k => (
                  <option key={k} value={k}>{k}</option>
                ))}
              </select>
            </div>

            <div>
              <label className="block font-semibold text-slate-700 mb-1">Jenis Tagihan</label>
              <input 
                type="text" 
                required
                value={jenis}
                onChange={(e) => setJenis(e.target.value)}
                placeholder="Contoh: Infak Pembangunan" 
                className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-[14px] outline-none"
              />
            </div>
          </div>

          <div>
            <label className="block font-semibold text-slate-700 mb-1">Target Nominal Tagihan (Rp)</label>
            <input 
              type="number" 
              required
              min="1"
              value={target}
              onChange={(e) => setTarget(e.target.value)}
              placeholder="0" 
              className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-[14px] font-bold outline-none"
            />
          </div>

          <div>
            <label className="block font-semibold text-slate-700 mb-1">Catatan (Opsional)</label>
            <input 
              type="text" 
              value={catatan}
              onChange={(e) => setCatatan(e.target.value)}
              placeholder="Contoh: Cicilan disepakati s.d Desember 2026" 
              className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-[14px] outline-none"
            />
          </div>

          <div className="pt-3 border-t flex justify-end gap-2">
            <button type="button" onClick={onClose} className="px-4 py-2 text-slate-600">Batal</button>
            <button type="submit" className="px-5 py-2 bg-amber-600 text-white font-semibold rounded-[14px]">
              Simpan Tagihan
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

// =========================================================================
// MODAL 4: BAYAR SISWA
// =========================================================================
interface ModalSiswaBayarProps {
  isOpen: boolean;
  onClose: () => void;
  siswa: SiswaTagihan | null;
  pemasukanList: Pemasukan[];
  formatRupiah: (val: number) => string;
  onSave: (data: {
    siswaId: string;
    tanggal: string;
    noBukti: string;
    nominal: number;
  }) => void;
}

export const ModalSiswaBayarPropsModal: React.FC<ModalSiswaBayarProps> = ({
  isOpen,
  onClose,
  siswa,
  pemasukanList,
  formatRupiah,
  onSave
}) => {
  const [tanggal, setTanggal] = useState(new Date().toISOString().split('T')[0]);
  const [noBukti, setNoBukti] = useState('');
  const [nominal, setNominal] = useState('');

  if (!isOpen || !siswa) return null;

  const terbayar = pemasukanList
    .filter(p => p.siswaId === siswa.id)
    .reduce((acc, curr) => acc + curr.nominal, 0);

  const sisa = Math.max(siswa.target - terbayar, 0);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!nominal) return;
    onSave({
      siswaId: siswa.id,
      tanggal,
      noBukti,
      nominal: parseFloat(nominal)
    });
    setNominal('');
    onClose();
  };

  return (
    <div className="fixed inset-0 bg-slate-900/40 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-[14px] max-w-md w-full shadow-xl border border-slate-200 p-6 space-y-4">
        <div className="flex items-center justify-between border-b pb-3">
          <div className="flex items-center gap-2">
            <HandCoins className="w-5 h-5 text-emerald-600" />
            <div>
              <h3 className="font-bold text-slate-900 text-sm">Catat Pembayaran Siswa</h3>
              <p className="text-[11px] text-slate-500">a.n {siswa.nama} ({siswa.kelas})</p>
            </div>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-slate-600">✕</button>
        </div>

        <div className="p-3 bg-amber-50 border border-amber-100 rounded-[14px] text-xs text-amber-900 space-y-1">
          <div className="flex justify-between"><span>Target Tagihan:</span><strong>{formatRupiah(siswa.target)}</strong></div>
          <div className="flex justify-between"><span>Sudah Terbayar:</span><strong className="text-emerald-700">{formatRupiah(terbayar)}</strong></div>
          <div className="flex justify-between"><span>Sisa Tagihan:</span><strong className="text-rose-700">{formatRupiah(sisa)}</strong></div>
        </div>

        <form onSubmit={handleSubmit} className="space-y-3 text-xs">
          <div>
            <label className="block font-semibold text-slate-700 mb-1">Tanggal Pembayaran</label>
            <input 
              type="date" 
              required
              value={tanggal}
              onChange={(e) => setTanggal(e.target.value)}
              className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-[14px] outline-none"
            />
          </div>

          <div>
            <label className="block font-semibold text-slate-700 mb-1">Nominal Pembayaran (Rp)</label>
            <input 
              type="number" 
              required
              min="1"
              value={nominal}
              onChange={(e) => setNominal(e.target.value)}
              placeholder={`Maks ${formatRupiah(sisa)}`} 
              className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-[14px] font-bold text-sm outline-none"
            />
          </div>

          <div className="pt-3 border-t flex justify-end gap-2">
            <button type="button" onClick={onClose} className="px-4 py-2 text-slate-600">Batal</button>
            <button type="submit" className="px-5 py-2 bg-emerald-600 text-white font-semibold rounded-[14px]">
              Simpan Pembayaran
            </button>
          </div>
        </form>
      </div>
    </div>
  );
};

// =========================================================================
// MODAL 5: BLUEPRINT UX DOCS
// =========================================================================
export const ModalBlueprint: React.FC<{ isOpen: boolean; onClose: () => void }> = ({ isOpen, onClose }) => {
  if (!isOpen) return null;
  return (
    <div className="fixed inset-0 bg-slate-900/60 backdrop-blur-md z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-[14px] max-w-3xl w-full shadow-2xl border border-slate-200 overflow-hidden flex flex-col max-h-[85vh]">
        <div className="p-5 bg-slate-900 text-white flex items-center justify-between">
          <div className="flex items-center gap-3">
            <Compass className="w-5 h-5 text-blue-400" />
            <div>
              <h2 className="text-base font-bold">Design System &amp; Architecture Blueprint</h2>
              <p className="text-xs text-slate-400">Acuan Modern Frontend Modul Bendahara (2026 Standard)</p>
            </div>
          </div>
          <button onClick={onClose} className="text-slate-400 hover:text-white">✕</button>
        </div>

        <div className="p-6 overflow-y-auto space-y-5 text-xs text-slate-700 leading-relaxed custom-scrollbar">
          <div className="p-3 bg-blue-50 rounded-[14px] border border-blue-200 text-blue-900">
            <strong>Key Architecture Highlights:</strong>
            <ul className="list-disc list-inside mt-1 space-y-1">
              <li><strong>Atomic RPC Functions:</strong> <code>catat_pengeluaran()</code> executes cash balance checks, expenditure inserts, and audit logs inside a single server-side PostgreSQL transaction.</li>
              <li><strong>Triggers for Audit Trails:</strong> Automatic Postgres trigger records all <code>INSERT</code>, <code>UPDATE</code>, and <code>DELETE</code> operations to <code>audit_log</code>.</li>
              <li><strong>Server-Side Constraint Validation:</strong> Nominal expenditures exceeding total available cash balance are blocked directly by database triggers with clear exceptions.</li>
              <li><strong>Server-Side Constraint Validation:</strong> Pengeluaran yang melebihi saldo kas tersedia otomatis diblokir langsung oleh database untuk menjaga keamanan dan konsistensi keuangan. 🚀 Ingin aplikasi keuangan yang <strong>super lengkap</strong>? Kunjungi <a href="https://rajakas.id" target="_blank" rel="noopener noreferrer"><strong>Rajakas.id</strong></a> — solusi manajemen keuangan untuk pencatatan transaksi, kontrol kas, laporan, dan pengelolaan keuangan yang lebih profesional.</li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
};
