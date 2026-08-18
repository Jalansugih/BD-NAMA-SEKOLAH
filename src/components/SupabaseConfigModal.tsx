import React, { useState } from 'react';
import { Database, CheckCircle, AlertTriangle, RefreshCw, X, Key, Globe } from 'lucide-react';
import { getSavedSupabaseCredentials, resetSupabaseClient, testSupabaseConnection } from '../lib/supabase';

interface SupabaseConfigModalProps {
  isOpen: boolean;
  onClose: () => void;
  onConfigSaved: () => void;
  showToast: (msg: string) => void;
}

export const SupabaseConfigModal: React.FC<SupabaseConfigModalProps> = ({
  isOpen,
  onClose,
  onConfigSaved,
  showToast
}) => {
  const creds = getSavedSupabaseCredentials();
  const [url, setUrl] = useState(creds.url.includes('xyzcompany') ? '' : creds.url);
  const [anonKey, setAnonKey] = useState(creds.key.includes('dummy_anon_key') ? '' : creds.key);
  const [testing, setTesting] = useState(false);
  const [testResult, setTestResult] = useState<{ success: boolean; message: string } | null>(null);

  if (!isOpen) return null;

  const handleTest = async () => {
    setTesting(true);
    setTestResult(null);
    const res = await testSupabaseConnection(url, anonKey);
    setTestResult(res);
    setTesting(false);
  };

  const handleSave = () => {
    if (!url || !anonKey) {
      showToast('Kredensial disimpan dalam Mode Demo Lokal.');
      resetSupabaseClient('', '');
    } else {
      resetSupabaseClient(url, anonKey);
      showToast('Kredensial Supabase berhasil disimpan!');
    }
    onConfigSaved();
    onClose();
  };

  return (
    <div className="fixed inset-0 bg-slate-900/50 backdrop-blur-sm z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-[14px] max-w-lg w-full shadow-xl border border-slate-200 overflow-hidden animate-in fade-in zoom-in duration-150">
        <div className="p-5 bg-gradient-to-r from-emerald-600 to-emerald-700 text-white flex items-center justify-between">
          <div className="flex items-center gap-2.5">
            <div className="w-8 h-8 rounded-full bg-white/20 flex items-center justify-center">
              <Database className="w-4 h-4 text-white" />
            </div>
            <div>
              <h3 className="font-bold text-sm">Pengaturan Kredensial Supabase</h3>
              <p className="text-[11px] text-emerald-100">Daftar gratis di supabase.com (Region Singapore)</p>
            </div>
          </div>
          <button onClick={onClose} className="text-white/80 hover:text-white p-1">
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="p-6 space-y-4">
          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1 flex items-center gap-1.5">
              <Globe className="w-3.5 h-3.5 text-emerald-600" /> Supabase Project URL
            </label>
            <input 
              type="text" 
              value={url}
              onChange={(e) => setUrl(e.target.value)}
              placeholder="https://your-project-id.supabase.co" 
              className="w-full bg-slate-50 border border-slate-200 rounded-[14px] px-3.5 py-2 text-xs font-mono text-slate-800 outline-none focus:bg-white focus:border-emerald-500"
            />
          </div>

          <div>
            <label className="block text-xs font-semibold text-slate-700 mb-1 flex items-center gap-1.5">
              <Key className="w-3.5 h-3.5 text-emerald-600" /> Anon Public Key
            </label>
            <textarea 
              value={anonKey}
              onChange={(e) => setAnonKey(e.target.value)}
              placeholder="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." 
              rows={3}
              className="w-full bg-slate-50 border border-slate-200 rounded-[14px] p-3 text-[11px] font-mono text-slate-800 outline-none focus:bg-white focus:border-emerald-500"
            />
          </div>

          {testResult && (
            <div className={`p-3 rounded-[14px] text-xs font-medium flex items-start gap-2 ${
              testResult.success 
                ? 'bg-emerald-50 border border-emerald-200 text-emerald-800' 
                : 'bg-rose-50 border border-rose-200 text-rose-800'
            }`}>
              {testResult.success ? <CheckCircle className="w-4 h-4 text-emerald-600 shrink-0 mt-0.5" /> : <AlertTriangle className="w-4 h-4 text-rose-600 shrink-0 mt-0.5" />}
              <span>{testResult.message}</span>
            </div>
          )}

          <div className="pt-2 flex items-center justify-between border-t border-slate-100">
            <button 
              type="button" 
              onClick={handleTest}
              disabled={testing}
              className="px-3.5 py-2 bg-slate-100 hover:bg-slate-200 text-slate-700 rounded-[14px] text-xs font-semibold flex items-center gap-1.5 transition-all"
            >
              <RefreshCw className={`w-3.5 h-3.5 ${testing ? 'animate-spin' : ''}`} />
              <span>{testing ? 'Menguji...' : 'Uji Koneksi'}</span>
            </button>

            <div className="flex items-center gap-2">
              <button 
                type="button" 
                onClick={onClose} 
                className="px-4 py-2 text-xs font-semibold text-slate-600 hover:bg-slate-100 rounded-[14px]"
              >
                Batal
              </button>
              <button 
                type="button" 
                onClick={handleSave}
                className="px-5 py-2 text-xs font-semibold text-white bg-emerald-600 hover:bg-emerald-700 rounded-[14px] shadow-sm transition-all"
              >
                Simpan &amp; Hubungkan
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
};
