-- ============================================================================
-- RAJAKAS BENDAHARA - MULTI TENANT USER PROVISIONING V8
-- Jalankan SETELAH migration_v7_multi_tenant.sql.
--
-- Tujuan:
-- 1. User baru selalu memiliki organization/profile.
-- 2. User yang sudah ada tetapi provisioning-nya gagal dapat DIPERBAIKI
--    otomatis saat login.
-- 3. konfigurasi_lembaga selalu tersedia.
-- 4. periode_pembukuan selalu memiliki satu periode AKTIF per organization.
-- 5. Frontend cukup memanggil RPC ensure_user_setup() setiap selesai login.
-- ============================================================================

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
  v_existing_org UUID;
  v_nama_awal VARCHAR(150);
  v_tahun TEXT;
  v_tahun_mulai INT;
  v_tanggal_mulai DATE;
BEGIN
  IF p_user_id IS NULL THEN
    RAISE EXCEPTION 'USER_ID_INVALID';
  END IF;

  -- Jika profile sudah ada, gunakan organization yang sudah dimiliki.
  SELECT organization_id INTO v_existing_org
  FROM public.profiles
  WHERE id = p_user_id
  LIMIT 1;

  IF v_existing_org IS NOT NULL THEN
    v_org_id := v_existing_org;
  ELSE
    v_nama_awal := COALESCE(
      NULLIF(TRIM(p_name), ''),
      NULLIF(split_part(COALESCE(p_email, ''), '@', 1), ''),
      'Lembaga Baru'
    );

    INSERT INTO public.organizations (nama)
    VALUES (LEFT(v_nama_awal || ' - Lembaga Baru', 150))
    RETURNING id INTO v_org_id;

    INSERT INTO public.profiles (id, organization_id, email, role)
    VALUES (p_user_id, v_org_id, p_email, 'owner')
    ON CONFLICT (id) DO UPDATE SET
      organization_id = EXCLUDED.organization_id,
      email = COALESCE(public.profiles.email, EXCLUDED.email);
  END IF;

  -- Konfigurasi lembaga wajib ada sebelum dashboard digunakan.
  INSERT INTO public.konfigurasi_lembaga
    (organization_id, nama_lembaga, jenis_lembaga, saldo_awal, tahun_ajaran)
  VALUES (v_org_id, '', 'SD', 0, '2025/2026')
  ON CONFLICT (organization_id) DO NOTHING;

  -- Periode aktif default mengikuti tahun ajaran berjalan di server.
  IF to_regclass('public.periode_pembukuan') IS NOT NULL THEN
    IF EXTRACT(MONTH FROM CURRENT_DATE) >= 7 THEN
      v_tahun_mulai := EXTRACT(YEAR FROM CURRENT_DATE)::INT;
    ELSE
      v_tahun_mulai := EXTRACT(YEAR FROM CURRENT_DATE)::INT - 1;
    END IF;

    v_tahun := v_tahun_mulai::TEXT || '/' || (v_tahun_mulai + 1)::TEXT;
    v_tanggal_mulai := make_date(v_tahun_mulai, 7, 1);

    -- Jika tenant belum memiliki periode AKTIF, buat satu.
    IF NOT EXISTS (
      SELECT 1
      FROM public.periode_pembukuan
      WHERE organization_id = v_org_id
        AND status = 'AKTIF'
    ) THEN
      INSERT INTO public.periode_pembukuan
        (organization_id, nama_periode, tahun_ajaran, tanggal_mulai,
         saldo_awal, status, created_by)
      VALUES
        (v_org_id, v_tahun, v_tahun, v_tanggal_mulai,
         0, 'AKTIF', p_user_id)
      ON CONFLICT DO NOTHING;
    END IF;

    -- Sinkronkan konfigurasi awal dengan periode aktif yang sebenarnya.
    UPDATE public.konfigurasi_lembaga k
    SET tahun_ajaran = p.tahun_ajaran,
        saldo_awal = COALESCE(p.saldo_awal, 0),
        updated_at = NOW(),
        updated_by = p_user_id
    FROM (
      SELECT tahun_ajaran, saldo_awal
      FROM public.periode_pembukuan
      WHERE organization_id = v_org_id
        AND status = 'AKTIF'
      ORDER BY tanggal_mulai DESC
      LIMIT 1
    ) p
    WHERE k.organization_id = v_org_id;
  END IF;

  RETURN v_org_id;
END;
$$;

-- Trigger tidak boleh bergantung pada session auth.uid(), karena saat trigger
-- auth.users INSERT dijalankan konteks auth.uid() dapat NULL.
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
      NULLIF(NEW.raw_user_meta_data->>'name', ''),
      NULLIF(NEW.raw_user_meta_data->>'full_name', '')
    )
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_multi_tenant ON auth.users;
CREATE TRIGGER on_auth_user_created_multi_tenant
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_multi_tenant();

-- RPC yang dipanggil frontend setelah login. SECURITY DEFINER membuat proses
-- provisioning dapat memperbaiki profile/tenant yang belum ada tanpa memberi
-- client hak INSERT langsung ke organizations/profiles.
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
           NULLIF(raw_user_meta_data->>'name', ''),
           NULLIF(raw_user_meta_data->>'full_name', '')
         )
    INTO v_email, v_name
  FROM auth.users
  WHERE id = v_uid;

  IF v_email IS NULL THEN
    RAISE EXCEPTION 'USER_TIDAK_DITEMUKAN';
  END IF;

  v_org_id := public.provision_user_account(v_uid, v_email, v_name);

  RETURN jsonb_build_object(
    'organization_id', v_org_id,
    'ready', TRUE
  );
END;
$$;

REVOKE ALL ON FUNCTION public.provision_user_account(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_user_setup() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_user_setup() TO authenticated;

-- Pastikan periode aktif bersifat unik PER ORGANIZATION, bukan global.
DO $$
BEGIN
  IF to_regclass('public.periode_pembukuan') IS NOT NULL THEN
    DROP INDEX IF EXISTS public.ux_periode_pembukuan_satu_aktif;
    CREATE UNIQUE INDEX IF NOT EXISTS ux_periode_pembukuan_satu_aktif_per_org
      ON public.periode_pembukuan (organization_id)
      WHERE status = 'AKTIF';
  END IF;
END $$;


-- ---------------------------------------------------------------------------
-- RPC PEMBAYARAN SISWA: versi organization_id (menggantikan patch tenant_id lama)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.catat_pembayaran_siswa(
  p_siswa_id UUID,
  p_no_bukti TEXT,
  p_tanggal DATE,
  p_status TEXT,
  p_nominal NUMERIC
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID := public.get_auth_org_id();
  v_siswa RECORD;
  v_inserted RECORD;
BEGIN
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'TENANT_TIDAK_DITEMUKAN: User belum memiliki tenant.';
  END IF;
  IF p_nominal IS NULL OR p_nominal <= 0 THEN
    RAISE EXCEPTION 'NOMINAL_INVALID: Nominal pembayaran harus lebih dari Rp 0';
  END IF;

  SELECT * INTO v_siswa
  FROM public.siswa_tagihan
  WHERE id = p_siswa_id
    AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'SISWA_TIDAK_DITEMUKAN: Data tagihan siswa tidak ditemukan pada tenant ini';
  END IF;

  INSERT INTO public.pemasukan (
    no_bukti, tanggal, sumber, sub, nominal, keterangan, status,
    siswa_id, created_by, organization_id
  )
  VALUES (
    p_no_bukti, p_tanggal, 'Pembayaran', v_siswa.jenis, p_nominal,
    'Pembayaran ' || v_siswa.jenis || ' a.n ' || v_siswa.nama ||
      ' (' || v_siswa.kelas || ')',
    COALESCE(NULLIF(p_status, ''), 'Selesai'),
    p_siswa_id, auth.uid(), v_org_id
  )
  RETURNING * INTO v_inserted;

  RETURN row_to_json(v_inserted)::jsonb;
END;
$$;

REVOKE ALL ON FUNCTION public.catat_pembayaran_siswa(UUID, TEXT, DATE, TEXT, NUMERIC) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.catat_pembayaran_siswa(UUID, TEXT, DATE, TEXT, NUMERIC) TO authenticated;

-- ============================================================================
-- REPAIR SEKALI JALAN UNTUK USER LAMA
-- Tidak menghapus transaksi. Hanya melengkapi profile/tenant/config/periode
-- yang hilang. User lama yang sudah lengkap tidak diubah tenant-nya.
-- ============================================================================
DO $$
DECLARE
  u RECORD;
BEGIN
  FOR u IN SELECT id, email, raw_user_meta_data FROM auth.users LOOP
    PERFORM public.provision_user_account(
      u.id,
      u.email,
      COALESCE(
        NULLIF(u.raw_user_meta_data->>'name', ''),
        NULLIF(u.raw_user_meta_data->>'full_name', '')
      )
    );
  END LOOP;
END $$;
