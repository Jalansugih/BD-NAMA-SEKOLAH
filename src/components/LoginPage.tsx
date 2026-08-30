import React, { useState } from 'react';
import {
  Wallet, HelpCircle, ShieldCheck, Receipt, Lock, Mail, Eye, EyeOff,
  ArrowRight, Loader2, KeyRound, Headphones, X, AlertTriangle
} from 'lucide-react';
import { UserSession } from '../types';
import { signInWithPassword, signInWithGoogle, resetPasswordForEmail } from '../lib/supabase';

interface LoginPageProps {
  onLoginSuccess: (session: UserSession) => void;
  showToast: (msg: string) => void;
}

/**
 * Halaman login penuh (bukan modal) -- dipakai sebagai "gerbang" utama saat
 * aplikasi terhubung ke Supabase tapi belum ada sesi login. Desain mengikuti
 * mockup HTML yang diberikan (tema biru "brand" + font Plus Jakarta Sans,
 * di-scope lewat class `font-jakarta` supaya tidak mengubah font di halaman
 * lain / layout cetak laporan).
 */
export const LoginPage: React.FC<LoginPageProps> = ({ onLoginSuccess, showToast }) => {
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [showPassword, setShowPassword] = useState(false);
  const [rememberMe, setRememberMe] = useState(false);
  const [loading, setLoading] = useState(false);
  const [googleLoading, setGoogleLoading] = useState(false);
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [fieldErrors, setFieldErrors] = useState<{ email?: string; password?: string }>({});

  const [isHelpOpen, setIsHelpOpen] = useState(false);
  const [isForgotOpen, setIsForgotOpen] = useState(false);
  const [forgotEmail, setForgotEmail] = useState('');
  const [forgotLoading, setForgotLoading] = useState(false);

  const validate = () => {
    const errors: { email?: string; password?: string } = {};
    const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
    if (!email.trim()) errors.email = 'Email wajib diisi.';
    else if (!emailRegex.test(email.trim())) errors.email = 'Format email tidak valid.';
    if (!password) errors.password = 'Kata sandi wajib diisi.';
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
      showToast('Login berhasil! Selamat datang kembali.');
    } catch (err) {
      console.error('[LoginPage] Login error:', err);
      setErrorMsg('Terjadi kendala saat memproses login. Silakan coba lagi.');
      setLoading(false);
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
      // Kalau sukses: browser sedang dialihkan ke Google, biarkan tetap loading.
    } catch (err) {
      console.error('[LoginPage] Google login error:', err);
      setErrorMsg('Terjadi kendala saat memproses login dengan Google. Silakan coba lagi.');
      setGoogleLoading(false);
    }
  };

  const handleForgotSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!forgotEmail.trim() || forgotLoading) return;
    setForgotLoading(true);
    const res = await resetPasswordForEmail(forgotEmail.trim());
    setForgotLoading(false);
    setIsForgotOpen(false);
    setForgotEmail('');
    showToast(
      res.success
        ? 'Tautan pemulihan kata sandi telah dikirim ke email Anda.'
        : (res.message || 'Gagal mengirim tautan pemulihan kata sandi.')
    );
  };

  return (
    <div className="font-jakarta antialiased text-slate-800 bg-slate-50 min-h-screen flex flex-col login-bg-pattern relative overflow-x-hidden selection:bg-brand-500 selection:text-white">
      {/* Dekorasi latar belakang */}
      <div className="fixed top-0 left-0 w-full h-full overflow-hidden pointer-events-none z-0">
        <div className="absolute -top-32 -left-32 w-96 h-96 bg-brand-300/30 rounded-full blur-3xl login-animated-blob" />
        <div className="absolute top-1/3 -right-20 w-80 h-80 bg-cyan-200/40 rounded-full blur-3xl login-animated-blob-delay" />
        <div className="absolute -bottom-20 left-1/3 w-96 h-96 bg-brand-200/30 rounded-full blur-3xl login-animated-blob" />
      </div>

      {/* Header */}
      <header className="relative z-10 w-full max-w-7xl mx-auto px-6 py-5 flex justify-between items-center">
  <div className="flex items-center">
    <img
      src="\logo-rk-bendahara.png"
      alt="Rajakas.id - PT. Putera Raja Madina"
      className="w-[420px] max-w-full h-auto object-contain"
    />
  </div>

        <div className="flex items-center gap-4">
          <button
            type="button"
            onClick={() => setIsHelpOpen(true)}
            className="text-sm font-medium text-slate-600 hover:text-brand-600 transition-colors flex items-center gap-1.5"
          >
            <HelpCircle className="w-4 h-4" />
            <span className="hidden sm:inline">Bantuan &amp; Panduan</span>
          </button>
          <div className="h-4 w-px bg-slate-300 hidden sm:block" />
          <div className="text-xs text-slate-500 font-medium hidden sm:flex items-center gap-1">
            <ShieldCheck className="w-3.5 h-3.5 text-emerald-500" />
            E-Sistem Terenkripsi
          </div>
        </div>
      </header>

      {/* Konten Utama */}
      <main className="relative z-10 flex-1 flex items-center justify-center px-4 py-8">
        <div className="w-full max-w-5xl grid grid-cols-1 lg:grid-cols-12 gap-8 items-center">

          {/* Sisi Kiri: Branding */}
          <div className="lg:col-span-6 space-y-6 text-center lg:text-left px-2 sm:px-6">
            <div className="inline-flex items-center gap-2 px-3 py-1.5 rounded-full bg-brand-100/70 border border-brand-200 text-brand-800 text-xs font-semibold">
              <span className="w-2 h-2 rounded-full bg-brand-500 animate-pulse" />
              Sistem Keuangan Generasi Terbaru
            </div>

            <h1 className="text-3xl sm:text-4xl lg:text-5xl font-extrabold text-slate-900 leading-tight">
              Pengelolaan Kas Sekolah{' '}
              <span className="text-transparent bg-clip-text bg-gradient-to-r from-brand-600 to-cyan-600">Lebih Transparan</span>
            </h1>

            <p className="text-slate-600 text-base sm:text-lg leading-relaxed max-w-xl mx-auto lg:mx-0">
              Selamat datang di Portal Bendahara <strong>rajakas.id</strong>. Akses dasbor pencatatan, verifikasi transaksi, dan pelaporan keuangan terpadu dalam satu tempat.
            </p>

            <div className="grid grid-cols-2 gap-4 pt-2 max-w-lg mx-auto lg:mx-0">
              <div className="flex items-start gap-3 p-3 rounded-xl bg-white/60 border border-slate-200/80 shadow-sm">
                <div className="w-9 h-9 rounded-lg bg-brand-50 flex items-center justify-center text-brand-600 shrink-0 mt-0.5">
                  <Receipt className="w-4 h-4" />
                </div>
                <div>
                  <h4 className="text-sm font-bold text-slate-800">Laporan Otomatis</h4>
                  <p className="text-xs text-slate-500">Penyusunan laporan instan &amp; akurat</p>
                </div>
              </div>

              <div className="flex items-start gap-3 p-3 rounded-xl bg-white/60 border border-slate-200/80 shadow-sm">
                <div className="w-9 h-9 rounded-lg bg-brand-50 flex items-center justify-center text-brand-600 shrink-0 mt-0.5">
                  <Lock className="w-4 h-4" />
                </div>
                <div>
                  <h4 className="text-sm font-bold text-slate-800">Keamanan Tinggi</h4>
                  <p className="text-xs text-slate-500">Enkripsi data tingkat perbankan</p>
                </div>
              </div>
            </div>

            <div className="pt-4 border-t border-slate-200/80 flex items-center justify-center lg:justify-start gap-4 text-xs text-slate-500">
              <div className="flex -space-x-2 overflow-hidden">
                <div className="inline-block h-7 w-7 rounded-full ring-2 ring-white bg-brand-600 text-white flex items-center justify-center text-[10px] font-bold">BD</div>
                <div className="inline-block h-7 w-7 rounded-full ring-2 ring-white bg-cyan-600 text-white flex items-center justify-center text-[10px] font-bold">BK</div>
                <div className="inline-block h-7 w-7 rounded-full ring-2 ring-white bg-slate-700 text-white flex items-center justify-center text-[10px] font-bold">KS</div>
              </div>
              <span>Dipercaya oleh bendahara sekolah untuk pengelolaan kas harian</span>
            </div>
          </div>

          {/* Sisi Kanan: Kartu Login */}
          <div className="lg:col-span-6 flex justify-center">
            <div className="w-full max-w-sm login-glass-card rounded-2xl p-6 sm:p-7 shadow-xl shadow-brand-500/10 border border-brand-100 relative">
              <div className="mb-5">
                <h2 className="text-xl font-bold text-slate-900 mb-1.5">Masuk Portal</h2>
                <p className="text-xs text-slate-500">Silakan masukkan kredensial akun bendahara Anda</p>
              </div>

              <button
                type="button"
                onClick={handleGoogleLogin}
                disabled={googleLoading || loading}
                className="w-full mb-4 py-2.5 px-3.5 bg-white hover:bg-slate-50 text-slate-700 font-semibold rounded-xl border border-slate-200 shadow-sm transition-all duration-200 flex items-center justify-center gap-2.5 text-xs hover:border-brand-500 disabled:opacity-60 disabled:cursor-not-allowed"
              >
                {googleLoading ? (
                  <>
                    <Loader2 className="w-4 h-4 animate-spin motion-reduce:animate-none text-slate-500" />
                    <span>Mengalihkan ke Google...</span>
                  </>
                ) : (
                  <>
                    <svg className="w-4 h-4 shrink-0" viewBox="0 0 24 24" aria-hidden="true">
                      <path fill="#EA4335" d="M12 5c1.6 0 3 .6 4.1 1.6l3.1-3.1C17.3 1.7 14.8 1 12 1 7.5 1 3.7 3.6 1.9 7.3l3.7 2.9C6.5 7.2 9 5 12 5z"/>
                      <path fill="#4285F4" d="M23.5 12.3c0-.8-.1-1.6-.2-2.3H12v4.5h6.5c-.3 1.5-1.1 2.8-2.4 3.7l3.7 2.9c2.2-2 3.7-5 3.7-8.8z"/>
                      <path fill="#FBBC05" d="M5.6 14.8c-.2-.7-.4-1.5-.4-2.3s.2-1.6.4-2.3L1.9 7.3C.7 9.7 0 10.8 0 12s.7 2.3 1.9 4.7l3.7-2.9z"/>
                      <path fill="#34A853" d="M12 23c3.2 0 6-1.1 8-3l-3.7-2.9c-1.1.7-2.5 1.2-4.3 1.2-3 0-5.5-2.2-6.4-5.2L1.9 16C3.7 19.7 7.5 23 12 23z"/>
                    </svg>
                    <span>Masuk dengan Google</span>
                  </>
                )}
              </button>

              <div className="relative flex py-1 items-center mb-4">
                <div className="flex-grow border-t border-slate-200" />
                <span className="flex-shrink mx-2.5 text-[10px] font-semibold text-slate-400 uppercase tracking-wider">atau dengan email</span>
                <div className="flex-grow border-t border-slate-200" />
              </div>

              <form onSubmit={handleLogin} noValidate className="space-y-4">
                <div>
                  <label htmlFor="login-email" className="block text-[11px] font-bold uppercase tracking-wider text-slate-700 mb-1.5">
                    Email
                  </label>
                  <div className="relative rounded-xl shadow-sm">
                    <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-slate-400">
                      <Mail className="w-3.5 h-3.5" />
                    </div>
                    <input
                      id="login-email"
                      type="email"
                      autoComplete="email"
                      value={email}
                      onChange={(e) => {
                        setEmail(e.target.value);
                        if (fieldErrors.email) setFieldErrors((p) => ({ ...p, email: undefined }));
                      }}
                      placeholder="bendahara@sekolah.sch.id"
                      aria-invalid={!!fieldErrors.email}
                      aria-describedby={fieldErrors.email ? 'login-email-error' : undefined}
                      className={`block w-full pl-9 pr-3.5 py-2.5 bg-white border rounded-xl text-slate-800 placeholder-slate-400
                                 focus:outline-none focus:ring-2 transition-all text-xs font-medium
                                 ${fieldErrors.email ? 'border-rose-300 focus:ring-rose-400 focus:border-rose-400' : 'border-slate-200 focus:ring-brand-500 focus:border-brand-500'}`}
                    />
                  </div>
                  {fieldErrors.email && (
                    <p id="login-email-error" className="mt-1 text-[11px] text-rose-600">{fieldErrors.email}</p>
                  )}
                </div>

                <div>
                  <div className="flex justify-between items-center mb-1.5">
                    <label htmlFor="login-password" className="block text-[11px] font-bold uppercase tracking-wider text-slate-700">
                      Kata Sandi
                    </label>
                    <button
                      type="button"
                      onClick={() => { setForgotEmail(email); setIsForgotOpen(true); }}
                      className="text-xs font-semibold text-brand-600 hover:underline transition-colors"
                    >
                      Lupa?
                    </button>
                  </div>
                  <div className="relative rounded-xl shadow-sm">
                    <div className="absolute inset-y-0 left-0 pl-3 flex items-center pointer-events-none text-slate-400">
                      <Lock className="w-3.5 h-3.5" />
                    </div>
                    <input
                      id="login-password"
                      type={showPassword ? 'text' : 'password'}
                      autoComplete="current-password"
                      value={password}
                      onChange={(e) => {
                        setPassword(e.target.value);
                        if (fieldErrors.password) setFieldErrors((p) => ({ ...p, password: undefined }));
                      }}
                      placeholder="••••••••••••"
                      aria-invalid={!!fieldErrors.password}
                      aria-describedby={fieldErrors.password ? 'login-password-error' : undefined}
                      className={`block w-full pl-9 pr-10 py-2.5 bg-white border rounded-xl text-slate-800 placeholder-slate-400
                                 focus:outline-none focus:ring-2 transition-all text-xs font-medium
                                 ${fieldErrors.password ? 'border-rose-300 focus:ring-rose-400 focus:border-rose-400' : 'border-slate-200 focus:ring-brand-500 focus:border-brand-500'}`}
                    />
                    <button
                      type="button"
                      onClick={() => setShowPassword((v) => !v)}
                      aria-label={showPassword ? 'Sembunyikan kata sandi' : 'Tampilkan kata sandi'}
                      className="absolute inset-y-0 right-0 pr-3 flex items-center text-slate-400 hover:text-slate-600 focus:outline-none"
                    >
                      {showPassword ? <EyeOff className="w-3.5 h-3.5" /> : <Eye className="w-3.5 h-3.5" />}
                    </button>
                  </div>
                  {fieldErrors.password && (
                    <p id="login-password-error" className="mt-1 text-[11px] text-rose-600">{fieldErrors.password}</p>
                  )}
                </div>

                <div className="flex items-center justify-between pt-0.5">
                  <label className="flex items-center cursor-pointer">
                    <input
                      type="checkbox"
                      checked={rememberMe}
                      onChange={(e) => setRememberMe(e.target.checked)}
                      className="w-3.5 h-3.5 text-brand-600 bg-slate-100 border-slate-300 rounded focus:ring-brand-500 focus:ring-2 cursor-pointer"
                    />
                    <span className="ml-2 text-xs font-medium text-slate-600">Ingat sesi saya</span>
                  </label>
                </div>

                {errorMsg && (
                  <div className="p-3 bg-rose-50 border border-rose-200 rounded-xl text-[11px] text-rose-800 flex items-start gap-2">
                    <AlertTriangle className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />
                    <span>{errorMsg}</span>
                  </div>
                )}

                <button
                  type="submit"
                  disabled={loading}
                  className="w-full py-2.5 px-4 bg-brand-500 hover:bg-brand-600 text-white font-bold rounded-xl shadow-md shadow-brand-500/30
                             hover:shadow-brand-500/40 focus:outline-none focus:ring-2 focus:ring-brand-500 focus:ring-offset-2
                             transition-all transform active:scale-[0.99] flex items-center justify-center gap-2 text-xs mt-1
                             disabled:opacity-70 disabled:cursor-not-allowed"
                >
                  {loading ? (
                    <>
                      <span>Verifikasi Kredensial...</span>
                      <Loader2 className="w-3.5 h-3.5 animate-spin motion-reduce:animate-none" />
                    </>
                  ) : (
                    <>
                      <span>Masuk ke Portal Bendahara</span>
                      <ArrowRight className="w-3.5 h-3.5" />
                    </>
                  )}
                </button>
              </form>

              <div className="mt-6 pt-4 border-t border-slate-200/80 text-center">
                <p className="text-xs text-slate-500">
                  Belum memiliki akun?{' '}
                  <button
                    type="button"
                    onClick={() => showToast('Silakan hubungi Administrator Sekolah untuk membuat akun Bendahara baru.')}
                    className="font-bold text-brand-600 hover:underline"
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
      <footer className="relative z-10 w-full max-w-7xl mx-auto px-6 py-6 border-t border-slate-200/60 mt-8 flex flex-col sm:flex-row justify-between items-center gap-4 text-xs text-slate-500">
        <div>
          © 2026 <strong className="text-slate-700">rajakas.id</strong> — Hak Cipta Dilindungi. Sistem Keuangan Sekolah.
        </div>
        <div className="flex items-center gap-2 text-slate-400">
          <ShieldCheck className="w-3.5 h-3.5" />
          Portal Bendahara Digital
        </div>
      </footer>

      {/* MODAL LUPA KATA SANDI */}
      {isForgotOpen && (
        <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-md w-full p-6 sm:p-8 shadow-2xl border border-slate-100">
            <div className="w-12 h-12 bg-brand-100 text-brand-600 rounded-2xl flex items-center justify-center mb-4">
              <KeyRound className="w-5 h-5" />
            </div>
            <h3 className="text-xl font-bold text-slate-900 mb-2">Reset Kata Sandi Portal</h3>
            <p className="text-sm text-slate-500 mb-6">
              Masukkan email bendahara terdaftar. Kami akan mengirimkan tautan pemulihan kata sandi.
            </p>
            <form onSubmit={handleForgotSubmit} className="space-y-4">
              <div>
                <label className="block text-xs font-bold uppercase text-slate-700 mb-1">Email Terdaftar</label>
                <input
                  type="email"
                  required
                  value={forgotEmail}
                  onChange={(e) => setForgotEmail(e.target.value)}
                  placeholder="bendahara@sekolah.sch.id"
                  className="w-full px-4 py-2.5 border border-slate-200 rounded-xl text-sm focus:ring-2 focus:ring-brand-500 focus:outline-none"
                />
              </div>
              <div className="flex items-center gap-3 pt-2">
                <button
                  type="button"
                  onClick={() => setIsForgotOpen(false)}
                  className="flex-1 py-2.5 px-4 border border-slate-200 rounded-xl text-xs font-bold text-slate-600 hover:bg-slate-50 transition-colors"
                >
                  Batal
                </button>
                <button
                  type="submit"
                  disabled={forgotLoading}
                  className="flex-1 py-2.5 px-4 bg-brand-600 text-white rounded-xl text-xs font-bold hover:bg-brand-700 transition-colors shadow-md shadow-brand-600/20 disabled:opacity-70"
                >
                  {forgotLoading ? 'Mengirim...' : 'Kirim Tautan'}
                </button>
              </div>
            </form>
          </div>
        </div>
      )}

      {/* MODAL BANTUAN */}
      {isHelpOpen && (
        <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <div className="bg-white rounded-2xl max-w-lg w-full p-6 sm:p-8 shadow-2xl border border-slate-100">
            <div className="flex justify-between items-start mb-4">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-brand-50 text-brand-600 flex items-center justify-center">
                  <Headphones className="w-5 h-5" />
                </div>
                <div>
                  <h3 className="text-lg font-bold text-slate-900">Pusat Bantuan Bendahara</h3>
                  <p className="text-xs text-slate-500">Layanan kendala akun &amp; akses sistem</p>
                </div>
              </div>
              <button onClick={() => setIsHelpOpen(false)} aria-label="Tutup" className="text-slate-400 hover:text-slate-600">
                <X className="w-5 h-5" />
              </button>
            </div>

            <div className="space-y-3 text-sm text-slate-600 my-6">
              <div className="p-3 bg-slate-50 rounded-xl border border-slate-100">
                <h5 className="font-bold text-slate-800 text-xs uppercase mb-1">Gagal Login?</h5>
                <p className="text-xs">Pastikan email dan kata sandi sudah benar. Gunakan menu "Lupa?" jika kata sandi tidak diingat.</p>
              </div>
              <div className="p-3 bg-slate-50 rounded-xl border border-slate-100">
                <h5 className="font-bold text-slate-800 text-xs uppercase mb-1">Pendaftaran Akun Baru</h5>
                <p className="text-xs">Pendaftaran bendahara baru dilakukan oleh Administrator Sekolah melalui menu Pengaturan.</p>
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
