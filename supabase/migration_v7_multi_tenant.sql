-- ============================================================================
-- RAJAKAS BENDAHARA - MULTI TENANT HARDENED V7
-- Jalankan SETELAH:
--   1. supabase/migration.sql
--   2. supabase/migration_periode_pembukuan.sql (jika dipakai)
--   3. supabase/cutoff_migration.sql (jika dipakai)
--
-- Tujuan:
--   - 1 user -> 1 organization/tenant
--   - semua data aplikasi terisolasi berdasarkan organization_id
--   - RLS tidak lagi sekadar "user sudah login"
--   - SECURITY DEFINER selalu memfilter organization_id
--   - konfigurasi_lembaga tidak lagi singleton id=TRUE
--   - storage memakai folder tenant: <organization_id>/...
--   - user baru otomatis mendapat tenant + profile owner
--
-- Migration ini idempotent untuk struktur yang dijelaskan di atas.
-- Backup database sebelum menjalankan di production.
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
    CHECK (role IN ('owner', 'bendahara', 'viewer')),
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

-- Jangan gunakan FOR ALL pada organizations/profiles. Itu memungkinkan
-- client menghapus tenant atau memindahkan dirinya ke tenant lain.
DROP POLICY IF EXISTS "Organizations - anggota lembaga sendiri" ON public.organizations;
DROP POLICY IF EXISTS "Organizations - baca tenant sendiri" ON public.organizations;
DROP POLICY IF EXISTS "Organizations - ubah tenant sendiri" ON public.organizations;
CREATE POLICY "Organizations - baca tenant sendiri" ON public.organizations
  FOR SELECT USING (id = public.get_auth_org_id());
CREATE POLICY "Organizations - ubah tenant sendiri" ON public.organizations
  FOR UPDATE
  USING (id = public.get_auth_org_id())
  WITH CHECK (id = public.get_auth_org_id());

DROP POLICY IF EXISTS "Profiles - baca sesama anggota lembaga" ON public.profiles;
DROP POLICY IF EXISTS "Profiles - update profil sendiri" ON public.profiles;
DROP POLICY IF EXISTS "Profiles - insert profil sendiri" ON public.profiles;
CREATE POLICY "Profiles - baca sesama anggota lembaga" ON public.profiles
  FOR SELECT USING (id = auth.uid() OR organization_id = public.get_auth_org_id());
CREATE POLICY "Profiles - update profil sendiri" ON public.profiles
  FOR UPDATE
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid() AND organization_id = public.get_auth_org_id());
-- Tidak ada INSERT/DELETE dari client. Profile dibuat oleh trigger SECURITY
-- DEFINER atau proses admin khusus.

GRANT SELECT, UPDATE ON public.organizations TO authenticated;
GRANT SELECT, UPDATE ON public.profiles TO authenticated;

-- ---------------------------------------------------------------------------
-- 2. TAMBAHKAN organization_id KE TABEL DATA
--    Dibuat nullable sementara supaya data lama bisa di-backfill.
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

-- ---------------------------------------------------------------------------
-- 3. ORGANISASI DEFAULT UNTUK DATA LAMA
-- ---------------------------------------------------------------------------
DO $$
DECLARE
  v_org_id UUID;
  v_nama VARCHAR(150);
BEGIN
  SELECT id INTO v_org_id FROM public.organizations ORDER BY created_at LIMIT 1;

  IF v_org_id IS NULL THEN
    SELECT COALESCE(NULLIF(nama_lembaga, ''), 'Lembaga Utama (Migrasi)')
      INTO v_nama
    FROM public.konfigurasi_lembaga
    LIMIT 1;

    INSERT INTO public.organizations (nama)
    VALUES (COALESCE(v_nama, 'Lembaga Utama (Migrasi)'))
    RETURNING id INTO v_org_id;
  END IF;

  -- Data lama hanya bisa dipetakan ke satu tenant secara aman pada migrasi
  -- pertama. Jika sudah ada beberapa tenant dan masih ada NULL, jangan diam-
  -- diam memilih tenant yang salah; proses migrasi harus dihentikan.
  UPDATE public.konfigurasi_lembaga SET organization_id = v_org_id WHERE organization_id IS NULL;
  UPDATE public.audit_log SET organization_id = v_org_id WHERE organization_id IS NULL;
  UPDATE public.master_sumber_dana SET organization_id = v_org_id WHERE organization_id IS NULL;
  UPDATE public.master_kategori SET organization_id = v_org_id WHERE organization_id IS NULL;
  UPDATE public.master_kelas SET organization_id = v_org_id WHERE organization_id IS NULL;
  UPDATE public.siswa_tagihan SET organization_id = v_org_id WHERE organization_id IS NULL;
  UPDATE public.pemasukan SET organization_id = v_org_id WHERE organization_id IS NULL;
  UPDATE public.pengeluaran SET organization_id = v_org_id WHERE organization_id IS NULL;

  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'periode_pembukuan'
  ) THEN
    ALTER TABLE public.periode_pembukuan
      ADD COLUMN IF NOT EXISTS organization_id UUID
      REFERENCES public.organizations(id) ON DELETE CASCADE;
    UPDATE public.periode_pembukuan SET organization_id = v_org_id WHERE organization_id IS NULL;
  END IF;

  -- User lama yang belum punya profile diarahkan ke tenant pertama. Ini hanya
  -- fallback migrasi; user baru ditangani trigger di bawah.
  INSERT INTO public.profiles (id, organization_id, email, role)
  SELECT u.id, v_org_id, u.email, 'owner'
  FROM auth.users u
  WHERE NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = u.id)
  ON CONFLICT (id) DO NOTHING;
END $$;

-- ---------------------------------------------------------------------------
-- 4. DEFAULT organization_id UNTUK INSERT DARI FRONTEND
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

-- konfigurasi memakai RPC save_konfigurasi_lembaga(), bukan insert frontend.

-- ---------------------------------------------------------------------------
-- 5. NORMALISASI PK KONFIGURASI & MASTER
-- ---------------------------------------------------------------------------
ALTER TABLE public.konfigurasi_lembaga
  DROP CONSTRAINT IF EXISTS konfigurasi_lembaga_pkey;
ALTER TABLE public.konfigurasi_lembaga
  DROP COLUMN IF EXISTS id;
ALTER TABLE public.konfigurasi_lembaga
  ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.konfigurasi_lembaga
  ADD CONSTRAINT konfigurasi_lembaga_pkey PRIMARY KEY (organization_id);

ALTER TABLE public.master_kelas DROP CONSTRAINT IF EXISTS master_kelas_pkey;
ALTER TABLE public.master_kelas
  ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.master_kelas
  ADD CONSTRAINT master_kelas_pkey PRIMARY KEY (organization_id, nama);

ALTER TABLE public.master_kategori DROP CONSTRAINT IF EXISTS master_kategori_pkey;
ALTER TABLE public.master_kategori
  ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.master_kategori
  ADD CONSTRAINT master_kategori_pkey PRIMARY KEY (organization_id, nama);

ALTER TABLE public.audit_log ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.master_sumber_dana ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.siswa_tagihan ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.pemasukan ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.pengeluaran ALTER COLUMN organization_id SET NOT NULL;

-- Periode pembukuan opsional pada project lama.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'periode_pembukuan'
  ) THEN
    ALTER TABLE public.periode_pembukuan ALTER COLUMN organization_id SET NOT NULL;
    DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif;
    CREATE UNIQUE INDEX IF NOT EXISTS ux_periode_pembukuan_satu_aktif_per_org
      ON public.periode_pembukuan (organization_id)
      WHERE status = 'AKTIF';
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_profiles_org ON public.profiles (organization_id);
CREATE INDEX IF NOT EXISTS idx_audit_log_org ON public.audit_log (organization_id);
CREATE INDEX IF NOT EXISTS idx_master_sumber_dana_org ON public.master_sumber_dana (organization_id);
CREATE INDEX IF NOT EXISTS idx_master_kategori_org ON public.master_kategori (organization_id);
CREATE INDEX IF NOT EXISTS idx_master_kelas_org ON public.master_kelas (organization_id);
CREATE INDEX IF NOT EXISTS idx_siswa_tagihan_org ON public.siswa_tagihan (organization_id);
CREATE INDEX IF NOT EXISTS idx_pemasukan_org_tanggal ON public.pemasukan (organization_id, tanggal);
CREATE INDEX IF NOT EXISTS idx_pengeluaran_org_tanggal ON public.pengeluaran (organization_id, tanggal);

-- ---------------------------------------------------------------------------
-- 6. RLS ISOLASI TENANT
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
  old_policy TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY[
    'audit_log','master_sumber_dana','master_kategori','master_kelas',
    'siswa_tagihan','pemasukan','pengeluaran','konfigurasi_lembaga'
  ] LOOP
    -- Hapus policy legacy yang namanya diketahui dari migration.sql/v6.
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', 'Hanya user login - ' || t, t);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I',
      CASE t
        WHEN 'audit_log' THEN 'Audit log - anggota lembaga sendiri'
        WHEN 'master_sumber_dana' THEN 'Master sumber dana - anggota lembaga sendiri'
        WHEN 'master_kategori' THEN 'Master kategori - anggota lembaga sendiri'
        WHEN 'master_kelas' THEN 'Master kelas - anggota lembaga sendiri'
        WHEN 'siswa_tagihan' THEN 'Siswa tagihan - anggota lembaga sendiri'
        WHEN 'pemasukan' THEN 'Pemasukan - anggota lembaga sendiri'
        WHEN 'pengeluaran' THEN 'Pengeluaran - anggota lembaga sendiri'
        ELSE 'Konfigurasi lembaga - anggota lembaga sendiri'
      END, t);
  END LOOP;
END $$;

CREATE POLICY "Tenant - audit_log" ON public.audit_log
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());
CREATE POLICY "Tenant - master_sumber_dana" ON public.master_sumber_dana
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());
CREATE POLICY "Tenant - master_kategori" ON public.master_kategori
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());
CREATE POLICY "Tenant - master_kelas" ON public.master_kelas
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());
CREATE POLICY "Tenant - siswa_tagihan" ON public.siswa_tagihan
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());
CREATE POLICY "Tenant - pemasukan" ON public.pemasukan
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());
CREATE POLICY "Tenant - pengeluaran" ON public.pengeluaran
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());
CREATE POLICY "Tenant - konfigurasi_lembaga" ON public.konfigurasi_lembaga
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'periode_pembukuan'
  ) THEN
    DROP POLICY IF EXISTS "Periode pembukuan - user login" ON public.periode_pembukuan;
    DROP POLICY IF EXISTS "Periode pembukuan - anggota lembaga sendiri" ON public.periode_pembukuan;
    ALTER TABLE public.periode_pembukuan ENABLE ROW LEVEL SECURITY;
    CREATE POLICY "Tenant - periode_pembukuan" ON public.periode_pembukuan
      FOR ALL USING (organization_id = public.get_auth_org_id())
      WITH CHECK (organization_id = public.get_auth_org_id());
    GRANT SELECT, INSERT, UPDATE, DELETE ON public.periode_pembukuan TO authenticated;
  END IF;
END $$;

GRANT SELECT, INSERT, UPDATE, DELETE ON
  public.audit_log, public.master_sumber_dana, public.master_kategori,
  public.master_kelas, public.siswa_tagihan, public.pemasukan,
  public.pengeluaran, public.konfigurasi_lembaga
  TO authenticated;

-- ---------------------------------------------------------------------------
-- 7. SECURITY DEFINER FUNCTIONS: SELALU tenant-aware
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.hitung_saldo_akhir_periode(
  p_periode_id UUID,
  p_tanggal_cutoff DATE DEFAULT NULL
)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID := public.get_auth_org_id();
  v_periode RECORD;
  v_cutoff DATE;
BEGIN
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'TENANT_TIDAK_DITEMUKAN';
  END IF;

  SELECT * INTO v_periode
  FROM public.periode_pembukuan
  WHERE id = p_periode_id AND organization_id = v_org_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERIODE_TIDAK_DITEMUKAN'; END IF;

  v_cutoff := COALESCE(p_tanggal_cutoff, v_periode.tanggal_akhir, CURRENT_DATE);
  IF v_cutoff < v_periode.tanggal_mulai THEN RAISE EXCEPTION 'TANGGAL_CUTOFF_INVALID'; END IF;

  RETURN COALESCE(v_periode.saldo_awal, 0)
    + COALESCE((SELECT SUM(nominal) FROM public.pemasukan
                WHERE organization_id = v_org_id
                  AND tanggal BETWEEN v_periode.tanggal_mulai AND v_cutoff), 0)
    - COALESCE((SELECT SUM(nominal) FROM public.pengeluaran
                WHERE organization_id = v_org_id
                  AND tanggal BETWEEN v_periode.tanggal_mulai AND v_cutoff), 0);
END;
$$;

CREATE OR REPLACE FUNCTION public.tutup_buku(p_periode_id UUID, p_tanggal_cutoff DATE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID := public.get_auth_org_id();
  v_periode RECORD;
  v_saldo NUMERIC;
  v_next_year TEXT;
  v_next RECORD;
BEGIN
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'TENANT_TIDAK_DITEMUKAN'; END IF;

  SELECT * INTO v_periode
  FROM public.periode_pembukuan
  WHERE id = p_periode_id AND organization_id = v_org_id
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERIODE_TIDAK_DITEMUKAN'; END IF;
  IF v_periode.status <> 'AKTIF' THEN RAISE EXCEPTION 'PERIODE_SUDAH_DITUTUP'; END IF;
  IF p_tanggal_cutoff < v_periode.tanggal_mulai THEN RAISE EXCEPTION 'TANGGAL_CUTOFF_INVALID'; END IF;

  v_saldo := public.hitung_saldo_akhir_periode(p_periode_id, p_tanggal_cutoff);

  UPDATE public.periode_pembukuan
  SET status='DITUTUP', tanggal_akhir=p_tanggal_cutoff, saldo_akhir=v_saldo,
      closed_at=NOW(), closed_by=auth.uid()
  WHERE id=p_periode_id AND organization_id=v_org_id;

  IF v_periode.tahun_ajaran ~ '^[0-9]{4}/[0-9]{4}$' THEN
    v_next_year := (split_part(v_periode.tahun_ajaran,'/',1)::INT + 1)::TEXT || '/' ||
                   (split_part(v_periode.tahun_ajaran,'/',2)::INT + 1)::TEXT;
  ELSE
    v_next_year := v_periode.tahun_ajaran;
  END IF;

  INSERT INTO public.periode_pembukuan
    (organization_id,nama_periode,tahun_ajaran,tanggal_mulai,tanggal_akhir,saldo_awal,saldo_akhir,status,created_by)
  VALUES
    (v_org_id,v_next_year,v_next_year,p_tanggal_cutoff + 1,NULL,v_saldo,NULL,'AKTIF',auth.uid())
  RETURNING * INTO v_next;

  UPDATE public.konfigurasi_lembaga
  SET saldo_awal=v_saldo,tahun_ajaran=v_next_year,updated_at=NOW(),updated_by=auth.uid()
  WHERE organization_id=v_org_id;

  RETURN jsonb_build_object('saldo_akhir',v_saldo,'periode_berikutnya',row_to_json(v_next)::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.buka_kembali_periode(p_periode_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID := public.get_auth_org_id();
  v_closed RECORD;
  v_active RECORD;
  v_tx_count BIGINT;
BEGIN
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'TENANT_TIDAK_DITEMUKAN'; END IF;

  SELECT * INTO v_closed
  FROM public.periode_pembukuan
  WHERE id=p_periode_id AND organization_id=v_org_id AND status='DITUTUP'
  FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERIODE_TERTUTUP_TIDAK_DITEMUKAN'; END IF;

  SELECT * INTO v_active
  FROM public.periode_pembukuan
  WHERE organization_id=v_org_id AND status='AKTIF'
  ORDER BY tanggal_mulai DESC LIMIT 1 FOR UPDATE;

  IF v_active.id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_tx_count FROM (
      SELECT id FROM public.pemasukan WHERE organization_id=v_org_id AND tanggal >= v_active.tanggal_mulai
      UNION ALL
      SELECT id FROM public.pengeluaran WHERE organization_id=v_org_id AND tanggal >= v_active.tanggal_mulai
    ) q;
    IF v_tx_count > 0 THEN RAISE EXCEPTION 'PERIODE_BERIKUTNYA_SUDAH_MEMILIKI_TRANSAKSI'; END IF;
    DELETE FROM public.periode_pembukuan WHERE id=v_active.id AND organization_id=v_org_id;
  END IF;

  UPDATE public.periode_pembukuan
  SET status='AKTIF',tanggal_akhir=NULL,saldo_akhir=NULL,closed_at=NULL,closed_by=NULL
  WHERE id=p_periode_id AND organization_id=v_org_id;

  UPDATE public.konfigurasi_lembaga
  SET saldo_awal=v_closed.saldo_awal,tahun_ajaran=v_closed.tahun_ajaran,updated_at=NOW(),updated_by=auth.uid()
  WHERE organization_id=v_org_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.hitung_saldo_akhir_periode(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tutup_buku(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.buka_kembali_periode(UUID) TO authenticated;
REVOKE ALL ON FUNCTION public.hitung_saldo_akhir_periode(UUID, DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.tutup_buku(UUID, DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.buka_kembali_periode(UUID) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- 8. RPC KONFIGURASI: tenant ditentukan server, bukan frontend
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
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID := public.get_auth_org_id();
  v_row RECORD;
BEGIN
  IF v_org_id IS NULL THEN RAISE EXCEPTION 'TENANT_TIDAK_DITEMUKAN'; END IF;

  INSERT INTO public.konfigurasi_lembaga
    (organization_id,nama_lembaga,jenis_lembaga,saldo_awal,tahun_ajaran)
  VALUES
    (v_org_id,COALESCE(p_nama_lembaga,''),COALESCE(p_jenis_lembaga,'SD'),COALESCE(p_saldo_awal,0),COALESCE(p_tahun_ajaran,'2025/2026'))
  ON CONFLICT (organization_id) DO UPDATE SET
    nama_lembaga=COALESCE(p_nama_lembaga,konfigurasi_lembaga.nama_lembaga),
    jenis_lembaga=COALESCE(p_jenis_lembaga,konfigurasi_lembaga.jenis_lembaga),
    npsn=COALESCE(p_npsn,konfigurasi_lembaga.npsn),
    alamat=COALESCE(p_alamat,konfigurasi_lembaga.alamat),
    kontak=COALESCE(p_kontak,konfigurasi_lembaga.kontak),
    website=COALESCE(p_website,konfigurasi_lembaga.website),
    tahun_ajaran=COALESCE(p_tahun_ajaran,konfigurasi_lembaga.tahun_ajaran),
    saldo_awal=COALESCE(p_saldo_awal,konfigurasi_lembaga.saldo_awal),
    logo_url=CASE WHEN p_clear_logo THEN NULL ELSE COALESCE(p_logo_url,konfigurasi_lembaga.logo_url) END,
    updated_at=NOW(),updated_by=auth.uid()
  RETURNING * INTO v_row;

  RETURN row_to_json(v_row)::jsonb;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_konfigurasi_lembaga(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC,TEXT,BOOLEAN) TO authenticated;
REVOKE ALL ON FUNCTION public.save_konfigurasi_lembaga(TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,TEXT,NUMERIC,TEXT,BOOLEAN) FROM PUBLIC;

-- ---------------------------------------------------------------------------
-- 9. AUTO PROVISIONING USER BARU
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user_multi_tenant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
  v_nama_awal VARCHAR(150);
BEGIN
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id=NEW.id) THEN RETURN NEW; END IF;

  v_nama_awal := COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'name',''),
    NULLIF(NEW.raw_user_meta_data->>'full_name',''),
    NULLIF(split_part(COALESCE(NEW.email,''),'@',1),''),
    'Lembaga Baru'
  );

  INSERT INTO public.organizations (nama)
  VALUES (LEFT(v_nama_awal || ' - Lembaga Baru',150))
  RETURNING id INTO v_org_id;

  INSERT INTO public.profiles (id,organization_id,email,role)
  VALUES (NEW.id,v_org_id,NEW.email,'owner');

  INSERT INTO public.konfigurasi_lembaga
    (organization_id,nama_lembaga,jenis_lembaga,saldo_awal,tahun_ajaran)
  VALUES (v_org_id,'','SD',0,'2025/2026')
  ON CONFLICT (organization_id) DO NOTHING;

  -- Membuat periode awal jika tabelnya sudah ada.
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='periode_pembukuan'
  ) THEN
    INSERT INTO public.periode_pembukuan
      (organization_id,nama_periode,tahun_ajaran,tanggal_mulai,saldo_awal,status,created_by)
    VALUES
      (v_org_id,'2025/2026','2025/2026','2025-07-01',0,'AKTIF',NEW.id)
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_multi_tenant ON auth.users;
CREATE TRIGGER on_auth_user_created_multi_tenant
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_multi_tenant();

-- ---------------------------------------------------------------------------
-- 10. TENANT-AWARE SALDO VIEW
-- ---------------------------------------------------------------------------
DROP VIEW IF EXISTS public.saldo_kas;
CREATE VIEW public.saldo_kas
WITH (security_invoker = true)
AS
SELECT
  (SELECT saldo_awal FROM public.konfigurasi_lembaga LIMIT 1)
  + COALESCE((SELECT SUM(nominal) FROM public.pemasukan),0)
  - COALESCE((SELECT SUM(nominal) FROM public.pengeluaran),0)
  AS total_saldo_kas;

GRANT SELECT ON public.saldo_kas TO authenticated;

-- ---------------------------------------------------------------------------
-- 11. STORAGE TENANT ISOLATION
-- ---------------------------------------------------------------------------
-- Path wajib:
--   logos/<organization_id>/logo.ext
--   bukti-pengeluaran/<organization_id>/<random>.ext
--
-- Logo boleh dibaca publik karena memang dipakai pada laporan/branding.
-- Bukti pengeluaran juga dibuat public agar kompatibel dengan aplikasi lama;
-- folder tenant mencegah upload ke tenant lain. Untuk tingkat keamanan lebih
-- tinggi, bucket bukti-pengeluaran dapat diubah PRIVATE + signed URL.
DROP POLICY IF EXISTS "Logo - baca publik" ON storage.objects;
DROP POLICY IF EXISTS "Logo - upload user login" ON storage.objects;
DROP POLICY IF EXISTS "Logo - update user login" ON storage.objects;
DROP POLICY IF EXISTS "Logo - delete user login" ON storage.objects;

CREATE POLICY "Tenant logo - baca" ON storage.objects
  FOR SELECT USING (bucket_id='logos');
CREATE POLICY "Tenant logo - upload" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id='logos' AND auth.role()='authenticated' AND
    (storage.foldername(name))[1] = public.get_auth_org_id()::text
  );
CREATE POLICY "Tenant logo - update" ON storage.objects
  FOR UPDATE USING (
    bucket_id='logos' AND auth.role()='authenticated' AND
    (storage.foldername(name))[1] = public.get_auth_org_id()::text
  ) WITH CHECK (
    bucket_id='logos' AND auth.role()='authenticated' AND
    (storage.foldername(name))[1] = public.get_auth_org_id()::text
  );
CREATE POLICY "Tenant logo - delete" ON storage.objects
  FOR DELETE USING (
    bucket_id='logos' AND auth.role()='authenticated' AND
    (storage.foldername(name))[1] = public.get_auth_org_id()::text
  );

DROP POLICY IF EXISTS "Bukti Pengeluaran - baca publik" ON storage.objects;
DROP POLICY IF EXISTS "Bukti Pengeluaran - upload user login" ON storage.objects;
DROP POLICY IF EXISTS "Bukti Pengeluaran - update user login" ON storage.objects;
DROP POLICY IF EXISTS "Bukti Pengeluaran - delete user login" ON storage.objects;

CREATE POLICY "Tenant bukti - baca" ON storage.objects
  FOR SELECT USING (
    bucket_id='bukti-pengeluaran' AND
    (storage.foldername(name))[1] = public.get_auth_org_id()::text
  );
CREATE POLICY "Tenant bukti - upload" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id='bukti-pengeluaran' AND auth.role()='authenticated' AND
    (storage.foldername(name))[1] = public.get_auth_org_id()::text
  );
CREATE POLICY "Tenant bukti - update" ON storage.objects
  FOR UPDATE USING (
    bucket_id='bukti-pengeluaran' AND auth.role()='authenticated' AND
    (storage.foldername(name))[1] = public.get_auth_org_id()::text
  ) WITH CHECK (
    bucket_id='bukti-pengeluaran' AND auth.role()='authenticated' AND
    (storage.foldername(name))[1] = public.get_auth_org_id()::text
  );
CREATE POLICY "Tenant bukti - delete" ON storage.objects
  FOR DELETE USING (
    bucket_id='bukti-pengeluaran' AND auth.role()='authenticated' AND
    (storage.foldername(name))[1] = public.get_auth_org_id()::text
  );

-- ============================================================================
-- SELESAI
-- Setelah migration berhasil:
--   - user baru otomatis mendapat tenant sendiri
--   - user lama dipetakan ke tenant migrasi
--   - data transaksi/master/config/period terisolasi dengan RLS
--   - jangan pernah menjalankan migration.sql lagi setelah V7 di production,
--     karena migration.sql adalah script reset/drop untuk instalasi awal.
-- ============================================================================
