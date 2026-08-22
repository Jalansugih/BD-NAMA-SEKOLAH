import React from 'react';
import {
  PieChart,
  ArrowDownLeft,
  ArrowUpRight,
  GraduationCap,
  FileText,
  Sliders,
  Compass,
  ArrowRight,
} from 'lucide-react';

interface SidebarProps {
  activeTab: string;
  onSwitchTab: (tab: string) => void;
  pemasukanCount: number;
  pengeluaranCount: number;
  siswaBelumLunasCount: number;
  isOpenMobile: boolean;
  onCloseMobile: () => void;
  onOpenBlueprint: () => void;
}

export const Sidebar: React.FC<SidebarProps> = ({
  activeTab,
  onSwitchTab,
  pemasukanCount,
  pengeluaranCount,
  siswaBelumLunasCount,
  isOpenMobile,
  onCloseMobile,
  onOpenBlueprint,
}) => {
  const getNavItemClass = (tab: string) => {
    const isActive = activeTab === tab;

    return `w-full flex items-center gap-3 px-3 py-2.5 rounded-[14px] text-sm font-medium transition-all ${
      isActive
        ? 'text-blue-600 bg-blue-50 font-semibold'
        : 'text-slate-600 hover:bg-slate-50 hover:text-slate-900'
    }`;
  };

  return (
    <>
      {/* Mobile Overlay */}
      {isOpenMobile && (
        <div
          className="fixed inset-0 bg-slate-900/30 z-20 md:hidden"
          onClick={onCloseMobile}
          aria-hidden="true"
        />
      )}

      {/* Sidebar Container */}
      <aside
        className={`w-64 bg-white border-r border-slate-200/80 flex flex-col justify-between shrink-0 z-30 fixed md:static inset-y-0 left-0 transition-transform duration-200 ease-in-out ${
          isOpenMobile
            ? 'translate-x-0'
            : '-translate-x-full md:translate-x-0'
        }`}
      >
        <div>
          {/* Brand Header */}
          <div className="h-16 flex items-center px-6 border-b border-slate-100 justify-between">
            <div className="flex items-center gap-3">
              
              {/* Logo SVG */}
              <div className="w-9 h-9 flex items-center justify-center shrink-0">
                <img
                  src="/logo-rk-bendahara.png"
                  alt="RajaKas.id"
                  className="w-9 h-9 object-contain"
                />
              </div>

              {/* Nama Aplikasi */}
              <div>
                <span className="font-bold text-slate-900 tracking-tight text-lg">
                  RajaKas<span className="text-blue-600">.id</span>
                </span>

                <span className="block text-[10px] font-semibold uppercase tracking-wider text-slate-400">
                  Portal Bendahara
                </span>
              </div>
            </div>
          </div>

          {/* Navigation Links */}
          <nav className="p-4 space-y-1">
            <p className="px-3 text-[11px] font-semibold text-slate-400 uppercase tracking-wider mb-2">
              Menu Utama
            </p>

            <button
              onClick={() => onSwitchTab('dashboard')}
              className={getNavItemClass('dashboard')}
            >
              <PieChart className="w-5 h-5" />
              <span>Dashboard</span>
            </button>

            <div className="pt-2">
              <p className="px-3 text-[11px] font-semibold text-slate-400 uppercase tracking-wider mb-2">
                Transaksi
              </p>

              <button
                onClick={() => onSwitchTab('pemasukan')}
                className={getNavItemClass('pemasukan')}
              >
                <ArrowDownLeft className="w-5 h-5 text-emerald-500" />
                <span>Pemasukan</span>

                <span className="ml-auto bg-emerald-50 text-emerald-700 text-xs px-2 py-0.5 rounded-full font-semibold">
                  {pemasukanCount}
                </span>
              </button>

              <button
                onClick={() => onSwitchTab('pengeluaran')}
                className={`${getNavItemClass('pengeluaran')} mt-1`}
              >
                <ArrowUpRight className="w-5 h-5 text-rose-500" />
                <span>Pengeluaran</span>

                <span className="ml-auto bg-rose-50 text-rose-700 text-xs px-2 py-0.5 rounded-full font-semibold">
                  {pengeluaranCount}
                </span>
              </button>
            </div>

            <div className="pt-2">
              <p className="px-3 text-[11px] font-semibold text-slate-400 uppercase tracking-wider mb-2">
                Monitoring Siswa
              </p>

              <button
                onClick={() => onSwitchTab('siswa')}
                className={getNavItemClass('siswa')}
              >
                <GraduationCap className="w-5 h-5 text-amber-500" />
                <span>Pembayaran Siswa</span>

                <span className="ml-auto bg-amber-50 text-amber-700 text-xs px-2 py-0.5 rounded-full font-semibold">
                  {siswaBelumLunasCount}
                </span>
              </button>
            </div>

            <div className="pt-2">
              <p className="px-3 text-[11px] font-semibold text-slate-400 uppercase tracking-wider mb-2">
                Analitik & Laporan
              </p>

              <button
                onClick={() => onSwitchTab('laporan')}
                className={getNavItemClass('laporan')}
              >
                <FileText className="w-5 h-5 text-blue-500" />
                <span>Laporan Kas</span>
              </button>
            </div>

            <div className="pt-2">
              <p className="px-3 text-[11px] font-semibold text-slate-400 uppercase tracking-wider mb-2">
                Pengaturan & Audit
              </p>

              <button
                onClick={() => onSwitchTab('pengaturan')}
                className={getNavItemClass('pengaturan')}
              >
                <Sliders className="w-5 h-5 text-slate-500" />
                <span>Pengaturan & Audit</span>
              </button>
            </div>
          </nav>
        </div>

        {/* Bottom Profile & Blueprint Button */}
        <div className="p-4 border-t border-slate-100 bg-slate-50/50">
          <button
            onClick={onOpenBlueprint}
            className="w-full mb-3 flex items-center justify-between p-2.5 bg-blue-600 hover:bg-blue-700 text-white rounded-[14px] text-xs font-semibold shadow-sm transition-all"
          >
            <span className="flex items-center gap-2">
              <Compass className="w-4 h-4" />
              Design System Blueprint
            </span>

            <ArrowRight className="w-3.5 h-3.5" />
          </button>

          <div className="flex items-center gap-3">
            <div className="w-9 h-9 rounded-full bg-blue-100 text-blue-700 font-bold text-xs flex items-center justify-center shrink-0 border border-slate-200">
              SR
            </div>

            <div className="truncate">
              <p className="text-xs font-semibold text-slate-900 truncate">
                Anas Abdul Latif, S.Pd
              </p>

              <p className="text-[10px] text-slate-500 truncate">
                Bendahara Utama
              </p>
            </div>
          </div>
        </div>
      </aside>
    </>
  );
};
