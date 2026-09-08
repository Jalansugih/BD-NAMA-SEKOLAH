-- ============================================================================
-- RAJAKAS BENDAHARA - FIX MULTI-TENANT BOOTSTRAP
--
-- Jalankan SETELAH migration_v7_multi_tenant.sql.
--
-- Gejala yang diperbaiki:
--   "new row violates row-level security policy for table master_kelas"
--
-- Penyebab utama:
--   RLS master_kelas memeriksa:
--     organization_id = public.get_auth_org_id()
--   tetapi sebagian akun belum mempunyai baris public.profiles.
--   Akibatnya get_auth_org_id() = NULL dan INSERT selalu ditolak.
--
-- Solusi:
--   1. Sediakan RPC SECURITY DEFINER yang memastikan setiap user login
--      mempunyai organization + profile + konfigurasi awal.
--   2. RPC idempotent: aman dipanggil setiap kali aplikasi selesai login.
--   3. Frontend memanggil RPC INI sebelum membaca/menulis data tenant.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.ensure_my_organization()
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_org_id UUID;
  v_new_org_id UUID;
  v_inserted BOOLEAN := FALSE;
  v_email TEXT;
  v_name TEXT;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'User belum login.';
  END IF;

  -- Normal path: profile sudah tersedia (trigger atau bootstrap sebelumnya).
  SELECT p.organization_id
    INTO v_org_id
    FROM public.profiles p
   WHERE p.id = v_uid
   LIMIT 1;

  IF v_org_id IS NOT NULL THEN
    -- Pastikan konfigurasi dasar tersedia.
    INSERT INTO public.konfigurasi_lembaga
      (organization_id, nama_lembaga, jenis_lembaga, saldo_awal, tahun_ajaran)
    VALUES
      (v_org_id, '', 'SD', 0, '2025/2026')
    ON CONFLICT (organization_id) DO NOTHING;

    RETURN v_org_id;
  END IF;

  -- Bootstrap akun yang belum mempunyai profile.
  SELECT email,
         COALESCE(
           NULLIF(raw_user_meta_data->>'name', ''),
           NULLIF(raw_user_meta_data->>'full_name', ''),
           NULLIF(split_part(COALESCE(email, ''), '@', 1), ''),
           'Lembaga Baru'
         )
    INTO v_email, v_name
    FROM auth.users
   WHERE id = v_uid;

  IF v_email IS NULL THEN
    RAISE EXCEPTION 'User authentication tidak ditemukan.';
  END IF;

  INSERT INTO public.organizations (nama)
  VALUES (LEFT(v_name || ' - Lembaga Baru', 150))
  RETURNING id INTO v_new_org_id;

  INSERT INTO public.profiles (id, organization_id, email, role)
  VALUES (v_uid, v_new_org_id, v_email, 'owner')
  ON CONFLICT (id) DO NOTHING;

  IF FOUND THEN
    v_inserted := TRUE;
    v_org_id := v_new_org_id;
  ELSE
    -- Ada request paralel yang lebih dulu membuat profile.
    SELECT p.organization_id
      INTO v_org_id
      FROM public.profiles p
     WHERE p.id = v_uid
     LIMIT 1;

    IF v_org_id IS NULL THEN
      RAISE EXCEPTION 'Gagal membuat organization/profile untuk user.';
    END IF;

    -- Jangan meninggalkan organisasi yatim yang dibuat oleh request ini.
    DELETE FROM public.organizations WHERE id = v_new_org_id;
  END IF;

  INSERT INTO public.konfigurasi_lembaga
    (organization_id, nama_lembaga, jenis_lembaga, saldo_awal, tahun_ajaran)
  VALUES
    (v_org_id, '', 'SD', 0, '2025/2026')
  ON CONFLICT (organization_id) DO NOTHING;

  -- Periode awal dibuat jika tabel sudah tersedia. ON CONFLICT membuatnya aman
  -- dipanggil berulang kali.
  IF to_regclass('public.periode_pembukuan') IS NOT NULL THEN
    INSERT INTO public.periode_pembukuan
      (organization_id, nama_periode, tahun_ajaran, tanggal_mulai, saldo_awal, status, created_by)
    VALUES
      (v_org_id, '2025/2026', '2025/2026', '2025-07-01', 0, 'AKTIF', v_uid)
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN v_org_id;
END;
$$;

REVOKE ALL ON FUNCTION public.ensure_my_organization() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_my_organization() TO authenticated;

-- Pastikan trigger auto-provisioning tetap terpasang untuk akun yang benar-benar baru.
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
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = NEW.id) THEN
    RETURN NEW;
  END IF;

  v_nama_awal := COALESCE(
    NULLIF(NEW.raw_user_meta_data->>'name',''),
    NULLIF(NEW.raw_user_meta_data->>'full_name',''),
    NULLIF(split_part(COALESCE(NEW.email,''),'@',1),''),
    'Lembaga Baru'
  );

  INSERT INTO public.organizations (nama)
  VALUES (LEFT(v_nama_awal || ' - Lembaga Baru', 150))
  RETURNING id INTO v_org_id;

  INSERT INTO public.profiles (id, organization_id, email, role)
  VALUES (NEW.id, v_org_id, NEW.email, 'owner');

  INSERT INTO public.konfigurasi_lembaga
    (organization_id, nama_lembaga, jenis_lembaga, saldo_awal, tahun_ajaran)
  VALUES (v_org_id, '', 'SD', 0, '2025/2026')
  ON CONFLICT (organization_id) DO NOTHING;

  IF to_regclass('public.periode_pembukuan') IS NOT NULL THEN
    INSERT INTO public.periode_pembukuan
      (organization_id, nama_periode, tahun_ajaran, tanggal_mulai, saldo_awal, status, created_by)
    VALUES
      (v_org_id, '2025/2026', '2025/2026', '2025-07-01', 0, 'AKTIF', NEW.id)
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_multi_tenant ON auth.users;
CREATE TRIGGER on_auth_user_created_multi_tenant
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_multi_tenant();

-- ============================================================================
-- VERIFIKASI (jalankan setelah login bila ingin mengecek)
-- SELECT public.get_auth_org_id();
-- SELECT public.ensure_my_organization();
-- ============================================================================
