import React, { useState } from 'react';
import { Lock, Mail, Eye, EyeOff, ShieldCheck, X, AlertTriangle, ArrowRight, Loader2 } from 'lucide-react';
import { UserSession } from '../types';
import { signInWithPassword } from '../lib/supabase';

interface AuthModalProps {
  isOpen: boolean;
  onClose: () => void;
  userSession: UserSession | null;
  onLoginSuccess: (session: UserSession) => void;
  showToast: (msg: string) => void;
  /** Jika true (mode demo lokal tanpa Supabase), form login tidak ditampilkan sama sekali. */
  isDemoMode?: boolean;
  /**
   * Opsional: dipanggil saat pengguna menekan "Lupa kata sandi?".
   * Sambungkan ke fungsi reset password Supabase yang sudah ada di project (mis. resetPasswordForEmail).
   * Jika tidak disediakan, tombol akan menampilkan toast pemberitahuan sederhana.
   */
  onForgotPassword?: (email: string) => void;
}

export const AuthModal: React.FC<AuthModalProps> = ({
  isOpen,
  onClose,
  onLoginSuccess,
  showToast,
  isDemoMode,
  onForgotPassword
}) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [rememberMe, setRememberMe] = useState(false);
  const [loading, setLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<{ email?: string; password?: string }>({});
  const [logoFailed, setLogoFailed] = useState(false);

  if (!isOpen) return null;

  const validate = () => {
    const errors: { email?: string; password?: string } = {};
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

    if (!email.trim()) {
      errors.email = 'Email wajib diisi.';
    } else if (!emailRegex.test(email.trim())) {
      errors.email = 'Format email tidak valid.';
    }

    if (!password) {
      errors.password = 'Kata sandi wajib diisi.';
    }

    setFieldErrors(errors);
    return Object.keys(errors).length === 0;
  };

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault();
    setErrorMsg(null);

    if (!validate()) return;
    if (loading) return; // cegah klik ganda saat proses login berlangsung

    setLoading(true);

    try {
      const res = await signInWithPassword(email, password);

      if (!res.success || !res.session) {
        // TIDAK ADA FALLBACK: kalau login gagal, akses tetap ditolak.
        setErrorMsg(res.message || 'Email atau kata sandi yang Anda masukkan tidak sesuai.');
        setLoading(false);
        return;
      }

      onLoginSuccess({
        id: res.session.user.id,
        email: res.session.user.email || email,
        role: 'Bendahara Utama'
      });
      showToast('Login berhasil!');
      onClose();
    } catch (err) {
      console.error('[AuthModal] Login error:', err);
      setErrorMsg('Terjadi kendala saat memproses login. Silakan coba lagi.');
      setLoading(false);
    }
  };

  const handleForgotPassword = () => {
    if (onForgotPassword) {
      onForgotPassword(email);
    } else {
      showToast('Silakan hubungi admin sekolah untuk reset kata sandi.');
    }
  };

  return (
    <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div
        className="bg-white rounded-[20px] max-w-md w-full shadow-2xl border border-slate-200/80 overflow-hidden
                   animate-in fade-in zoom-in-95 duration-200 motion-reduce:animate-none"
      >
        {/* Header brand */}
        <div className="relative px-6 pt-7 pb-6 bg-gradient-to-br from-blue-600 via-blue-600 to-blue-800 text-white overflow-hidden">
          {/* subtle decorative glow */}
          <div className="pointer-events-none absolute -top-10 -right-10 w-40 h-40 rounded-full bg-white/10 blur-2xl" />
          <div className="pointer-events-none absolute -bottom-16 -left-10 w-48 h-48 rounded-full bg-white/5 blur-2xl" />

          <button
            onClick={onClose}
            aria-label="Tutup"
            className="absolute top-4 right-4 text-white/70 hover:text-white p-1 rounded-full hover:bg-white/10 transition-colors"
          >
            <X className="w-4 h-4" />
          </button>

          <div className="relative flex items-center gap-2.5 mb-4">
            {!logoFailed ? (
              <img
                src="/logo-login.png"
                alt="RajaKas"
                className="h-8 w-auto object-contain"
                onError={() => setLogoFailed(true)}
              />
            ) : (
              <div className="w-8 h-8 rounded-lg bg-white/15 flex items-center justify-center">
                <ShieldCheck className="w-4.5 h-4.5 text-white" />
              </div>
            )}
            <span className="font-bold text-sm tracking-wide">RAJAKAS.ID</span>
          </div>

          <h3 className="relative font-bold text-lg leading-snug">Selamat Datang Kembali</h3>
          <p className="relative text-[12.5px] text-blue-100 mt-1">
            Masuk ke sistem pengelolaan keuangan Anda
          </p>
          <p className="relative text-[11px] text-blue-200/90 mt-2">
            Kelola kas, transaksi, dan laporan keuangan dengan lebih mudah.
          </p>
        </div>

        {isDemoMode ? (
          <div className="p-6 space-y-4">
            <div className="p-3 bg-amber-50 border border-amber-200 rounded-[14px] text-[11px] text-amber-900 flex items-start gap-2">
              <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
              <span>Aplikasi belum terhubung ke akun sungguhan. Silakan konfigurasi koneksi terlebih dahulu di menu Pengaturan.</span>
            </div>
            <div className="pt-2 flex items-center justify-end border-t border-slate-100">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-[14px] transition-colors"
              >
                Tutup
              </button>
            </div>
          </div>
        ) : (
          <form onSubmit={handleLogin} noValidate className="p-6 space-y-4">
            <div>
              <label htmlFor="rajakas-email" className="block text-xs font-semibold text-slate-700 mb-1.5">
                Email
              </label>
              <div className="relative">
                <Mail className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
                <input
                  id="rajakas-email"
                  type="email"
                  autoComplete="email"
                  value={email}
                  onChange={(e) => {
                    setEmail(e.target.value);
                    if (fieldErrors.email) setFieldErrors((p) => ({ ...p, email: undefined }));
                  }}
                  placeholder="nama@email.com"
                  aria-invalid={!!fieldErrors.email}
                  aria-describedby={fieldErrors.email ? 'rajakas-email-error' : undefined}
                  className={`w-full bg-slate-50 border rounded-[14px] pl-10 pr-3.5 h-[50px] text-sm font-medium text-slate-800
                             outline-none transition-colors focus:bg-white
                             ${fieldErrors.email ? 'border-rose-300 focus:border-rose-400' : 'border-slate-200 focus:border-blue-500'}`}
                />
              </div>
              {fieldErrors.email && (
                <p id="rajakas-email-error" className="mt-1 text-[11px] text-rose-600">{fieldErrors.email}</p>
              )}
            </div>

            <div>
              <div className="flex items-center justify-between mb-1.5">
                <label htmlFor="rajakas-password" className="block text-xs font-semibold text-slate-700">
                  Kata Sandi
                </label>
                <button
                  type="button"
                  onClick={handleForgotPassword}
                  className="text-[11px] font-semibold text-blue-600 hover:text-blue-700 hover:underline transition-colors"
                >
                  Lupa kata sandi?
                </button>
              </div>
              <div className="relative">
                <Lock className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
                <input
                  id="rajakas-password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  value={password}
                  onChange={(e) => {
                    setPassword(e.target.value);
                    if (fieldErrors.password) setFieldErrors((p) => ({ ...p, password: undefined }));
                  }}
                  placeholder="Masukkan kata sandi"
                  aria-invalid={!!fieldErrors.password}
                  aria-describedby={fieldErrors.password ? 'rajakas-password-error' : undefined}
                  className={`w-full bg-slate-50 border rounded-[14px] pl-10 pr-10 h-[50px] text-sm font-medium text-slate-800
                             outline-none transition-colors focus:bg-white
                             ${fieldErrors.password ? 'border-rose-300 focus:border-rose-400' : 'border-slate-200 focus:border-blue-500'}`}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword((v) => !v)}
                  aria-label={showPassword ? 'Sembunyikan kata sandi' : 'Tampilkan kata sandi'}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 transition-colors"
                >
                  {showPassword ? <EyeOff className="w-4 h-4" /> : <Eye className="w-4 h-4" />}
                </button>
              </div>
              {fieldErrors.password && (
                <p id="rajakas-password-error" className="mt-1 text-[11px] text-rose-600">{fieldErrors.password}</p>
              )}
            </div>

            <label className="flex items-center gap-2 cursor-pointer select-none">
              <input
                type="checkbox"
                checked={rememberMe}
                onChange={(e) => setRememberMe(e.target.checked)}
                className="w-3.5 h-3.5 rounded border-slate-300 text-blue-600 focus:ring-blue-500"
              />
              <span className="text-[12px] text-slate-600">Ingat saya</span>
            </label>

            {errorMsg && (
              <div className="p-3 bg-rose-50 border border-rose-200 rounded-[14px] text-[11px] text-rose-800 flex items-start gap-2">
                <AlertTriangle className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />
                <span>{errorMsg}</span>
              </div>
            )}

            <button
              type="submit"
              disabled={loading}
              className="w-full h-[52px] flex items-center justify-center gap-2 text-sm font-semibold text-white
                         bg-blue-600 hover:bg-blue-700 active:bg-blue-800 rounded-[14px] shadow-sm shadow-blue-600/20
                         transition-all disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {loading ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin motion-reduce:animate-none" />
                  <span>Memproses...</span>
                </>
              ) : (
                <>
                  <span>Masuk ke Aplikasi</span>
                  <ArrowRight className="w-4 h-4" />
                </>
              )}
            </button>

            <div className="flex items-start gap-2 text-[11px] text-slate-500">
              <ShieldCheck className="w-4 h-4 text-blue-500 shrink-0 mt-0.5" />
              <span>Keamanan akun Anda terjamin dengan sistem terenkripsi dan rekam jejak aktivitas.</span>
            </div>
          </form>
        )}

        {/* Promo banner */}
        <a
          href="https://rajakas.id"
          target="_blank"
          rel="noopener noreferrer"
          className="group block mx-6 mb-5 rounded-[14px] bg-gradient-to-r from-blue-600 to-blue-500 p-4
                     transition-transform hover:-translate-y-0.5 motion-reduce:transform-none"
        >
          <p className="text-white text-[12.5px] font-semibold">Kelola Keuangan Lebih Mudah dengan RajaKas</p>
          <p className="text-blue-100 text-[11px] mt-0.5">
            Solusi digital untuk pencatatan transaksi, kas, dan laporan keuangan.
          </p>
          <div className="mt-2 flex items-center justify-between">
            <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-white group-hover:underline">
              Kenal RajaKas <ArrowRight className="w-3 h-3" />
            </span>
            <span className="text-[10px] text-blue-100/80">rajakas.id</span>
          </div>
        </a>

        {/* Footer */}
        <div className="px-6 pb-5 text-center">
          <p className="text-[10.5px] text-slate-400">© 2026 RajaKas.ID · Aplikasi Keuangan Digital</p>
        </div>
      </div>
    </div>
  );
};
