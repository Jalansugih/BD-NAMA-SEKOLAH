import React, { useState } from 'react';
import {
  Mail,
  Lock,
  Eye,
  EyeOff,
  ShieldCheck,
  ArrowRight,
  Loader2,
  AlertTriangle,
  HelpCircle,
  Receipt,
  KeyRound,
  Headphones,
  X,
} from 'lucide-react';
import { UserSession } from '../types';
import { signInWithPassword, signInWithGoogle } from '../lib/supabase';

interface LoginGateScreenProps {
  onLoginSuccess: (session: UserSession) => void;
  showToast: (msg: string) => void;
  /**
   * Opsional: dipanggil saat pengguna menekan "Lupa kata sandi?".
   * Sambungkan ke fungsi reset password Supabase yang sudah ada di project.
   * Jika tidak disediakan, akan menampilkan toast pemberitahuan sederhana.
   */
  onForgotPassword?: (email: string) => void;
}

/**
 * Layar gerbang login versi full-page (dipakai HANYA saat aplikasi sudah
 * terhubung ke Supabase tapi belum ada sesi valid). Ini BUKAN pengganti
 * AuthModal -- AuthModal tetap dipakai apa adanya untuk modal overlay di
 * dalam aplikasi (mode demo / re-login). Semua logic autentikasi di sini
 * sengaja disalin identik dari AuthModal supaya tidak ada perubahan pada
 * behavior yang sudah berjalan.
 */
export const LoginGateScreen: React.FC<LoginGateScreenProps> = ({
  onLoginSuccess,
  showToast,
  onForgotPassword,
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
  const [isHelpOpen, setIsHelpOpen] = useState(false);

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
        role: 'Bendahara Utama',
      });
      showToast('Login berhasil!');
    } catch (err) {
      console.error('[LoginGateScreen] Login error:', err);
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
      // Jika sukses: browser sedang dialihkan ke halaman Google, jadi layar
      // dibiarkan dalam kondisi loading -- tidak perlu setGoogleLoading(false)
      // karena komponen ini akan unmount saat halaman berpindah.
    } catch (err) {
      console.error('[LoginGateScreen] Google login error:', err);
      setErrorMsg('Terjadi kendala saat memproses login dengan Google. Silakan coba lagi.');
      setGoogleLoading(false);
    }
  };

  return (
    <div className="min-h-screen w-full bg-slate-50 flex flex-col justify-between relative overflow-x-hidden">
      {/* Dekorasi latar belakang */}
      <div className="fixed inset-0 overflow-hidden pointer-events-none z-0">
        <div
          className="absolute -top-32 -left-32 w-96 h-96 bg-blue-200/40 rounded-full blur-3xl"
          style={{ animation: 'rk-float 8s ease-in-out infinite' }}
        />
        <div
          className="absolute top-1/3 -right-20 w-80 h-80 bg-cyan-200/30 rounded-full blur-3xl"
          style={{ animation: 'rk-float 10s ease-in-out 3s infinite' }}
        />
        <div
          className="absolute -bottom-20 left-1/3 w-96 h-96 bg-blue-100/40 rounded-full blur-3xl"
          style={{ animation: 'rk-float 9s ease-in-out 1.5s infinite' }}
        />
        <style>{`
          @keyframes rk-float {
            0%, 100% { transform: translateY(0px) scale(1); }
            50% { transform: translateY(-18px) scale(1.04); }
          }
        `}</style>
      </div>

      {/* Header */}
      <header className="relative z-10 w-full max-w-7xl mx-auto px-6 py-5 flex justify-between items-center">
        <div className="flex items-center gap-2.5">
  {!logoFailed ? (
    <img
  src="/logo-rk-bendahara.png"
  alt="RajaKas"
  className="h-9 w-9 object-contain shrink-0"
  onError={() => setLogoFailed(true)}
/>
) : (
  <div className="w-9 h-9 rounded-xl bg-gradient-to-tr from-blue-700 to-blue-500 flex items-center justify-center text-white shadow-lg shadow-blue-500/25">
    <ShieldCheck className="w-4.5 h-4.5" />
  </div>
)}

<div className="flex flex-col justify-center">
  <div className="text-lg font-bold leading-[1] tracking-tight">
    <span className="text-slate-900">Rajakas</span>
    <span className="text-blue-400">.id</span>
  </div>

    <div className="mt-0.5 text-[10px] sm:text-[11px] font-medium leading-[1] text-slate-500">
      Portal Bendahara
    </div>
  </div>
</div>

        <div className="flex items-center gap-4">
          <button
            type="button"
            onClick={() => setIsHelpOpen(true)}
            className="text-sm font-medium text-slate-600 hover:text-blue-600 transition-colors flex items-center gap-1.5"
          >
            <HelpCircle className="w-4 h-4" />
            <span className="hidden sm:inline">Bantuan &amp; Panduan</span>
          </button>
          <div className="h-4 w-px bg-slate-300 hidden sm:block" />
          <div className="text-xs text-slate-500 font-medium hidden sm:flex items-center gap-1">
            <ShieldCheck className="w-3.5 h-3.5 text-emerald-500" />
            Sistem Terenkripsi
          </div>
        </div>
      </header>

      {/* Konten utama */}
      <main className="relative z-10 flex-1 flex items-center justify-center px-4 py-8">
        <div className="w-full max-w-5xl grid grid-cols-1 lg:grid-cols-12 gap-8 items-center">
          {/* Sisi kiri: branding & informasi */}
          <div className="lg:col-span-6 space-y-6 text-center lg:text-left px-2 sm:px-6">
            <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-blue-100/70 border border-blue-200 text-blue-800 text-xs font-semibold">
              <span className="w-2 h-2 rounded-full bg-blue-500 animate-pulse" />
              Sistem Keuangan Sekolah
            </div>

            <h1 className="text-3xl sm:text-4xl lg:text-5xl font-extrabold text-slate-900 leading-tight">
              Pengelolaan Kas Sekolah{' '}
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-blue-600 to-cyan-600">
                Lebih Transparan
              </span>
            </h1>

            <p className="text-slate-600 text-base sm:text-lg leading-relaxed max-w-xl mx-auto lg:mx-0">
              Selamat datang di Portal Bendahara <strong>RajaKas</strong>. Akses dasbor kas, Infaq
              siswa, dan laporan keuangan sekolah dalam satu tempat.
            </p>

            <div className="grid grid-cols-2 gap-4 pt-2 max-w-lg mx-auto lg:mx-0">
              <div className="flex items-start gap-3 p-3 rounded-xl bg-white/60 border border-slate-200/80 shadow-sm">
                <div className="w-9 h-9 rounded-lg bg-blue-50 flex items-center justify-center text-blue-600 shrink-0 mt-0.5">
                  <Receipt className="w-4.5 h-4.5" />
                </div>
                <div>
                  <h4 className="text-sm font-bold text-slate-800">Laporan Otomatis</h4>
                  <p className="text-xs text-slate-500">Rekap kas &amp; laporan instan</p>
                </div>
              </div>

              <div className="flex items-start gap-3 p-3 rounded-xl bg-white/60 border border-slate-200/80 shadow-sm">
                <div className="w-9 h-9 rounded-lg bg-blue-50 flex items-center justify-center text-blue-600 shrink-0 mt-0.5">
                  <Lock className="w-4.5 h-4.5" />
                </div>
                <div>
                  <h4 className="text-sm font-bold text-slate-800">Untuk System POS</h4>
                  <p className="text-xs text-slate-500">Data terenkripsi &amp; tercatat rapi</p>
                </div>
              </div>
            </div>
          </div>

          {/* Sisi kanan: form login */}
          <div className="lg:col-span-6 flex justify-center">
            <div className="w-full max-w-sm bg-white/90 backdrop-blur-md rounded-2xl p-6 sm:p-7 shadow-xl shadow-blue-500/10 border border-blue-100">
              <div className="mb-5">
                <h2 className="text-xl font-bold text-slate-900 mb-1.5">Masuk Portal</h2>
                <p className="text-xs text-slate-500">Silakan masukkan kredensial akun bendahara Anda</p>
              </div>

              <button
                type="button"
                onClick={handleGoogleLogin}
                disabled={googleLoading || loading}
                className="w-full mb-4 h-[46px] flex items-center justify-center gap-2.5 text-sm font-semibold text-slate-700 bg-white border border-slate-200 rounded-xl shadow-sm hover:bg-slate-50 hover:border-blue-300 transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
              >
                {googleLoading ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin motion-reduce:animate-none text-slate-500" />
                    <span>Mengalihkan ke Google...</span>
                  </>
                ) : (
                  <>
                    <svg className="w-4 h-4 shrink-0" viewBox="0 0 48 48" aria-hidden="true">
                      <path fill="#FFC107" d="M43.6 20.5H42V20.4H24v7.2h11.3c-1.6 4.7-6.1 8-11.3 8-6.6 0-12-5.4-12-12s5.4-12 12-12c3.1 0 5.9 1.2 8 3.1l5.1-5.1C33.5 6.1 29 4 24 4 12.9 4 4 12.9 4 24s8.9 20 20 20 20-8.9 20-20c0-1.3-.1-2.7-.4-3.5z" />
                      <path fill="#FF3D00" d="M6.3 14.7l5.9 4.3C13.8 15.3 18.6 12 24 12c3.1 0 5.9 1.2 8 3.1l5.1-5.1C33.5 6.1 29 4 24 4c-7.4 0-13.8 4.1-17.1 10.1z" />
                      <path fill="#4CAF50" d="M24 44c4.9 0 9.4-1.9 12.7-4.9l-5.9-4.9C29 35.9 26.6 36.8 24 36.8c-5.2 0-9.6-3.3-11.2-7.9l-6 4.6C10.1 39.8 16.5 44 24 44z" />
                      <path fill="#1976D2" d="M43.6 20.5H42V20.4H24v7.2h11.3c-.8 2.3-2.2 4.2-4.1 5.6l5.9 4.9C40.8 35 44 30.2 44 24c0-1.3-.1-2.7-.4-3.5z" />
                    </svg>
                    <span>Masuk dengan Google</span>
                  </>
                )}
              </button>

              <div className="relative flex py-1 items-center mb-4">
                <div className="flex-grow border-t border-slate-200" />
                <span className="flex-shrink mx-2.5 text-[10px] font-semibold text-slate-400 uppercase tracking-wider">
                  atau dengan email
                </span>
                <div className="flex-grow border-t border-slate-200" />
              </div>

              <form onSubmit={handleLogin} noValidate className="space-y-4">
                <div>
                  <label htmlFor="rajakas-gate-email" className="block text-[11px] font-bold uppercase tracking-wider text-slate-700 mb-1.5">
                    Email
                  </label>
                  <div className="relative">
                    <Mail className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
                    <input
                      id="rajakas-gate-email"
                      type="email"
                      autoComplete="email"
                      value={email}
                      onChange={(e) => {
                        setEmail(e.target.value);
                        if (fieldErrors.email) setFieldErrors((p) => ({ ...p, email: undefined }));
                      }}
                      placeholder="nama@email.com"
                      aria-invalid={!!fieldErrors.email}
                      aria-describedby={fieldErrors.email ? 'rajakas-gate-email-error' : undefined}
                      className={`w-full bg-slate-50 border rounded-xl pl-10 pr-3.5 h-[46px] text-sm font-medium text-slate-800 outline-none transition-colors focus:bg-white ${
                        fieldErrors.email ? 'border-rose-300 focus:border-rose-400' : 'border-slate-200 focus:border-blue-500'
                      }`}
                    />
                  </div>
                  {fieldErrors.email && (
                    <p id="rajakas-gate-email-error" className="mt-1 text-[11px] text-rose-600">
                      {fieldErrors.email}
                    </p>
                  )}
                </div>

                <div>
                  <div className="flex items-center justify-between mb-1.5">
                    <label htmlFor="rajakas-gate-password" className="block text-[11px] font-bold uppercase tracking-wider text-slate-700">
                      Kata Sandi
                    </label>
                    <button
                      type="button"
                      onClick={handleForgotPassword}
                      className="text-xs font-semibold text-blue-600 hover:text-blue-700 hover:underline transition-colors"
                    >
                      Lupa?
                    </button>
                  </div>
                  <div className="relative">
                    <Lock className="w-4 h-4 text-slate-400 absolute left-3 top-1/2 -translate-y-1/2" />
                    <input
                      id="rajakas-gate-password"
                      type={showPassword ? 'text' : 'password'}
                      autoComplete="current-password"
                      value={password}
                      onChange={(e) => {
                        setPassword(e.target.value);
                        if (fieldErrors.password) setFieldErrors((p) => ({ ...p, password: undefined }));
                      }}
                      placeholder="Masukkan kata sandi"
                      aria-invalid={!!fieldErrors.password}
                      aria-describedby={fieldErrors.password ? 'rajakas-gate-password-error' : undefined}
                      className={`w-full bg-slate-50 border rounded-xl pl-10 pr-10 h-[46px] text-sm font-medium text-slate-800 outline-none transition-colors focus:bg-white ${
                        fieldErrors.password ? 'border-rose-300 focus:border-rose-400' : 'border-slate-200 focus:border-blue-500'
                      }`}
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
                    <p id="rajakas-gate-password-error" className="mt-1 text-[11px] text-rose-600">
                      {fieldErrors.password}
                    </p>
                  )}
                </div>

                <label className="flex items-center gap-2 cursor-pointer select-none">
                  <input
                    type="checkbox"
                    checked={rememberMe}
                    onChange={(e) => setRememberMe(e.target.checked)}
                    className="w-3.5 h-3.5 rounded border-slate-300 text-blue-600 focus:ring-blue-500"
                  />
                  <span className="text-xs text-slate-600">Ingat sesi saya</span>
                </label>

                {errorMsg && (
                  <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-[11px] text-rose-800 flex items-start gap-2">
                    <AlertTriangle className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />
                    <span>{errorMsg}</span>
                  </div>
                )}

                <button
                  type="submit"
                  disabled={loading}
                  className="w-full h-[48px] flex items-center justify-center gap-2 text-sm font-semibold text-white bg-blue-600 hover:bg-blue-700 active:bg-blue-800 rounded-xl shadow-md shadow-blue-600/20 transition-all disabled:opacity-60 disabled:cursor-not-allowed"
                >
                  {loading ? (
                    <>
                      <Loader2 className="w-4 h-4 animate-spin motion-reduce:animate-none" />
                      <span>Memproses...</span>
                    </>
                  ) : (
                    <>
                      <span>Masuk ke Portal Bendahara</span>
                      <ArrowRight className="w-4 h-4" />
                    </>
                  )}
                </button>
              </form>

              <div className="mt-6 pt-4 border-t border-slate-200/80 text-center">
                <p className="text-xs text-slate-500">
                  Belum memiliki akun?{' '}
                  <button
                    type="button"
                    onClick={() =>
                      showToast('Silakan hubungi Administrator Sekolah untuk membuat akun Bendahara baru.')
                    }
                    className="font-bold text-blue-600 hover:underline"
                  >
                    Pengajuan Akun
                  </button>
                </p>
              </div>
            </div>
          </div>
        </div>
      </main>

      {/* Footer */}
      <footer className="relative z-10 w-full max-w-7xl mx-auto px-6 py-6 border-t border-slate-200/60 mt-8 text-center text-xs text-slate-500">
        &copy; 2026 <strong className="text-slate-700">RajaKas.ID</strong> — Aplikasi Keuangan Digital Sekolah.
      </footer>

      {/* Modal Bantuan */}
      {isHelpOpen && (
        <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-lg w-full p-6 sm:p-8 shadow-2xl border border-slate-100">
            <div className="flex justify-between items-start mb-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-blue-50 text-blue-600 flex items-center justify-center">
                  <Headphones className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-lg font-bold text-slate-900">Pusat Bantuan Bendahara</h3>
                  <p className="text-xs text-slate-500">Layanan kendala akun &amp; akses sistem</p>
                </div>
              </div>
              <button onClick={() => setIsHelpOpen(false)} className="text-slate-400 hover:text-slate-600">
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-3 text-sm text-slate-600 my-6">
              <div className="p-3 bg-slate-50 rounded-xl border border-slate-100">
                <h5 className="font-bold text-slate-800 text-xs uppercase mb-1 flex items-center gap-1.5">
                  <KeyRound className="w-3.5 h-3.5" /> Lupa Kata Sandi?
                </h5>
                <p className="text-xs">Gunakan tombol "Lupa?" di samping kolom kata sandi untuk memulai reset.</p>
              </div>
              <div className="p-3 bg-slate-50 rounded-xl border border-slate-100">
                <h5 className="font-bold text-slate-800 text-xs uppercase mb-1">Pendaftaran Akun Baru</h5>
                <p className="text-xs">Akun bendahara baru dibuat oleh Administrator Sekolah melalui menu Pengaturan.</p>
              </div>
            </div>

            <button
              type="button"
              onClick={() => setIsHelpOpen(false)}
              className="w-full py-2.5 bg-slate-100 text-slate-700 font-bold rounded-xl text-xs hover:bg-slate-200 transition-colors"
            >
              Tutup Panduan
            </button>
          </div>
        </div>
      )}
    </div>
  );
};
