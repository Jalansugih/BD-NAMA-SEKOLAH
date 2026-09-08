-- ============================================================================
-- RAJAKAS BENDAHARA - FINAL PRODUCTION PATCH
--
-- Jalankan SETELAH migration.sql + migration_periode_pembukuan.sql (bila
-- belum ada) + cutoff_migration.sql + migration_v6_multi_tenant.sql +
-- migration_v7_multi_tenant.sql.
--
-- PATCH INI TIDAK DROP DATA TRANSAKSI.
-- ============================================================================

BEGIN;

-- 1) Pastikan periode benar-benar tenant-scoped.
DO $$
BEGIN
  IF to_regclass('public.periode_pembukuan') IS NOT NULL THEN
    ALTER TABLE public.periode_pembukuan
      ADD COLUMN IF NOT EXISTS organization_id UUID
      REFERENCES public.organizations(id) ON DELETE CASCADE;

    -- Hanya aman jika project sudah selesai menjalankan backfill V7.
    IF EXISTS (
      SELECT 1 FROM public.periode_pembukuan
      WHERE organization_id IS NULL
    ) THEN
      RAISE EXCEPTION 'MASIH_ADA_PERIODE_TANPA_ORGANIZATION_ID: jalankan migration_v7_multi_tenant.sql terlebih dahulu';
    END IF;

    ALTER TABLE public.periode_pembukuan
      ALTER COLUMN organization_id SET NOT NULL;

    DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif;
    DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif_per_org;
    CREATE UNIQUE INDEX ux_periode_pembukuan_satu_aktif_per_org
      ON public.periode_pembukuan (organization_id)
      WHERE status = 'AKTIF';

    ALTER TABLE public.periode_pembukuan ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "Periode pembukuan - user login" ON public.periode_pembukuan;
    DROP POLICY IF EXISTS "Tenant - periode_pembukuan" ON public.periode_pembukuan;
    CREATE POLICY "Tenant - periode_pembukuan" ON public.periode_pembukuan
      FOR ALL
      USING (organization_id = public.get_auth_org_id())
      WITH CHECK (organization_id = public.get_auth_org_id());
  END IF;
END $$;

-- 2) Frontend lama memanggil buka_kembali_buku(). Pertahankan kompatibilitas
--    dengan alias ke fungsi canonical buka_kembali_periode().
CREATE OR REPLACE FUNCTION public.buka_kembali_buku(p_periode_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  PERFORM public.buka_kembali_periode(p_periode_id);
END;
$$;

REVOKE ALL ON FUNCTION public.buka_kembali_buku(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.buka_kembali_buku(UUID) TO authenticated;

-- 3) Harden search_path untuk function tenant helper.
ALTER FUNCTION public.get_auth_org_id() SET search_path = public;

COMMIT;

-- ============================================================================
-- VERIFIKASI MANUAL SETELAH RUN
-- ============================================================================
-- SELECT id, nama, created_at FROM public.organizations ORDER BY created_at;
-- SELECT id, organization_id, nama_periode, status FROM public.periode_pembukuan ORDER BY tanggal_mulai;
-- SELECT indexname, indexdef FROM pg_indexes WHERE tablename='periode_pembukuan';
-- SELECT proname, prosrc FROM pg_proc WHERE proname IN ('tutup_buku','buka_kembali_periode','buka_kembali_buku','catat_pengeluaran');
