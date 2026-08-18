import React, { useState, useEffect } from 'react';
import {
  Pemasukan, Pengeluaran, SiswaTagihan, MasterSumberDana,
  AuditLog, UserSession, KonfigurasiLembaga, PeriodePembukuan
} from './types';

import {
  INITIAL_MASTER_KELAS, INITIAL_MASTER_SUMBER, INITIAL_MASTER_KATEGORI,
  INITIAL_PEMASUKAN, INITIAL_PENGELUARAN, INITIAL_SISWA_TAGIHAN, INITIAL_AUDIT_LOGS
} from './data/initialData';

import {
  testSupabaseConnection, getCurrentSession, onAuthStateChange, signOutSupabase
} from './lib/supabase';

import {
  fetchKonfigurasiLembaga, getDefaultConfiguration, saveKonfigurasiLembaga,
  saveSaldoAwal, uploadLogoToStorage
} from './lib/configuration';

import {
  fetchMasterKelas, insertMasterKelas, deleteMasterKelas,
  fetchMasterSumberDana, insertMasterSumberDana, deleteMasterSumberDana,
  fetchMasterKategori, insertMasterKategori, deleteMasterKategori
} from './lib/masterData';

import {
  fetchPemasukanFromSupabase, insertPemasukanSupabase, deletePemasukanSupabase
} from './lib/pemasukan';

import {
  fetchPengeluaranFromSupabase, rpcCatatPengeluaran, deletePengeluaranSupabase,
  uploadBuktiPengeluaranToStorage
} from './lib/pengeluaran';

import {
  fetchSiswaTagihan, insertSiswaTagihan, deleteSiswaTagihan, rpcCatatPembayaranSiswa
} from './lib/siswa';

import { fetchAuditLogsFromSupabase } from './lib/audit';
import {
  fetchPeriodePembukuan, getActivePeriode, closePeriodePembukuan,
  updateSaldoAwalPeriode, updateTahunAjaranAktif, updatePeriodeAktifSettings, defaultTanggalMulaiTahunAjaran, defaultTanggalAkhirTahunAjaran
} from './lib/periodePembukuan';

import { Navbar } from './components/Navbar';
import { Sidebar } from './components/Sidebar';
import { DashboardView } from './components/DashboardView';
import { PemasukanView } from './components/PemasukanView';
import { PengeluaranView } from './components/PengeluaranView';
import { SiswaView } from './components/SiswaView';
import { LaporanView } from './components/LaporanView';
import { PengaturanView } from './components/PengaturanView';
import { AuthModal } from './components/AuthModal';
import { SupabaseConfigModal } from './components/SupabaseConfigModal';
import {
  ModalPemasukan, ModalPengeluaran,
  ModalSiswaTagihanPropsModal, ModalSiswaBayarPropsModal,
  ModalBlueprint
} from './components/Modals';

export default function App() {
  // Navigation & UI State
  const [activeTab, setActiveTab] = useState('dashboard');
  const [isOpenMobileSidebar, setIsOpenMobileSidebar] = useState(false);
  const [toastMessage, setToastMessage] = useState<string | null>(null);

  // Institution Context -- sekarang sumber kebenarannya adalah Supabase
  // (tabel konfigurasi_lembaga), bukan lagi murni React State (poin 2 & 9
  // panduan). Nilai default kosong dipakai sebelum data selesai dimuat.
  const [konfigurasi, setKonfigurasi] = useState<KonfigurasiLembaga>(getDefaultConfiguration());

  // App Master Data & Local Store
  const [masterKelas, setMasterKelas] = useState<string[]>([]);
  const [masterSumberDana, setMasterSumberDana] = useState<MasterSumberDana[]>([]);
  const [masterKategoriPengeluaran, setMasterKategoriPengeluaran] = useState<string[]>([]);

  const [pemasukanList, setPemasukanList] = useState<Pemasukan[]>([]);
  const [pengeluaranList, setPengeluaranList] = useState<Pengeluaran[]>([]);
  const [siswaTagihanList, setSiswaTagihanList] = useState<SiswaTagihan[]>([]);
  const [auditLogs, setAuditLogs] = useState<AuditLog[]>([]);
  const [periodePembukuanList, setPeriodePembukuanList] = useState<PeriodePembukuan[]>([]);

  // Auth & Supabase Status
  const [userSession, setUserSession] = useState<UserSession | null>(null);
  const [isConnectedToSupabase, setIsConnectedToSupabase] = useState<boolean>(false);
  const [authChecked, setAuthChecked] = useState<boolean>(false);

  // Modals visibility
  const [isAuthModalOpen, setIsAuthModalOpen] = useState(false);
  const [isSupabaseModalOpen, setIsSupabaseModalOpen] = useState(false);
  const [isPemasukanModalOpen, setIsPemasukanModalOpen] = useState(false);
  const [isPengeluaranModalOpen, setIsPengeluaranModalOpen] = useState(false);
  const [isSiswaTagihanModalOpen, setIsSiswaTagihanModalOpen] = useState(false);
  const [isSiswaBayarModalOpen, setIsSiswaBayarModalOpen] = useState(false);
  const [selectedSiswaForBayar, setSelectedSiswaForBayar] = useState<SiswaTagihan | null>(null);
  const [isBlueprintModalOpen, setIsBlueprintModalOpen] = useState(false);

  // Toast Helper
  const showToast = (msg: string) => {
    setToastMessage(msg);
    setTimeout(() => {
      setToastMessage(null);
    }, 3500);
  };

  const handleUpdateSaldoAwal = async (nominal: number) => {
    const active = getActivePeriode(periodePembukuanList);
    if (active) {
      const res = await updateSaldoAwalPeriode(active.id, nominal);
      if (!res.success) {
        showToast(`Gagal menyimpan Kas Awal: ${res.message}`);
        return;
      }
      setPeriodePembukuanList(prev => prev.map(x => x.id === active.id ? { ...x, saldoAwal: nominal } : x));
    }

    if (isConnectedToSupabase) {
      const res = await saveSaldoAwal(nominal);
      if (!res.success) {
        showToast(`Gagal menyimpan Kas Awal: ${res.message}`);
        return;
      }
      setKonfigurasi(prev => ({ ...prev, saldoAwal: nominal }));
      showToast(`Kas Awal berhasil disimpan ke database: ${formatRupiah(nominal)}`);
    } else {
      setKonfigurasi(prev => ({ ...prev, saldoAwal: nominal }));
      showToast(`[Demo Lokal] Kas Awal diisi: ${formatRupiah(nominal)} (tidak permanen)`);
    }
  };

  const handleSavePeriodeSettings = async (tahun: string, tanggalMulai: string, nominal: number) => {
    const normalized = tahun.trim();
    if (!/^\d{4}\/\d{4}$/.test(normalized)) {
      showToast('Format Tahun Ajaran harus YYYY/YYYY, contoh 2025/2026');
      return;
    }
    if (!/^\d{4}-\d{2}-\d{2}$/.test(tanggalMulai)) {
      showToast('Tanggal Mulai Periode tidak valid.');
      return;
    }
    if (Number.isNaN(nominal) || nominal < 0) {
      showToast('Nominal Saldo Awal tidak valid');
      return;
    }

    // Jangan bergantung pada ID periode yang tersimpan di React state.
    // Fungsi penyimpanan akan mencari periode AKTIF langsung di database bila
    // state belum memuat ID yang benar.
    const active = getActivePeriode(periodePembukuanList);
    const res = await updatePeriodeAktifSettings(
      active?.id ?? null,
      normalized,
      tanggalMulai,
      nominal
    );
    if (!res.success) {
      showToast(`Gagal menyimpan pengaturan periode: ${res.message}`);
      return;
    }

    if (isConnectedToSupabase) {
      // Tahun Ajaran sekarang bersumber dari periode_pembukuan.
      // Jangan menulis tahun_ajaran ke konfigurasi_lembaga karena kolom tersebut
      // memang tidak ada pada schema database RajaKas saat ini.
      const saldoRes = await saveSaldoAwal(nominal);
      if (!saldoRes.success) {
        showToast(`Periode tersimpan, tetapi Saldo Awal gagal disimpan: ${saldoRes.message}`);
        return;
      }
    }

    // Muat ulang dari database agar UI menggunakan nilai yang benar-benar tersimpan.
    const refreshedPeriods = await fetchPeriodePembukuan();
    setPeriodePembukuanList(refreshedPeriods);

    const refreshedActive = getActivePeriode(refreshedPeriods);
    setKonfigurasi(prev => ({
      ...prev,
      tahunAjaran: normalized,
      saldoAwal: nominal
    }));

    if (!refreshedActive) {
      showToast('Periode tersimpan, tetapi periode aktif belum dapat dimuat ulang.');
      return;
    }

    showToast(`Pengaturan periode berhasil disimpan: ${normalized} • mulai ${tanggalMulai}`);
  };

  const handleUpdateTahunAjaran = async (tahun: string) => {
    const normalized = tahun.trim();
    if (!/^\d{4}\/\d{4}$/.test(normalized)) {
      showToast('Format Tahun Ajaran harus YYYY/YYYY, contoh 2025/2026');
      return;
    }

    if (isConnectedToSupabase) {
      const res = await saveKonfigurasiLembaga({ tahunAjaran: normalized });
      if (!res.success) {
        showToast(`Gagal menyimpan Tahun Ajaran: ${res.message}`);
        return;
      }
    }

    const periodRes = await updateTahunAjaranAktif(normalized);
    if (!periodRes.success) {
      showToast(`Tahun Ajaran tersimpan di profil, tetapi periode aktif gagal diperbarui: ${periodRes.message}`);
      return;
    }

    setKonfigurasi(prev => ({ ...prev, tahunAjaran: normalized }));
    setPeriodePembukuanList(prev => prev.map(x => x.status === 'AKTIF' ? { ...x, tahunAjaran: normalized, namaPeriode: normalized } : x));
    showToast(`Tahun Ajaran Aktif disimpan: ${normalized}`);
  };

  const handleTutupBuku = async () => {
    const active = getActivePeriode(periodePembukuanList);
    if (!active) {
      showToast('Tidak ada periode aktif untuk ditutup.');
      return;
    }

    const tanggalCutoff = prompt(
      `Masukkan tanggal cut-off untuk periode ${active.namaPeriode}. Format YYYY-MM-DD.`,
      defaultTanggalAkhirTahunAjaran(active.tahunAjaran)
    );
    if (!tanggalCutoff) return;

    if (!/^\d{4}-\d{2}-\d{2}$/.test(tanggalCutoff) || tanggalCutoff < active.tanggalMulai) {
      showToast('Tanggal cut-off tidak valid atau sebelum tanggal mulai periode.');
      return;
    }

    if (!confirm(`Tutup Buku ${active.namaPeriode} sampai ${tanggalCutoff}? Transaksi tidak akan dihapus.`)) return;

    const res = await closePeriodePembukuan(active.id, tanggalCutoff);
    if (!res.success) {
      showToast(`Tutup Buku gagal: ${res.message}`);
      return;
    }

    const periods = await fetchPeriodePembukuan();
    setPeriodePembukuanList(periods);
    const next = getActivePeriode(periods);
    if (next) {
      setKonfigurasi(prev => ({ ...prev, saldoAwal: next.saldoAwal, tahunAjaran: next.tahunAjaran }));
    }
    await refreshPemasukan();
    await refreshPengeluaran();
    await refreshSiswaTagihan();
    await refreshAuditLogs();

    showToast(`Tutup Buku berhasil. Saldo akhir ${formatRupiah(res.data?.saldoAkhir || 0)} menjadi saldo awal ${next?.tahunAjaran || 'periode berikutnya'}.`);
  };

  // Sync / Test Supabase on mount
  useEffect(() => {
    checkAndSyncSupabase();
    const unsubscribe = onAuthStateChange((session) => {
      if (session) {
        setUserSession({
          id: session.user.id,
          email: session.user.email || '',
          role: 'Bendahara Utama'
        });
      } else if (isConnectedToSupabase) {
        setUserSession(null);
      }
    });
    return () => unsubscribe();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  // Poin 3 panduan: urutan load saat startup adalah cek session -> cek
  // Supabase -> konfigurasi lembaga & saldo awal -> master data -> transaksi
  // -> siswa/tagihan -> audit. Dashboard TIDAK dirender sebelum semua ini
  // selesai (lihat gate `!authChecked` di bagian render bawah).
  const checkAndSyncSupabase = async () => {
    const res = await testSupabaseConnection();
    setIsConnectedToSupabase(res.success);

    if (res.success) {
      const session = await getCurrentSession();
      if (session) {
        setUserSession({
          id: session.user.id,
          email: session.user.email || '',
          role: 'Bendahara Utama'
        });
      } else {
        setUserSession(null);
        setIsAuthModalOpen(true);
      }

      const [config, kelas, sumber, kategori, inData, outData, stData, logs, periods] = await Promise.all([
        fetchKonfigurasiLembaga(),
        fetchMasterKelas(),
        fetchMasterSumberDana(),
        fetchMasterKategori(),
        fetchPemasukanFromSupabase(),
        fetchPengeluaranFromSupabase(),
        fetchSiswaTagihan(),
        fetchAuditLogsFromSupabase(),
        fetchPeriodePembukuan()
      ]);

      if (config) setKonfigurasi(config);
      setMasterKelas(kelas ?? []);
      setMasterSumberDana(sumber ?? []);
      setMasterKategoriPengeluaran(kategori ?? []);
      setPemasukanList(inData ?? []);
      setPengeluaranList(outData ?? []);
      setSiswaTagihanList(stData ?? []);
      setAuditLogs(logs ?? []);
      setPeriodePembukuanList(periods ?? []);
    } else {
      // Mode Demo Lokal: tidak ada Supabase terhubung -> data initial hanya
      // dipakai DI SINI, khusus untuk demo (poin 4 panduan), tidak pernah
      // dipakai sebagai fallback diam-diam saat mode produksi gagal konek.
      console.error('[Supabase] Gagal terhubung:', res.message);
      showToast(`Supabase belum terhubung: ${res.message}`);
      setUserSession({
        id: 'demo_local',
        email: 'demo@local (mode tanpa Supabase)',
        role: 'Demo Lokal'
      });
      setKonfigurasi({ ...getDefaultConfiguration(), namaLembaga: 'SD Negeri 1 Merdeka (Contoh Demo)' });
      setMasterKelas(INITIAL_MASTER_KELAS);
      setMasterSumberDana(INITIAL_MASTER_SUMBER);
      setMasterKategoriPengeluaran(INITIAL_MASTER_KATEGORI);
      setPemasukanList(INITIAL_PEMASUKAN);
      setPengeluaranList(INITIAL_PENGELUARAN);
      setSiswaTagihanList(INITIAL_SISWA_TAGIHAN);
      setAuditLogs(INITIAL_AUDIT_LOGS);
      const demoYear = '2025/2026';
      setKonfigurasi(prev => ({ ...prev, tahunAjaran: demoYear }));
      setPeriodePembukuanList([{
        id: 'PER-DEMO',
        namaPeriode: demoYear,
        tahunAjaran: demoYear,
        tanggalMulai: defaultTanggalMulaiTahunAjaran(demoYear),
        tanggalAkhir: null,
        saldoAwal: 0,
        saldoAkhir: null,
        status: 'AKTIF',
        createdAt: new Date().toISOString()
      }]);
    }
    setAuthChecked(true);
  };

  const refreshAuditLogs = async () => {
    if (isConnectedToSupabase) {
      const logs = await fetchAuditLogsFromSupabase();
      if (logs) setAuditLogs(logs);
    }
  };

  const refreshPemasukan = async () => {
    const data = await fetchPemasukanFromSupabase();
    if (data) setPemasukanList(data);
  };

  const refreshPengeluaran = async () => {
    const data = await fetchPengeluaranFromSupabase();
    if (data) setPengeluaranList(data);
  };

  const refreshSiswaTagihan = async () => {
    const data = await fetchSiswaTagihan();
    if (data) setSiswaTagihanList(data);
  };

  // Helper ID generator -- HANYA dipakai di jalur Mode Demo Lokal (tidak ada
  // Supabase sungguhan). Untuk data produksi, ID selalu dibuat oleh database
  // (UUID default), bukan lagi dari fungsi ini (poin 12 panduan).
  const generateDemoId = (list: { id: string }[], prefix: string) => {
    let maxNum = 0;
    list.forEach(item => {
      const parts = String(item.id).split('-');
      const num = parseInt(parts[parts.length - 1], 10);
      if (!isNaN(num) && num > maxNum) maxNum = num;
    });
    return `${prefix}-${String(maxNum + 1).padStart(3, '0')}`;
  };

  const formatRupiah = (num: number) => {
    if (isNaN(num)) return 'Rp 0';
    return 'Rp ' + Math.round(num).toLocaleString('id-ID');
  };

  // Handlers for Save / Delete
  const handleSavePemasukan = async (data: {
    tanggal: string;
    noBukti: string;
    sumber: string;
    sub: string;
    nominal: number;
    keterangan: string;
  }) => {
    if (isConnectedToSupabase) {
      // Poin 5 panduan: jangan anggap transaksi berhasil hanya karena
      // setState -- alur yang benar: validasi -> INSERT Supabase -> fetch
      // ulang -> update state -> baru tampilkan sukses.
      const res = await insertPemasukanSupabase({
        noBukti: data.noBukti,
        tanggal: data.tanggal,
        sumber: data.sumber,
        sub: data.sub,
        nominal: data.nominal,
        keterangan: data.keterangan,
        status: 'Selesai'
      });

      if (!res.success) {
        showToast(`Gagal menyimpan pemasukan: ${res.message}`);
        return;
      }

      await refreshPemasukan();
      refreshAuditLogs();
      showToast('Pemasukan Kas berhasil disimpan ke database!');
      return;
    }

    // Mode Demo Lokal saja
    const id = generateDemoId(pemasukanList, 'IN');
    const newTx: Pemasukan = {
      id,
      noBukti: data.noBukti || id,
      tanggal: data.tanggal,
      sumber: data.sumber,
      sub: data.sub,
      nominal: data.nominal,
      keterangan: data.keterangan,
      status: 'Selesai'
    };
    setPemasukanList(prev => [newTx, ...prev]);
    showToast('[Demo Lokal] Pemasukan Kas dicatat sementara di browser ini!');
  };

  const handleSavePengeluaran = async (data: {
    tanggal: string;
    noBukti: string;
    kategori: string;
    nominal: number;
    keterangan: string;
    buktiFile?: File | null;
  }): Promise<{ success: boolean; message?: string }> => {
    if (isConnectedToSupabase) {
      // Upload nota/kwitansi (jika ada) ke Supabase Storage dulu, baru
      // simpan URL-nya bersamaan dengan transaksi lewat RPC di bawah.
      let buktiUrl: string | undefined;
      if (data.buktiFile) {
        const uploadRes = await uploadBuktiPengeluaranToStorage(data.buktiFile);
        if (!uploadRes.success) {
          return { success: false, message: uploadRes.message };
        }
        buktiUrl = uploadRes.url;
      }

      // Poin 13 panduan: RPC catat_pengeluaran() dipertahankan (validasi
      // saldo server-side), TANPA mengirim ID buatan frontend.
      const res = await rpcCatatPengeluaran({
        noBukti: data.noBukti,
        tanggal: data.tanggal,
        kategori: data.kategori,
        nominal: data.nominal,
        keterangan: data.keterangan,
        buktiUrl
      });

      if (!res.success) {
        return { success: false, message: res.message };
      }

      await refreshPengeluaran();
      refreshAuditLogs();
      showToast('Pengeluaran berhasil dicatat & diverifikasi server Supabase!');
      return { success: true };
    }

    // Mode Demo Lokal saja: validasi saldo dilakukan di sisi klien karena
    // tidak ada server sungguhan untuk memvalidasinya.
    const totalInAll = pemasukanList.reduce((acc, curr) => acc + curr.nominal, 0);
    const totalOutAll = pengeluaranList.reduce((acc, curr) => acc + curr.nominal, 0);
    const currentSaldo = konfigurasi.saldoAwal + totalInAll - totalOutAll;

    if (data.nominal > currentSaldo) {
      return {
        success: false,
        message: `[Demo Lokal] Nominal pengeluaran (${formatRupiah(data.nominal)}) melebihi total saldo kas tersedia (${formatRupiah(currentSaldo)})!`
      };
    }

    const id = generateDemoId(pengeluaranList, 'OUT');
    const newTx: Pengeluaran = {
      id,
      noBukti: data.noBukti || id,
      tanggal: data.tanggal,
      kategori: data.kategori,
      nominal: data.nominal,
      keterangan: data.keterangan,
      status: 'Terbayar',
      // Mode Demo Lokal: tidak ada Supabase Storage, jadi hanya pakai
      // object URL sementara di browser (hilang saat refresh halaman).
      buktiUrl: data.buktiFile ? URL.createObjectURL(data.buktiFile) : undefined
    };
    setPengeluaranList(prev => [newTx, ...prev]);

    const localAudit: AuditLog = {
      id: String(Date.now()),
      tabel_terkait: 'pengeluaran',
      record_id: id,
      aksi: 'INSERT',
      data_sebelum: null,
      data_sesudah: newTx,
      user_id: userSession?.id || 'demo_local',
      waktu: new Date().toISOString()
    };
    setAuditLogs(prev => [localAudit, ...prev]);

    showToast('[Demo Lokal] Pengeluaran Kas dicatat sementara di browser ini!');
    return { success: true };
  };

  const handleDeletePemasukan = async (id: string) => {
    if (!confirm('Hapus transaksi pemasukan ini?')) return;

    if (isConnectedToSupabase) {
      // Poin 14 panduan: konfirmasi -> DELETE Supabase -> kalau berhasil
      // baru fetch ulang & update state. Kalau gagal, data JANGAN hilang
      // dari UI seperti perilaku lama (filter local state duluan).
      const res = await deletePemasukanSupabase(id);
      if (!res.success) {
        showToast(`Gagal menghapus transaksi: ${res.message}`);
        return;
      }
      await refreshPemasukan();
      refreshAuditLogs();
      showToast('Transaksi pemasukan dihapus dari database');
      return;
    }

    setPemasukanList(prev => prev.filter(x => x.id !== id));
    showToast('[Demo Lokal] Transaksi pemasukan dihapus');
  };

  const handleDeletePengeluaran = async (id: string) => {
    if (!confirm('Hapus transaksi pengeluaran ini?')) return;

    if (isConnectedToSupabase) {
      const res = await deletePengeluaranSupabase(id);
      if (!res.success) {
        showToast(`Gagal menghapus transaksi: ${res.message}`);
        return;
      }
      await refreshPengeluaran();
      refreshAuditLogs();
      showToast('Transaksi pengeluaran dihapus dari database');
      return;
    }

    setPengeluaranList(prev => prev.filter(x => x.id !== id));
    showToast('[Demo Lokal] Transaksi pengeluaran dihapus');
  };

  const handleSaveSiswaTagihan = async (data: {
    nama: string;
    kelas: string;
    jenis: string;
    target: number;
    catatan?: string;
  }) => {
    if (isConnectedToSupabase) {
      // Poin 7 panduan: siswa & tagihan server-side, bukan hanya
      // setSiswaTagihanList seperti sebelumnya.
      const res = await insertSiswaTagihan(data);
      if (!res.success) {
        showToast(`Gagal menyimpan tagihan siswa: ${res.message}`);
        return;
      }
      await refreshSiswaTagihan();
      refreshAuditLogs();
      showToast(`Tagihan siswa a.n ${data.nama} berhasil disimpan ke database`);
      return;
    }

    const id = generateDemoId(siswaTagihanList, 'ST');
    const newSiswa: SiswaTagihan = { id, ...data };
    setSiswaTagihanList(prev => [...prev, newSiswa]);
    showToast(`[Demo Lokal] Tagihan siswa a.n ${data.nama} ditambahkan`);
  };

  const handleSaveBayarSiswa = async (data: {
    siswaId: string;
    tanggal: string;
    noBukti: string;
    nominal: number;
  }) => {
    const siswa = siswaTagihanList.find(s => s.id === data.siswaId);
    if (!siswa) return;

    if (isConnectedToSupabase) {
      // Poin 6 panduan: pembayaran siswa WAJIB masuk Supabase lewat RPC
      // catat_pembayaran_siswa(), bukan hanya menambah ke React State
      // seperti handleSaveBayarSiswa sebelumnya. Setelah reload, pembayaran
      // harus tetap ada.
      const res = await rpcCatatPembayaranSiswa({
        siswaId: data.siswaId,
        noBukti: data.noBukti,
        tanggal: data.tanggal,
        nominal: data.nominal
      });

      if (!res.success) {
        showToast(`Gagal mencatat pembayaran: ${res.message}`);
        return;
      }

      await refreshPemasukan();
      refreshAuditLogs();
      showToast(`Pembayaran ${siswa.nama} sebesar ${formatRupiah(data.nominal)} berhasil disimpan ke database!`);
      return;
    }

    const idBaru = generateDemoId(pemasukanList, 'IN');
    const newIn: Pemasukan = {
      id: idBaru,
      noBukti: data.noBukti || idBaru,
      tanggal: data.tanggal,
      sumber: 'Pembayaran',
      sub: siswa.jenis,
      nominal: data.nominal,
      keterangan: `Pembayaran ${siswa.jenis} a.n ${siswa.nama} (${siswa.kelas})`,
      status: 'Selesai',
      siswaId: siswa.id
    };
    setPemasukanList(prev => [newIn, ...prev]);
    showToast(`[Demo Lokal] Pembayaran ${siswa.nama} sebesar ${formatRupiah(data.nominal)} dicatat sementara`);
  };

  const handleDeleteTagihan = async (id: string) => {
    const siswa = siswaTagihanList.find(s => s.id === id);
    if (!siswa) return;
    if (!confirm(`Hapus data tagihan a.n ${siswa.nama}?`)) return;

    if (isConnectedToSupabase) {
      const res = await deleteSiswaTagihan(id);
      if (!res.success) {
        showToast(`Gagal menghapus data tagihan: ${res.message}`);
        return;
      }
      await refreshSiswaTagihan();
      refreshAuditLogs();
      showToast('Data tagihan dihapus dari database');
      return;
    }

    setSiswaTagihanList(prev => prev.filter(s => s.id !== id));
    showToast('[Demo Lokal] Data tagihan dihapus');
  };

  // Logo upload -- poin 10 panduan: produksi memakai Supabase Storage +
  // URL disimpan di konfigurasi_lembaga, bukan Base64 permanen di state.
  const handleLogoUpload = async (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    if (isConnectedToSupabase) {
      const res = await uploadLogoToStorage(file);
      if (!res.success) {
        showToast(`Gagal upload logo: ${res.message}`);
        return;
      }
      setKonfigurasi(prev => ({ ...prev, logoUrl: res.url || null }));
      showToast('Logo lembaga berhasil disimpan ke Supabase Storage!');
      return;
    }

    // Mode Demo Lokal: Base64 sementara di browser (tidak permanen).
    const reader = new FileReader();
    reader.onload = (ev) => {
      setKonfigurasi(prev => ({ ...prev, logoUrl: ev.target?.result as string }));
      showToast('[Demo Lokal] Logo lembaga diperbarui sementara di browser ini!');
    };
    reader.readAsDataURL(file);
  };

  // Profil lembaga -- poin 9 panduan: UPDATE ke Supabase, status "berhasil"
  // hanya ditampilkan SETELAH database mengonfirmasi.
  const handleUpdateLembaga = async (nama: string, jenis: string) => {
    if (isConnectedToSupabase) {
      const res = await saveKonfigurasiLembaga({ namaLembaga: nama, jenisLembaga: jenis });
      if (!res.success) {
        showToast(`Gagal menyimpan profil lembaga: ${res.message}`);
        return;
      }
      setKonfigurasi(prev => ({ ...prev, namaLembaga: nama, jenisLembaga: jenis }));
      refreshAuditLogs();
      showToast('Profil lembaga berhasil disimpan ke database');
      return;
    }

    setKonfigurasi(prev => ({ ...prev, namaLembaga: nama, jenisLembaga: jenis }));
    showToast('[Demo Lokal] Profil lembaga diperbarui sementara');
  };

  // Master data (poin 8 panduan): setiap tambah/hapus memanggil Supabase,
  // lalu refresh data -- tidak lagi murni memodifikasi array React State.
  const handleAddMasterKelas = async () => {
    const name = prompt('Nama Kelas/Rombel baru:');
    if (!name) return;
    const trimmed = name.trim();
    if (!trimmed) return;

    if (isConnectedToSupabase) {
      const res = await insertMasterKelas(trimmed);
      if (!res.success) {
        showToast(`Gagal menambah kelas: ${res.message}`);
        return;
      }
      const data = await fetchMasterKelas();
      setMasterKelas(data ?? []);
      showToast('Kelas/Rombel berhasil disimpan ke database');
      return;
    }

    setMasterKelas(prev => [...prev, trimmed]);
    showToast('[Demo Lokal] Kelas/Rombel ditambahkan sementara');
  };

  const handleRemoveMasterKelas = async (k: string) => {
    if (isConnectedToSupabase) {
      const res = await deleteMasterKelas(k);
      if (!res.success) {
        showToast(`Gagal menghapus kelas: ${res.message}`);
        return;
      }
      const data = await fetchMasterKelas();
      setMasterKelas(data ?? []);
      return;
    }
    setMasterKelas(prev => prev.filter(x => x !== k));
  };

  const handleAddMasterSumber = async () => {
    const name = prompt('Nama Sumber Dana baru:');
    if (!name) return;
    const trimmed = name.trim();
    if (!trimmed) return;
    const id = trimmed.replace(/[^a-zA-Z0-9]/g, '');
    const item: MasterSumberDana = { id, name: trimmed, subs: [] };

    if (isConnectedToSupabase) {
      const res = await insertMasterSumberDana(item);
      if (!res.success) {
        showToast(`Gagal menambah sumber dana: ${res.message}`);
        return;
      }
      const data = await fetchMasterSumberDana();
      setMasterSumberDana(data ?? []);
      showToast('Sumber Dana berhasil disimpan ke database');
      return;
    }

    setMasterSumberDana(prev => [...prev, item]);
    showToast('[Demo Lokal] Sumber Dana ditambahkan sementara');
  };

  const handleRemoveMasterSumber = async (id: string) => {
    if (isConnectedToSupabase) {
      const res = await deleteMasterSumberDana(id);
      if (!res.success) {
        showToast(`Gagal menghapus sumber dana: ${res.message}`);
        return;
      }
      const data = await fetchMasterSumberDana();
      setMasterSumberDana(data ?? []);
      return;
    }
    setMasterSumberDana(prev => prev.filter(x => x.id !== id));
  };

  const handleAddMasterKategori = async () => {
    const name = prompt('Nama Kategori Pengeluaran baru:');
    if (!name) return;
    const trimmed = name.trim();
    if (!trimmed) return;

    if (isConnectedToSupabase) {
      const res = await insertMasterKategori(trimmed);
      if (!res.success) {
        showToast(`Gagal menambah kategori: ${res.message}`);
        return;
      }
      const data = await fetchMasterKategori();
      setMasterKategoriPengeluaran(data ?? []);
      showToast('Kategori Pengeluaran berhasil disimpan ke database');
      return;
    }

    setMasterKategoriPengeluaran(prev => [...prev, trimmed]);
    showToast('[Demo Lokal] Kategori Pengeluaran ditambahkan sementara');
  };

  const handleRemoveMasterKategori = async (k: string) => {
    if (isConnectedToSupabase) {
      const res = await deleteMasterKategori(k);
      if (!res.success) {
        showToast(`Gagal menghapus kategori: ${res.message}`);
        return;
      }
      const data = await fetchMasterKategori();
      setMasterKategoriPengeluaran(data ?? []);
      return;
    }
    setMasterKategoriPengeluaran(prev => prev.filter(x => x !== k));
  };

  const unreadBelumLunasCount = siswaTagihanList.filter(s => {
    const paid = pemasukanList.filter(p => p.siswaId === s.id).reduce((a, b) => a + b.nominal, 0);
    return paid < s.target;
  }).length;

  // Tunggu pengecekan sesi + konfigurasi selesai dulu sebelum render apa pun,
  // supaya data keuangan tidak "berkedip" tampil sebelum status login &
  // konfigurasi lembaga diketahui (poin 3 panduan).
  if (!authChecked) {
    return (
      <div className="flex h-screen w-full items-center justify-center bg-[#FAFAFC] text-slate-500 text-sm font-semibold">
        Memeriksa sesi login &amp; memuat konfigurasi lembaga...
      </div>
    );
  }

  // GERBANG LOGIN: kalau terhubung ke Supabase (mode produksi sungguhan) tapi
  // belum ada sesi yang valid, jangan render app/data sama sekali -- hanya
  // tampilkan layar login.
  if (isConnectedToSupabase && !userSession) {
    return (
      <div className="flex h-screen w-full items-center justify-center bg-[#FAFAFC]">
        <AuthModal
          isOpen={true}
          onClose={() => { /* tidak bisa ditutup tanpa login saat mode Supabase */ }}
          userSession={null}
          onLoginSuccess={(session) => {
            setUserSession(session);
            setIsAuthModalOpen(false);
            checkAndSyncSupabase();
          }}
          showToast={showToast}
        />
      </div>
    );
  }

  const currentLembaga = konfigurasi.namaLembaga || 'Lembaga Belum Diatur';
  const jenisLembaga = konfigurasi.jenisLembaga;
  const logoDataUrl = konfigurasi.logoUrl;
  const activePeriode = getActivePeriode(periodePembukuanList);
  const saldoAwal = activePeriode?.saldoAwal ?? konfigurasi.saldoAwal;
  const tahunAjaran = activePeriode?.tahunAjaran || konfigurasi.tahunAjaran || '2025/2026';
  const activePemasukanList = activePeriode
    ? pemasukanList.filter(x => x.tanggal >= activePeriode.tanggalMulai && (!activePeriode.tanggalAkhir || x.tanggal <= activePeriode.tanggalAkhir))
    : pemasukanList;
  const activePengeluaranList = activePeriode
    ? pengeluaranList.filter(x => x.tanggal >= activePeriode.tanggalMulai && (!activePeriode.tanggalAkhir || x.tanggal <= activePeriode.tanggalAkhir))
    : pengeluaranList;

  return (
    <div className="flex h-screen w-full overflow-hidden relative bg-[#FAFAFC] text-slate-800 antialiased font-sans">
      {/* Peringatan Mode Demo Lokal */}
      {!isConnectedToSupabase && (
        <div className="fixed top-0 inset-x-0 z-40 bg-amber-500 text-white text-[11px] font-semibold text-center py-1">
          Mode Demo Lokal -- belum terhubung ke Supabase. Data hanya tersimpan sementara di browser ini, tidak aman untuk data keuangan sungguhan.
        </div>
      )}

      {/* Toast Notification */}
      {toastMessage && (
        <div className="fixed bottom-6 right-6 bg-slate-900 text-white px-4 py-3 rounded-[14px] shadow-2xl z-50 flex items-center gap-3 animate-in fade-in slide-in-from-bottom duration-200 text-xs font-semibold">
          <span className="w-2 h-2 rounded-full bg-emerald-400 animate-pulse"></span>
          <span>{toastMessage}</span>
        </div>
      )}

      {/* Sidebar Navigation */}
      <Sidebar
        activeTab={activeTab}
        onSwitchTab={setActiveTab}
        pemasukanCount={pemasukanList.length}
        pengeluaranCount={pengeluaranList.length}
        siswaBelumLunasCount={unreadBelumLunasCount}
        isOpenMobile={isOpenMobileSidebar}
        onCloseMobile={() => setIsOpenMobileSidebar(false)}
        onOpenBlueprint={() => setIsBlueprintModalOpen(true)}
      />

      {/* Main Area */}
      <div className={`flex-1 flex flex-col h-full overflow-hidden ${!isConnectedToSupabase ? 'pt-5' : ''}`}>
        {/* Top Navbar */}
        <Navbar
          currentLembaga={currentLembaga}
          tahunAjaran={tahunAjaran}
          onSelectLembaga={(nama, jenis) => {
            handleUpdateLembaga(nama, jenis);
          }}
          onOpenPemasukanModal={() => setIsPemasukanModalOpen(true)}
          onOpenPengeluaranModal={() => setIsPengeluaranModalOpen(true)}
          onSwitchTab={setActiveTab}
          onToggleSidebar={() => setIsOpenMobileSidebar(!isOpenMobileSidebar)}
          userSession={userSession}
          onOpenAuthModal={() => setIsAuthModalOpen(true)}
          onSignOut={async () => {
            if (isConnectedToSupabase) {
              await signOutSupabase();
            }
            setUserSession(null);
            if (isConnectedToSupabase) setIsAuthModalOpen(true);
            showToast('Sesi pengguna telah keluar');
          }}
        />

        {/* Content Body */}
        <main className="flex-1 overflow-y-auto p-4 md:p-8 custom-scrollbar">
          {activeTab === 'dashboard' && (
            <DashboardView
              pemasukanList={activePemasukanList}
              pengeluaranList={activePengeluaranList}
              masterSumberDana={masterSumberDana}
              saldoAwal={saldoAwal}
              tahunAjaran={tahunAjaran}
              formatRupiah={formatRupiah}
              onSwitchTab={setActiveTab}
            />
          )}

          {activeTab === 'pemasukan' && (
            <PemasukanView
              pemasukanList={pemasukanList}
              masterSumberDana={masterSumberDana}
              onOpenModal={() => setIsPemasukanModalOpen(true)}
              onDeletePemasukan={handleDeletePemasukan}
              formatRupiah={formatRupiah}
              onSwitchTab={setActiveTab}
            />
          )}

          {activeTab === 'pengeluaran' && (
            <PengeluaranView
              pengeluaranList={pengeluaranList}
              masterKategoriPengeluaran={masterKategoriPengeluaran}
              onOpenModal={() => setIsPengeluaranModalOpen(true)}
              onDeletePengeluaran={handleDeletePengeluaran}
              formatRupiah={formatRupiah}
            />
          )}

          {activeTab === 'siswa' && (
            <SiswaView
              siswaTagihanList={siswaTagihanList}
              pemasukanList={pemasukanList}
              masterKelas={masterKelas}
              onOpenModalTambahTagihan={() => setIsSiswaTagihanModalOpen(true)}
              onOpenModalBayar={(siswaId) => {
                const s = siswaTagihanList.find(x => x.id === siswaId);
                if (s) {
                  setSelectedSiswaForBayar(s);
                  setIsSiswaBayarModalOpen(true);
                }
              }}
              onOpenRiwayat={(siswaId) => {
                const s = siswaTagihanList.find(x => x.id === siswaId);
                if (s) {
                  showToast(`Membuka riwayat pembayaran a.n ${s.nama}`);
                }
              }}
              onDeleteTagihan={handleDeleteTagihan}
              formatRupiah={formatRupiah}
            />
          )}

          {activeTab === 'laporan' && (
            <LaporanView
              pemasukanList={pemasukanList}
              pengeluaranList={pengeluaranList}
              currentLembaga={currentLembaga}
              logoDataUrl={logoDataUrl}
              saldoAwal={saldoAwal}
              formatRupiah={formatRupiah}
              onLogoUpload={handleLogoUpload}
              masterKelas={masterKelas}
              siswaTagihanList={siswaTagihanList}
            />
          )}

          {activeTab === 'pengaturan' && (
            <PengaturanView
              currentLembaga={currentLembaga}
              jenisLembaga={jenisLembaga}
              logoDataUrl={logoDataUrl}
              masterKelas={masterKelas}
              masterSumberDana={masterSumberDana}
              masterKategoriPengeluaran={masterKategoriPengeluaran}
              auditLogs={auditLogs}
              saldoAwal={saldoAwal}
              tahunAjaran={tahunAjaran}
              periodeAktifNama={activePeriode?.namaPeriode || ''}
              periodeAktifTanggalMulai={activePeriode?.tanggalMulai || ''}
              periodeAktifStatus={activePeriode?.status || null}
              onUpdateLembaga={handleUpdateLembaga}
              onLogoUpload={handleLogoUpload}
              onRemoveLogo={() => setKonfigurasi(prev => ({ ...prev, logoUrl: null }))}
              onOpenWizard={() => showToast('Menjalankan Setup Wizard...')}
              onAddMasterKelas={handleAddMasterKelas}
              onRemoveMasterKelas={handleRemoveMasterKelas}
              onAddMasterSumber={handleAddMasterSumber}
              onRemoveMasterSumber={handleRemoveMasterSumber}
              onAddMasterKategori={handleAddMasterKategori}
              onRemoveMasterKategori={handleRemoveMasterKategori}
              onRefreshAuditLogs={refreshAuditLogs}
              onUpdateSaldoAwal={handleUpdateSaldoAwal}
              onUpdateTahunAjaran={handleUpdateTahunAjaran}
              onSavePeriodeSettings={handleSavePeriodeSettings}
              onTutupBuku={handleTutupBuku}
              showToast={showToast}
            />
          )}
        </main>
      </div>

      {/* MODALS */}
      <AuthModal
        isOpen={isAuthModalOpen}
        onClose={() => setIsAuthModalOpen(false)}
        userSession={userSession}
        onLoginSuccess={(session) => setUserSession(session)}
        showToast={showToast}
        isDemoMode={!isConnectedToSupabase}
      />

      <SupabaseConfigModal
        isOpen={isSupabaseModalOpen}
        onClose={() => setIsSupabaseModalOpen(false)}
        onConfigSaved={() => checkAndSyncSupabase()}
        showToast={showToast}
      />

      <ModalPemasukan
        isOpen={isPemasukanModalOpen}
        onClose={() => setIsPemasukanModalOpen(false)}
        masterSumberDana={masterSumberDana}
        masterKelas={masterKelas}
        onSave={handleSavePemasukan}
      />

      <ModalPengeluaran
        isOpen={isPengeluaranModalOpen}
        onClose={() => setIsPengeluaranModalOpen(false)}
        masterKategoriPengeluaran={masterKategoriPengeluaran}
        onSave={handleSavePengeluaran}
      />

      <ModalSiswaTagihanPropsModal
        isOpen={isSiswaTagihanModalOpen}
        onClose={() => setIsSiswaTagihanModalOpen(false)}
        masterKelas={masterKelas}
        onSave={handleSaveSiswaTagihan}
      />

      <ModalSiswaBayarPropsModal
        isOpen={isSiswaBayarModalOpen}
        onClose={() => setIsSiswaBayarModalOpen(false)}
        siswa={selectedSiswaForBayar}
        pemasukanList={pemasukanList}
        formatRupiah={formatRupiah}
        onSave={handleSaveBayarSiswa}
      />

      <ModalBlueprint
        isOpen={isBlueprintModalOpen}
        onClose={() => setIsBlueprintModalOpen(false)}
      />
    </div>
  );
}
