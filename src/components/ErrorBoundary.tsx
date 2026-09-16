import React from 'react';

/**
 * src/components/ErrorBoundary.tsx
 *
 * Tanpa ini, satu error render (misal fungsi yang lupa di-import) membuat
 * seluruh layar menjadi PUTIH KOSONG tanpa pesan apa pun -- bendahara tidak
 * tahu apa yang terjadi dan mengira datanya hilang.
 *
 * Catatan: error boundary hanya menangkap error saat render/lifecycle.
 * Error di dalam event handler async ditangani lewat showToast di App.tsx.
 */

interface Props {
  children: React.ReactNode;
}

interface State {
  error: Error | null;
}

export class ErrorBoundary extends React.Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: React.ErrorInfo) {
    console.error('[ErrorBoundary]', error, info.componentStack);
  }

  render() {
    const { error } = this.state;
    if (!error) return this.props.children;

    return (
      <div className="flex h-screen w-full items-center justify-center bg-[#FAFAFC] p-6">
        <div className="w-full max-w-md rounded-2xl border border-slate-200 bg-white p-7 text-center shadow-sm">
          <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-amber-50 text-2xl font-bold text-amber-600">
            !
          </div>
          <h1 className="text-base font-bold text-slate-900">Terjadi kesalahan pada tampilan</h1>
          <p className="mt-2 text-xs leading-relaxed text-slate-600">
            Data yang sudah tersimpan di database <strong>tidak terpengaruh</strong>. Muat ulang
            halaman untuk melanjutkan.
          </p>
          <p className="mt-3 break-words rounded-lg bg-slate-50 px-3 py-2 text-[11px] font-mono text-slate-500">
            {error.message}
          </p>
          <button
            type="button"
            onClick={() => window.location.reload()}
            className="mt-5 w-full rounded-xl bg-slate-900 px-4 py-2.5 text-xs font-bold text-white hover:bg-slate-800"
          >
            Muat Ulang Halaman
          </button>
        </div>
      </div>
    );
  }
}
