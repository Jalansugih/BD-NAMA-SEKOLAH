import { config as loadEnv } from 'dotenv';
import { existsSync } from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const rootDir = path.resolve(__dirname, '..');

// Node does NOT auto-load .env.local the way Vite does — this script runs
// as a plain "node scripts/check-env.mjs" prebuild step, so we load it here.
const isVercel = process.env.VERCEL === '1';

if (!isVercel) {
  for (const file of ['.env.local', '.env']) {
    const filePath = path.join(rootDir, file);
    if (existsSync(filePath)) {
      loadEnv({ path: filePath, override: false });
    }
  }
}

const url = (process.env.VITE_SUPABASE_URL || '').trim();
const key = (process.env.VITE_SUPABASE_ANON_KEY || '').trim();

if (!url || !key) {
  console.error('\n[production-check] Missing VITE_SUPABASE_URL or VITE_SUPABASE_ANON_KEY.');
  console.error('Set them in .env.local for local builds or Vercel Environment Variables for deployment.\n');
  process.exit(1);
}

if (!/^https:\/\/[^\s/]+(?:\.[^\s/]+)+/i.test(url)) {
  console.error('[production-check] VITE_SUPABASE_URL is not a valid HTTPS Supabase URL.');
  process.exit(1);
}

if (key.includes('dummy') || key.includes('placeholder')) {
  console.error('[production-check] VITE_SUPABASE_ANON_KEY appears to be a placeholder.');
  process.exit(1);
}

console.log(`[production-check] Supabase environment OK${isVercel ? ' (Vercel)' : ''}.`);
