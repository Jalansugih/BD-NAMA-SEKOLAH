-- ============================================================================
-- RAJAKAS BENDAHARA - FINAL PRODUCTION FIX V8
--
-- TUJUAN:
-- 1. Memperbaiki migrasi V6 yang gagal karena view saldo_kas bergantung pada
--    konfigurasi_lembaga.id.
-- 2. Memperbaiki migrasi V7 yang gagal karena trigger transaksi berjalan saat
--    backfill tanpa sesi auth.
-- 3. Menormalkan fungsi periode dan kompatibilitas RPC buka_kembali_buku.
-- 4. Menjadikan periode aktif unik PER ORGANISASI, bukan global.
-- 5. Menjadikan saldo_kas tenant-aware.
--
-- PENTING:
-- - Jalankan script ini SEBAGAI SATU SCRIPT di Supabase SQL Editor.
-- - JANGAN jalankan migration_v6_multi_tenant.sql atau migration_v7_multi_tenant.sql
--   lagi setelah script ini berhasil.
-- - Script ini TIDAK DROP TABLE dan TIDAK menghapus transaksi.
-- - Sebelum production, backup database terlebih dahulu.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. TENANT + PROFILE
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organizations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nama VARCHAR(150) NOT NULL DEFAULT 'Lembaga Baru',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  email VARCHAR(255),
  role VARCHAR(20) NOT NULL DEFAULT 'owner'
    CHECK (role IN ('owner','bendahara','viewer')),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.get_auth_org_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.organization_id
  FROM public.profiles p
  WHERE p.id = auth.uid()
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_auth_org_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_auth_org_id() TO authenticated;

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Organizations - anggota lembaga sendiri" ON public.organizations;
DROP POLICY IF EXISTS "Organizations - baca tenant sendiri" ON public.organizations;
DROP POLICY IF EXISTS "Organizations - ubah tenant sendiri" ON public.organizations;
CREATE POLICY "Organizations - baca tenant sendiri" ON public.organizations
  FOR SELECT USING (id = public.get_auth_org_id());
CREATE POLICY "Organizations - ubah tenant sendiri" ON public.organizations
  FOR UPDATE USING (id = public.get_auth_org_id())
  WITH CHECK (id = public.get_auth_org_id());

DROP POLICY IF EXISTS "Profiles - baca sesama anggota lembaga" ON public.profiles;
DROP POLICY IF EXISTS "Profiles - update profil sendiri" ON public.profiles;
DROP POLICY IF EXISTS "Profiles - insert profil sendiri" ON public.profiles;
CREATE POLICY "Profiles - baca sesama anggota lembaga" ON public.profiles
  FOR SELECT USING (id = auth.uid() OR organization_id = public.get_auth_org_id());
CREATE POLICY "Profiles - update profil sendiri" ON public.profiles
  FOR UPDATE USING (id = auth.uid())
  WITH CHECK (id = auth.uid() AND organization_id = public.get_auth_org_id());

GRANT SELECT, UPDATE ON public.organizations TO authenticated;
GRANT SELECT, UPDATE ON public.profiles TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. TAMBAHKAN organization_id TANPA DEFAULT DULU.
--    Default baru dipasang SETELAH backfill selesai agar trigger tidak mencari
--    tenant ketika SQL Editor tidak memiliki auth.uid().
-- ---------------------------------------------------------------------------
ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.audit_log
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.master_sumber_dana
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.master_kategori
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.master_kelas
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.siswa_tagihan
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.pemasukan
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.pengeluaran
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;

DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='periode_pembukuan') THEN
    ALTER TABLE public.periode_pembukuan
      ADD COLUMN IF NOT EXISTS organization_id UUID
      REFERENCES public.organizations(id) ON DELETE CASCADE;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 3. VIEW LAMA HARUS DILEPAS SEBELUM konfigurasi_lembaga.id DIHAPUS.
--    Ini langsung memperbaiki ERROR 2BP01 yang Anda dapatkan.
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS public.saldo_kas;

-- ---------------------------------------------------------------------------
-- 4. BACKFILL TANPA MENJALANKAN TRIGGER TRANSAKSI.
--    Error V7 TENANT_TIDAK_DITEMUKAN terjadi karena UPDATE pengeluaran/pemasukan
--    memicu trigger yang memanggil get_auth_org_id(), sementara SQL Editor tidak
--    punya auth.uid(). Trigger dinonaktifkan sementara hanya selama backfill.
-- ---------------------------------------------------------------------------
ALTER TABLE public.konfigurasi_lembaga DISABLE TRIGGER USER;
ALTER TABLE public.audit_log DISABLE TRIGGER USER;
ALTER TABLE public.master_sumber_dana DISABLE TRIGGER USER;
ALTER TABLE public.master_kategori DISABLE TRIGGER USER;
ALTER TABLE public.master_kelas DISABLE TRIGGER USER;
ALTER TABLE public.siswa_tagihan DISABLE TRIGGER USER;
ALTER TABLE public.pemasukan DISABLE TRIGGER USER;
ALTER TABLE public.pengeluaran DISABLE TRIGGER USER;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='periode_pembukuan') THEN
    ALTER TABLE public.periode_pembukuan DISABLE TRIGGER USER;
  END IF;
END $$;

DO $$
DECLARE
  v_org_id UUID;
  v_nama TEXT;
BEGIN
  SELECT id INTO v_org_id
  FROM public.organizations
  ORDER BY created_at, id
  LIMIT 1;

  IF v_org_id IS NULL THEN
    SELECT COALESCE(NULLIF(nama_lembaga,''),'Lembaga Utama (Migrasi)')
      INTO v_nama
    FROM public.konfigurasi_lembaga
    LIMIT 1;

    INSERT INTO public.organizations(nama)
    VALUES (COALESCE(v_nama,'Lembaga Utama (Migrasi)'))
    RETURNING id INTO v_org_id;
  END IF;

  UPDATE public.konfigurasi_lembaga
     SET organization_id = v_org_id
   WHERE organization_id IS NULL;
  UPDATE public.audit_log SET organization_id=v_org_id WHERE organization_id IS NULL;
  UPDATE public.master_sumber_dana SET organization_id=v_org_id WHERE organization_id IS NULL;
  UPDATE public.master_kategori SET organization_id=v_org_id WHERE organization_id IS NULL;
  UPDATE public.master_kelas SET organization_id=v_org_id WHERE organization_id IS NULL;
  UPDATE public.siswa_tagihan SET organization_id=v_org_id WHERE organization_id IS NULL;
  UPDATE public.pemasukan SET organization_id=v_org_id WHERE organization_id IS NULL;
  UPDATE public.pengeluaran SET organization_id=v_org_id WHERE organization_id IS NULL;

  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='periode_pembukuan') THEN
    UPDATE public.periode_pembukuan SET organization_id=v_org_id WHERE organization_id IS NULL;
  END IF;

  -- User lama -> tenant lama/default.
  INSERT INTO public.profiles(id, organization_id, email, role)
  SELECT u.id, v_org_id, u.email, 'owner'
  FROM auth.users u
  WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id=u.id)
  ON CONFLICT (id) DO NOTHING;
END $$;

ALTER TABLE public.konfigurasi_lembaga ENABLE TRIGGER USER;
ALTER TABLE public.audit_log ENABLE TRIGGER USER;
ALTER TABLE public.master_sumber_dana ENABLE TRIGGER USER;
ALTER TABLE public.master_kategori ENABLE TRIGGER USER;
ALTER TABLE public.master_kelas ENABLE TRIGGER USER;
ALTER TABLE public.siswa_tagihan ENABLE TRIGGER USER;
ALTER TABLE public.pemasukan ENABLE TRIGGER USER;
ALTER TABLE public.pengeluaran ENABLE TRIGGER USER;
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='periode_pembukuan') THEN
    ALTER TABLE public.periode_pembukuan ENABLE TRIGGER USER;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 5. NORMALISASI konfigurasi_lembaga.
--    id lama dihapus SETELAH view saldo_kas dilepas.
-- ---------------------------------------------------------------------------
ALTER TABLE public.konfigurasi_lembaga
  DROP CONSTRAINT IF EXISTS konfigurasi_lembaga_pkey;
ALTER TABLE public.konfigurasi_lembaga
  DROP COLUMN IF EXISTS id;
ALTER TABLE public.konfigurasi_lembaga
  ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.konfigurasi_lembaga
  ADD CONSTRAINT konfigurasi_lembaga_pkey PRIMARY KEY (organization_id);

-- ---------------------------------------------------------------------------
-- 6. MASTER PK COMPOSITE PER TENANT
-- ---------------------------------------------------------------------------
ALTER TABLE public.master_kelas DROP CONSTRAINT IF EXISTS master_kelas_pkey;
ALTER TABLE public.master_kelas ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.master_kelas
  ADD CONSTRAINT master_kelas_pkey PRIMARY KEY (organization_id,nama);

ALTER TABLE public.master_kategori DROP CONSTRAINT IF EXISTS master_kategori_pkey;
ALTER TABLE public.master_kategori ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.master_kategori
  ADD CONSTRAINT master_kategori_pkey PRIMARY KEY (organization_id,nama);

ALTER TABLE public.audit_log ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.master_sumber_dana ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.siswa_tagihan ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.pemasukan ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.pengeluaran ALTER COLUMN organization_id SET NOT NULL;

-- ---------------------------------------------------------------------------
-- 7. PERIODE PER TENANT
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables
             WHERE table_schema='public' AND table_name='periode_pembukuan') THEN
    ALTER TABLE public.periode_pembukuan ALTER COLUMN organization_id SET NOT NULL;
    DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif;
    DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif_per_org;
    CREATE UNIQUE INDEX IF NOT EXISTS ux_periode_pembukuan_satu_aktif_per_org
      ON public.periode_pembukuan(organization_id)
      WHERE status='AKTIF';
    ALTER TABLE public.periode_pembukuan ENABLE ROW LEVEL SECURITY;
    DROP POLICY IF EXISTS "Periode pembukuan - user login" ON public.periode_pembukuan;
    DROP POLICY IF EXISTS "Periode pembukuan - anggota lembaga sendiri" ON public.periode_pembukuan;
    DROP POLICY IF EXISTS "Tenant - periode_pembukuan" ON public.periode_pembukuan;
    CREATE POLICY "Tenant - periode_pembukuan" ON public.periode_pembukuan
      FOR ALL USING (organization_id=public.get_auth_org_id())
      WITH CHECK (organization_id=public.get_auth_org_id());
    GRANT SELECT,INSERT,UPDATE,DELETE ON public.periode_pembukuan TO authenticated;
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 8. DEFAULT tenant untuk INSERT frontend setelah login.
-- ---------------------------------------------------------------------------
ALTER TABLE public.audit_log
  ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.master_sumber_dana
  ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.master_kategori
  ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.master_kelas
  ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.siswa_tagihan
  ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.pemasukan
  ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.pengeluaran
  ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();

-- ---------------------------------------------------------------------------
-- 9. RLS DATA
-- ---------------------------------------------------------------------------
ALTER TABLE public.konfigurasi_lembaga ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_sumber_dana ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_kategori ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_kelas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.siswa_tagihan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pemasukan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pengeluaran ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'audit_log','master_sumber_dana','master_kategori','master_kelas',
    'siswa_tagihan','pemasukan','pengeluaran','konfigurasi_lembaga'
  ] LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'Hanya user login - '||t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'Tenant - '||t, t);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL USING (organization_id=public.get_auth_org_id()) WITH CHECK (organization_id=public.get_auth_org_id())',
      'Tenant - '||t, t
    );
  END LOOP;
END $$;

GRANT SELECT,INSERT,UPDATE,DELETE ON
  public.audit_log, public.master_sumber_dana, public.master_kategori,
  public.master_kelas, public.siswa_tagihan, public.pemasukan,
  public.pengeluaran, public.konfigurasi_lembaga
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 10. FUNGSI PERIODE: DROP DULU UNTUK MENGHINDARI ERROR 42P13.
-- ---------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.hitung_saldo_akhir_periode(UUID,DATE);
DROP FUNCTION IF EXISTS public.tutup_buku(UUID,DATE);
DROP FUNCTION IF EXISTS public.buka_kembali_periode(UUID);
DROP FUNCTION IF EXISTS public.buka_kembali_buku(UUID);

CREATE FUNCTION public.hitung_saldo_akhir_periode(
  p_periode_id UUID,
  p_tanggal_cutoff DATE DEFAULT NULL
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_org UUID := public.get_auth_org_id();
  v_p RECORD;
  v_cutoff DATE;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'TENANT_TIDAK_DITEMUKAN'; END IF;
  SELECT * INTO v_p FROM public.periode_pembukuan
   WHERE id=p_periode_id AND organization_id=v_org;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERIODE_TIDAK_DITEMUKAN'; END IF;
  v_cutoff:=COALESCE(p_tanggal_cutoff,v_p.tanggal_akhir,CURRENT_DATE);
  IF v_cutoff<v_p.tanggal_mulai THEN RAISE EXCEPTION 'TANGGAL_CUTOFF_INVALID'; END IF;
  RETURN COALESCE(v_p.saldo_awal,0)
    + COALESCE((SELECT SUM(nominal) FROM public.pemasukan
                WHERE organization_id=v_org AND tanggal BETWEEN v_p.tanggal_mulai AND v_cutoff),0)
    - COALESCE((SELECT SUM(nominal) FROM public.pengeluaran
                WHERE organization_id=v_org AND tanggal BETWEEN v_p.tanggal_mulai AND v_cutoff),0);
END;
$$;

CREATE FUNCTION public.tutup_buku(p_periode_id UUID,p_tanggal_cutoff DATE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_org UUID:=public.get_auth_org_id();
  v_p RECORD;
  v_saldo NUMERIC;
  v_next_year TEXT;
  v_next RECORD;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'TENANT_TIDAK_DITEMUKAN'; END IF;
  SELECT * INTO v_p FROM public.periode_pembukuan
   WHERE id=p_periode_id AND organization_id=v_org FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERIODE_TIDAK_DITEMUKAN'; END IF;
  IF v_p.status<>'AKTIF' THEN RAISE EXCEPTION 'PERIODE_SUDAH_DITUTUP'; END IF;
  IF p_tanggal_cutoff<v_p.tanggal_mulai THEN RAISE EXCEPTION 'TANGGAL_CUTOFF_INVALID'; END IF;
  v_saldo:=public.hitung_saldo_akhir_periode(p_periode_id,p_tanggal_cutoff);
  UPDATE public.periode_pembukuan
    SET status='DITUTUP',tanggal_akhir=p_tanggal_cutoff,saldo_akhir=v_saldo,
        closed_at=NOW(),closed_by=auth.uid()
    WHERE id=p_periode_id AND organization_id=v_org;
  IF v_p.tahun_ajaran ~ '^[0-9]{4}/[0-9]{4}$' THEN
    v_next_year:=(split_part(v_p.tahun_ajaran,'/',1)::INT+1)::TEXT||'/'||
                 (split_part(v_p.tahun_ajaran,'/',2)::INT+1)::TEXT;
  ELSE
    v_next_year:=v_p.tahun_ajaran;
  END IF;
  INSERT INTO public.periode_pembukuan
    (organization_id,nama_periode,tahun_ajaran,tanggal_mulai,tanggal_akhir,saldo_awal,saldo_akhir,status,created_by)
  VALUES (v_org,v_next_year,v_next_year,p_tanggal_cutoff+1,NULL,v_saldo,NULL,'AKTIF',auth.uid())
  RETURNING * INTO v_next;
  UPDATE public.konfigurasi_lembaga
    SET saldo_awal=v_saldo,tahun_ajaran=v_next_year,updated_at=NOW(),updated_by=auth.uid()
    WHERE organization_id=v_org;
  RETURN jsonb_build_object('saldo_akhir',v_saldo,'periode_berikutnya',row_to_json(v_next)::jsonb);
END;
$$;

CREATE FUNCTION public.buka_kembali_periode(p_periode_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_org UUID:=public.get_auth_org_id();
  v_closed RECORD;
  v_active RECORD;
  v_tx_count BIGINT;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'TENANT_TIDAK_DITEMUKAN'; END IF;
  SELECT * INTO v_closed FROM public.periode_pembukuan
   WHERE id=p_periode_id AND organization_id=v_org AND status='DITUTUP' FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERIODE_TERTUTUP_TIDAK_DITEMUKAN'; END IF;
  SELECT * INTO v_active FROM public.periode_pembukuan
   WHERE organization_id=v_org AND status='AKTIF'
   ORDER BY tanggal_mulai DESC LIMIT 1 FOR UPDATE;
  IF v_active.id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_tx_count FROM (
      SELECT id FROM public.pemasukan WHERE organization_id=v_org AND tanggal>=v_active.tanggal_mulai
      UNION ALL
      SELECT id FROM public.pengeluaran WHERE organization_id=v_org AND tanggal>=v_active.tanggal_mulai
    ) q;
    IF v_tx_count>0 THEN RAISE EXCEPTION 'PERIODE_BERIKUTNYA_SUDAH_MEMILIKI_TRANSAKSI'; END IF;
    DELETE FROM public.periode_pembukuan WHERE id=v_active.id AND organization_id=v_org;
  END IF;
  UPDATE public.periode_pembukuan
    SET status='AKTIF',tanggal_akhir=NULL,saldo_akhir=NULL,closed_at=NULL,closed_by=NULL
    WHERE id=p_periode_id AND organization_id=v_org;
  UPDATE public.konfigurasi_lembaga
    SET saldo_awal=v_closed.saldo_awal,tahun_ajaran=v_closed.tahun_ajaran,
        updated_at=NOW(),updated_by=auth.uid()
    WHERE organization_id=v_org;
END;
$$;

-- Kompatibilitas dengan frontend lama yang memanggil buka_kembali_buku().
CREATE FUNCTION public.buka_kembali_buku(p_periode_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
BEGIN
  PERFORM public.buka_kembali_periode(p_periode_id);
  RETURN jsonb_build_object('success',true,'periode_id',p_periode_id);
END;
$$;

GRANT EXECUTE ON FUNCTION public.hitung_saldo_akhir_periode(UUID,DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tutup_buku(UUID,DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.buka_kembali_periode(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.buka_kembali_buku(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.hitung_saldo_akhir_periode(UUID,DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tutup_buku(UUID,DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.buka_kembali_periode(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.buka_kembali_buku(UUID) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- 11. VIEW SALDO TENANT-AWARE.
-- ---------------------------------------------------------------------------
CREATE VIEW public.saldo_kas
WITH (security_invoker=true)
AS
SELECT
  COALESCE((SELECT saldo_awal FROM public.konfigurasi_lembaga
            WHERE organization_id=public.get_auth_org_id()),0)
  + COALESCE((SELECT SUM(nominal) FROM public.pemasukan
              WHERE organization_id=public.get_auth_org_id()),0)
  - COALESCE((SELECT SUM(nominal) FROM public.pengeluaran
              WHERE organization_id=public.get_auth_org_id()),0)
  AS total_saldo_kas;

GRANT SELECT ON public.saldo_kas TO authenticated;

-- ---------------------------------------------------------------------------
-- 12. AUTO PROVISION USER BARU
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user_multi_tenant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path=public
AS $$
DECLARE
  v_org UUID;
  v_nama TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id=NEW.id) THEN RETURN NEW; END IF;
  v_nama:=COALESCE(NULLIF(NEW.raw_user_meta_data->>'nama_lembaga',''),
                   NULLIF(NEW.raw_user_meta_data->>'full_name',''),
                   'Lembaga Baru');
  INSERT INTO public.organizations(nama) VALUES(v_nama) RETURNING id INTO v_org;
  INSERT INTO public.profiles(id,organization_id,email,role)
  VALUES(NEW.id,v_org,NEW.email,'owner');
  INSERT INTO public.konfigurasi_lembaga(organization_id,nama_lembaga,tahun_ajaran,saldo_awal)
  VALUES(v_org,v_nama,'2025/2026',0)
  ON CONFLICT (organization_id) DO NOTHING;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_multi_tenant ON auth.users;
CREATE TRIGGER on_auth_user_created_multi_tenant
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_multi_tenant();

-- ---------------------------------------------------------------------------
-- 13. HASIL AKHIR: sanity check. Jika ada NULL tenant, script gagal sekarang,
--    bukan nanti saat aplikasi sudah production.
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_nulls BIGINT:=0;
BEGIN
  SELECT COUNT(*) INTO v_nulls FROM (
    SELECT organization_id FROM public.konfigurasi_lembaga WHERE organization_id IS NULL
    UNION ALL SELECT organization_id FROM public.audit_log WHERE organization_id IS NULL
    UNION ALL SELECT organization_id FROM public.master_sumber_dana WHERE organization_id IS NULL
    UNION ALL SELECT organization_id FROM public.master_kategori WHERE organization_id IS NULL
    UNION ALL SELECT organization_id FROM public.master_kelas WHERE organization_id IS NULL
    UNION ALL SELECT organization_id FROM public.siswa_tagihan WHERE organization_id IS NULL
    UNION ALL SELECT organization_id FROM public.pemasukan WHERE organization_id IS NULL
    UNION ALL SELECT organization_id FROM public.pengeluaran WHERE organization_id IS NULL
  ) q;
  IF v_nulls>0 THEN
    RAISE EXCEPTION 'MIGRASI_GAGAL: masih ada % baris tanpa organization_id',v_nulls;
  END IF;
END $$;

-- ============================================================================
-- SELESAI
-- ============================================================================
