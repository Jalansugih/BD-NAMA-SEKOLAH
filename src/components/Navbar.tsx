import React, { useState } from 'react';
import { 
  Plus, Minus, Printer, ChevronDown, Calendar, 
  Database, UserCheck, LogIn, Check, Menu
} from 'lucide-react';
import { UserSession } from '../types';

interface NavbarProps {
  currentLembaga: string;
  tahunAjaran: string;
  onSelectLembaga: (nama: string, jenis: string) => void;
  onOpenPemasukanModal: () => void;
  onOpenPengeluaranModal: () => void;
  onSwitchTab: (tab: string) => void;
  onToggleSidebar: () => void;
  userSession: UserSession | null;
  onOpenAuthModal: () => void;
  onSignOut: () => void;
}

export const Navbar: React.FC<NavbarProps> = ({
  currentLembaga,
  tahunAjaran,
  onSelectLembaga,
  onOpenPemasukanModal,
  onOpenPengeluaranModal,
  onSwitchTab,
  onToggleSidebar,
  userSession,
  onOpenAuthModal,
  onSignOut
}) => {
  const [dropdownOpen, setDropdownOpen] = useState(false);

  const lembagaOptions = [
    { nama: 'SD Negeri 1 Merdeka', jenis: 'SD' },
    { nama: 'SMP Tungturunan', jenis: 'SMP' },
    { nama: 'Yayasan Pendidikan Nusantara', jenis: 'Yayasan' }
  ];

  return (
    <header className="h-16 bg-white border-b border-slate-200/80 px-4 md:px-8 flex items-center justify-between shrink-0 z-10 gap-2">
      {/* Active Institution Badge */}
      <div className="flex items-center gap-2 md:gap-4 min-w-0">
        <button 
          onClick={onToggleSidebar}
          className="md:hidden w-8 h-8 flex items-center justify-center rounded-[14px] border border-slate-200 text-slate-600 hover:bg-slate-50 shrink-0"
        >
          <Menu className="w-4 h-4" />
        </button>

        <div className="flex items-center gap-2.5 px-3 py-1.5 rounded-[14px] bg-slate-100/90 border border-slate-200/90 text-xs font-semibold text-slate-800">
          <span className="w-2 h-2 rounded-full bg-emerald-500 animate-pulse"></span>
          <span className="truncate max-w-[140px] sm:max-w-none">{currentLembaga}</span>
          <span className="hidden sm:inline text-[10px] font-bold text-slate-400 uppercase bg-white px-2 py-0.5 rounded-md border border-slate-200">
            Unit Aktif
          </span>
        </div>

        <span className="text-slate-300 hidden lg:inline">|</span>

        <div className="hidden lg:flex items-center gap-2 text-xs text-slate-500 font-medium">
          <Calendar className="w-3.5 h-3.5 text-slate-400" />
          <span>Tahun Ajaran: <strong className="text-slate-700">{tahunAjaran}</strong></span>
        </div>
      </div>

      {/* Quick Action Buttons */}
      <div className="flex items-center gap-2 md:gap-3 shrink-0">
        {/* User Auth Badge / Login */}
        {userSession ? (
          <div className="flex items-center gap-2">
            <span className="hidden sm:inline text-xs font-semibold text-slate-700 bg-slate-100 px-2.5 py-1.5 rounded-[14px]">
              <UserCheck className="w-3.5 h-3.5 inline mr-1 text-emerald-600" />
              {userSession.email.split('@')[0]}
            </span>
            <button
              onClick={onSignOut}
              className="text-xs font-semibold text-rose-600 hover:bg-rose-50 px-2 py-1.5 rounded-[14px] transition-all"
            >
              Keluar
            </button>
          </div>
        ) : (
          <button
            onClick={onOpenAuthModal}
            className="flex items-center gap-1.5 px-2.5 py-1.5 rounded-[14px] bg-slate-100 hover:bg-slate-200 text-slate-700 text-xs font-semibold transition-all"
          >
            <LogIn className="w-3.5 h-3.5 text-blue-600" />
            <span className="hidden sm:inline">Login User</span>
          </button>
        )}

        {/* Main Action Buttons (2-3 Click Rule) */}
        <button 
          onClick={onOpenPemasukanModal} 
          className="flex items-center gap-1.5 px-2.5 md:px-3.5 py-2 bg-emerald-600 hover:bg-emerald-700 text-white rounded-[14px] text-xs font-semibold transition-all shadow-sm active:scale-95"
        >
          <Plus className="w-3.5 h-3.5" />
          <span className="hidden sm:inline">Pemasukan</span>
        </button>

        <button 
          onClick={onOpenPengeluaranModal} 
          className="flex items-center gap-1.5 px-2.5 md:px-3.5 py-2 bg-rose-600 hover:bg-rose-700 text-white rounded-[14px] text-xs font-semibold transition-all shadow-sm active:scale-95"
        >
          <Minus className="w-3.5 h-3.5" />
          <span className="hidden sm:inline">Pengeluaran</span>
        </button>

        <button 
          onClick={() => onSwitchTab('laporan')} 
          className="hidden sm:flex items-center gap-1.5 px-2.5 md:px-3.5 py-2 bg-slate-900 hover:bg-slate-800 text-white rounded-[14px] text-xs font-semibold transition-all shadow-sm active:scale-95"
        >
          <Printer className="w-3.5 h-3.5" />
          <span className="hidden md:inline">Cetak Laporan</span>
        </button>
      </div>
    </header>
  );
};
