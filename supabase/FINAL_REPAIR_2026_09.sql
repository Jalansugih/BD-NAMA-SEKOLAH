-- RAJAKAS - FINAL REPAIR 2026-09
-- Jalankan SEKALI di Supabase SQL Editor menggunakan role postgres.
-- Tidak menghapus data transaksi.
-- Fokus: organisasi/profil, periode aktif, RPC profil, pembayaran siswa,
-- pengeluaran, dan Storage bukti/logo.

BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS public.organizations (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama varchar(150) NOT NULL DEFAULT 'Lembaga Baru',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.profiles (
  id uuid PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE,
  email varchar(255),
  role varchar(20) NOT NULL DEFAULT 'owner',
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS public.periode_pembukuan (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nama_periode varchar(50) NOT NULL,
  tahun_ajaran varchar(20) NOT NULL DEFAULT '2025/2026',
  tanggal_mulai date NOT NULL,
  tanggal_akhir date,
  saldo_awal numeric(15,2) NOT NULL DEFAULT 0,
  saldo_akhir numeric(15,2),
  status varchar(10) NOT NULL DEFAULT 'AKTIF',
  created_at timestamptz DEFAULT now(),
  created_by uuid,
  closed_at timestamptz,
  closed_by uuid
);

-- ================================================================
-- 0. KOMPATIBILITAS SCHEMA ORGANISASI
-- V6/V7 memakai `nama`, sedangkan repair final memakai `name`,
-- `organization_type`, `email`, dan `updated_at`. Tambahkan kolom
-- yang mungkin belum ada agar satu repair SQL bisa dipakai pada
-- database lama maupun database yang sudah dimigrasikan sebagian.
-- ================================================================
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS nama varchar(150);
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS name varchar(255);
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS organization_type varchar(30) DEFAULT 'yayasan';
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS email varchar(255);
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

UPDATE public.organizations
SET name = COALESCE(NULLIF(name, ''), NULLIF(nama, ''), 'Lembaga Baru'),
    email = COALESCE(NULLIF(email, ''), 'admin@local'),
    organization_type = COALESCE(NULLIF(organization_type, ''), 'yayasan'),
    updated_at = COALESCE(updated_at, now());

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS name varchar(255);
ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();

UPDATE public.profiles
SET name = COALESCE(NULLIF(name, ''), split_part(COALESCE(email, ''), '@', 1), 'Pengguna'),
    updated_at = COALESCE(updated_at, now())
WHERE name IS NULL OR name = '';


-- ================================================================
-- 0B. NORMALISASI KONFIGURASI LEMBAGA
-- Provisioning memakai ON CONFLICT (organization_id), jadi constraint
-- unik/PK harus siap SEBELUM fungsi provisioning dipanggil.
-- ================================================================
CREATE TABLE IF NOT EXISTS public.konfigurasi_lembaga (
  organization_id uuid PRIMARY KEY REFERENCES public.organizations(id) ON DELETE CASCADE,
  nama_lembaga varchar(150) NOT NULL DEFAULT '',
  jenis_lembaga varchar(30) NOT NULL DEFAULT 'SD',
  logo_url text,
  saldo_awal numeric(15,2) NOT NULL DEFAULT 0,
  npsn varchar(30),
  alamat text,
  kontak varchar(50),
  website varchar(150),
  tahun_ajaran varchar(20),
  updated_at timestamptz DEFAULT now(),
  updated_by uuid
);

-- Tambahkan organization_id sebelum blok normalisasi menyentuh kolom tersebut.
ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE;

-- Jika schema lama masih singleton id=TRUE, lepaskan view/dependency dan
-- kaitkan baris lama ke organisasi pertama sebelum mengubah primary key.
DO $$
DECLARE
  v_org uuid;
  v_has_id boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='konfigurasi_lembaga' AND column_name='id'
  ) INTO v_has_id;

  IF v_has_id THEN
    DROP VIEW IF EXISTS public.saldo_kas;

    SELECT id INTO v_org
    FROM public.organizations
    ORDER BY created_at, id
    LIMIT 1;

    IF v_org IS NULL THEN
      INSERT INTO public.organizations (nama)
      VALUES ('Lembaga Utama (Migrasi)')
      RETURNING id INTO v_org;
    END IF;

    UPDATE public.konfigurasi_lembaga
    SET organization_id = COALESCE(organization_id, v_org)
    WHERE organization_id IS NULL;

    ALTER TABLE public.konfigurasi_lembaga
      DROP CONSTRAINT IF EXISTS konfigurasi_lembaga_pkey;

    ALTER TABLE public.konfigurasi_lembaga
      DROP COLUMN IF EXISTS id;
  END IF;
END $$;

-- Pastikan semua konfigurasi lama terikat organisasi.
DO $$
DECLARE
  v_org uuid;
BEGIN
  SELECT id INTO v_org FROM public.organizations ORDER BY created_at, id LIMIT 1;
  IF v_org IS NOT NULL THEN
    UPDATE public.konfigurasi_lembaga
    SET organization_id = v_org
    WHERE organization_id IS NULL;
  END IF;
END $$;

-- Deduplikasi konfigurasi jika repair lama pernah membuat lebih dari satu row.
DELETE FROM public.konfigurasi_lembaga k
WHERE k.ctid IN (
  SELECT ctid FROM (
    SELECT ctid, ROW_NUMBER() OVER (
      PARTITION BY organization_id
      ORDER BY updated_at DESC NULLS LAST, ctid DESC
    ) rn
    FROM public.konfigurasi_lembaga
    WHERE organization_id IS NOT NULL
  ) d WHERE d.rn > 1
);

ALTER TABLE public.konfigurasi_lembaga
  ALTER COLUMN organization_id SET NOT NULL;

ALTER TABLE public.konfigurasi_lembaga
  DROP CONSTRAINT IF EXISTS konfigurasi_lembaga_pkey;
ALTER TABLE public.konfigurasi_lembaga
  ADD CONSTRAINT konfigurasi_lembaga_pkey PRIMARY KEY (organization_id);

-- ================================================================
-- 1. FONDASI MULTI-LEMBAGA: organization user yang sedang login
-- ================================================================
CREATE OR REPLACE FUNCTION public.get_auth_org_id()
RETURNS uuid
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'AUTH_REQUIRED';
  END IF;

  -- Arsitektur final hanya memakai profiles.organization_id.
  -- Jangan lagi membaca tenant_members agar legacy schema tidak memblokir login.
  SELECT p.organization_id
    INTO v_org
    FROM public.profiles p
   WHERE p.id = auth.uid()
   LIMIT 1;

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'AUTH_ORGANIZATION_NOT_FOUND';
  END IF;

  RETURN v_org;
END;
$$;

REVOKE ALL ON FUNCTION public.get_auth_org_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_auth_org_id() TO authenticated;

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS rk_org_select ON public.organizations;
DROP POLICY IF EXISTS rk_org_update ON public.organizations;
CREATE POLICY rk_org_select ON public.organizations
  FOR SELECT TO authenticated
  USING (id = public.get_auth_org_id());
CREATE POLICY rk_org_update ON public.organizations
  FOR UPDATE TO authenticated
  USING (id = public.get_auth_org_id())
  WITH CHECK (id = public.get_auth_org_id());

DROP POLICY IF EXISTS rk_profile_select ON public.profiles;
DROP POLICY IF EXISTS rk_profile_update ON public.profiles;
CREATE POLICY rk_profile_select ON public.profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid() OR organization_id = public.get_auth_org_id());
CREATE POLICY rk_profile_update ON public.profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid() AND organization_id = public.get_auth_org_id());

GRANT SELECT, UPDATE ON public.organizations TO authenticated;
GRANT SELECT, UPDATE ON public.profiles TO authenticated;

-- ================================================================
-- 2. Pastikan kolom periode/config yang dibutuhkan tersedia
-- ================================================================
ALTER TABLE public.periode_pembukuan
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.periode_pembukuan
  ADD COLUMN IF NOT EXISTS tahun_ajaran varchar(20);
ALTER TABLE public.periode_pembukuan
  ADD COLUMN IF NOT EXISTS tanggal_akhir date;
ALTER TABLE public.periode_pembukuan
  ADD COLUMN IF NOT EXISTS saldo_akhir numeric(15,2);
ALTER TABLE public.periode_pembukuan
  ADD COLUMN IF NOT EXISTS created_by uuid;
ALTER TABLE public.periode_pembukuan
  ADD COLUMN IF NOT EXISTS closed_at timestamptz;
ALTER TABLE public.periode_pembukuan
  ADD COLUMN IF NOT EXISTS closed_by uuid;
ALTER TABLE public.audit_log
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.master_kelas
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.master_sumber_dana
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.master_kategori
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.siswa_tagihan
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.pemasukan
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.pengeluaran
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE;

ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS organization_id uuid REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS tahun_ajaran varchar(20);
ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS npsn varchar(30);
ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS alamat text;
ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS kontak varchar(50);
ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS website varchar(150);
ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS logo_url text;
ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now();
ALTER TABLE public.konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS updated_by uuid;

-- ================================================================
-- 3. SELF-HEALING AKUN: profile -> organization -> config -> periode aktif
-- ================================================================
-- PostgreSQL tidak mengizinkan CREATE OR REPLACE mengubah return type
-- fungsi yang sudah ada. Hapus signature lama terlebih dahulu.
DROP FUNCTION IF EXISTS public.provision_user_account(uuid,text,text);

CREATE OR REPLACE FUNCTION public.provision_user_account(
  p_user_id uuid,
  p_email text DEFAULT NULL,
  p_name text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id uuid;
  v_email text;
  v_name text;
  v_org_name text;
  v_tahun text;
  v_tanggal_mulai date;
  v_owner_id uuid;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'USER_ID_INVALID';
  END IF;

  v_email := COALESCE(NULLIF(trim(p_email), ''), 'user-' || p_user_id::text || '@local');
  v_name := COALESCE(NULLIF(trim(p_name), ''), split_part(v_email, '@', 1), 'Lembaga Baru');
  v_org_name := LEFT(v_name || ' - Lembaga Baru', 255);

  SELECT p.organization_id
    INTO v_org_id
    FROM public.profiles p
   WHERE p.id = p_user_id
   LIMIT 1;

  -- Jika profile belum punya organisasi, buat organisasi BARU untuk user ini.
  IF v_org_id IS NULL THEN
    INSERT INTO public.organizations
      (id, organization_type, name, email, created_at, updated_at)
    VALUES
      (gen_random_uuid(), 'yayasan', v_org_name, v_email, now(), now())
    RETURNING id INTO v_org_id;

    INSERT INTO public.profiles
      (id, organization_id, name, email, role, created_at, updated_at)
    VALUES
      (p_user_id, v_org_id, v_name, v_email, 'owner', now(), now())
    ON CONFLICT (id) DO UPDATE
      SET organization_id = COALESCE(public.profiles.organization_id, EXCLUDED.organization_id),
          name = COALESCE(NULLIF(public.profiles.name, ''), EXCLUDED.name),
          email = COALESCE(NULLIF(public.profiles.email, ''), EXCLUDED.email),
          updated_at = now();
  ELSE
    UPDATE public.profiles
       SET email = COALESCE(NULLIF(email, ''), v_email),
           name = COALESCE(NULLIF(name, ''), v_name),
           updated_at = now()
     WHERE id = p_user_id;
  END IF;

  -- Bila organisasi sudah ada tetapi profile belum menunjuknya, pastikan profile valid.
  UPDATE public.profiles
     SET organization_id = v_org_id,
         updated_at = now()
   WHERE id = p_user_id AND organization_id IS NULL;

  -- Pastikan konfigurasi lembaga ada.
  INSERT INTO public.konfigurasi_lembaga
    (organization_id, nama_lembaga, jenis_lembaga, saldo_awal, tahun_ajaran, updated_at, updated_by)
  VALUES
    (v_org_id, '', 'SD', 0, NULL, now(), p_user_id)
  ON CONFLICT (organization_id) DO NOTHING;

  -- Tahun ajaran aktif: Juli 2026 -> 2026/2027; Januari-Juni -> tahun sebelumnya.
  IF EXTRACT(MONTH FROM CURRENT_DATE) >= 7 THEN
    v_tahun := EXTRACT(YEAR FROM CURRENT_DATE)::int::text || '/' || (EXTRACT(YEAR FROM CURRENT_DATE)::int + 1)::text;
    v_tanggal_mulai := make_date(EXTRACT(YEAR FROM CURRENT_DATE)::int, 7, 1);
  ELSE
    v_tahun := (EXTRACT(YEAR FROM CURRENT_DATE)::int - 1)::text || '/' || EXTRACT(YEAR FROM CURRENT_DATE)::int::text;
    v_tanggal_mulai := make_date(EXTRACT(YEAR FROM CURRENT_DATE)::int - 1, 7, 1);
  END IF;

  SELECT p.id
    INTO v_owner_id
    FROM public.profiles p
   WHERE p.organization_id = v_org_id
   ORDER BY CASE WHEN p.role = 'owner' THEN 0 ELSE 1 END, p.created_at
   LIMIT 1;

  IF NOT EXISTS (
    SELECT 1 FROM public.periode_pembukuan pp
     WHERE pp.organization_id = v_org_id AND pp.status = 'AKTIF'
  ) THEN
    INSERT INTO public.periode_pembukuan
      (organization_id, nama_periode, tahun_ajaran, tanggal_mulai, tanggal_akhir, saldo_awal, saldo_akhir, status, created_by)
    VALUES
      (v_org_id, v_tahun, v_tahun, v_tanggal_mulai, NULL, 0, NULL, 'AKTIF', COALESCE(v_owner_id, p_user_id));
  END IF;

  -- Sinkronkan konfigurasi awal dengan periode aktif jika masih kosong.
  UPDATE public.konfigurasi_lembaga k
     SET tahun_ajaran = COALESCE(NULLIF(k.tahun_ajaran, ''), v_tahun),
         updated_at = now(),
         updated_by = p_user_id
   WHERE k.organization_id = v_org_id;

  RETURN v_org_id;
END;
$$;

REVOKE ALL ON FUNCTION public.provision_user_account(uuid,text,text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.provision_user_account(uuid,text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.ensure_user_setup()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_email text;
  v_name text;
  v_org uuid;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'AUTH_REQUIRED'; END IF;

  SELECT u.email,
         COALESCE(NULLIF(u.raw_user_meta_data->>'full_name',''),
                  NULLIF(u.raw_user_meta_data->>'name',''))
    INTO v_email, v_name
    FROM auth.users u
   WHERE u.id = v_uid;

  IF v_email IS NULL THEN RAISE EXCEPTION 'USER_TIDAK_DITEMUKAN'; END IF;

  v_org := public.provision_user_account(v_uid, v_email, v_name);
  RETURN jsonb_build_object('organization_id', v_org, 'ready', true);
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_user_setup() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_user_setup() TO authenticated;

-- Trigger user baru: email/password maupun Google first login.
CREATE OR REPLACE FUNCTION public.handle_new_user_multi_tenant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM public.provision_user_account(
    NEW.id,
    NEW.email,
    COALESCE(NULLIF(NEW.raw_user_meta_data->>'full_name',''), NULLIF(NEW.raw_user_meta_data->>'name',''))
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS on_auth_user_created_multi_tenant ON auth.users;
CREATE TRIGGER on_auth_user_created_multi_tenant
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_multi_tenant();

-- ================================================================
-- 3B. BACKFILL ORGANIZATION UNTUK TRANSAKSI LEGACY
-- Prioritaskan created_by -> profiles. Jika sudah terisi oleh migration lama,
-- blok ini tidak mengubah apa pun.
-- ================================================================
UPDATE public.siswa_tagihan s
SET organization_id = p.organization_id
FROM public.profiles p
WHERE s.organization_id IS NULL
  AND s.created_by = p.id
  AND p.organization_id IS NOT NULL;

UPDATE public.pemasukan x
SET organization_id = p.organization_id
FROM public.profiles p
WHERE x.organization_id IS NULL
  AND x.created_by = p.id
  AND p.organization_id IS NOT NULL;

UPDATE public.pengeluaran x
SET organization_id = p.organization_id
FROM public.profiles p
WHERE x.organization_id IS NULL
  AND x.created_by = p.id
  AND p.organization_id IS NOT NULL;

UPDATE public.audit_log a
SET organization_id = p.organization_id
FROM public.profiles p
WHERE a.organization_id IS NULL
  AND a.user_id = p.id::text
  AND p.organization_id IS NOT NULL;

-- ================================================================
-- 4. Backfill semua user Auth yang belum punya fondasi
-- ================================================================
DO $$
DECLARE u record;
BEGIN
  FOR u IN SELECT id, email, raw_user_meta_data FROM auth.users LOOP
    PERFORM public.provision_user_account(
      u.id,
      u.email,
      COALESCE(NULLIF(u.raw_user_meta_data->>'full_name',''), NULLIF(u.raw_user_meta_data->>'name',''))
    );
  END LOOP;
END $$;

-- ================================================================
-- 5. Tepat satu periode AKTIF per organisasi
-- ================================================================
DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif;
DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif_per_org;

-- Jika repair pernah dijalankan sebagian dan ada lebih dari satu AKTIF
-- dalam organisasi yang sama, pertahankan periode terbaru saja.
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
    tanggal_akhir = COALESCE(p.tanggal_akhir, p.tanggal_mulai),
    saldo_akhir = COALESCE(p.saldo_akhir, p.saldo_awal),
    closed_at = COALESCE(p.closed_at, now())
FROM ranked r
WHERE p.id = r.id AND r.rn > 1;

CREATE UNIQUE INDEX IF NOT EXISTS ux_periode_pembukuan_satu_aktif_per_org
  ON public.periode_pembukuan (organization_id)
  WHERE status = 'AKTIF';

-- ================================================================
-- 6. RPC PROFIL LEMBAGA - signature final 10 argumen
-- ================================================================
DROP FUNCTION IF EXISTS public.save_konfigurasi_lembaga(text,text,text,text,text,text,text,numeric,text,boolean);
DROP FUNCTION IF EXISTS public.save_konfigurasi_lembaga(text,text);
DROP FUNCTION IF EXISTS public.save_konfigurasi_lembaga(numeric);

CREATE OR REPLACE FUNCTION public.save_konfigurasi_lembaga(
  p_nama_lembaga text,
  p_jenis_lembaga text,
  p_npsn text,
  p_alamat text,
  p_kontak text,
  p_website text,
  p_tahun_ajaran text,
  p_saldo_awal numeric,
  p_logo_url text,
  p_clear_logo boolean
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.get_auth_org_id();
  v_row public.konfigurasi_lembaga;
BEGIN
  INSERT INTO public.konfigurasi_lembaga
    (organization_id, nama_lembaga, jenis_lembaga, npsn, alamat, kontak, website, tahun_ajaran, saldo_awal, logo_url, updated_at, updated_by)
  VALUES
    (v_org,
     COALESCE(p_nama_lembaga, ''),
     COALESCE(p_jenis_lembaga, 'SD'),
     p_npsn, p_alamat, p_kontak, p_website,
     p_tahun_ajaran,
     COALESCE(p_saldo_awal, 0),
     CASE WHEN COALESCE(p_clear_logo, false) THEN NULL ELSE p_logo_url END,
     now(), auth.uid())
  ON CONFLICT (organization_id) DO UPDATE SET
    nama_lembaga = COALESCE(p_nama_lembaga, public.konfigurasi_lembaga.nama_lembaga),
    jenis_lembaga = COALESCE(p_jenis_lembaga, public.konfigurasi_lembaga.jenis_lembaga),
    npsn = COALESCE(p_npsn, public.konfigurasi_lembaga.npsn),
    alamat = COALESCE(p_alamat, public.konfigurasi_lembaga.alamat),
    kontak = COALESCE(p_kontak, public.konfigurasi_lembaga.kontak),
    website = COALESCE(p_website, public.konfigurasi_lembaga.website),
    tahun_ajaran = COALESCE(p_tahun_ajaran, public.konfigurasi_lembaga.tahun_ajaran),
    saldo_awal = COALESCE(p_saldo_awal, public.konfigurasi_lembaga.saldo_awal),
    logo_url = CASE
      WHEN COALESCE(p_clear_logo, false) THEN NULL
      WHEN p_logo_url IS NOT NULL THEN p_logo_url
      ELSE public.konfigurasi_lembaga.logo_url
    END,
    updated_at = now(),
    updated_by = auth.uid()
  RETURNING * INTO v_row;

  RETURN row_to_json(v_row)::jsonb;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_konfigurasi_lembaga(text,text,text,text,text,text,text,numeric,text,boolean) TO authenticated;

-- Kompatibilitas dengan frontend/versi lama yang hanya mengirim 2 parameter.
CREATE OR REPLACE FUNCTION public.save_konfigurasi_lembaga(
  p_jenis_lembaga text,
  p_nama_lembaga text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.save_konfigurasi_lembaga(
    p_nama_lembaga, p_jenis_lembaga, NULL, NULL, NULL, NULL, NULL, NULL, NULL, false
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.save_konfigurasi_lembaga(text,text) TO authenticated;

CREATE OR REPLACE FUNCTION public.save_konfigurasi_lembaga(p_saldo_awal numeric)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN public.save_konfigurasi_lembaga(
    NULL, NULL, NULL, NULL, NULL, NULL, NULL, p_saldo_awal, NULL, false
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.save_konfigurasi_lembaga(numeric) TO authenticated;

-- ================================================================
-- 7. PEMBAYARAN SISWA - org scoped + periode aktif
-- ================================================================
CREATE OR REPLACE FUNCTION public.catat_pembayaran_siswa(
  p_siswa_id uuid,
  p_no_bukti text,
  p_tanggal date,
  p_status text,
  p_nominal numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.get_auth_org_id();
  v_siswa public.siswa_tagihan%ROWTYPE;
  v_periode public.periode_pembukuan%ROWTYPE;
  v_row public.pemasukan%ROWTYPE;
  v_no_bukti text;
BEGIN
  SELECT * INTO v_siswa
    FROM public.siswa_tagihan
   WHERE id = p_siswa_id AND organization_id = v_org;
  IF NOT FOUND THEN RAISE EXCEPTION 'SISWA_TIDAK_DITEMUKAN'; END IF;

  SELECT * INTO v_periode
    FROM public.periode_pembukuan
   WHERE organization_id = v_org AND status = 'AKTIF'
   ORDER BY tanggal_mulai DESC
   LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERIODE_AKTIF_TIDAK_DITEMUKAN'; END IF;

  IF COALESCE(p_nominal, 0) <= 0 THEN RAISE EXCEPTION 'NOMINAL_INVALID'; END IF;
  IF COALESCE(p_tanggal, CURRENT_DATE) < v_periode.tanggal_mulai THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI';
  END IF;

  v_no_bukti := NULLIF(BTRIM(COALESCE(p_no_bukti, '')), '');
  IF v_no_bukti IS NULL THEN
    v_no_bukti := 'BYR-' || TO_CHAR(COALESCE(p_tanggal, CURRENT_DATE), 'YYYYMMDD') || '-' || TO_CHAR(CLOCK_TIMESTAMP(), 'HH24MISSMS');
  END IF;

  INSERT INTO public.pemasukan
    (organization_id, no_bukti, tanggal, sumber, sub, nominal, keterangan, status, siswa_id, created_by)
  VALUES
    (v_org, v_no_bukti, COALESCE(p_tanggal, CURRENT_DATE), 'Pembayaran', v_siswa.jenis,
     p_nominal,
     'Pembayaran ' || v_siswa.jenis || ' a.n ' || v_siswa.nama || ' (' || v_siswa.kelas || ')',
     COALESCE(NULLIF(BTRIM(p_status), ''), 'Selesai'), p_siswa_id, auth.uid())
  RETURNING * INTO v_row;

  RETURN row_to_json(v_row)::jsonb;
END;
$$;
GRANT EXECUTE ON FUNCTION public.catat_pembayaran_siswa(uuid,text,date,text,numeric) TO authenticated;

-- ================================================================
-- 8. PENGELUARAN - org scoped + periode aktif
-- ================================================================
CREATE OR REPLACE FUNCTION public.catat_pengeluaran(
  p_no_bukti text,
  p_tanggal date,
  p_kategori text,
  p_nominal numeric,
  p_keterangan text,
  p_status text DEFAULT 'Terbayar',
  p_bukti_url text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.get_auth_org_id();
  v_periode public.periode_pembukuan%ROWTYPE;
  v_row public.pengeluaran%ROWTYPE;
BEGIN
  SELECT * INTO v_periode
    FROM public.periode_pembukuan
   WHERE organization_id = v_org AND status = 'AKTIF'
   ORDER BY tanggal_mulai DESC
   LIMIT 1;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERIODE_AKTIF_TIDAK_DITEMUKAN'; END IF;

  IF COALESCE(p_nominal, 0) <= 0 THEN RAISE EXCEPTION 'NOMINAL_INVALID'; END IF;
  IF COALESCE(p_tanggal, CURRENT_DATE) < v_periode.tanggal_mulai THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI';
  END IF;

  INSERT INTO public.pengeluaran
    (organization_id, no_bukti, tanggal, kategori, nominal, keterangan, status, bukti_url, created_by)
  VALUES
    (v_org, p_no_bukti, COALESCE(p_tanggal, CURRENT_DATE), p_kategori, p_nominal,
     p_keterangan, COALESCE(NULLIF(BTRIM(p_status), ''), 'Terbayar'), p_bukti_url, auth.uid())
  RETURNING * INTO v_row;

  RETURN row_to_json(v_row)::jsonb;
END;
$$;
GRANT EXECUTE ON FUNCTION public.catat_pengeluaran(text,date,text,numeric,text,text,text) TO authenticated;

-- ================================================================
-- 8A. GET PERIODE AKTIF
-- ================================================================
CREATE OR REPLACE FUNCTION public.get_active_periode_pembukuan()
RETURNS public.periode_pembukuan
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.get_auth_org_id();
  v_row public.periode_pembukuan;
BEGIN
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'AUTH_ORGANIZATION_NOT_FOUND';
  END IF;

  SELECT * INTO v_row
  FROM public.periode_pembukuan
  WHERE organization_id = v_org
    AND UPPER(status) = 'AKTIF'
  ORDER BY tanggal_mulai DESC, created_at DESC
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PERIODE_AKTIF_TIDAK_DITEMUKAN';
  END IF;

  RETURN v_row;
END;
$$;

REVOKE ALL ON FUNCTION public.get_active_periode_pembukuan() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_active_periode_pembukuan() TO authenticated;

-- ================================================================
-- 8B. SIMPAN PERIODE AKTIF SECARA ATOMIC
-- Frontend tidak lagi melakukan UPDATE langsung yang bergantung pada
-- state React. Organization dan status AKTIF divalidasi server-side.
-- ================================================================
DROP FUNCTION IF EXISTS public.save_periode_aktif(uuid,text,date,numeric);

CREATE FUNCTION public.save_periode_aktif(
  p_periode_id uuid,
  p_tahun_ajaran text,
  p_tanggal_mulai date,
  p_saldo_awal numeric
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.get_auth_org_id();
  v_row public.periode_pembukuan%ROWTYPE;
BEGIN
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'AUTH_ORGANIZATION_NOT_FOUND';
  END IF;

  IF p_periode_id IS NULL THEN
    RAISE EXCEPTION 'PERIODE_AKTIF_TIDAK_DITEMUKAN';
  END IF;

  IF p_tahun_ajaran IS NULL OR p_tahun_ajaran !~ '^[0-9]{4}/[0-9]{4}$' THEN
    RAISE EXCEPTION 'TAHUN_AJARAN_INVALID';
  END IF;

  IF p_tanggal_mulai IS NULL THEN
    RAISE EXCEPTION 'TANGGAL_MULAI_INVALID';
  END IF;

  IF p_saldo_awal IS NULL OR p_saldo_awal < 0 THEN
    RAISE EXCEPTION 'SALDO_AWAL_INVALID';
  END IF;

  SELECT * INTO v_row
  FROM public.periode_pembukuan
  WHERE id = p_periode_id
    AND organization_id = v_org
    AND status = 'AKTIF'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PERIODE_AKTIF_TIDAK_DITEMUKAN';
  END IF;

  UPDATE public.periode_pembukuan
  SET nama_periode = p_tahun_ajaran,
      tahun_ajaran = p_tahun_ajaran,
      tanggal_mulai = p_tanggal_mulai,
      saldo_awal = p_saldo_awal
  WHERE id = p_periode_id
    AND organization_id = v_org
    AND status = 'AKTIF'
  RETURNING * INTO v_row;

  UPDATE public.konfigurasi_lembaga
  SET tahun_ajaran = p_tahun_ajaran,
      saldo_awal = p_saldo_awal,
      updated_at = now(),
      updated_by = auth.uid()
  WHERE organization_id = v_org;

  RETURN row_to_json(v_row)::jsonb;
END;
$$;

REVOKE ALL ON FUNCTION public.save_periode_aktif(uuid,text,date,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.save_periode_aktif(uuid,text,date,numeric) TO authenticated;

-- ================================================================
-- 9. Tutup buku - org scoped
-- ================================================================
-- PostgreSQL tidak mengizinkan CREATE OR REPLACE menghapus default parameter
-- dari signature yang sudah ada. Drop signature persis sebelum recreate.
DROP FUNCTION IF EXISTS public.hitung_saldo_akhir_periode(uuid,date);

CREATE FUNCTION public.hitung_saldo_akhir_periode(
  p_periode_id uuid,
  p_tanggal_cutoff date
)
RETURNS numeric
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.get_auth_org_id();
  v_awal numeric;
  v_mulai date;
BEGIN
  SELECT saldo_awal, tanggal_mulai INTO v_awal, v_mulai
    FROM public.periode_pembukuan
   WHERE id = p_periode_id AND organization_id = v_org;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERIODE_TIDAK_DITEMUKAN'; END IF;
  IF p_tanggal_cutoff < v_mulai THEN RAISE EXCEPTION 'TANGGAL_CUTOFF_INVALID'; END IF;

  RETURN COALESCE(v_awal,0)
    + COALESCE((SELECT SUM(nominal) FROM public.pemasukan WHERE organization_id=v_org AND tanggal BETWEEN v_mulai AND p_tanggal_cutoff),0)
    - COALESCE((SELECT SUM(nominal) FROM public.pengeluaran WHERE organization_id=v_org AND tanggal BETWEEN v_mulai AND p_tanggal_cutoff),0);
END;
$$;
GRANT EXECUTE ON FUNCTION public.hitung_saldo_akhir_periode(uuid,date) TO authenticated;

CREATE OR REPLACE FUNCTION public.tutup_buku(p_periode_id uuid, p_tanggal_cutoff date)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.get_auth_org_id();
  v_p public.periode_pembukuan%ROWTYPE;
  v_next public.periode_pembukuan%ROWTYPE;
  v_saldo numeric;
  v_next_year text;
BEGIN
  SELECT * INTO v_p
    FROM public.periode_pembukuan
   WHERE id=p_periode_id AND organization_id=v_org
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'PERIODE_TIDAK_DITEMUKAN'; END IF;
  IF v_p.status <> 'AKTIF' THEN RAISE EXCEPTION 'PERIODE_SUDAH_DITUTUP'; END IF;
  IF p_tanggal_cutoff < v_p.tanggal_mulai THEN RAISE EXCEPTION 'TANGGAL_CUTOFF_INVALID'; END IF;

  v_saldo := public.hitung_saldo_akhir_periode(p_periode_id, p_tanggal_cutoff);

  IF v_p.tahun_ajaran ~ '^[0-9]{4}/[0-9]{4}$' THEN
    v_next_year := (split_part(v_p.tahun_ajaran,'/',1)::int+1)::text || '/' || (split_part(v_p.tahun_ajaran,'/',2)::int+1)::text;
  ELSE
    v_next_year := v_p.tahun_ajaran;
  END IF;

  UPDATE public.periode_pembukuan
     SET status='DITUTUP', tanggal_akhir=p_tanggal_cutoff, saldo_akhir=v_saldo, closed_at=now(), closed_by=auth.uid()
   WHERE id=p_periode_id AND organization_id=v_org;

  INSERT INTO public.periode_pembukuan
    (organization_id,nama_periode,tahun_ajaran,tanggal_mulai,tanggal_akhir,saldo_awal,saldo_akhir,status,created_by)
  VALUES
    (v_org,v_next_year,v_next_year,p_tanggal_cutoff+1,NULL,v_saldo,NULL,'AKTIF',auth.uid())
  RETURNING * INTO v_next;

  UPDATE public.konfigurasi_lembaga
     SET saldo_awal=v_saldo,tahun_ajaran=v_next_year,updated_at=now(),updated_by=auth.uid()
   WHERE organization_id=v_org;

  RETURN jsonb_build_object('saldo_akhir',v_saldo,'periode_berikutnya',row_to_json(v_next)::jsonb);
END;
$$;
GRANT EXECUTE ON FUNCTION public.tutup_buku(uuid,date) TO authenticated;

-- ================================================================
-- 9B. BUKA KEMBALI BUKU
-- ================================================================
CREATE OR REPLACE FUNCTION public.buka_kembali_buku(p_periode_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org uuid := public.get_auth_org_id();
  v_target public.periode_pembukuan%ROWTYPE;
BEGIN
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'AUTH_ORGANIZATION_NOT_FOUND';
  END IF;

  SELECT * INTO v_target
  FROM public.periode_pembukuan
  WHERE id = p_periode_id
    AND organization_id = v_org
    AND status = 'DITUTUP'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PERIODE_TERTUTUP_TIDAK_DITEMUKAN';
  END IF;

  -- Hanya satu periode aktif per organisasi.
  IF EXISTS (
    SELECT 1 FROM public.periode_pembukuan
    WHERE organization_id = v_org AND status = 'AKTIF'
  ) THEN
    RAISE EXCEPTION 'PERIODE_AKTIF_SUDAH_ADA';
  END IF;

  UPDATE public.periode_pembukuan
  SET status = 'AKTIF',
      tanggal_akhir = NULL,
      saldo_akhir = NULL,
      closed_at = NULL,
      closed_by = NULL
  WHERE id = p_periode_id AND organization_id = v_org;

  RETURN jsonb_build_object(
    'success', true,
    'periode', (
      SELECT row_to_json(x)::jsonb
      FROM public.periode_pembukuan x
      WHERE x.id = p_periode_id
    )
  );
END;
$$;
GRANT EXECUTE ON FUNCTION public.buka_kembali_buku(uuid) TO authenticated;

-- ================================================================
-- 10. RLS bisnis: pastikan org isolation aktif
-- ================================================================
ALTER TABLE public.konfigurasi_lembaga ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.siswa_tagihan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pemasukan ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pengeluaran ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.periode_pembukuan ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS konfigurasi_lembaga_org ON public.konfigurasi_lembaga;
CREATE POLICY konfigurasi_lembaga_org ON public.konfigurasi_lembaga
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS siswa_tagihan_org ON public.siswa_tagihan;
CREATE POLICY siswa_tagihan_org ON public.siswa_tagihan
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS pemasukan_org ON public.pemasukan;
CREATE POLICY pemasukan_org ON public.pemasukan
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS pengeluaran_org ON public.pengeluaran;
CREATE POLICY pengeluaran_org ON public.pengeluaran
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS periode_org ON public.periode_pembukuan;
CREATE POLICY periode_org ON public.periode_pembukuan
  FOR ALL TO authenticated
  USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

GRANT SELECT, INSERT, UPDATE, DELETE ON public.konfigurasi_lembaga TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.siswa_tagihan TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pemasukan TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.pengeluaran TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.periode_pembukuan TO authenticated;

-- ================================================================
-- 11. STORAGE: logos + bukti-pengeluaran
--     Path aplikasi: <auth.uid()>/filename.ext
-- ================================================================
INSERT INTO storage.buckets (id, name, public)
VALUES ('logos', 'logos', true)
ON CONFLICT (id) DO UPDATE SET public = true;

INSERT INTO storage.buckets (id, name, public)
VALUES ('bukti-pengeluaran', 'bukti-pengeluaran', true)
ON CONFLICT (id) DO UPDATE SET public = true;

DROP POLICY IF EXISTS rk_logo_read ON storage.objects;
DROP POLICY IF EXISTS rk_logo_insert ON storage.objects;
DROP POLICY IF EXISTS rk_logo_update ON storage.objects;
DROP POLICY IF EXISTS rk_bukti_read ON storage.objects;
DROP POLICY IF EXISTS rk_bukti_insert ON storage.objects;

CREATE POLICY rk_logo_read ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'logos');

CREATE POLICY rk_logo_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY rk_logo_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'logos'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY rk_bukti_read ON storage.objects
  FOR SELECT TO public
  USING (bucket_id = 'bukti-pengeluaran');

CREATE POLICY rk_bukti_insert ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'bukti-pengeluaran'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY rk_bukti_update ON storage.objects
  FOR UPDATE TO authenticated
  USING (
    bucket_id = 'bukti-pengeluaran'
    AND (storage.foldername(name))[1] = auth.uid()::text
  )
  WITH CHECK (
    bucket_id = 'bukti-pengeluaran'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY rk_bukti_delete ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'bukti-pengeluaran'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );


-- ================================================================
-- 12. Refresh PostgREST schema cache
-- ================================================================
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ================================================================
-- 13. CHECK SETELAH RUN
-- ================================================================
SELECT
  u.email,
  p.organization_id,
  o.name AS organization_name,
  k.nama_lembaga,
  pp.id AS periode_aktif_id,
  pp.tahun_ajaran,
  pp.tanggal_mulai
FROM auth.users u
LEFT JOIN public.profiles p ON p.id=u.id
LEFT JOIN public.organizations o ON o.id=p.organization_id
LEFT JOIN public.konfigurasi_lembaga k ON k.organization_id=p.organization_id
LEFT JOIN LATERAL (
  SELECT * FROM public.periode_pembukuan x
   WHERE x.organization_id=p.organization_id AND x.status='AKTIF'
   ORDER BY x.tanggal_mulai DESC LIMIT 1
) pp ON true
ORDER BY u.created_at DESC;
