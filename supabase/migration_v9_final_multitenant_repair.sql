-- ============================================================================
-- RAJAKAS BENDAHARA V9 - FINAL MULTI-TENANT REPAIR
--
-- Kondisi database yang ditangani:
--   - organizations + profiles sudah ada dan berisi 4 organisasi.
--   - tabel data lama masih memakai tenant_id.
--   - periode_pembukuan sudah memiliki organization_id.
--   - konfigurasi_lembaga belum memiliki organization_id.
--   - sebagian schema siswa_tagihan lama belum lengkap.
--
-- Mapping DATA LAMA yang sudah diverifikasi:
--   tenant f511cf45-58fc-4466-8f35-5985b9c77fbd
--   -> organization be4c6030-f13b-4f4c-af0c-4ffd16942fe6
--
-- Prinsip:
--   1. Tidak menghapus user/organization/transaksi.
--   2. tenant_id dipertahankan sementara sebagai legacy/audit trail.
--   3. organization_id menjadi sumber isolasi aplikasi + RLS.
--   4. Provisioning user baru idempotent.
--   5. Tidak ada fallback Demo Lokal dari sisi database.
-- ============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- ---------------------------------------------------------------------------
-- 1. PASTIKAN FUNGSI ORGANISASI ADA DAN AMAN
-- ---------------------------------------------------------------------------
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

-- ---------------------------------------------------------------------------
-- 2. LENGKAPI KOLOM ORGANIZATION_ID
-- ---------------------------------------------------------------------------
ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;

ALTER TABLE public.audit_log
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;

ALTER TABLE public.master_kelas
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;

ALTER TABLE public.master_sumber_dana
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;

ALTER TABLE public.master_kategori
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

ALTER TABLE public.periode_pembukuan
  ADD COLUMN IF NOT EXISTS organization_id UUID
  REFERENCES public.organizations(id) ON DELETE CASCADE;

-- Lengkapi schema siswa_tagihan jika project lama belum memiliki kolom ini.
ALTER TABLE public.siswa_tagihan ADD COLUMN IF NOT EXISTS target NUMERIC(15,2) NOT NULL DEFAULT 0;
ALTER TABLE public.siswa_tagihan ADD COLUMN IF NOT EXISTS catatan TEXT;
ALTER TABLE public.siswa_tagihan ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE public.siswa_tagihan ADD COLUMN IF NOT EXISTS created_by UUID;

-- ---------------------------------------------------------------------------
-- 2B. PERBAIKI TRIGGER CUTOFF LEGACY SEBELUM BACKFILL
-- ---------------------------------------------------------------------------
-- Database lama masih memiliki trigger UPDATE yang memanggil
-- get_my_tenant_id(). Saat migration dijalankan tidak ada auth.uid(),
-- sehingga backfill UPDATE ditolak dengan TENANT_TIDAK_DITEMUKAN.
-- Untuk operasi migration/service-role, auth.uid() NULL diperbolehkan.
-- User biasa tetap mendapat penguncian periode berbasis organization_id.
CREATE OR REPLACE FUNCTION public.cegah_update_transaksi_periode_tertutup()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_mulai DATE;
BEGIN
  -- Migration/service role: jangan blokir backfill administratif.
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT pp.tanggal_mulai
  INTO v_mulai
  FROM public.periode_pembukuan pp
  WHERE pp.status = 'AKTIF'
    AND pp.organization_id = NEW.organization_id
  ORDER BY pp.tanggal_mulai DESC
  LIMIT 1;

  IF v_mulai IS NOT NULL
     AND (OLD.tanggal < v_mulai OR NEW.tanggal < v_mulai) THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Transaksi periode yang sudah ditutup tidak dapat diubah.';
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger INSERT juga harus konsisten dengan organization_id.
CREATE OR REPLACE FUNCTION public.cegah_transaksi_di_luar_periode_aktif()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_mulai DATE;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT pp.tanggal_mulai
  INTO v_mulai
  FROM public.periode_pembukuan pp
  WHERE pp.status = 'AKTIF'
    AND pp.organization_id = NEW.organization_id
  ORDER BY pp.tanggal_mulai DESC
  LIMIT 1;

  IF v_mulai IS NOT NULL AND NEW.tanggal < v_mulai THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Tanggal transaksi berada pada periode yang sudah ditutup.';
  END IF;

  RETURN NEW;
END;
$$;

-- ---------------------------------------------------------------------------
-- 3. BACKFILL DATA LAMA DENGAN MAPPING YANG SUDAH DIVERIFIKASI
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_old_tenant UUID := 'f511cf45-58fc-4466-8f35-5985b9c77fbd';
  v_old_org UUID := 'be4c6030-f13b-4f4c-af0c-4ffd16942fe6';
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.organizations WHERE id = v_old_org) THEN
    RAISE EXCEPTION 'Organization legacy target % tidak ditemukan.', v_old_org;
  END IF;

  UPDATE public.konfigurasi_lembaga
  SET organization_id = v_old_org
  WHERE tenant_id = v_old_tenant AND organization_id IS NULL;

  UPDATE public.master_kelas
  SET organization_id = v_old_org
  WHERE tenant_id = v_old_tenant AND organization_id IS NULL;

  UPDATE public.master_kategori
  SET organization_id = v_old_org
  WHERE tenant_id = v_old_tenant AND organization_id IS NULL;

  UPDATE public.master_sumber_dana
  SET organization_id = v_old_org
  WHERE tenant_id = v_old_tenant AND organization_id IS NULL;

  UPDATE public.pemasukan
  SET organization_id = v_old_org
  WHERE tenant_id = v_old_tenant AND organization_id IS NULL;

  UPDATE public.pengeluaran
  SET organization_id = v_old_org
  WHERE tenant_id = v_old_tenant AND organization_id IS NULL;

  UPDATE public.siswa_tagihan
  SET organization_id = v_old_org
  WHERE organization_id IS NULL;

  UPDATE public.periode_pembukuan
  SET organization_id = v_old_org
  WHERE tenant_id = v_old_tenant AND organization_id IS NULL;

  -- Audit lama: jika ada created_by yang cocok dengan profile, gunakan org user.
  UPDATE public.audit_log a
  SET organization_id = p.organization_id
  FROM public.profiles p
  WHERE a.organization_id IS NULL
    AND a.user_id = p.id::text;

  -- Audit yang tidak punya user yang dapat dipetakan tetapi berasal dari
  -- periode/data legacy diarahkan ke org legacy yang sudah diverifikasi.
  UPDATE public.audit_log
  SET organization_id = v_old_org
  WHERE organization_id IS NULL;
END $$;

-- ---------------------------------------------------------------------------
-- 4. VALIDASI: JANGAN LANJUTKAN JIKA DATA LEGACY MASIH TANPA ORGANISASI
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.konfigurasi_lembaga WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'REPAIR_STOP: konfigurasi_lembaga masih memiliki organization_id NULL.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.master_kelas WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'REPAIR_STOP: master_kelas masih memiliki organization_id NULL.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.master_kategori WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'REPAIR_STOP: master_kategori masih memiliki organization_id NULL.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.master_sumber_dana WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'REPAIR_STOP: master_sumber_dana masih memiliki organization_id NULL.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.pemasukan WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'REPAIR_STOP: pemasukan masih memiliki organization_id NULL.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.pengeluaran WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'REPAIR_STOP: pengeluaran masih memiliki organization_id NULL.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.siswa_tagihan WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'REPAIR_STOP: siswa_tagihan masih memiliki organization_id NULL.';
  END IF;
  IF EXISTS (SELECT 1 FROM public.periode_pembukuan WHERE organization_id IS NULL) THEN
    RAISE EXCEPTION 'REPAIR_STOP: periode_pembukuan masih memiliki organization_id NULL.';
  END IF;
END $$;

-- ---------------------------------------------------------------------------
-- 5. KONFIGURASI: SATU BARIS PER ORGANIZATION
-- ---------------------------------------------------------------------------
-- Simpan view lama dulu karena migration.sql masih memiliki referensi id=TRUE.
DROP VIEW IF EXISTS public.saldo_kas;

ALTER TABLE public.konfigurasi_lembaga
  DROP CONSTRAINT IF EXISTS konfigurasi_lembaga_pkey;

-- Buat konfigurasi default untuk organisasi yang sudah ada tetapi belum punya
-- baris konfigurasi. Ini tidak menyentuh data konfigurasi lama milik org A.
INSERT INTO public.konfigurasi_lembaga
  (organization_id, nama_lembaga, jenis_lembaga, saldo_awal, tahun_ajaran)
SELECT
  o.id,
  '',
  'SD',
  0,
  '2026/2027'
FROM public.organizations o
WHERE NOT EXISTS (
  SELECT 1
  FROM public.konfigurasi_lembaga k
  WHERE k.organization_id = o.id
);

ALTER TABLE public.konfigurasi_lembaga
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.konfigurasi_lembaga
  ADD CONSTRAINT konfigurasi_lembaga_pkey PRIMARY KEY (organization_id);

-- id BOOLEAN lama tidak lagi dipakai aplikasi.
ALTER TABLE public.konfigurasi_lembaga
  DROP COLUMN IF EXISTS id;

-- ---------------------------------------------------------------------------
-- 6. ORGANIZATION_ID WAJIB + DEFAULT SERVER-SIDE
-- ---------------------------------------------------------------------------
ALTER TABLE public.master_kelas ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.master_sumber_dana ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.master_kategori ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.siswa_tagihan ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.pemasukan ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.pengeluaran ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.audit_log ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();
ALTER TABLE public.periode_pembukuan ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();

ALTER TABLE public.master_kelas ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.master_sumber_dana ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.master_kategori ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.siswa_tagihan ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.pemasukan ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.pengeluaran ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.audit_log ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.periode_pembukuan ALTER COLUMN organization_id SET NOT NULL;

-- ---------------------------------------------------------------------------
-- 7. NORMALISASI PRIMARY KEY MASTER
-- ---------------------------------------------------------------------------
ALTER TABLE public.master_kelas DROP CONSTRAINT IF EXISTS master_kelas_pkey;
ALTER TABLE public.master_kelas
  ADD CONSTRAINT master_kelas_pkey PRIMARY KEY (organization_id, nama);

ALTER TABLE public.master_kategori DROP CONSTRAINT IF EXISTS master_kategori_pkey;
ALTER TABLE public.master_kategori
  ADD CONSTRAINT master_kategori_pkey PRIMARY KEY (organization_id, nama);

-- ---------------------------------------------------------------------------
-- 8. PERIODE: SATU AKTIF PER ORGANIZATION
-- ---------------------------------------------------------------------------
DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif;
DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif_per_org;
CREATE UNIQUE INDEX ux_periode_pembukuan_satu_aktif_per_org
  ON public.periode_pembukuan (organization_id)
  WHERE status = 'AKTIF';

-- Pastikan semua organization lama memiliki satu periode aktif.
INSERT INTO public.periode_pembukuan
  (organization_id, nama_periode, tahun_ajaran, tanggal_mulai, saldo_awal, status, created_by)
SELECT
  o.id,
  '2026/2027',
  '2026/2027',
  '2026-07-01',
  0,
  'AKTIF',
  p.id
FROM public.organizations o
JOIN public.profiles p ON p.organization_id = o.id
WHERE p.role = 'owner'
  AND NOT EXISTS (
    SELECT 1 FROM public.periode_pembukuan pp
    WHERE pp.organization_id = o.id AND pp.status = 'AKTIF'
  );

-- ---------------------------------------------------------------------------
-- 9. RLS: HAPUS POLICY LAMA PADA TABEL DATA, LALU BUAT ISOLASI ORGANISASI
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'organizations','profiles','konfigurasi_lembaga','audit_log',
    'master_kelas','master_sumber_dana','master_kategori','siswa_tagihan',
    'pemasukan','pengeluaran','periode_pembukuan'
  ] LOOP
    FOR r IN
      SELECT policyname
      FROM pg_policies
      WHERE schemaname='public' AND tablename=t
    LOOP
      EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', r.policyname, t);
    END LOOP;
  END LOOP;
END $$;

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.konfigurasi_lembaga ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_kelas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_sumber_dana ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_kategori ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.siswa_tagihan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pemasukan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pengeluaran ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.periode_pembukuan ENABLE ROW LEVEL SECURITY;

CREATE POLICY organizations_select_own ON public.organizations
  FOR SELECT TO authenticated
  USING (id = public.get_auth_org_id());
CREATE POLICY organizations_update_own ON public.organizations
  FOR UPDATE TO authenticated
  USING (id = public.get_auth_org_id())
  WITH CHECK (id = public.get_auth_org_id());

CREATE POLICY profiles_select_org ON public.profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid() OR organization_id = public.get_auth_org_id());
CREATE POLICY profiles_update_self ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid() AND organization_id = public.get_auth_org_id());

CREATE POLICY konfigurasi_select_org ON public.konfigurasi_lembaga
  FOR SELECT TO authenticated
  USING (organization_id = public.get_auth_org_id());
CREATE POLICY konfigurasi_update_org ON public.konfigurasi_lembaga
  FOR UPDATE TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

CREATE POLICY audit_select_org ON public.audit_log
  FOR SELECT TO authenticated
  USING (organization_id = public.get_auth_org_id());

CREATE POLICY master_kelas_org ON public.master_kelas
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

CREATE POLICY master_sumber_dana_org ON public.master_sumber_dana
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

CREATE POLICY master_kategori_org ON public.master_kategori
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

CREATE POLICY siswa_tagihan_org ON public.siswa_tagihan
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

CREATE POLICY pemasukan_org ON public.pemasukan
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

CREATE POLICY pengeluaran_org ON public.pengeluaran
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

CREATE POLICY periode_org ON public.periode_pembukuan
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

-- ---------------------------------------------------------------------------
-- 10. GRANT DASAR
-- ---------------------------------------------------------------------------
GRANT SELECT, UPDATE ON public.organizations TO authenticated;
GRANT SELECT, UPDATE ON public.profiles TO authenticated;
GRANT SELECT, UPDATE ON public.konfigurasi_lembaga TO authenticated;
GRANT SELECT ON public.audit_log TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.master_kelas TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.master_sumber_dana TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.master_kategori TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.siswa_tagihan TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pemasukan TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pengeluaran TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.periode_pembukuan TO authenticated;

-- ---------------------------------------------------------------------------
-- 11. KONFIGURASI RPC - SERVER SIDE ORGANIZATION
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.save_konfigurasi_lembaga(
  p_nama_lembaga TEXT DEFAULT NULL,
  p_jenis_lembaga TEXT DEFAULT NULL,
  p_npsn TEXT DEFAULT NULL,
  p_alamat TEXT DEFAULT NULL,
  p_kontak TEXT DEFAULT NULL,
  p_website TEXT DEFAULT NULL,
  p_tahun_ajaran TEXT DEFAULT NULL,
  p_saldo_awal NUMERIC DEFAULT NULL,
  p_logo_url TEXT DEFAULT NULL,
  p_clear_logo BOOLEAN DEFAULT FALSE
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID := public.get_auth_org_id();
  v_row public.konfigurasi_lembaga;
BEGIN
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'AUTH_ORGANIZATION_NOT_FOUND';
  END IF;

  INSERT INTO public.konfigurasi_lembaga
    (organization_id, nama_lembaga, jenis_lembaga, npsn, alamat, kontak, website, tahun_ajaran, saldo_awal, logo_url, updated_by)
  VALUES
    (v_org_id, COALESCE(p_nama_lembaga,''), COALESCE(p_jenis_lembaga,'SD'), p_npsn, p_alamat, p_kontak, p_website,
     COALESCE(p_tahun_ajaran,'2026/2027'), COALESCE(p_saldo_awal,0),
     CASE WHEN p_clear_logo THEN NULL ELSE p_logo_url END, auth.uid())
  ON CONFLICT (organization_id) DO UPDATE SET
    nama_lembaga = COALESCE(p_nama_lembaga, public.konfigurasi_lembaga.nama_lembaga),
    jenis_lembaga = COALESCE(p_jenis_lembaga, public.konfigurasi_lembaga.jenis_lembaga),
    npsn = COALESCE(p_npsn, public.konfigurasi_lembaga.npsn),
    alamat = COALESCE(p_alamat, public.konfigurasi_lembaga.alamat),
    kontak = COALESCE(p_kontak, public.konfigurasi_lembaga.kontak),
    website = COALESCE(p_website, public.konfigurasi_lembaga.website),
    tahun_ajaran = COALESCE(p_tahun_ajaran, public.konfigurasi_lembaga.tahun_ajaran),
    saldo_awal = COALESCE(p_saldo_awal, public.konfigurasi_lembaga.saldo_awal),
    logo_url = CASE WHEN p_clear_logo THEN NULL ELSE COALESCE(p_logo_url, public.konfigurasi_lembaga.logo_url) END,
    updated_at = NOW(), updated_by = auth.uid()
  RETURNING * INTO v_row;

  RETURN row_to_json(v_row)::jsonb;
END;
$$;

REVOKE ALL ON FUNCTION public.save_konfigurasi_lembaga(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC,TEXT,BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_konfigurasi_lembaga(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC,TEXT,BOOLEAN) TO authenticated;

-- ---------------------------------------------------------------------------
-- 12. USER PROVISIONING FINAL
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.provision_user_account(
  p_user_id UUID,
  p_email TEXT DEFAULT NULL,
  p_name TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
  v_name TEXT;
  v_tahun TEXT := '2026/2027';
  v_tanggal_mulai DATE := '2026-07-01';
  v_owner_id UUID;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'USER_ID_INVALID';
  END IF;

  SELECT organization_id INTO v_org_id
  FROM public.profiles
  WHERE id = p_user_id
  LIMIT 1;

  IF v_org_id IS NULL THEN
    v_name := COALESCE(
      NULLIF(TRIM(p_name), ''),
      NULLIF(split_part(COALESCE(p_email,''), '@', 1), ''),
      'Lembaga Baru'
    );

    INSERT INTO public.organizations (name)
    VALUES (LEFT(v_name || ' - Lembaga Baru', 150))
    RETURNING id INTO v_org_id;

    INSERT INTO public.profiles (id, organization_id, email, role)
    VALUES (p_user_id, v_org_id, p_email, 'owner')
    ON CONFLICT (id) DO NOTHING;
  ELSE
    UPDATE public.profiles
    SET email = COALESCE(email, p_email), updated_at = NOW()
    WHERE id = p_user_id;
  END IF;

  INSERT INTO public.konfigurasi_lembaga
    (organization_id, nama_lembaga, jenis_lembaga, saldo_awal, tahun_ajaran)
  VALUES (v_org_id, '', 'SD', 0, v_tahun)
  ON CONFLICT (organization_id) DO NOTHING;

  SELECT id INTO v_owner_id
  FROM public.profiles
  WHERE organization_id = v_org_id
    AND role = 'owner'
  ORDER BY created_at
  LIMIT 1;

  IF NOT EXISTS (
    SELECT 1 FROM public.periode_pembukuan
    WHERE organization_id = v_org_id AND status = 'AKTIF'
  ) THEN
    INSERT INTO public.periode_pembukuan
      (organization_id, nama_periode, tahun_ajaran, tanggal_mulai, saldo_awal, status, created_by)
    VALUES
      (v_org_id, v_tahun, v_tahun, v_tanggal_mulai, 0, 'AKTIF', COALESCE(v_owner_id, p_user_id));
  END IF;

  RETURN v_org_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_new_user_multi_tenant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.provision_user_account(
    NEW.id,
    NEW.email,
    COALESCE(
      NULLIF(NEW.raw_user_meta_data->>'name',''),
      NULLIF(NEW.raw_user_meta_data->>'full_name','')
    )
  );
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.ensure_user_setup()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_email TEXT;
  v_name TEXT;
  v_org_id UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT email,
         COALESCE(
           NULLIF(raw_user_meta_data->>'name',''),
           NULLIF(raw_user_meta_data->>'full_name','')
         )
  INTO v_email, v_name
  FROM auth.users
  WHERE id = v_uid;

  IF v_email IS NULL THEN
    RAISE EXCEPTION 'USER_TIDAK_DITEMUKAN';
  END IF;

  v_org_id := public.provision_user_account(v_uid, v_email, v_name);

  RETURN jsonb_build_object('organization_id', v_org_id, 'ready', TRUE);
END;
$$;

REVOKE ALL ON FUNCTION public.provision_user_account(UUID,TEXT,TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_user_setup() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_user_setup() TO authenticated;

-- Hapus trigger custom lama yang diketahui, lalu pasang satu trigger final.
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_created_multi_tenant ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION public.handle_new_user_multi_tenant();

-- ---------------------------------------------------------------------------
-- 13. PERBAIKI USER LAMA TANPA MENGUBAH ORGANIZATION YANG SUDAH ADA
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  u RECORD;
BEGIN
  FOR u IN SELECT id, email, raw_user_meta_data FROM auth.users LOOP
    PERFORM public.provision_user_account(
      u.id,
      u.email,
      COALESCE(
        NULLIF(u.raw_user_meta_data->>'name',''),
        NULLIF(u.raw_user_meta_data->>'full_name','')
      )
    );
  END LOOP;
END $$;

-- ---------------------------------------------------------------------------
-- 14. VIEW SALDO KAS TENANT-AWARE
-- ---------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.saldo_kas
WITH (security_invoker = true)
AS
SELECT
  COALESCE((
    SELECT k.saldo_awal
    FROM public.konfigurasi_lembaga k
    WHERE k.organization_id = public.get_auth_org_id()
    LIMIT 1
  ), 0)
  + COALESCE((
    SELECT SUM(p.nominal)
    FROM public.pemasukan p
    WHERE p.organization_id = public.get_auth_org_id()
  ), 0)
  - COALESCE((
    SELECT SUM(p.nominal)
    FROM public.pengeluaran p
    WHERE p.organization_id = public.get_auth_org_id()
  ), 0)
  AS total_saldo_kas;

GRANT SELECT ON public.saldo_kas TO authenticated;

-- ---------------------------------------------------------------------------
-- 15. FINAL SANITY CHECK
-- ---------------------------------------------------------------------------
DO $$
BEGIN
  IF (SELECT COUNT(*) FROM public.profiles) = 0 THEN
    RAISE EXCEPTION 'FINAL_CHECK_FAIL: profiles kosong.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.profiles p WHERE p.organization_id IS NULL) THEN
    RAISE EXCEPTION 'FINAL_CHECK_FAIL: ada profile tanpa organization_id.';
  END IF;

  IF EXISTS (SELECT 1 FROM public.konfigurasi_lembaga k WHERE k.organization_id IS NULL) THEN
    RAISE EXCEPTION 'FINAL_CHECK_FAIL: ada konfigurasi tanpa organization_id.';
  END IF;
END $$;

COMMENT ON COLUMN public.konfigurasi_lembaga.tenant_id IS 'LEGACY: dipertahankan sementara untuk audit/migrasi. Aplikasi menggunakan organization_id.';
COMMENT ON COLUMN public.master_kelas.tenant_id IS 'LEGACY: dipertahankan sementara untuk audit/migrasi. Aplikasi menggunakan organization_id.';
COMMENT ON COLUMN public.master_kategori.tenant_id IS 'LEGACY: dipertahankan sementara untuk audit/migrasi. Aplikasi menggunakan organization_id.';
COMMENT ON COLUMN public.master_sumber_dana.tenant_id IS 'LEGACY: dipertahankan sementara untuk audit/migrasi. Aplikasi menggunakan organization_id.';
COMMENT ON COLUMN public.pemasukan.tenant_id IS 'LEGACY: dipertahankan sementara untuk audit/migrasi. Aplikasi menggunakan organization_id.';
COMMENT ON COLUMN public.pengeluaran.tenant_id IS 'LEGACY: dipertahankan sementara untuk audit/migrasi. Aplikasi menggunakan organization_id.';
COMMENT ON COLUMN public.periode_pembukuan.tenant_id IS 'LEGACY: dipertahankan sementara untuk audit/migrasi. Aplikasi menggunakan organization_id.';
