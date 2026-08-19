import React, { useEffect, useState } from 'react';
import {
  Building, Users, Vault, Tags, Wand2, ShieldAlert,
  RefreshCw, Trash2, Plus, Eye, Wallet, Save, RotateCcw,
  Sparkles, ChevronRight, ChevronLeft, Check, ImagePlus, X,
  Landmark, CalendarRange, ScrollText
} from 'lucide-react';
import { MasterSumberDana, AuditLog } from '../types';

interface PengaturanViewProps {
  currentLembaga: string;
  jenisLembaga: string;
  logoDataUrl: string | null;
  masterKelas: string[];
  masterSumberDana: MasterSumberDana[];
  masterKategoriPengeluaran: string[];
  auditLogs: AuditLog[];
  saldoAwal: number;
  tahunAjaran: string;
  periodeAktifNama: string;
  periodeAktifTanggalMulai: string;
  periodeAktifStatus: 'AKTIF' | 'DITUTUP' | null;
  onUpdateLembaga: (nama: string, jenis: string) => void;
  onLogoUpload: (e: React.ChangeEvent<HTMLInputElement>) => void;
  onRemoveLogo: () => void;
  onOpenWizard: () => void;
  onAddMasterKelas: () => void;
  onRemoveMasterKelas: (k: string) => void;
  onAddMasterSumber: () => void;
  onRemoveMasterSumber: (id: string) => void;
  onAddMasterKategori: () => void;
  onRemoveMasterKategori: (k: string) => void;
  onRefreshAuditLogs: () => void;
  onUpdateSaldoAwal: (nominal: number) => void;
  onUpdateTahunAjaran: (tahun: string) => void;
  onSavePeriodeSettings: (tahun: string, tanggalMulai: string, nominal: number) => void;
  onTutupBuku: () => void;
  onBukaBukuKembali: () => void;
  adaPeriodeUntukDibukaKembali: boolean;
  showToast: (msg: string) => void;
}

/** Kartu wadah premium: border tipis, shadow lembut berlapis, radius konsisten. */
const PremiumCard: React.FC<{ className?: string; children: React.ReactNode }> = ({ className = '', children }) => (
  <div
    className={`bg-white rounded-[20px] border border-slate-200/70 shadow-[0_1px_2px_rgba(15,23,42,0.04),0_10px_30px_-16px_rgba(15,23,42,0.18)] ${className}`}
  >
    {children}
  </div>
);

/** Label kecil kapital dengan aksen — dipakai sebagai "eyebrow" tiap bagian. */
const SectionEyebrow: React.FC<{
  icon: React.ReactNode;
  tone: 'blue' | 'emerald' | 'rose' | 'amber' | 'slate';
  title: string;
  subtitle?: string;
  action?: React.ReactNode;
}> = ({ icon, tone, title, subtitle, action }) => {
  const toneMap: Record<string, string> = {
    blue: 'bg-blue-50 text-blue-600 ring-blue-100',
    emerald: 'bg-emerald-50 text-emerald-600 ring-emerald-100',
    rose: 'bg-rose-50 text-rose-600 ring-rose-100',
    amber: 'bg-amber-50 text-amber-600 ring-amber-100',
    slate: 'bg-slate-100 text-slate-600 ring-slate-200'
  };
  return (
    <div className="flex items-center justify-between gap-4 mb-5">
      <div className="flex items-center gap-3">
        <div className={`w-9 h-9 rounded-[12px] flex items-center justify-center ring-1 ${toneMap[tone]}`}>
          {icon}
        </div>
        <div>
          <h3 className="text-sm font-bold text-slate-900 tracking-tight">{title}</h3>
          {subtitle && <p className="text-[11px] text-slate-500 mt-0.5">{subtitle}</p>}
        </div>
      </div>
      {action}
    </div>
  );
};

export const PengaturanView: React.FC<PengaturanViewProps> = ({
  currentLembaga,
  jenisLembaga,
  logoDataUrl,
  masterKelas,
  masterSumberDana,
  masterKategoriPengeluaran,
  auditLogs,
  saldoAwal,
  tahunAjaran,
  periodeAktifNama,
  periodeAktifTanggalMulai,
  periodeAktifStatus,
  onUpdateLembaga,
  onLogoUpload,
  onRemoveLogo,
  onOpenWizard,
  onAddMasterKelas,
  onRemoveMasterKelas,
  onAddMasterSumber,
  onRemoveMasterSumber,
  onAddMasterKategori,
  onRemoveMasterKategori,
  onRefreshAuditLogs,
  onUpdateSaldoAwal,
  onUpdateTahunAjaran,
  onSavePeriodeSettings,
  onTutupBuku,
  onBukaBukuKembali,
  adaPeriodeUntukDibukaKembali,
  showToast
}) => {
  const [activeSubTab, setActiveSubTab] = useState<'master' | 'audit'>('master');
  const [selectedAuditLog, setSelectedAuditLog] = useState<AuditLog | null>(null);
  const [inputKasAwal, setInputKasAwal] = useState<string>(saldoAwal.toString());
  const [inputTahunAjaran, setInputTahunAjaran] = useState<string>(tahunAjaran);
  const [inputTanggalMulai, setInputTanggalMulai] = useState<string>(periodeAktifTanggalMulai || '');
  useEffect(() => setInputTahunAjaran(tahunAjaran), [tahunAjaran]);
  useEffect(() => setInputTanggalMulai(periodeAktifTanggalMulai || ''), [periodeAktifTanggalMulai]);
  useEffect(() => setInputKasAwal(String(saldoAwal ?? 0)), [saldoAwal]);
  const [namaLembagaInput, setNamaLembagaInput] = useState<string>(currentLembaga);
  const [jenisLembagaInput, setJenisLembagaInput] = useState<string>(jenisLembaga);
  const [isWizardModalOpen, setIsWizardModalOpen] = useState<boolean>(false);
  const [wizardStep, setWizardStep] = useState<number>(1);

  const handleSaveProfil = () => {
    if (!namaLembagaInput.trim()) {
      showToast('Nama Lembaga tidak boleh kosong');
      return;
    }
    onUpdateLembaga(namaLembagaInput.trim(), jenisLembagaInput);
    showToast('Profil & Identitas Lembaga berhasil disimpan!');
  };

  const handleSaveKasAwal = () => {
    const val = Number(inputKasAwal);
    if (isNaN(val) || val < 0) {
      showToast('Nominal Kas Awal tidak valid');
      return;
    }
    onUpdateSaldoAwal(val);
  };

  const handleSavePeriode = () => {
    const val = Number(inputKasAwal);
    const tahun = inputTahunAjaran.trim();
    if (!/^\d{4}\/\d{4}$/.test(tahun)) {
      showToast('Format Tahun Ajaran harus YYYY/YYYY, contoh 2025/2026');
      return;
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(inputTanggalMulai)) {
      showToast('Tanggal Mulai Periode tidak valid');
      return;
    }
    if (isNaN(val) || val < 0) {
      showToast('Nominal Saldo Awal tidak valid');
      return;
    }
    onSavePeriodeSettings(tahun, inputTanggalMulai, val);
  };

  const jenisLembagaOptions = [
    { value: 'SD', label: 'Sekolah Dasar (SD)' },
    { value: 'SMP', label: 'Sekolah Menengah Pertama (SMP)' },
    { value: 'SMA', label: 'Sekolah Menengah Atas (SMA)' },
    { value: 'SMK', label: 'Sekolah Menengah Kejuruan (SMK)' },
    { value: 'Pesantren', label: 'Pondok Pesantren' },
    { value: 'Yayasan', label: 'Yayasan' },
    { value: 'Kampus', label: 'Perguruan Tinggi / Kampus' },
    { value: 'Ormas', label: 'Organisasi Masyarakat (Ormas)' }
  ];

  return (
    <div className="space-y-6 max-w-7xl mx-auto">
      {/* HERO HEADER */}
      <div className="relative overflow-hidden rounded-[22px] bg-gradient-to-br from-slate-900 via-slate-900 to-indigo-950 p-6 sm:p-7 shadow-[0_20px_50px_-24px_rgba(15,23,42,0.55)]">
        <div className="absolute -top-16 -right-16 w-64 h-64 bg-blue-500/20 rounded-full blur-3xl pointer-events-none" />
        <div className="absolute -bottom-20 -left-10 w-56 h-56 bg-amber-400/10 rounded-full blur-3xl pointer-events-none" />
        <div className="relative flex flex-col sm:flex-row sm:items-center justify-between gap-4">
          <div className="flex items-start gap-3">
            <div className="w-11 h-11 rounded-[14px] bg-white/10 ring-1 ring-white/15 backdrop-blur-md flex items-center justify-center shrink-0">
              <Landmark className="w-5 h-5 text-amber-300" />
            </div>
            <div>
              <div className="flex items-center gap-2">
                <h1 className="text-xl font-bold text-white tracking-tight">Pengaturan &amp; Audit Database</h1>
                <span className="hidden sm:inline-flex items-center gap-1 px-2 py-0.5 rounded-full bg-amber-400/15 text-amber-300 text-[10px] font-bold ring-1 ring-amber-400/25">
                  <Sparkles className="w-3 h-3" /> Premium
                </span>
              </div>
              <p className="text-xs text-slate-300 mt-1 max-w-md">
                Profil lembaga, master data, periode pembukuan, dan Riwayat Audit Log — semuanya di satu tempat.
              </p>
            </div>
          </div>
          <button
            onClick={() => {
              setIsWizardModalOpen(true);
              onOpenWizard();
            }}
            className="px-4 py-2.5 bg-white text-slate-900 hover:bg-amber-300 rounded-[14px] text-xs font-bold transition-all flex items-center gap-1.5 shadow-lg active:scale-95 shrink-0"
          >
            <Wand2 className="w-3.5 h-3.5" />
            <span>Setup Wizard</span>
          </button>
        </div>
      </div>

      {/* SUB-TAB NAVIGATION — pill style */}
      <div className="inline-flex items-center gap-1 p-1 bg-slate-100/80 rounded-[16px] border border-slate-200/70">
        <button
          onClick={() => setActiveSubTab('master')}
          className={`px-4 py-2 text-xs font-bold rounded-[12px] transition-all flex items-center gap-2 ${
            activeSubTab === 'master'
              ? 'bg-white text-slate-900 shadow-sm ring-1 ring-slate-200/70'
              : 'text-slate-500 hover:text-slate-800'
          }`}
        >
          <Building className="w-3.5 h-3.5" />
          <span>Master Data &amp; Profil</span>
        </button>

        <button
          onClick={() => { setActiveSubTab('audit'); onRefreshAuditLogs(); }}
          className={`px-4 py-2 text-xs font-bold rounded-[12px] transition-all flex items-center gap-2 ${
            activeSubTab === 'audit'
              ? 'bg-white text-slate-900 shadow-sm ring-1 ring-slate-200/70'
              : 'text-slate-500 hover:text-slate-800'
          }`}
        >
          <ShieldAlert className="w-3.5 h-3.5 text-amber-500" />
          <span>Riwayat Audit Log</span>
          <span className="bg-amber-100 text-amber-800 text-[10px] px-1.5 py-0.5 rounded-full font-extrabold min-w-[18px] text-center">
            {auditLogs.length}
          </span>
        </button>
      </div>

      {/* TAB 1: MASTER DATA & PROFIL */}
      {activeSubTab === 'master' && (
        <div className="space-y-6">
          {/* Institution Profile */}
          <PremiumCard className="p-6">
            <SectionEyebrow
              icon={<Building className="w-4 h-4" />}
              tone="blue"
              title="Profil & Identitas Lembaga"
              subtitle="Data ini tampil pada kop laporan dan bukti transaksi"
              action={
                <button
                  type="button"
                  onClick={handleSaveProfil}
                  className="px-4 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-[12px] text-xs font-semibold shadow-sm shadow-blue-600/20 transition-all flex items-center gap-1.5 active:scale-95"
                >
                  <Save className="w-3.5 h-3.5" />
                  <span>Simpan Profil</span>
                </button>
              }
            />

            <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
              <div>
                <label className="block text-[11px] font-bold text-slate-500 uppercase tracking-wide mb-1.5">Jenis Lembaga</label>
                <select
                  value={jenisLembagaInput}
                  onChange={(e) => setJenisLembagaInput(e.target.value)}
                  className="w-full bg-slate-50/70 border border-slate-200 rounded-[12px] px-3 py-2.5 text-xs font-medium text-slate-700 outline-none focus:border-blue-500 focus:bg-white focus:ring-4 focus:ring-blue-500/10 transition-all"
                >
                  {jenisLembagaOptions.map(opt => (
                    <option key={opt.value} value={opt.value}>{opt.label}</option>
                  ))}
                </select>
              </div>
              <div className="md:col-span-2">
                <label className="block text-[11px] font-bold text-slate-500 uppercase tracking-wide mb-1.5">Nama Lembaga</label>
                <input
                  type="text"
                  value={namaLembagaInput}
                  onChange={(e) => setNamaLembagaInput(e.target.value)}
                  placeholder="Ketik Nama Sekolah / Lembaga..."
                  className="w-full bg-slate-50/70 border border-slate-200 rounded-[12px] px-3 py-2.5 text-xs font-medium text-slate-800 focus:border-blue-500 focus:bg-white focus:ring-4 focus:ring-blue-500/10 outline-none transition-all"
                />
              </div>
            </div>

            {/* Logo Upload */}
            <div className="mt-5 pt-5 border-t border-slate-100 flex items-center gap-4">
              <label
                className="w-16 h-16 shrink-0 bg-slate-50 rounded-[14px] flex items-center justify-center border border-dashed border-slate-300 font-bold text-slate-400 text-[10px] overflow-hidden cursor-pointer hover:border-blue-400 hover:bg-blue-50/40 transition-all relative group"
                title="Klik untuk mengganti logo"
              >
                {logoDataUrl ? (
                  <img src={logoDataUrl} className="w-full h-full object-contain p-1.5" alt="Logo" />
                ) : (
                  <ImagePlus className="w-5 h-5 text-slate-300 group-hover:text-blue-400 transition-colors" />
                )}
                <input type="file" accept="image/*" onChange={onLogoUpload} className="hidden" />
              </label>
              <div>
                <label className="block text-[11px] font-bold text-slate-500 uppercase tracking-wide mb-1">Logo Lembaga</label>
                <p className="text-[11px] text-slate-500 mb-1.5">Klik kotak logo untuk mengunggah. Gambar otomatis disesuaikan ke ukuran tetap 64×64px.</p>
                <div className="flex items-center gap-2">
                  <label className="px-3 py-1.5 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-[10px] text-[11px] font-semibold transition-all cursor-pointer">
                    Ganti Logo
                    <input type="file" accept="image/*" onChange={onLogoUpload} className="hidden" />
                  </label>
                  {logoDataUrl && (
                    <button
                      type="button"
                      onClick={onRemoveLogo}
                      className="px-3 py-1.5 text-rose-600 hover:bg-rose-50 rounded-[10px] text-[11px] font-semibold transition-all"
                    >
                      Hapus Logo
                    </button>
                  )}
                </div>
              </div>
            </div>
          </PremiumCard>

          {/* Pengaturan Periode & Tutup Buku */}
          <div>
            <div className="flex items-center gap-2 mb-3 px-1">
              <CalendarRange className="w-4 h-4 text-emerald-600" />
              <h3 className="text-sm font-bold text-slate-900 tracking-tight">Pengaturan Periode &amp; Tutup Buku</h3>
            </div>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {/* Pengaturan Periode Aktif */}
              <PremiumCard className="p-5 bg-gradient-to-b from-emerald-50/60 to-white border-emerald-200/60">
                <div className="flex items-center gap-2.5 mb-1">
                  <div className="w-8 h-8 rounded-[10px] bg-emerald-100 text-emerald-600 flex items-center justify-center ring-1 ring-emerald-200/70">
                    <Wallet className="w-4 h-4" />
                  </div>
                  <h4 className="text-xs font-bold text-emerald-900">Pengaturan Periode Aktif</h4>
                </div>
                <p className="text-[11px] text-emerald-700/80 mt-1 mb-4 leading-relaxed">
                  Atur Tahun Ajaran, tanggal mulai periode, dan saldo awal saat mulai menggunakan RajaKas.
                </p>
                <div className="space-y-3">
                  <div>
                    <label className="block text-[11px] font-bold text-slate-500 uppercase tracking-wide mb-1">Tahun Ajaran Aktif</label>
                    <input
                      type="text"
                      value={inputTahunAjaran}
                      onChange={(e) => setInputTahunAjaran(e.target.value)}
                      placeholder="2026/2027"
                      className="w-full bg-white border border-slate-200 rounded-[12px] px-3 py-2.5 text-xs font-medium text-slate-800 outline-none focus:border-emerald-500 focus:ring-4 focus:ring-emerald-500/10 transition-all"
                    />
                  </div>
                  <div>
                    <label className="block text-[11px] font-bold text-slate-500 uppercase tracking-wide mb-1">Tanggal Mulai Periode</label>
                    <input
                      type="date"
                      value={inputTanggalMulai}
                      onChange={(e) => setInputTanggalMulai(e.target.value)}
                      className="w-full bg-white border border-slate-200 rounded-[12px] px-3 py-2.5 text-xs font-medium text-slate-800 outline-none focus:border-emerald-500 focus:ring-4 focus:ring-emerald-500/10 transition-all"
                    />
                  </div>
                  <div>
                    <label className="block text-[11px] font-bold text-slate-500 uppercase tracking-wide mb-1">Saldo Awal</label>
                    <div className="relative">
                      <span className="absolute left-3 top-1/2 -translate-y-1/2 text-xs font-bold text-emerald-600">Rp</span>
                      <input
                        type="number"
                        value={inputKasAwal}
                        onChange={(e) => setInputKasAwal(e.target.value)}
                        placeholder="0"
                        className="w-full pl-9 pr-3 py-2.5 bg-white border border-emerald-300 rounded-[12px] text-xs font-bold text-slate-900 outline-none focus:border-emerald-600 focus:ring-4 focus:ring-emerald-500/10 transition-all"
                      />
                    </div>
                  </div>
                  <button
                    onClick={handleSavePeriode}
                    className="w-full py-2.5 px-4 bg-emerald-600 hover:bg-emerald-700 text-white rounded-[12px] text-xs font-semibold transition-all flex items-center justify-center gap-1.5 shadow-sm shadow-emerald-600/20 active:scale-[0.99]"
                  >
                    <Save className="w-3.5 h-3.5" />
                    <span>Simpan</span>
                  </button>
                </div>
              </PremiumCard>

              {/* Box Tutup Buku (Cut-Off) */}
              <PremiumCard className="p-5 bg-gradient-to-b from-rose-50/60 to-white border-rose-200/60 flex flex-col justify-between">
                <div>
                  <div className="flex items-center gap-2.5 mb-1">
                    <div className="w-8 h-8 rounded-[10px] bg-rose-100 text-rose-600 flex items-center justify-center ring-1 ring-rose-200/70">
                      <RotateCcw className="w-4 h-4" />
                    </div>
                    <h4 className="text-xs font-bold text-rose-900">{adaPeriodeUntukDibukaKembali ? 'Buka Buku Kembali' : 'Tutup Buku (Cut-Off)'}</h4>
                  </div>
                  <p className="text-[11px] text-rose-700/80 mt-1 leading-relaxed">
                    {adaPeriodeUntukDibukaKembali
                      ? 'Membuka kembali periode terakhir yang ditutup agar dapat digunakan dan diperbaiki kembali.'
                      : 'Mengunci transaksi periode lama tanpa menghapus data. Saldo akhir dihitung otomatis dari database dan menjadi saldo awal periode berikutnya.'}
                  </p>
                  <div className="mt-3 p-3 bg-white/70 border border-rose-100 rounded-[12px] flex items-center justify-between gap-2">
                    <div className="min-w-0">
                      <p className="text-[10px] font-bold text-slate-400 uppercase tracking-wide">Periode Aktif</p>
                      <p className="text-xs font-bold text-slate-800 truncate">{periodeAktifNama || tahunAjaran}</p>
                      {periodeAktifTanggalMulai && (
                        <p className="text-[10px] text-slate-500 mt-0.5">mulai {periodeAktifTanggalMulai}</p>
                      )}
                    </div>
                    <span className={`shrink-0 px-2 py-1 rounded-full text-[10px] font-extrabold ${
                      periodeAktifStatus === 'AKTIF'
                        ? 'bg-emerald-100 text-emerald-700'
                        : 'bg-slate-200 text-slate-600'
                    }`}>
                      {periodeAktifStatus || '—'}
                    </span>
                  </div>
                </div>
                {adaPeriodeUntukDibukaKembali ? (
                  <button
                    type="button"
                    onClick={onBukaBukuKembali}
                    className="w-full mt-4 py-2.5 px-4 bg-emerald-600 hover:bg-emerald-700 text-white rounded-[12px] text-xs font-semibold transition-all flex items-center justify-center gap-1.5 shadow-sm shadow-emerald-600/20 active:scale-[0.99]"
                  >
                    <RotateCcw className="w-3.5 h-3.5" />
                    <span>Buka Buku Kembali</span>
                  </button>
                ) : (
                  <button
                    type="button"
                    onClick={onTutupBuku}
                    disabled={periodeAktifStatus !== 'AKTIF'}
                    className="w-full mt-4 py-2.5 px-4 bg-rose-600 hover:bg-rose-700 disabled:opacity-50 disabled:cursor-not-allowed text-white rounded-[12px] text-xs font-semibold transition-all flex items-center justify-center gap-1.5 shadow-sm shadow-rose-600/20 active:scale-[0.99]"
                  >
                    <RotateCcw className="w-3.5 h-3.5" />
                    <span>Tutup Buku</span>
                  </button>
                )}
              </PremiumCard>
            </div>
          </div>

          {/* Master Kelas */}
          <PremiumCard className="p-6">
            <SectionEyebrow
              icon={<Users className="w-4 h-4" />}
              tone="blue"
              title="Master Kelas & Rombel"
              action={
                <button
                  onClick={onAddMasterKelas}
                  className="text-xs font-semibold text-blue-600 hover:text-white hover:bg-blue-600 border border-blue-200 hover:border-blue-600 px-3 py-1.5 rounded-[10px] transition-all flex items-center gap-1"
                >
                  <Plus className="w-3.5 h-3.5" /> Tambah Kelas
                </button>
              }
            />
            {masterKelas.length === 0 ? (
              <p className="text-xs text-slate-400 italic">Belum ada kelas terdaftar.</p>
            ) : (
              <div className="flex flex-wrap gap-2">
                {masterKelas.map(k => (
                  <span key={k} className="group inline-flex items-center gap-1.5 px-3 py-1.5 bg-slate-50 border border-slate-200 text-slate-800 text-xs font-semibold rounded-[12px] hover:border-slate-300 transition-colors">
                    {k}
                    <button onClick={() => onRemoveMasterKelas(k)} className="text-slate-400 hover:text-rose-600 transition-colors">
                      <X className="w-3 h-3" />
                    </button>
                  </span>
                ))}
              </div>
            )}
          </PremiumCard>

          {/* Master Sumber Dana */}
          <PremiumCard className="p-6">
            <SectionEyebrow
              icon={<Vault className="w-4 h-4" />}
              tone="blue"
              title="Master Sumber Dana (Pemasukan)"
              action={
                <button
                  onClick={onAddMasterSumber}
                  className="text-xs font-semibold text-blue-600 hover:text-white hover:bg-blue-600 border border-blue-200 hover:border-blue-600 px-3 py-1.5 rounded-[10px] transition-all flex items-center gap-1"
                >
                  <Plus className="w-3.5 h-3.5" /> Tambah Sumber Dana
                </button>
              }
            />
            {masterSumberDana.length === 0 ? (
              <p className="text-xs text-slate-400 italic">Belum ada sumber dana terdaftar.</p>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
                {masterSumberDana.map(s => (
                  <div key={s.id} className="p-3.5 bg-slate-50/70 border border-slate-200 rounded-[14px] text-xs hover:border-slate-300 hover:bg-slate-50 transition-colors">
                    <div className="flex items-center justify-between mb-2">
                      <span className="font-bold text-slate-900">{s.name}</span>
                      <button onClick={() => onRemoveMasterSumber(s.id)} className="text-slate-400 hover:text-rose-600 transition-colors">
                        <Trash2 className="w-3.5 h-3.5" />
                      </button>
                    </div>
                    <div className="flex flex-wrap gap-1">
                      {s.subs.map(sub => (
                        <span key={sub} className="px-2 py-0.5 bg-white border border-slate-200 text-slate-600 text-[10px] rounded-full">
                          {sub}
                        </span>
                      ))}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </PremiumCard>

          {/* Master Kategori Pengeluaran */}
          <PremiumCard className="p-6">
            <SectionEyebrow
              icon={<Tags className="w-4 h-4" />}
              tone="rose"
              title="Master Kategori Pengeluaran"
              action={
                <button
                  onClick={onAddMasterKategori}
                  className="text-xs font-semibold text-blue-600 hover:text-white hover:bg-blue-600 border border-blue-200 hover:border-blue-600 px-3 py-1.5 rounded-[10px] transition-all flex items-center gap-1"
                >
                  <Plus className="w-3.5 h-3.5" /> Tambah Kategori
                </button>
              }
            />
            {masterKategoriPengeluaran.length === 0 ? (
              <p className="text-xs text-slate-400 italic">Belum ada kategori terdaftar.</p>
            ) : (
              <div className="flex flex-wrap gap-2">
                {masterKategoriPengeluaran.map(k => (
                  <span key={k} className="inline-flex items-center gap-1.5 px-3 py-1.5 bg-rose-50 text-rose-700 border border-rose-100 text-xs font-semibold rounded-[12px] hover:border-rose-200 transition-colors">
                    {k}
                    <button onClick={() => onRemoveMasterKategori(k)} className="text-rose-400 hover:text-rose-800 transition-colors">
                      <X className="w-3 h-3" />
                    </button>
                  </span>
                ))}
              </div>
            )}
          </PremiumCard>
        </div>
      )}

      {/* TAB 2: AUDIT LOG */}
      {activeSubTab === 'audit' && (
        <div className="space-y-4">
          <div className="relative overflow-hidden bg-gradient-to-r from-amber-50 to-amber-50/40 border border-amber-200/70 p-4 rounded-[16px] flex items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-[12px] bg-amber-100 text-amber-600 flex items-center justify-center ring-1 ring-amber-200 shrink-0">
                <ScrollText className="w-4 h-4" />
              </div>
              <p className="text-xs text-amber-900 leading-relaxed">
                <strong>Postgres Trigger Audit Log:</strong> Setiap aksi <code className="bg-amber-100/70 px-1 py-0.5 rounded text-[10px]">INSERT</code>, <code className="bg-amber-100/70 px-1 py-0.5 rounded text-[10px]">UPDATE</code>, atau <code className="bg-amber-100/70 px-1 py-0.5 rounded text-[10px]">DELETE</code> pada tabel <code className="bg-amber-100/70 px-1 py-0.5 rounded text-[10px]">pemasukan</code> &amp; <code className="bg-amber-100/70 px-1 py-0.5 rounded text-[10px]">pengeluaran</code> dicatat secara otomatis oleh trigger database tanpa perantara kode frontend.
              </p>
            </div>
            <button
              onClick={onRefreshAuditLogs}
              className="px-3 py-2 bg-white border border-amber-300 rounded-[12px] text-xs font-semibold text-amber-800 hover:bg-amber-100 flex items-center gap-1.5 shrink-0 transition-all active:scale-95"
            >
              <RefreshCw className="w-3.5 h-3.5" />
              <span>Refresh Log</span>
            </button>
          </div>

          <PremiumCard className="overflow-hidden">
            <div className="overflow-x-auto">
              <table className="w-full text-left text-xs text-slate-600">
                <thead className="bg-slate-50/80 text-slate-500 font-bold border-b border-slate-200 text-[10px] uppercase tracking-wide">
                  <tr>
                    <th className="p-3.5">Waktu</th>
                    <th className="p-3.5">Aksi</th>
                    <th className="p-3.5">Tabel Terkait</th>
                    <th className="p-3.5">Record ID</th>
                    <th className="p-3.5">User</th>
                    <th className="p-3.5 text-center">Detail JSON</th>
                  </tr>
                </thead>
                <tbody className="divide-y divide-slate-100 font-mono text-[11px]">
                  {auditLogs.length === 0 ? (
                    <tr>
                      <td colSpan={6} className="p-10 text-center text-slate-400 font-sans">
                        <ShieldAlert className="w-6 h-6 mx-auto mb-2 text-slate-300" />
                        Belum ada riwayat audit log tercatat.
                      </td>
                    </tr>
                  ) : (
                    auditLogs.map(log => (
                      <tr key={log.id} className="hover:bg-slate-50/80 transition-colors">
                        <td className="p-3.5 text-slate-500">
                          {new Date(log.waktu).toLocaleString('id-ID')}
                        </td>
                        <td className="p-3.5">
                          <span className={`px-2 py-0.5 rounded-full font-bold text-[10px] ${
                            log.aksi === 'INSERT' ? 'bg-emerald-100 text-emerald-800' :
                            log.aksi === 'UPDATE' ? 'bg-amber-100 text-amber-800' :
                            'bg-rose-100 text-rose-800'
                          }`}>
                            {log.aksi}
                          </span>
                        </td>
                        <td className="p-3.5 font-bold text-slate-800">{log.tabel_terkait}</td>
                        <td className="p-3.5 text-slate-600">{log.record_id}</td>
                        <td className="p-3.5 text-slate-500">{log.user_id}</td>
                        <td className="p-3.5 text-center font-sans">
                          <button
                            onClick={() => setSelectedAuditLog(log)}
                            className="px-2.5 py-1.5 bg-slate-100 hover:bg-slate-800 hover:text-white text-slate-700 rounded-[8px] text-[10px] font-semibold flex items-center gap-1 mx-auto transition-all"
                          >
                            <Eye className="w-3 h-3" /> Inspect
                          </button>
                        </td>
                      </tr>
                    ))
                  )}
                </tbody>
              </table>
            </div>
          </PremiumCard>
        </div>
      )}

      {/* AUDIT LOG JSON INSPECTOR MODAL */}
      {selectedAuditLog && (
        <div className="fixed inset-0 bg-slate-900/60 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-[20px] max-w-lg w-full shadow-2xl border border-slate-200/70 p-6 space-y-4">
            <div className="flex items-center justify-between border-b border-slate-100 pb-3">
              <h3 className="font-bold text-slate-900 text-sm flex items-center gap-2">
                <Eye className="w-4 h-4 text-slate-400" /> Detail Audit Log Inspector
              </h3>
              <button onClick={() => setSelectedAuditLog(null)} className="w-7 h-7 rounded-full flex items-center justify-center text-slate-400 hover:bg-slate-100 hover:text-slate-700 transition-colors">
                <X className="w-4 h-4" />
              </button>
            </div>

            <div className="space-y-3 text-xs">
              <div>
                <span className="font-bold text-slate-500">Aksi &amp; Tabel:</span>
                <span className="ml-2 font-mono font-bold text-blue-600">{selectedAuditLog.aksi} on {selectedAuditLog.tabel_terkait}</span>
              </div>
              <div>
                <span className="font-bold text-slate-500">Record ID:</span>
                <span className="ml-2 font-mono text-slate-800">{selectedAuditLog.record_id}</span>
              </div>
              <div>
                <span className="font-bold text-slate-500">Data Sebelum (OLD):</span>
                <pre className="bg-slate-50 border border-slate-100 p-2.5 rounded-[10px] font-mono text-[10px] mt-1 max-h-28 overflow-y-auto">
                  {JSON.stringify(selectedAuditLog.data_sebelum, null, 2)}
                </pre>
              </div>
              <div>
                <span className="font-bold text-slate-500">Data Sesudah (NEW):</span>
                <pre className="bg-slate-50 border border-slate-100 p-2.5 rounded-[10px] font-mono text-[10px] mt-1 max-h-28 overflow-y-auto">
                  {JSON.stringify(selectedAuditLog.data_sesudah, null, 2)}
                </pre>
              </div>
            </div>

            <div className="pt-3 border-t border-slate-100 text-right">
              <button onClick={() => setSelectedAuditLog(null)} className="px-4 py-2 bg-slate-900 hover:bg-slate-800 text-white rounded-[12px] text-xs font-semibold transition-colors">Tutup</button>
            </div>
          </div>
        </div>
      )}

      {/* SETUP WIZARD MODAL */}
      {isWizardModalOpen && (
        <div className="fixed inset-0 bg-slate-900/70 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-[22px] max-w-lg w-full shadow-2xl border border-slate-200/70 overflow-hidden flex flex-col animate-in fade-in zoom-in duration-150">
            <div className="p-5 bg-gradient-to-br from-slate-900 to-indigo-950 text-white relative overflow-hidden">
              <div className="absolute -top-10 -right-10 w-40 h-40 bg-blue-500/20 rounded-full blur-3xl pointer-events-none" />
              <div className="relative flex items-center justify-between">
                <div className="flex items-center gap-2.5">
                  <div className="w-9 h-9 rounded-[12px] bg-white/10 ring-1 ring-white/15 flex items-center justify-center">
                    <Wand2 className="w-4 h-4 text-amber-300" />
                  </div>
                  <div>
                    <h3 className="font-bold text-sm">Setup Wizard Panduan Lembaga</h3>
                    <p className="text-[11px] text-slate-300">Langkah {wizardStep} dari 3 &middot; Konfigurasi Instan</p>
                  </div>
                </div>
                <button
                  onClick={() => setIsWizardModalOpen(false)}
                  className="w-7 h-7 rounded-full flex items-center justify-center text-slate-300 hover:bg-white/10 hover:text-white transition-colors"
                >
                  <X className="w-4 h-4" />
                </button>
              </div>
              {/* Progress dots */}
              <div className="relative flex items-center gap-1.5 mt-4">
                {[1, 2, 3].map(step => (
                  <div
                    key={step}
                    className={`h-1.5 rounded-full transition-all ${
                      step === wizardStep ? 'w-8 bg-amber-300' : step < wizardStep ? 'w-4 bg-white/60' : 'w-4 bg-white/20'
                    }`}
                  />
                ))}
              </div>
            </div>

            <div className="p-6 space-y-4 text-xs">
              {wizardStep === 1 && (
                <div className="space-y-3">
                  <h4 className="font-bold text-slate-900 text-sm">Langkah 1: Profil &amp; Nama Lembaga</h4>
                  <p className="text-slate-500 text-[11px]">Tentukan nama unit/sekolah dan jenis tingkatannya:</p>
                  <div>
                    <label className="block font-bold text-slate-500 uppercase tracking-wide text-[10px] mb-1.5">Jenis Lembaga</label>
                    <select
                      value={jenisLembagaInput}
                      onChange={(e) => setJenisLembagaInput(e.target.value)}
                      className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-[12px] font-medium outline-none focus:border-blue-500 focus:ring-4 focus:ring-blue-500/10 transition-all"
                    >
                      <option value="SD">Sekolah Dasar (SD)</option>
                      <option value="SMP">Sekolah Menengah Pertama (SMP)</option>
                      <option value="SMA">Sekolah Menengah Atas (SMA)</option>
                      <option value="SMK">Sekolah Menengah Kejuruan (SMK)</option>
                      <option value="Pesantren">Pondok Pesantren</option>
                      <option value="Yayasan">Yayasan</option>
                    </select>
                  </div>
                  <div>
                    <label className="block font-bold text-slate-500 uppercase tracking-wide text-[10px] mb-1.5">Nama Lembaga</label>
                    <input
                      type="text"
                      value={namaLembagaInput}
                      onChange={(e) => setNamaLembagaInput(e.target.value)}
                      className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-[12px] font-semibold text-slate-800 outline-none focus:border-blue-500 focus:ring-4 focus:ring-blue-500/10 transition-all"
                    />
                  </div>
                </div>
              )}

              {wizardStep === 2 && (
                <div className="space-y-3">
                  <h4 className="font-bold text-slate-900 text-sm">Langkah 2: Saldo Kas Awal Periode</h4>
                  <p className="text-slate-500 text-[11px]">Masukkan posisi kas fisik awal lembaga Anda saat ini:</p>
                  <div>
                    <label className="block font-bold text-slate-500 uppercase tracking-wide text-[10px] mb-1.5">Saldo Kas Awal (Rp)</label>
                    <input
                      type="number"
                      value={inputKasAwal}
                      onChange={(e) => setInputKasAwal(e.target.value)}
                      className="w-full p-2.5 bg-slate-50 border border-slate-200 rounded-[12px] font-bold text-sm text-slate-900 outline-none focus:border-blue-500 focus:ring-4 focus:ring-blue-500/10 transition-all"
                    />
                  </div>
                </div>
              )}

              {wizardStep === 3 && (
                <div className="space-y-3 text-center py-2">
                  <div className="w-14 h-14 rounded-full bg-gradient-to-br from-emerald-400 to-emerald-600 text-white mx-auto flex items-center justify-center shadow-lg shadow-emerald-500/30">
                    <Check className="w-6 h-6" />
                  </div>
                  <h4 className="font-bold text-slate-900 text-sm">Setup Selesai!</h4>
                  <p className="text-slate-600 text-xs">
                    Pengaturan untuk <strong className="text-slate-900">{namaLembagaInput} ({jenisLembagaInput})</strong> dengan Kas Awal <strong>Rp {Number(inputKasAwal).toLocaleString('id-ID')}</strong> siap disimpan.
                  </p>
                </div>
              )}
            </div>

            <div className="p-4 bg-slate-50 border-t border-slate-100 flex items-center justify-between">
              {wizardStep > 1 ? (
                <button
                  onClick={() => setWizardStep(prev => prev - 1)}
                  className="px-4 py-2 text-slate-600 hover:bg-slate-200 rounded-[12px] font-semibold text-xs flex items-center gap-1 transition-colors"
                >
                  <ChevronLeft className="w-3.5 h-3.5" /> Kembali
                </button>
              ) : <div />}

              {wizardStep < 3 ? (
                <button
                  onClick={() => setWizardStep(prev => prev + 1)}
                  className="px-5 py-2 bg-blue-600 hover:bg-blue-700 text-white rounded-[12px] font-semibold text-xs flex items-center gap-1 shadow-sm shadow-blue-600/20 transition-all active:scale-95"
                >
                  Lanjut <ChevronRight className="w-3.5 h-3.5" />
                </button>
              ) : (
                <button
                  onClick={() => {
                    handleSaveProfil();
                    handleSaveKasAwal();
                    setIsWizardModalOpen(false);
                    setWizardStep(1);
                    showToast('Setup Wizard berhasil diselesaikan!');
                  }}
                  className="px-5 py-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded-[12px] font-semibold text-xs shadow-sm shadow-emerald-600/20 flex items-center gap-1.5 transition-all active:scale-95"
                >
                  <Check className="w-3.5 h-3.5" /> Simpan &amp; Terapkan
                </button>
              )}
            </div>
          </div>
        </div>
      )}
    </div>
  );
};
