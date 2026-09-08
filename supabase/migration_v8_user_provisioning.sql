-- RAJAKAS BENDAHARA V8.1 - REPAIR SCHEMA PERIODE
-- Jalankan INI TERLEBIH DAHULU jika V8 gagal dengan:
-- ERROR 42703: column "organization_id" does not exist
-- pada periode_pembukuan.
--
-- Penyebab: periode_pembukuan kemungkinan dibuat SETELAH migration V7,
-- sehingga blok V7 yang menambahkan organization_id belum pernah berjalan.

BEGIN;

-- 1. Pastikan tabel periode memang ada.
DO $$
BEGIN
  IF to_regclass('public.periode_pembukuan') IS NULL THEN
    RAISE EXCEPTION 'TABEL periode_pembukuan BELUM ADA. Jalankan migration_periode_pembukuan.sql atau cutoff_migration.sql terlebih dahulu.';
  END IF;
END $$;

-- 2. Pastikan organization_id ada pada periode.
ALTER TABLE public.periode_pembukuan
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;

-- 3. V8 juga membutuhkan tahun_ajaran pada periode.
ALTER TABLE public.periode_pembukuan
  ADD COLUMN IF NOT EXISTS tahun_ajaran VARCHAR(20);

-- 4. Isi tahun_ajaran dari nama_periode untuk data lama.
UPDATE public.periode_pembukuan
SET tahun_ajaran = COALESCE(NULLIF(tahun_ajaran, ''), nama_periode, '2025/2026')
WHERE tahun_ajaran IS NULL OR tahun_ajaran = '';

-- 5. Pastikan ada organization default untuk data periode lama.
DO $$
DECLARE
  v_org_id UUID;
  v_nama VARCHAR(150);
BEGIN
  SELECT id INTO v_org_id
  FROM public.organizations
  ORDER BY created_at
  LIMIT 1;

  IF v_org_id IS NULL THEN
    SELECT COALESCE(NULLIF(nama_lembaga, ''), 'Lembaga Utama (Migrasi)')
    INTO v_nama
    FROM public.konfigurasi_lembaga
    LIMIT 1;

    INSERT INTO public.organizations (nama)
    VALUES (COALESCE(v_nama, 'Lembaga Utama (Migrasi)'))
    RETURNING id INTO v_org_id;
  END IF;

  UPDATE public.periode_pembukuan
  SET organization_id = v_org_id
  WHERE organization_id IS NULL;
END $$;

-- 6. Data lama sekarang wajib memiliki tenant.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.periode_pembukuan
    WHERE organization_id IS NULL
  ) THEN
    RAISE EXCEPTION 'Masih ada periode_pembukuan tanpa organization_id. Migrasi dihentikan agar data tidak salah tenant.';
  END IF;
END $$;

ALTER TABLE public.periode_pembukuan
  ALTER COLUMN organization_id SET NOT NULL;

-- 7. Hapus constraint/index aktif global dari migration lama.
DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif;
DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif_per_org;

-- 8. Jika ada lebih dari satu periode AKTIF dalam organization yang sama,
-- pertahankan yang tanggal_mulai paling baru dan tutup sisanya.
WITH ranked AS (
  SELECT id,
         ROW_NUMBER() OVER (
           PARTITION BY organization_id
           ORDER BY tanggal_mulai DESC NULLS LAST, created_at DESC NULLS LAST, id DESC
         ) AS rn
  FROM public.periode_pembukuan
  WHERE status = 'AKTIF'
)
UPDATE public.periode_pembukuan p
SET status = 'DITUTUP',
    closed_at = COALESCE(p.closed_at, NOW())
FROM ranked r
WHERE p.id = r.id
  AND r.rn > 1;

-- 9. Satu periode aktif per organization.
CREATE UNIQUE INDEX ux_periode_pembukuan_satu_aktif_per_org
  ON public.periode_pembukuan (organization_id)
  WHERE status = 'AKTIF';

-- 10. Index pencarian tenant.
CREATE INDEX IF NOT EXISTS idx_periode_pembukuan_organization
  ON public.periode_pembukuan (organization_id, tanggal_mulai DESC);

COMMIT;

-- VERIFIKASI
SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'periode_pembukuan'
  AND column_name IN ('organization_id', 'tahun_ajaran')
ORDER BY column_name;

SELECT organization_id, status, COUNT(*) AS jumlah
FROM public.periode_pembukuan
GROUP BY organization_id, status
ORDER BY organization_id, status;
