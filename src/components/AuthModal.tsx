import React, { useState } from 'react';
import { Lock, Mail, Eye, EyeOff, ShieldCheck, X, AlertTriangle, ArrowRight, Loader2 } from 'lucide-react';
import { UserSession } from '../types';
import { signInWithPassword, signInWithGoogle } from '../lib/supabase';

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
  const [googleLoading, setGoogleLoading] = useState(false);
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

  const handleGoogleLogin = async () => {
    if (googleLoading || loading) return;
    setErrorMsg(null);
    setGoogleLoading(true);
    try {
      const res = await signInWithGoogle();
      if (!res.success) {
        setErrorMsg(res.message || 'Gagal memulai login dengan Google.');
        setGoogleLoading(false);
      }
      // Jika sukses: browser sedang dialihkan ke halaman Google, jadi modal
      // dibiarkan dalam kondisi loading -- tidak perlu setGoogleLoading(false)
      // karena komponen ini akan unmount saat halaman berpindah.
    } catch (err) {
      console.error('[AuthModal] Google login error:', err);
      setErrorMsg('Terjadi kendala saat memproses login dengan Google. Silakan coba lagi.');
      setGoogleLoading(false);
    }
  };

  return (
    <div className="fixed inset-0 bg-[#05070d]/75 backdrop-blur-md z-50 flex items-center justify-center p-4">
      <div
        className="bg-[#FAF8F3] rounded-[20px] max-w-md w-full shadow-2xl shadow-black/40 border border-[#2A3352]/10 overflow-hidden
                   animate-in fade-in zoom-in-95 duration-200 motion-reduce:animate-none"
      >
        {/* Header brand */}
        <div className="relative px-6 pt-7 pb-7 bg-gradient-to-br from-[#0A0F1D] via-[#131B33] to-[#1F2A4D] text-white overflow-hidden">
          {/* subtle decorative gold glow, premium accent */}
          <div className="pointer-events-none absolute -top-16 -right-12 w-56 h-56 rounded-full bg-[#C9A44C]/20 blur-3xl" />
          <div className="pointer-events-none absolute -bottom-20 -left-14 w-56 h-56 rounded-full bg-[#C9A44C]/10 blur-3xl" />

          <button
            onClick={onClose}
            aria-label="Tutup"
            className="absolute top-4 right-4 text-white/60 hover:text-white p-1 rounded-full hover:bg-white/10 transition-colors"
          >
            <X className="w-4 h-4" />
          </button>

          <div className="relative flex items-center gap-2.5 mb-5">
            {!logoFailed ? (
              <img
                src="/logo-rk-bendahara.png"
                alt="RajaKas"
                className="h-8 w-auto object-contain"
                onError={() => setLogoFailed(true)}
              />
            ) : (
              <div className="w-8 h-8 rounded-lg bg-[#C9A44C]/15 border border-[#C9A44C]/40 flex items-center justify-center">
                <ShieldCheck className="w-4.5 h-4.5 text-[#E8D5A3]" />
              </div>
            )}
            <span className="font-bold text-sm tracking-[0.15em] text-[#E8D5A3]">RAJAKAS.ID</span>
          </div>

          <h3 className="relative font-bold text-lg leading-snug tracking-tight">Selamat Datang Kembali</h3>
          <p className="relative text-[12.5px] text-white/70 mt-1">
            Masuk ke sistem pengelolaan keuangan Anda
          </p>
          <p className="relative text-[11px] text-white/45 mt-2">
            Lembaga baru? "Masuk dengan Google" di bawah juga otomatis mendaftarkan lembaga Anda.
          </p>

          {/* gold hairline signature */}
          <div className="relative mt-6 h-px bg-gradient-to-r from-transparent via-[#C9A44C]/70 to-transparent" />
        </div>

        {isDemoMode ? (
          <div className="p-6 space-y-4">
            <div className="p-3 bg-amber-50 border border-amber-200 rounded-[14px] text-[11px] text-amber-900 flex items-start gap-2">
              <AlertTriangle className="w-4 h-4 text-amber-600 shrink-0 mt-0.5" />
              <span>Aplikasi belum terhubung ke akun sungguhan. Silakan konfigurasi koneksi terlebih dahulu di menu Pengaturan.</span>
            </div>
            <div className="pt-2 flex items-center justify-end border-t border-[#2A3352]/10">
              <button
                type="button"
                onClick={onClose}
                className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-black/5 rounded-[14px] transition-colors"
              >
                Tutup
              </button>
            </div>
          </div>
        ) : (
          <form onSubmit={handleLogin} noValidate className="p-6 space-y-4">
            <button
              type="button"
              onClick={handleGoogleLogin}
              disabled={googleLoading || loading}
              className="w-full h-[50px] flex items-center justify-center gap-2.5 text-sm font-semibold text-slate-700
                         bg-white border border-slate-200 rounded-[14px] shadow-sm shadow-black/5
                         hover:shadow-md hover:-translate-y-px active:translate-y-0
                         transition-all disabled:opacity-60 disabled:cursor-not-allowed disabled:translate-y-0"
            >
              {googleLoading ? (
                <>
                  <Loader2 className="w-4 h-4 animate-spin motion-reduce:animate-none text-slate-500" />
                  <span>Mengalihkan ke Google...</span>
                </>
              ) : (
                <>
                  <svg className="w-4 h-4" viewBox="0 0 48 48" aria-hidden="true">
                    <path fill="#FFC107" d="M43.6 20.5H42V20.4H24v7.2h11.3c-1.6 4.7-6.1 8-11.3 8-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.9 1.2 8 3.1l5.1-5.1C33.5 6.1 29 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.7-.4-3.5z"/>
                    <path fill="#FF3D00" d="M6.3 14.7l5.9 4.3C13.8 15.3 18.6 12 24 12c3.1 0 5.9 1.2 8 3.1l5.1-5.1C33.5 6.1 29 4 24 4c-7.4 0-13.8 4.1-17.1 10.1z"/>
                    <path fill="#4CAF50" d="M24 44c4.9 0 9.4-1.9 12.7-4.9l-5.9-4.9C29 35.9 26.6 36.8 24 36.8c-5.2 0-9.6-3.3-11.2-7.9l-6 4.6C10.1 39.8 16.5 44 24 44z"/>
                    <path fill="#1976D2" d="M43.6 20.5H42V20.4H24v7.2h11.3c-.8 2.3-2.2 4.2-4.1 5.6l5.9 4.9C40.8 35 44 30.2 44 24c0-1.3-.1-2.7-.4-3.5z"/>
                  </svg>
                  <span>Masuk dengan Google</span>
                </>
              )}
            </button>

            <div className="flex items-center gap-3">
              <div className="h-px flex-1 bg-[#2A3352]/10" />
              <span className="text-[11px] text-slate-400 font-medium">atau masuk dengan email</span>
              <div className="h-px flex-1 bg-[#2A3352]/10" />
            </div>

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
                  className={`w-full bg-white border rounded-[14px] pl-10 pr-3.5 h-[50px] text-sm font-medium text-slate-800
                             outline-none transition-all shadow-inner shadow-black/[0.02]
                             focus:ring-[3px] focus:ring-[#C9A44C]/15
                             ${fieldErrors.email ? 'border-rose-300 focus:border-rose-400' : 'border-slate-200 focus:border-[#C9A44C]'}`}
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
                  className="text-[11px] font-semibold text-[#9C7A2A] hover:text-[#7A5E1F] hover:underline transition-colors"
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
                  className={`w-full bg-white border rounded-[14px] pl-10 pr-10 h-[50px] text-sm font-medium text-slate-800
                             outline-none transition-all shadow-inner shadow-black/[0.02]
                             focus:ring-[3px] focus:ring-[#C9A44C]/15
                             ${fieldErrors.password ? 'border-rose-300 focus:border-rose-400' : 'border-slate-200 focus:border-[#C9A44C]'}`}
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
                className="w-3.5 h-3.5 rounded border-slate-300 text-[#9C7A2A] focus:ring-[#C9A44C]/40"
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
              className="relative w-full h-[52px] flex items-center justify-center gap-2 text-sm font-semibold text-[#F3E6C0]
                         bg-gradient-to-b from-[#141B32] to-[#0A0F1D] rounded-[14px]
                         border border-[#C9A44C]/40 shadow-lg shadow-black/20
                         hover:shadow-xl hover:shadow-[#C9A44C]/10 hover:-translate-y-px active:translate-y-0
                         transition-all disabled:opacity-60 disabled:cursor-not-allowed disabled:translate-y-0"
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
              <ShieldCheck className="w-4 h-4 text-[#9C7A2A] shrink-0 mt-0.5" />
              <span>Keamanan akun Anda terjamin dengan sistem terenkripsi dan rekam jejak aktivitas.</span>
            </div>
          </form>
        )}

        {/* Promo banner */}
        <a
          href="https://rajakas.id"
          target="_blank"
          rel="noopener noreferrer"
          className="group block mx-6 mb-5 rounded-[14px] bg-gradient-to-br from-[#0A0F1D] to-[#1F2A4D] p-4
                     border border-[#C9A44C]/20
                     transition-all hover:-translate-y-0.5 hover:border-[#C9A44C]/40 motion-reduce:transform-none"
        >
          <p className="text-white text-[12.5px] font-semibold">Kelola Keuangan Lebih Mudah dengan RajaKas</p>
          <p className="text-white/50 text-[11px] mt-0.5">
            Solusi digital untuk pencatatan transaksi, kas, dan laporan keuangan.
          </p>
          <div className="mt-2 flex items-center justify-between">
            <span className="inline-flex items-center gap-1 text-[11px] font-semibold text-[#E8D5A3] group-hover:underline">
              Kenal RajaKas <ArrowRight className="w-3 h-3" />
            </span>
            <span className="text-[10px] text-white/35">rajakas.id</span>
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
