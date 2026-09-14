-- =========================================================================
-- BILLINGFLOW V10 — PRODUCTION ORGANIZATION BOOTSTRAP & LEGACY USER REPAIR
-- Jalankan SETELAH migration.sql / v8 / v9 di Supabase SQL Editor.
--
-- Memperbaiki kasus user Auth yang sudah ada sebelum trigger V9 dipasang.
-- V9 mengamankan user BARU, tetapi tidak otomatis memperbaiki auth.users lama.
-- V10 melakukan backfill + menyediakan RPC aman untuk self-healing dari client.
-- =========================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -------------------------------------------------------------------------
-- 1. Internal SECURITY DEFINER bootstrap.
--    Hanya dipanggil oleh trigger atau wrapper current-user.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._bootstrap_user_profile(
  p_user_id UUID,
  p_email TEXT,
  p_full_name TEXT,
  p_org_name TEXT
)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
  v_profile public.profiles;
  v_org_name TEXT := COALESCE(NULLIF(trim(p_org_name), ''), 'Perusahaan Baru');
  v_name TEXT := COALESCE(NULLIF(trim(p_full_name), ''), split_part(COALESCE(p_email, 'user'), '@', 1), 'Pengguna');
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'User ID wajib diisi';
  END IF;

  -- Jika profile lama sudah memiliki organisasi, jangan pindahkan tenant.
  SELECT organization_id
    INTO v_org_id
    FROM public.profiles
   WHERE id = p_user_id;

  IF v_org_id IS NULL THEN
    v_org_id := gen_random_uuid();

    INSERT INTO public.organizations (id, name, email, created_at, updated_at)
    VALUES (v_org_id, v_org_name, COALESCE(p_email, ''), NOW(), NOW());
  END IF;

  INSERT INTO public.profiles (id, organization_id, name, email, role, created_at, updated_at)
  VALUES (
    p_user_id,
    v_org_id,
    v_name,
    COALESCE(p_email, ''),
    'owner',
    NOW(),
    NOW()
  )
  ON CONFLICT (id) DO UPDATE SET
    organization_id = COALESCE(public.profiles.organization_id, EXCLUDED.organization_id),
    name = COALESCE(NULLIF(public.profiles.name, ''), EXCLUDED.name),
    email = COALESCE(NULLIF(public.profiles.email, ''), EXCLUDED.email),
    updated_at = NOW();

  SELECT * INTO v_profile FROM public.profiles WHERE id = p_user_id;
  RETURN v_profile;
END;
$$;

REVOKE ALL ON FUNCTION public._bootstrap_user_profile(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public._bootstrap_user_profile(UUID, TEXT, TEXT, TEXT) FROM anon;
REVOKE ALL ON FUNCTION public._bootstrap_user_profile(UUID, TEXT, TEXT, TEXT) FROM authenticated;
GRANT EXECUTE ON FUNCTION public._bootstrap_user_profile(UUID, TEXT, TEXT, TEXT) TO service_role;

-- -------------------------------------------------------------------------
-- 2. Trigger untuk user baru. Tidak mempercayai organization_id / role dari
--    metadata browser.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_name TEXT;
  v_full_name TEXT;
BEGIN
  v_org_name := COALESCE(NULLIF(trim(NEW.raw_user_meta_data->>'organization_name'), ''), 'Perusahaan Baru');
  v_full_name := COALESCE(
    NULLIF(trim(NEW.raw_user_meta_data->>'full_name'), ''),
    NULLIF(trim(NEW.raw_user_meta_data->>'name'), ''),
    split_part(COALESCE(NEW.email, 'user'), '@', 1)
  );

  PERFORM public._bootstrap_user_profile(
    NEW.id,
    NEW.email,
    v_full_name,
    v_org_name
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

REVOKE ALL ON FUNCTION public.handle_new_user() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM anon;
REVOKE ALL ON FUNCTION public.handle_new_user() FROM authenticated;
GRANT EXECUTE ON FUNCTION public.handle_new_user() TO service_role;

-- -------------------------------------------------------------------------
-- 3. Safe RPC: user yang sedang login hanya boleh memperbaiki dirinya sendiri.
--    Tidak menerima user_id dari browser.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.bootstrap_current_user_profile(p_org_name TEXT DEFAULT NULL)
RETURNS public.profiles
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_email TEXT;
  v_full_name TEXT;
  v_org_name TEXT;
  v_profile public.profiles;
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'Sesi login tidak valid';
  END IF;

  SELECT email, raw_user_meta_data->>'full_name', raw_user_meta_data->>'name'
    INTO v_email, v_full_name, v_org_name
    FROM auth.users
   WHERE id = v_user_id;

  v_full_name := COALESCE(
    NULLIF(trim(v_full_name), ''),
    NULLIF(trim(v_org_name), ''),
    split_part(COALESCE(v_email, 'user'), '@', 1)
  );

  v_org_name := COALESCE(
    NULLIF(trim(p_org_name), ''),
    NULLIF(trim((SELECT raw_user_meta_data->>'organization_name' FROM auth.users WHERE id = v_user_id)), ''),
    'Perusahaan Baru'
  );

  v_profile := public._bootstrap_user_profile(v_user_id, v_email, v_full_name, v_org_name);

  RETURN v_profile;
END;
$$;

REVOKE ALL ON FUNCTION public.bootstrap_current_user_profile(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.bootstrap_current_user_profile(TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.bootstrap_current_user_profile(TEXT) TO authenticated;

-- -------------------------------------------------------------------------
-- 4. BACKFILL user lama.
--    Aman dijalankan ulang: profile/org yang sudah valid tidak dipindahkan.
-- -------------------------------------------------------------------------
DO $$
DECLARE
  u RECORD;
BEGIN
  FOR u IN
    SELECT
      id,
      email,
      raw_user_meta_data->>'full_name' AS full_name,
      raw_user_meta_data->>'name' AS name,
      raw_user_meta_data->>'organization_name' AS organization_name
    FROM auth.users
  LOOP
    PERFORM public._bootstrap_user_profile(
      u.id,
      u.email,
      COALESCE(NULLIF(trim(u.full_name), ''), NULLIF(trim(u.name), ''), split_part(COALESCE(u.email, 'user'), '@', 1)),
      COALESCE(NULLIF(trim(u.organization_name), ''), 'Perusahaan Baru')
    );
  END LOOP;
END;
$$;

-- -------------------------------------------------------------------------
-- 5. Pastikan helper tenant tetap aman dan dapat dipakai policy.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_auth_org_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT organization_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_auth_org_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_auth_org_id() TO authenticated;

-- Profiles tetap tidak boleh INSERT langsung dari browser.
DROP POLICY IF EXISTS "Profiles: client insert disabled" ON public.profiles;
DROP POLICY IF EXISTS "Users can create own profile" ON public.profiles;

-- Verifikasi RLS tetap aktif.
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- -------------------------------------------------------------------------
-- 6. Verifikasi sederhana (hasil terlihat di SQL Editor).
-- -------------------------------------------------------------------------
SELECT
  COUNT(*) AS auth_users,
  (SELECT COUNT(*) FROM public.profiles) AS profiles,
  (SELECT COUNT(*) FROM public.profiles WHERE organization_id IS NOT NULL) AS profiles_with_org
FROM auth.users;
