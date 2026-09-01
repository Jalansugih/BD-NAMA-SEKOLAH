-- =========================================================================
-- RAJASCH.ID / RAJAKAS — MIGRATION V6: MULTI-TENANT
-- Jalankan ini SETELAH migration.sql + migration_periode_pembukuan.sql +
-- cutoff_migration.sql, di Supabase SQL Editor. ADDITIVE & AMAN UNTUK DATA
-- YANG SUDAH ADA — tidak ada satu pun DROP TABLE/DELETE data transaksi di
-- sini. Boleh dijalankan berkali-kali (idempotent) kecuali disebutkan lain.
--
-- KENAPA INI PENTING (ringkasan audit):
-- Seluruh skema sebelumnya adalah SINGLE-TENANT MURNI:
--   - konfigurasi_lembaga: singleton (id BOOLEAN, hanya 1 baris SELAMANYA)
--   - pemasukan/pengeluaran/siswa_tagihan/audit_log/master_*: TIDAK PUNYA
--     kolom tenant sama sekali
--   - master_kelas/master_kategori: PRIMARY KEY hanya `nama` -- dua lembaga
--     tidak akan pernah bisa sama-sama punya kelas "1A" atau kategori "ATK"
--   - RLS semua tabel: "auth.role() = 'authenticated'" -- SIAPAPUN yang
--     login (dari lembaga manapun) bisa lihat & ubah SEMUA data SEMUA
--     lembaga lain. Ini bukan sekadar "belum multi-tenant", ini KEBOCORAN
--     DATA ANTAR SEKOLAH kalau project ini dipakai lebih dari satu lembaga.
--   - ux_periode_pembukuan_satu_aktif: unique index GLOBAL pada `status`
--     -- hanya SATU periode AKTIF diperbolehkan di SELURUH DATABASE. Begitu
--     lembaga kedua mendaftar & mencoba mengaktifkan tahun ajaran, mereka
--     akan gagal karena lembaga pertama "sudah pakai jatah" AKTIF itu.
--   - tutup_buku() / buka_kembali_periode() / hitung_saldo_akhir_periode():
--     SECURITY DEFINER (bypass RLS) TANPA filter organization_id apapun di
--     dalam query-nya -- kalaupun RLS di atas sudah benar, fungsi-fungsi
--     ini tetap bisa menutup buku / membuka kembali periode / menjumlah
--     saldo LEMBAGA LAIN, karena mereka tidak tunduk pada RLS sama sekali.
--
-- STRATEGI PERBAIKAN:
-- 1) Tabel baru: organizations (lembaga) + profiles (user -> organization).
-- 2) Setiap tabel data ditambah kolom organization_id UUID NOT NULL DEFAULT
--    public.get_auth_org_id() -- artinya SEBAGIAN BESAR kode aplikasi yang
--    sudah ada (insert tanpa menyebut organization_id) OTOMATIS tetap jalan
--    tanpa perlu diubah, karena Postgres mengisi kolom itu sendiri dari
--    sesi user yang sedang login.
-- 3) PRIMARY KEY master_kelas/master_kategori diubah jadi composite
--    (organization_id, nama) supaya nama boleh sama antar lembaga.
-- 4) Semua RLS policy diganti dari "auth.role()='authenticated'" menjadi
--    "organization_id = public.get_auth_org_id()".
-- 5) Semua fungsi SECURITY DEFINER (tutup_buku, buka_kembali_periode,
--    hitung_saldo_akhir_periode) ditulis ulang dengan filter organization_id
--    eksplisit di SETIAP query -- karena SECURITY DEFINER bypass RLS, filter
--    ini WAJIB ada di kode SQL-nya sendiri, tidak boleh cuma mengandalkan RLS.
-- 6) Index unique "satu periode aktif" diubah dari global menjadi per-
--    organisasi: (organization_id) WHERE status='AKTIF'.
-- 7) Data yang SUDAH ADA (kalau project ini sebelumnya sudah dipakai)
--    dipindahkan ke SATU organisasi default "Lembaga Utama (Migrasi)" agar
--    tidak hilang / tidak terkunci sama sekali.
-- 8) Trigger baru: setiap kali ada auth.users BARU (sign up email/password
--    ATAU login Google pertama kali), otomatis dibuatkan organisasi baru +
--    profil 'owner' -- jadi setiap lembaga baru mendaftar sendiri dengan
--    datanya masing-masing terisolasi, tanpa perlu langkah manual admin.
-- =========================================================================


-- -------------------------------------------------------------------------
-- 1. TABEL ORGANIZATIONS & PROFILES
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    nama VARCHAR(150) NOT NULL DEFAULT 'Lembaga Baru',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    email VARCHAR(255),
    role VARCHAR(20) NOT NULL DEFAULT 'owner' CHECK (role IN ('owner', 'bendahara', 'viewer')),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE OR REPLACE FUNCTION public.get_auth_org_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
    SELECT organization_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$;

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Organizations - anggota lembaga sendiri" ON public.organizations;
CREATE POLICY "Organizations - anggota lembaga sendiri" ON public.organizations
    FOR ALL
    USING (id = public.get_auth_org_id())
    WITH CHECK (id = public.get_auth_org_id());

DROP POLICY IF EXISTS "Profiles - baca sesama anggota lembaga" ON public.profiles;
CREATE POLICY "Profiles - baca sesama anggota lembaga" ON public.profiles
    FOR SELECT
    USING (id = auth.uid() OR organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "Profiles - update profil sendiri" ON public.profiles;
CREATE POLICY "Profiles - update profil sendiri" ON public.profiles
    FOR UPDATE
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "Profiles - insert profil sendiri" ON public.profiles;
CREATE POLICY "Profiles - insert profil sendiri" ON public.profiles
    FOR INSERT
    WITH CHECK (id = auth.uid());

-- Catatan: tidak ada policy DELETE untuk profiles -- keanggotaan lembaga
-- sengaja tidak bisa dihapus lewat client, supaya tidak ada user yang
-- "melepas diri" dari organisasi sendirian (kalau nanti dibutuhkan,
-- tambahkan lewat proses admin terpisah, bukan RLS permisif).

-- -------------------------------------------------------------------------
-- 2. BACKFILL: pindahkan data yang SUDAH ADA (kalau project ini sebelumnya
--    dipakai) ke satu organisasi default, supaya tidak ada yang hilang atau
--    terkunci begitu RLS berbasis organization_id diaktifkan.
-- -------------------------------------------------------------------------
DO $$
DECLARE
    v_default_org_id UUID;
    v_existing_nama VARCHAR;
    v_user RECORD;
BEGIN
    -- Hanya buat organisasi default kalau memang ada data lama untuk
    -- dipindahkan (konfigurasi_lembaga singleton sudah pernah diisi) DAN
    -- belum ada organizations sama sekali (migrasi belum pernah jalan).
    IF EXISTS (SELECT 1 FROM public.konfigurasi_lembaga LIMIT 1)
       AND NOT EXISTS (SELECT 1 FROM public.organizations LIMIT 1) THEN

        SELECT nama_lembaga INTO v_existing_nama FROM public.konfigurasi_lembaga LIMIT 1;

        INSERT INTO public.organizations (nama)
        VALUES (COALESCE(NULLIF(v_existing_nama, ''), 'Lembaga Utama (Migrasi)'))
        RETURNING id INTO v_default_org_id;

        -- Setiap auth.users yang SUDAH ADA sebelum migrasi ini otomatis
        -- jadi anggota organisasi default itu (mereka sebelumnya memang
        -- bisa lihat semua data yang sama di model single-tenant lama --
        -- ini mempertahankan akses yang sudah mereka punya, bukan
        -- menambah akses baru).
        FOR v_user IN SELECT id, email FROM auth.users LOOP
            INSERT INTO public.profiles (id, organization_id, email, role)
            VALUES (v_user.id, v_default_org_id, v_user.email, 'owner')
            ON CONFLICT (id) DO NOTHING;
        END LOOP;

        -- Backfill semua tabel data lama ke organisasi default ini.
        UPDATE public.konfigurasi_lembaga SET organization_id = v_default_org_id WHERE organization_id IS NULL;
        UPDATE public.audit_log SET organization_id = v_default_org_id WHERE organization_id IS NULL;
        UPDATE public.master_sumber_dana SET organization_id = v_default_org_id WHERE organization_id IS NULL;
        UPDATE public.master_kategori SET organization_id = v_default_org_id WHERE organization_id IS NULL;
        UPDATE public.master_kelas SET organization_id = v_default_org_id WHERE organization_id IS NULL;
        UPDATE public.siswa_tagihan SET organization_id = v_default_org_id WHERE organization_id IS NULL;
        UPDATE public.pemasukan SET organization_id = v_default_org_id WHERE organization_id IS NULL;
        UPDATE public.pengeluaran SET organization_id = v_default_org_id WHERE organization_id IS NULL;
        IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='periode_pembukuan') THEN
            UPDATE public.periode_pembukuan SET organization_id = v_default_org_id WHERE organization_id IS NULL;
        END IF;

        RAISE NOTICE 'Migrasi multi-tenant: data lama dipindahkan ke organisasi default %', v_default_org_id;
    END IF;
END $$;

-- -------------------------------------------------------------------------
-- 3. TAMBAHKAN KOLOM organization_id KE SETIAP TABEL DATA
--    DEFAULT public.get_auth_org_id() -- INSERT yang sudah ada di kode
--    aplikasi (yang tidak menyebutkan organization_id sama sekali) akan
--    otomatis terisi benar tanpa perlu diubah.
-- -------------------------------------------------------------------------

-- konfigurasi_lembaga: dari singleton (id BOOLEAN) -> satu baris per
-- organisasi (organization_id jadi PRIMARY KEY yang baru).
ALTER TABLE public.konfigurasi_lembaga ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE;
ALTER TABLE public.konfigurasi_lembaga DROP CONSTRAINT IF EXISTS konfigurasi_lembaga_pkey;
ALTER TABLE public.konfigurasi_lembaga ALTER COLUMN organization_id SET NOT NULL;
ALTER TABLE public.konfigurasi_lembaga ADD CONSTRAINT konfigurasi_lembaga_pkey PRIMARY KEY (organization_id);
ALTER TABLE public.konfigurasi_lembaga DROP COLUMN IF EXISTS id;

ALTER TABLE public.audit_log ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE DEFAULT public.get_auth_org_id();
ALTER TABLE public.master_sumber_dana ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE DEFAULT public.get_auth_org_id();
ALTER TABLE public.master_kategori ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE DEFAULT public.get_auth_org_id();
ALTER TABLE public.master_kelas ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE DEFAULT public.get_auth_org_id();
ALTER TABLE public.siswa_tagihan ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE DEFAULT public.get_auth_org_id();
ALTER TABLE public.pemasukan ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE DEFAULT public.get_auth_org_id();
ALTER TABLE public.pengeluaran ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE DEFAULT public.get_auth_org_id();

-- Kolom di atas dibiarkan NULLABLE untuk baris lama yang mungkin belum
-- ter-backfill (mis. project yang benar-benar baru, tanpa data lama sama
-- sekali) -- pada project baru, tabel-tabel ini toh masih kosong, jadi
-- aman untuk langsung NOT NULL. Uncomment baris berikut SETELAH memastikan
-- backfill di atas berhasil (tidak ada baris organization_id NULL):
--
-- ALTER TABLE public.audit_log ALTER COLUMN organization_id SET NOT NULL;
-- ALTER TABLE public.master_sumber_dana ALTER COLUMN organization_id SET NOT NULL;
-- ALTER TABLE public.master_kategori ALTER COLUMN organization_id SET NOT NULL;
-- ALTER TABLE public.master_kelas ALTER COLUMN organization_id SET NOT NULL;
-- ALTER TABLE public.siswa_tagihan ALTER COLUMN organization_id SET NOT NULL;
-- ALTER TABLE public.pemasukan ALTER COLUMN organization_id SET NOT NULL;
-- ALTER TABLE public.pengeluaran ALTER COLUMN organization_id SET NOT NULL;

-- master_kelas & master_kategori: PK lama cuma `nama` -- ganti jadi
-- composite supaya dua lembaga boleh sama-sama punya "1A" / "ATK".
ALTER TABLE public.master_kelas DROP CONSTRAINT IF EXISTS master_kelas_pkey;
ALTER TABLE public.master_kelas ADD CONSTRAINT master_kelas_pkey PRIMARY KEY (organization_id, nama);

ALTER TABLE public.master_kategori DROP CONSTRAINT IF EXISTS master_kategori_pkey;
ALTER TABLE public.master_kategori ADD CONSTRAINT master_kategori_pkey PRIMARY KEY (organization_id, nama);

-- periode_pembukuan (dibuat di migration_periode_pembukuan.sql /
-- cutoff_migration.sql) -- dibungkus IF EXISTS supaya migrasi ini tidak
-- gagal kalau kedua migration itu belum pernah dijalankan di project ini.
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='periode_pembukuan') THEN
        ALTER TABLE public.periode_pembukuan ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE DEFAULT public.get_auth_org_id();

        -- BUG KRITIS diperbaiki di sini: index lama mengunci "satu periode
        -- AKTIF" untuk SELURUH DATABASE (lintas lembaga). Diganti jadi satu
        -- periode AKTIF PER LEMBAGA.
        DROP INDEX IF EXISTS ux_periode_pembukuan_satu_aktif;
        CREATE UNIQUE INDEX IF NOT EXISTS ux_periode_pembukuan_satu_aktif_per_org
          ON public.periode_pembukuan (organization_id)
          WHERE status = 'AKTIF';
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_organizations_lookup ON public.organizations (id);
CREATE INDEX IF NOT EXISTS idx_profiles_org ON public.profiles (organization_id);

-- -------------------------------------------------------------------------
-- 4. RLS: GANTI SEMUA POLICY LAMA ("siapapun yang login") DENGAN ISOLASI
--    PER-ORGANISASI.
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "Hanya user login - audit_log" ON public.audit_log;
CREATE POLICY "Audit log - anggota lembaga sendiri" ON public.audit_log
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "Hanya user login - master_sumber_dana" ON public.master_sumber_dana;
CREATE POLICY "Master sumber dana - anggota lembaga sendiri" ON public.master_sumber_dana
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "Hanya user login - master_kategori" ON public.master_kategori;
CREATE POLICY "Master kategori - anggota lembaga sendiri" ON public.master_kategori
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "Hanya user login - master_kelas" ON public.master_kelas;
CREATE POLICY "Master kelas - anggota lembaga sendiri" ON public.master_kelas
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "Hanya user login - siswa_tagihan" ON public.siswa_tagihan;
CREATE POLICY "Siswa tagihan - anggota lembaga sendiri" ON public.siswa_tagihan
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "Hanya user login - pemasukan" ON public.pemasukan;
CREATE POLICY "Pemasukan - anggota lembaga sendiri" ON public.pemasukan
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "Hanya user login - pengeluaran" ON public.pengeluaran;
CREATE POLICY "Pengeluaran - anggota lembaga sendiri" ON public.pengeluaran
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "Hanya user login - konfigurasi_lembaga" ON public.konfigurasi_lembaga;
CREATE POLICY "Konfigurasi lembaga - anggota lembaga sendiri" ON public.konfigurasi_lembaga
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema='public' AND table_name='periode_pembukuan') THEN
        EXECUTE 'DROP POLICY IF EXISTS "Periode pembukuan - user login" ON public.periode_pembukuan';
        EXECUTE 'CREATE POLICY "Periode pembukuan - anggota lembaga sendiri" ON public.periode_pembukuan
          FOR ALL USING (organization_id = public.get_auth_org_id())
          WITH CHECK (organization_id = public.get_auth_org_id())';
    END IF;
END $$;

-- -------------------------------------------------------------------------
-- 5. RPC & FUNGSI SECURITY DEFINER: ditulis ulang dengan filter
--    organization_id EKSPLISIT (WAJIB -- SECURITY DEFINER bypass RLS).
-- -------------------------------------------------------------------------

-- catat_pengeluaran / catat_pembayaran_siswa TIDAK diubah di sini: keduanya
-- SECURITY INVOKER (bukan DEFINER), jadi otomatis tunduk pada RLS + kolom
-- organization_id DEFAULT di atas sudah cukup mengisolasi mereka dengan
-- benar tanpa perlu ditulis ulang.

CREATE OR REPLACE FUNCTION public.hitung_saldo_akhir_periode(p_periode_id UUID, p_tanggal_cutoff DATE DEFAULT NULL)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
  v_periode RECORD;
  v_cutoff DATE;
  v_saldo NUMERIC(15,2);
BEGIN
  v_org_id := public.get_auth_org_id();
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ditemukan organisasi untuk user yang sedang login.';
  END IF;

  SELECT * INTO v_periode
  FROM periode_pembukuan
  WHERE id = p_periode_id AND organization_id = v_org_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PERIODE_TIDAK_DITEMUKAN';
  END IF;

  v_cutoff := COALESCE(p_tanggal_cutoff, v_periode.tanggal_akhir, CURRENT_DATE);

  IF v_cutoff < v_periode.tanggal_mulai THEN
    RAISE EXCEPTION 'TANGGAL_CUTOFF_INVALID';
  END IF;

  SELECT
    COALESCE(v_periode.saldo_awal, 0)
    + COALESCE((SELECT SUM(nominal) FROM pemasukan
                WHERE organization_id = v_org_id
                  AND tanggal >= v_periode.tanggal_mulai AND tanggal <= v_cutoff), 0)
    - COALESCE((SELECT SUM(nominal) FROM pengeluaran
                WHERE organization_id = v_org_id
                  AND tanggal >= v_periode.tanggal_mulai AND tanggal <= v_cutoff), 0)
  INTO v_saldo;

  RETURN v_saldo;
END;
$$;

CREATE OR REPLACE FUNCTION public.tutup_buku(p_periode_id UUID, p_tanggal_cutoff DATE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
  v_periode RECORD;
  v_saldo NUMERIC(15,2);
  v_next_start DATE;
  v_next_year TEXT;
  v_next RECORD;
BEGIN
  v_org_id := public.get_auth_org_id();
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ditemukan organisasi untuk user yang sedang login.';
  END IF;

  SELECT * INTO v_periode
  FROM periode_pembukuan
  WHERE id = p_periode_id AND organization_id = v_org_id
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PERIODE_TIDAK_DITEMUKAN';
  END IF;

  IF v_periode.status <> 'AKTIF' THEN
    RAISE EXCEPTION 'PERIODE_SUDAH_DITUTUP';
  END IF;

  IF p_tanggal_cutoff < v_periode.tanggal_mulai THEN
    RAISE EXCEPTION 'TANGGAL_CUTOFF_INVALID';
  END IF;

  v_saldo := public.hitung_saldo_akhir_periode(p_periode_id, p_tanggal_cutoff);

  UPDATE periode_pembukuan
  SET status = 'DITUTUP',
      tanggal_akhir = p_tanggal_cutoff,
      saldo_akhir = v_saldo,
      closed_at = NOW(),
      closed_by = auth.uid()
  WHERE id = p_periode_id AND organization_id = v_org_id;

  IF v_periode.tahun_ajaran ~ '^[0-9]{4}/[0-9]{4}$' THEN
    v_next_year :=
      (split_part(v_periode.tahun_ajaran, '/', 1)::INT + 1)::TEXT
      || '/' ||
      (split_part(v_periode.tahun_ajaran, '/', 2)::INT + 1)::TEXT;
  ELSE
    v_next_year := v_periode.tahun_ajaran;
  END IF;

  v_next_start := p_tanggal_cutoff + 1;

  INSERT INTO periode_pembukuan
    (organization_id, nama_periode, tahun_ajaran, tanggal_mulai, tanggal_akhir, saldo_awal, saldo_akhir, status, created_by)
  VALUES
    (v_org_id, v_next_year, v_next_year, v_next_start, NULL, v_saldo, NULL, 'AKTIF', auth.uid())
  RETURNING * INTO v_next;

  UPDATE konfigurasi_lembaga
  SET saldo_awal = v_saldo,
      tahun_ajaran = v_next_year,
      updated_at = NOW(),
      updated_by = auth.uid()
  WHERE organization_id = v_org_id;

  RETURN jsonb_build_object(
    'saldo_akhir', v_saldo,
    'periode_berikutnya', row_to_json(v_next)::jsonb
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.buka_kembali_periode(p_periode_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
  v_closed RECORD;
  v_active RECORD;
  v_tx_count BIGINT;
BEGIN
  v_org_id := public.get_auth_org_id();
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ditemukan organisasi untuk user yang sedang login.';
  END IF;

  SELECT * INTO v_closed
  FROM periode_pembukuan
  WHERE id = p_periode_id AND organization_id = v_org_id AND status = 'DITUTUP'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PERIODE_TERTUTUP_TIDAK_DITEMUKAN';
  END IF;

  SELECT * INTO v_active
  FROM periode_pembukuan
  WHERE organization_id = v_org_id AND status = 'AKTIF'
  ORDER BY tanggal_mulai DESC
  LIMIT 1
  FOR UPDATE;

  IF v_active.id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_tx_count
    FROM (
      SELECT id FROM pemasukan WHERE organization_id = v_org_id AND tanggal >= v_active.tanggal_mulai
      UNION ALL
      SELECT id FROM pengeluaran WHERE organization_id = v_org_id AND tanggal >= v_active.tanggal_mulai
    ) q;

    IF v_tx_count > 0 THEN
      RAISE EXCEPTION 'PERIODE_BERIKUTNYA_SUDAH_MEMILIKI_TRANSAKSI';
    END IF;

    DELETE FROM periode_pembukuan WHERE id = v_active.id AND organization_id = v_org_id;
  END IF;

  UPDATE periode_pembukuan
  SET status = 'AKTIF',
      tanggal_akhir = NULL,
      saldo_akhir = NULL,
      closed_at = NULL,
      closed_by = NULL
  WHERE id = p_periode_id AND organization_id = v_org_id;

  UPDATE konfigurasi_lembaga
  SET saldo_awal = v_closed.saldo_awal,
      tahun_ajaran = v_closed.tahun_ajaran,
      updated_at = NOW(),
      updated_by = auth.uid()
  WHERE organization_id = v_org_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.hitung_saldo_akhir_periode(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.tutup_buku(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.buka_kembali_periode(UUID) TO authenticated;

-- Trigger-trigger pengunci periode (cegah_hapus/insert/update di luar
-- periode aktif) sengaja TIDAK ditulis ulang: mereka SECURITY INVOKER
-- (bukan DEFINER) sehingga otomatis tunduk pada RLS periode_pembukuan yang
-- sudah diperbaiki di atas -- tapi ditambah filter organization_id
-- eksplisit di sini juga untuk pertahanan berlapis (defense in depth),
-- tidak hanya bergantung pada RLS.
CREATE OR REPLACE FUNCTION public.cegah_hapus_transaksi_periode_tertutup()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_mulai DATE;
BEGIN
  SELECT tanggal_mulai INTO v_mulai
  FROM periode_pembukuan
  WHERE status = 'AKTIF' AND organization_id = OLD.organization_id
  ORDER BY tanggal_mulai DESC
  LIMIT 1;

  IF v_mulai IS NOT NULL AND OLD.tanggal < v_mulai THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Transaksi periode yang sudah ditutup tidak dapat dihapus.';
  END IF;

  RETURN OLD;
END;
$$;

CREATE OR REPLACE FUNCTION public.cegah_transaksi_di_luar_periode_aktif()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_mulai DATE;
BEGIN
  SELECT tanggal_mulai INTO v_mulai
  FROM periode_pembukuan
  WHERE status = 'AKTIF' AND organization_id = NEW.organization_id
  ORDER BY tanggal_mulai DESC
  LIMIT 1;

  IF v_mulai IS NOT NULL AND NEW.tanggal < v_mulai THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Tanggal transaksi berada pada periode yang sudah ditutup.';
  END IF;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.cegah_update_transaksi_periode_tertutup()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_mulai DATE;
BEGIN
  SELECT tanggal_mulai INTO v_mulai
  FROM periode_pembukuan
  WHERE status = 'AKTIF' AND organization_id = NEW.organization_id
  ORDER BY tanggal_mulai DESC
  LIMIT 1;

  IF v_mulai IS NOT NULL AND (OLD.tanggal < v_mulai OR NEW.tanggal < v_mulai) THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Transaksi periode yang sudah ditutup tidak dapat diubah.';
  END IF;

  RETURN NEW;
END;
$$;

-- Perbaiki saldo_kas view: dulu "WHERE id = TRUE" (singleton), sekarang
-- konfigurasi_lembaga sudah 1-baris-per-organisasi dan RLS otomatis
-- membatasi baris yang terlihat ke organisasi milik user yang sedang
-- login -- jadi cukup LIMIT 1 tanpa filter tambahan (view ini SECURITY
-- INVOKER / default, bukan DEFINER, sehingga tetap tunduk pada RLS).
CREATE OR REPLACE VIEW public.saldo_kas AS
SELECT
    (SELECT saldo_awal FROM public.konfigurasi_lembaga LIMIT 1)
    + COALESCE((SELECT SUM(nominal) FROM public.pemasukan), 0)
    - COALESCE((SELECT SUM(nominal) FROM public.pengeluaran), 0) AS total_saldo_kas;

-- -------------------------------------------------------------------------
-- 6. AUTO-PROVISIONING: setiap auth.users BARU (sign up email/password
--    ATAU login Google pertama kali) otomatis dibuatkan organisasi baru +
--    profil 'owner'. Ini menggantikan kebutuhan langkah manual "buat akun
--    di Authentication > Users" untuk lembaga baru -- sekarang lembaga
--    baru cukup mendaftar sendiri dari halaman login.
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.handle_new_user_multi_tenant()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
  v_nama_awal VARCHAR;
BEGIN
  -- Kalau profil untuk user ini sudah ada (mis. dibuat manual oleh admin
  -- sebelum trigger ini terpasang), jangan buat organisasi duplikat.
  IF EXISTS (SELECT 1 FROM public.profiles WHERE id = NEW.id) THEN
    RETURN NEW;
  END IF;

  v_nama_awal := COALESCE(
    NEW.raw_user_meta_data->>'name',
    NEW.raw_user_meta_data->>'full_name',
    split_part(NEW.email, '@', 1),
    'Lembaga Baru'
  );

  INSERT INTO public.organizations (nama)
  VALUES (v_nama_awal || ' - Lembaga Baru')
  RETURNING id INTO v_org_id;

  INSERT INTO public.profiles (id, organization_id, email, role)
  VALUES (NEW.id, v_org_id, NEW.email, 'owner');

  -- Baris konfigurasi_lembaga awal (kosong, diisi user lewat menu
  -- Pengaturan) supaya fetchKonfigurasiLembaga() langsung menemukan baris
  -- alih-alih NULL sejak login pertama.
  INSERT INTO public.konfigurasi_lembaga (organization_id, nama_lembaga, jenis_lembaga, saldo_awal, tahun_ajaran)
  VALUES (v_org_id, '', 'SD', 0, '2025/2026');

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_multi_tenant ON auth.users;
CREATE TRIGGER on_auth_user_created_multi_tenant
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_multi_tenant();

-- -------------------------------------------------------------------------
-- 7. GRANT tabel baru untuk role authenticated (RLS di atas tetap
--    membatasi baris mana yang benar-benar terlihat/bisa diubah).
-- -------------------------------------------------------------------------
GRANT SELECT, INSERT, UPDATE ON public.organizations TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.profiles TO authenticated;

-- -------------------------------------------------------------------------
-- 8. RPC save_konfigurasi_lembaga(): dulu client memanggil
--    .upsert({id: true, ...}, {onConflict: 'id'}) langsung ke tabel --
--    sekarang PK-nya organization_id yang TIDAK diketahui/disimpan di
--    frontend, jadi upsert diganti RPC ini yang menyelesaikan
--    organization_id dari sesi login di server (SECURITY INVOKER, tetap
--    tunduk RLS -- hanya membungkus resolusi org_id, bukan bypass akses).
--    Semua parameter opsional: hanya field yang dikirim (bukan NULL) yang
--    diperbarui, sisanya dipertahankan dari baris yang sudah ada.
-- -------------------------------------------------------------------------
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
SET search_path = public
AS $$
DECLARE
  v_org_id UUID;
  v_row RECORD;
BEGIN
  v_org_id := public.get_auth_org_id();
  IF v_org_id IS NULL THEN
    RAISE EXCEPTION 'Tidak ditemukan organisasi untuk user yang sedang login.';
  END IF;

  INSERT INTO konfigurasi_lembaga (organization_id, nama_lembaga, jenis_lembaga, saldo_awal, tahun_ajaran)
  VALUES (v_org_id, COALESCE(p_nama_lembaga, ''), COALESCE(p_jenis_lembaga, 'SD'), COALESCE(p_saldo_awal, 0), COALESCE(p_tahun_ajaran, '2025/2026'))
  ON CONFLICT (organization_id) DO UPDATE SET
    nama_lembaga = COALESCE(p_nama_lembaga, konfigurasi_lembaga.nama_lembaga),
    jenis_lembaga = COALESCE(p_jenis_lembaga, konfigurasi_lembaga.jenis_lembaga),
    npsn = COALESCE(p_npsn, konfigurasi_lembaga.npsn),
    alamat = COALESCE(p_alamat, konfigurasi_lembaga.alamat),
    kontak = COALESCE(p_kontak, konfigurasi_lembaga.kontak),
    website = COALESCE(p_website, konfigurasi_lembaga.website),
    tahun_ajaran = COALESCE(p_tahun_ajaran, konfigurasi_lembaga.tahun_ajaran),
    saldo_awal = COALESCE(p_saldo_awal, konfigurasi_lembaga.saldo_awal),
    logo_url = CASE WHEN p_clear_logo THEN NULL ELSE COALESCE(p_logo_url, konfigurasi_lembaga.logo_url) END,
    updated_at = NOW(),
    updated_by = auth.uid()
  RETURNING * INTO v_row;

  RETURN row_to_json(v_row)::jsonb;
END;
$$;

GRANT EXECUTE ON FUNCTION public.save_konfigurasi_lembaga(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, NUMERIC, TEXT, BOOLEAN) TO authenticated;

-- -------------------------------------------------------------------------
-- 9. STORAGE: perbaiki kebocoran multi-tenant di bucket "logos".
--    BUG di migration.sql lama: policy INSERT/UPDATE cuma mengecek
--    "auth.role() = 'authenticated'" tanpa membatasi PATH file sama sekali,
--    dan src/lib/configuration.ts (versi lama) selalu upload ke NAMA FILE
--    GLOBAL YANG SAMA ("logo-lembaga.<ext>") untuk SEMUA lembaga. Akibatnya
--    logo lembaga B akan MENIMPA FILE logo lembaga A di Storage -- lembaga
--    A tiba-tiba kehilangan logonya sendiri walau datanya (baris DB)
--    terisolasi dengan benar oleh RLS. Perbaikan: setiap lembaga upload ke
--    folder path miliknya sendiri (awalan auth.uid()), dan policy Storage
--    membatasi INSERT/UPDATE hanya ke folder auth.uid() sendiri. Bacaan
--    (SELECT) tetap publik supaya logo bisa tampil di laporan PDF/print.
--    (Kode pemanggilnya sudah diperbaiki di src/lib/configuration.ts,
--    fungsi uploadLogoToStorage, memakai path "<uid>/logo-lembaga.<ext>".)
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "Logo - upload user login" ON storage.objects;
DROP POLICY IF EXISTS "Logo - update user login" ON storage.objects;
DROP POLICY IF EXISTS "Logo - upload folder sendiri" ON storage.objects;
DROP POLICY IF EXISTS "Logo - update folder sendiri" ON storage.objects;

CREATE POLICY "Logo - upload folder sendiri" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'logos'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

CREATE POLICY "Logo - update folder sendiri" ON storage.objects
  FOR UPDATE USING (
    bucket_id = 'logos'
    AND auth.role() = 'authenticated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Catatan: kalau bucket "logos" sebelumnya sudah dipakai dengan skema lama
-- (file rata di root bucket, bukan di dalam folder "<uid>/..."), file lama
-- itu tidak otomatis pindah. Cukup upload ulang logo sekali lagi lewat menu
-- Pengaturan setelah migrasi ini -- URL baru akan otomatis tersimpan ke
-- konfigurasi_lembaga lewat RPC save_konfigurasi_lembaga di atas.


-- =========================================================================
-- SELESAI. LANGKAH SETELAH INI:
--
-- 1) Jika ini project yang SUDAH PERNAH dipakai (bukan baru), jalankan dulu
--    query berikut untuk memastikan backfill di Bagian 2 berhasil sebelum
--    mengunci kolom jadi NOT NULL:
--      SELECT 'pemasukan' t, count(*) FROM pemasukan WHERE organization_id IS NULL
--      UNION ALL SELECT 'pengeluaran', count(*) FROM pengeluaran WHERE organization_id IS NULL
--      UNION ALL SELECT 'siswa_tagihan', count(*) FROM siswa_tagihan WHERE organization_id IS NULL;
--    Semua harus menunjukkan 0. Kalau sudah, jalankan blok ALTER COLUMN
--    SET NOT NULL yang di-comment di Bagian 3 di atas.
--
-- 2) Setiap user BARU yang mendaftar (email/password ATAU Google) sekarang
--    OTOMATIS mendapat organisasi sendiri lewat trigger di Bagian 6 --
--    tidak perlu langkah manual apapun di Supabase Dashboard lagi.
--
-- 3) Aplikasi frontend (src/lib/configuration.ts) diperbarui untuk memakai
--    RPC save_konfigurasi_lembaga() dari Bagian 8 di atas, alih-alih
--    upsert langsung dengan "id = true" (lihat storage.ts / configuration.ts).
-- =========================================================================
