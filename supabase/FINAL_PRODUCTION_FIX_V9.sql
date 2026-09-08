-- RAJAKAS BENDAHARA - FINAL PRODUCTION FIX V9
-- Tujuan: akun BARU yang belum memiliki profile/tenant tetap bisa memakai
-- seluruh fitur (kelas, kategori, sumber dana, pemasukan, pengeluaran, siswa,
-- periode, konfigurasi) tanpa terkena RLS 42501.
--
-- AMAN: tidak DROP TABLE, tidak DELETE transaksi, dan tidak mengubah data tenant
-- yang sudah memiliki profile.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

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

-- Fungsi tenant harus bisa membaca profile walaupun RLS profiles aktif.
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

-- -------------------------------------------------------------------------
-- NORMALISASI konfigurasi_lembaga LAMA
-- V6/V7 bisa berhenti saat DROP COLUMN id karena view saldo_kas masih
-- bergantung pada id. Kita lepaskan view, migrasikan PK, lalu buat ulang view.
-- -------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema='public' AND table_name='konfigurasi_lembaga'
  ) THEN
    IF EXISTS (
      SELECT 1 FROM information_schema.columns
      WHERE table_schema='public' AND table_name='konfigurasi_lembaga'
        AND column_name='organization_id'
    ) THEN
      -- Pastikan ada tenant untuk data konfigurasi lama.
      IF NOT EXISTS (SELECT 1 FROM public.organizations) THEN
        INSERT INTO public.organizations(nama)
        VALUES ('Lembaga Utama (Migrasi)');
      END IF;

      UPDATE public.konfigurasi_lembaga
      SET organization_id = (SELECT id FROM public.organizations ORDER BY created_at LIMIT 1)
      WHERE organization_id IS NULL;

      -- Kalau PK lama masih id, view saldo_kas adalah dependency langsung.
      IF EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_schema='public' AND table_name='konfigurasi_lembaga'
          AND column_name='id'
      ) THEN
        EXECUTE 'DROP VIEW IF EXISTS public.saldo_kas CASCADE';
        ALTER TABLE public.konfigurasi_lembaga DROP CONSTRAINT IF EXISTS konfigurasi_lembaga_pkey;
        ALTER TABLE public.konfigurasi_lembaga ALTER COLUMN organization_id SET NOT NULL;
        ALTER TABLE public.konfigurasi_lembaga ADD CONSTRAINT konfigurasi_lembaga_pkey PRIMARY KEY (organization_id);
        ALTER TABLE public.konfigurasi_lembaga DROP COLUMN id;
      ELSE
        ALTER TABLE public.konfigurasi_lembaga DROP CONSTRAINT IF EXISTS konfigurasi_lembaga_pkey;
        ALTER TABLE public.konfigurasi_lembaga ALTER COLUMN organization_id SET NOT NULL;
        IF NOT EXISTS (
          SELECT 1 FROM pg_constraint
          WHERE conrelid='public.konfigurasi_lembaga'::regclass
            AND contype='p'
        ) THEN
          ALTER TABLE public.konfigurasi_lembaga ADD CONSTRAINT konfigurasi_lembaga_pkey PRIMARY KEY (organization_id);
        END IF;
      END IF;
    END IF;
  END IF;
END $$;

-- View saldo tenant-aware. security_invoker memastikan RLS tabel berlaku.
DROP VIEW IF EXISTS public.saldo_kas CASCADE;
CREATE VIEW public.saldo_kas
WITH (security_invoker = true)
AS
SELECT
  COALESCE((SELECT saldo_awal FROM public.konfigurasi_lembaga LIMIT 1),0)
  + COALESCE((SELECT SUM(nominal) FROM public.pemasukan),0)
  - COALESCE((SELECT SUM(nominal) FROM public.pengeluaran),0)
  AS total_saldo_kas;
GRANT SELECT ON public.saldo_kas TO authenticated;

-- -------------------------------------------------------------------------
-- BOOTSTRAP: dipanggil SETELAH LOGIN. Ini adalah pengaman utama.
-- Jika trigger signup belum terpasang, akun tetap mendapatkan tenant.
-- Jika sudah punya tenant, fungsi hanya mengembalikan tenant tersebut.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_my_tenant()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_email TEXT;
  v_org_id UUID;
  v_name TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  SELECT email INTO v_email FROM auth.users WHERE id = v_uid;
  IF v_email IS NULL THEN
    RAISE EXCEPTION 'USER_AUTH_TIDAK_DITEMUKAN';
  END IF;

  -- Idempotent: tenant yang sudah ada tidak diganti.
  SELECT organization_id INTO v_org_id
  FROM public.profiles
  WHERE id = v_uid;

  IF v_org_id IS NULL THEN
    v_name := COALESCE(
      NULLIF((SELECT raw_user_meta_data->>'name' FROM auth.users WHERE id=v_uid), ''),
      NULLIF((SELECT raw_user_meta_data->>'full_name' FROM auth.users WHERE id=v_uid), ''),
      split_part(v_email, '@', 1),
      'Lembaga Baru'
    );

    INSERT INTO public.organizations (nama)
    VALUES (LEFT(v_name || ' - Lembaga Baru',150))
    RETURNING id INTO v_org_id;

    INSERT INTO public.profiles (id, organization_id, email, role)
    VALUES (v_uid, v_org_id, v_email, 'owner')
    ON CONFLICT (id) DO UPDATE
      SET email = EXCLUDED.email;
  ELSE
    UPDATE public.profiles
    SET email = COALESCE(public.profiles.email, v_email)
    WHERE id = v_uid;
  END IF;

  -- Pastikan konfigurasi tenant tersedia bila tabel sudah bermigrasi.
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='konfigurasi_lembaga') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='konfigurasi_lembaga' AND column_name='organization_id') THEN
      INSERT INTO public.konfigurasi_lembaga
        (organization_id, nama_lembaga, jenis_lembaga, saldo_awal, tahun_ajaran)
      VALUES (v_org_id, '', 'SD', 0, '2025/2026')
      ON CONFLICT (organization_id) DO NOTHING;
    END IF;
  END IF;

  -- Pastikan periode aktif tersedia. Tidak menghapus periode yang ada.
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='periode_pembukuan') THEN
    IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema='public' AND table_name='periode_pembukuan' AND column_name='organization_id') THEN
      INSERT INTO public.periode_pembukuan
        (organization_id, nama_periode, tahun_ajaran, tanggal_mulai, saldo_awal, status, created_by)
      SELECT v_org_id, '2025/2026', '2025/2026', DATE '2025-07-01', 0, 'AKTIF', v_uid
      WHERE NOT EXISTS (
        SELECT 1 FROM public.periode_pembukuan
        WHERE organization_id=v_org_id AND status='AKTIF'
      );
    END IF;
  END IF;

  RETURN jsonb_build_object('success',true,'organization_id',v_org_id);
END;
$$;
REVOKE ALL ON FUNCTION public.ensure_my_tenant() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_my_tenant() TO authenticated;

-- Trigger untuk signup berikutnya. Bootstrap di atas tetap menjadi fallback.
CREATE OR REPLACE FUNCTION public.handle_new_user_multi_tenant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
DECLARE
  v_org_id UUID;
  v_name TEXT;
BEGIN
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id=NEW.id) THEN
    RETURN NEW;
  END IF;

  v_name := COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'name',''),
    NULLIF(NEW.raw_user_meta_data->>'full_name',''),
    split_part(COALESCE(NEW.email,''),'@',1),
    'Lembaga Baru'
  );

  INSERT INTO public.organizations(nama)
  VALUES (LEFT(v_name || ' - Lembaga Baru',150))
  RETURNING id INTO v_org_id;

  INSERT INTO public.profiles(id,organization_id,email,role)
  VALUES(NEW.id,v_org_id,NEW.email,'owner')
  ON CONFLICT(id) DO NOTHING;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_multi_tenant ON auth.users;
CREATE TRIGGER on_auth_user_created_multi_tenant
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_multi_tenant();

-- -------------------------------------------------------------------------
-- PERBAIKI DEFAULT TENANT PADA TABEL DATA.
-- -------------------------------------------------------------------------
DO $$
DECLARE r RECORD;
BEGIN
  FOR r IN
    SELECT table_name
    FROM information_schema.columns
    WHERE table_schema='public'
      AND column_name='organization_id'
      AND table_name IN ('audit_log','master_sumber_dana','master_kategori','master_kelas','siswa_tagihan','pemasukan','pengeluaran')
  LOOP
    EXECUTE format('ALTER TABLE public.%I ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id()', r.table_name);
  END LOOP;
END $$;

-- Pastikan RLS policy INSERT/UPDATE menggunakan tenant server.
DO $$
DECLARE t TEXT;
BEGIN
  FOREACH t IN ARRAY ARRAY['master_kelas','master_kategori','master_sumber_dana','pemasukan','pengeluaran','siswa_tagihan','audit_log'] LOOP
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name=t) THEN
      EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY', t);
      EXECUTE format('DROP POLICY IF EXISTS "tenant_all_%s" ON public.%I', t, t);
      EXECUTE format('CREATE POLICY "tenant_all_%s" ON public.%I FOR ALL TO authenticated USING (organization_id = public.get_auth_org_id()) WITH CHECK (organization_id = public.get_auth_org_id())', t, t);
    END IF;
  END LOOP;
END $$;

-- Backfill hanya untuk user yang sudah memiliki tenant; trigger saldo tidak
-- boleh menghalangi migration. Tidak ada perubahan terhadap baris yang sudah
-- memiliki organization_id.
DO $$
DECLARE v_org UUID;
BEGIN
  SELECT organization_id INTO v_org FROM public.profiles ORDER BY created_at LIMIT 1;
  IF v_org IS NOT NULL THEN
    ALTER TABLE public.pengeluaran DISABLE TRIGGER USER;
    UPDATE public.pengeluaran SET organization_id=v_org WHERE organization_id IS NULL;
    ALTER TABLE public.pengeluaran ENABLE TRIGGER USER;
  END IF;
END $$;

-- Diagnostik akhir (tidak mengubah data):
SELECT
  (SELECT count(*) FROM auth.users) AS total_auth_users,
  (SELECT count(*) FROM public.profiles) AS total_profiles,
  (SELECT count(*) FROM public.organizations) AS total_organizations,
  (SELECT count(*) FROM public.pemasukan WHERE organization_id IS NULL) AS pemasukan_tanpa_tenant,
  (SELECT count(*) FROM public.pengeluaran WHERE organization_id IS NULL) AS pengeluaran_tanpa_tenant,
  (SELECT count(*) FROM public.master_kelas WHERE organization_id IS NULL) AS kelas_tanpa_tenant;
