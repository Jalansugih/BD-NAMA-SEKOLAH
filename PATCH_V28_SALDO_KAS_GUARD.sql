-- =========================================================================
-- RajaKas.id — Modul Bendahara
-- PATCH V28: PEMULIHAN VALIDASI SALDO KAS SERVER-SIDE (TENANT-AWARE)
--
-- Jalankan SEKALI di Supabase SQL Editor sebagai role `postgres`,
-- SETELAH `FINAL_REPAIR_2026_09.sql`.
--
-- Script ini idempotent (aman dijalankan ulang) dan TIDAK menghapus
-- satu pun baris transaksi.
--
-- -------------------------------------------------------------------------
-- MASALAH YANG DIPERBAIKI
-- -------------------------------------------------------------------------
-- 1. `FINAL_REPAIR_2026_09.sql` baris 112 menjalankan
--       DROP VIEW IF EXISTS public.saldo_kas;
--    tetapi TIDAK pernah membuat ulang view tersebut. Akibatnya:
--      a. Trigger lama `trigger_check_saldo_pengeluaran` (dari migration.sql)
--         yang isinya `SELECT total_saldo_kas FROM saldo_kas` akan gagal
--         dengan error `relation "public.saldo_kas" does not exist` pada
--         SETIAP pencatatan pengeluaran; atau
--      b. Bila view sempat dibuat ulang oleh v7, basis perhitungannya memakai
--         `konfigurasi_lembaga.saldo_awal` dan MENJUMLAHKAN SELURUH transaksi
--         tanpa batas periode — berbeda dari angka yang ditampilkan aplikasi.
--
-- 2. RPC `catat_pengeluaran` versi FINAL sama sekali tidak memeriksa saldo.
--    Hanya memeriksa periode aktif dan nominal > 0. Saldo kas bisa minus.
--
-- 3. Menghapus PEMASUKAN tidak pernah divalidasi. Urutan
--    "catat pemasukan 5jt -> belanja 5jt -> hapus pemasukannya"
--    membuat saldo kas menjadi -5jt tanpa penolakan database.
--
-- 4. Trigger kunci periode (`cutoff_migration.sql`) query `periode_pembukuan`
--    TANPA filter `organization_id`. Karena `catat_pengeluaran` dan
--    `catat_pembayaran_siswa` berjalan sebagai SECURITY DEFINER (RLS
--    di-bypass), trigger itu melihat periode SELURUH sekolah dan memakai
--    `tanggal_mulai` terbaru lintas tenant. Sekolah A bisa tertolak gara-gara
--    periode sekolah B.
--
-- -------------------------------------------------------------------------
-- BASIS PERHITUNGAN SALDO (disamakan dengan tampilan aplikasi)
-- -------------------------------------------------------------------------
--   saldo = periode_aktif.saldo_awal
--         + SUM(pemasukan  DALAM rentang periode aktif)
--         - SUM(pengeluaran DALAM rentang periode aktif)
--
-- Sebelumnya aplikasi memakai `periode_pembukuan.saldo_awal` (App.tsx)
-- sementara database memakai `konfigurasi_lembaga.saldo_awal` — dua sumber
-- kebenaran yang bisa berbeda. Patch ini menjadikan `periode_pembukuan`
-- satu-satunya acuan, dengan fallback ke konfigurasi_lembaga hanya bila
-- periode aktif belum ada.
-- =========================================================================

BEGIN;

-- =========================================================================
-- 1. FUNGSI INTI: SALDO KAS BERJALAN PER ORGANISASI
-- =========================================================================
-- SECURITY DEFINER supaya tetap benar ketika dipanggil dari dalam trigger
-- yang berjalan di konteks RPC SECURITY DEFINER (RLS tidak aktif di sana).
-- Filter `organization_id` ditulis EKSPLISIT, tidak mengandalkan RLS.

CREATE OR REPLACE FUNCTION public.hitung_saldo_kas_berjalan(p_org uuid)
RETURNS numeric
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_awal    numeric := 0;
  v_mulai   date;
  v_akhir   date;
  v_masuk   numeric := 0;
  v_keluar  numeric := 0;
BEGIN
  IF p_org IS NULL THEN
    RAISE EXCEPTION 'AUTH_ORGANIZATION_NOT_FOUND: organisasi tidak dikenali.';
  END IF;

  SELECT saldo_awal, tanggal_mulai, tanggal_akhir
    INTO v_awal, v_mulai, v_akhir
    FROM public.periode_pembukuan
   WHERE organization_id = p_org
     AND UPPER(status) = 'AKTIF'
   ORDER BY tanggal_mulai DESC, created_at DESC
   LIMIT 1;

  IF NOT FOUND THEN
    -- Fallback: belum ada periode aktif (akun baru / data lama).
    -- Pakai saldo awal konfigurasi dan seluruh transaksi organisasi.
    SELECT COALESCE(saldo_awal, 0) INTO v_awal
      FROM public.konfigurasi_lembaga
     WHERE organization_id = p_org;

    v_awal  := COALESCE(v_awal, 0);
    v_mulai := NULL;
    v_akhir := NULL;
  END IF;

  SELECT COALESCE(SUM(nominal), 0) INTO v_masuk
    FROM public.pemasukan
   WHERE organization_id = p_org
     AND (v_mulai IS NULL OR tanggal >= v_mulai)
     AND (v_akhir IS NULL OR tanggal <= v_akhir);

  SELECT COALESCE(SUM(nominal), 0) INTO v_keluar
    FROM public.pengeluaran
   WHERE organization_id = p_org
     AND (v_mulai IS NULL OR tanggal >= v_mulai)
     AND (v_akhir IS NULL OR tanggal <= v_akhir);

  RETURN COALESCE(v_awal, 0) + v_masuk - v_keluar;
END;
$$;

GRANT EXECUTE ON FUNCTION public.hitung_saldo_kas_berjalan(uuid) TO authenticated;


-- =========================================================================
-- 2. VIEW saldo_kas DIBUAT ULANG (TENANT-AWARE)
-- =========================================================================
-- Dibuat ulang karena FINAL_REPAIR menghapusnya tanpa mengembalikan.
-- security_invoker = true supaya view tunduk pada RLS pemanggilnya.

DROP VIEW IF EXISTS public.saldo_kas;

CREATE VIEW public.saldo_kas
WITH (security_invoker = true)
AS
SELECT
  public.get_auth_org_id() AS organization_id,
  public.hitung_saldo_kas_berjalan(public.get_auth_org_id()) AS total_saldo_kas;

GRANT SELECT ON public.saldo_kas TO authenticated;


-- =========================================================================
-- 3. TRIGGER VALIDASI SALDO PADA PENGELUARAN (INSERT / UPDATE)
-- =========================================================================
-- Menggantikan `check_saldo_sebelum_pengeluaran()` dari migration.sql yang
-- membaca view global tanpa filter organisasi.

CREATE OR REPLACE FUNCTION public.check_saldo_sebelum_pengeluaran()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org     uuid;
  v_saldo   numeric;
  v_sesudah numeric;
BEGIN
  v_org := COALESCE(NEW.organization_id, public.get_auth_org_id());

  IF v_org IS NULL THEN
    RAISE EXCEPTION 'AUTH_ORGANIZATION_NOT_FOUND: transaksi tanpa organisasi ditolak.';
  END IF;

  v_saldo := public.hitung_saldo_kas_berjalan(v_org);

  IF TG_OP = 'INSERT' THEN
    v_sesudah := v_saldo - NEW.nominal;
  ELSE
    -- Saldo berjalan sudah memuat OLD.nominal, jadi dikembalikan dulu.
    v_sesudah := v_saldo + OLD.nominal - NEW.nominal;
  END IF;

  IF v_sesudah < 0 THEN
    RAISE EXCEPTION
      'SALDO_TIDAK_CUKUP: Nominal pengeluaran (Rp %) melebihi saldo kas tersedia (Rp %). Transaksi dibatalkan oleh database.',
      to_char(NEW.nominal, 'FM999,999,999,999'),
      to_char(COALESCE(v_saldo, 0), 'FM999,999,999,999');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_check_saldo_pengeluaran ON public.pengeluaran;
CREATE TRIGGER trigger_check_saldo_pengeluaran
BEFORE INSERT OR UPDATE ON public.pengeluaran
FOR EACH ROW
EXECUTE FUNCTION public.check_saldo_sebelum_pengeluaran();


-- =========================================================================
-- 4. TRIGGER BARU: HAPUS PEMASUKAN TIDAK BOLEH MEMBUAT SALDO MINUS
-- =========================================================================

CREATE OR REPLACE FUNCTION public.check_saldo_sebelum_hapus_pemasukan()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org     uuid;
  v_saldo   numeric;
  v_sesudah numeric;
BEGIN
  v_org := COALESCE(OLD.organization_id, public.get_auth_org_id());
  IF v_org IS NULL THEN
    RETURN OLD;
  END IF;

  v_saldo   := public.hitung_saldo_kas_berjalan(v_org);
  v_sesudah := v_saldo - OLD.nominal;

  IF v_sesudah < 0 THEN
    RAISE EXCEPTION
      'SALDO_TIDAK_CUKUP: Pemasukan Rp % tidak dapat dihapus karena dananya sudah terpakai. Saldo kas akan menjadi Rp %. Hapus atau koreksi pengeluaran terkait terlebih dahulu.',
      to_char(OLD.nominal, 'FM999,999,999,999'),
      to_char(v_sesudah, 'FM999,999,999,999');
  END IF;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trigger_check_saldo_hapus_pemasukan ON public.pemasukan;
CREATE TRIGGER trigger_check_saldo_hapus_pemasukan
BEFORE DELETE ON public.pemasukan
FOR EACH ROW
EXECUTE FUNCTION public.check_saldo_sebelum_hapus_pemasukan();

-- UPDATE pemasukan (menurunkan nominal) diperlakukan sama.
CREATE OR REPLACE FUNCTION public.check_saldo_sebelum_ubah_pemasukan()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org     uuid;
  v_saldo   numeric;
  v_sesudah numeric;
BEGIN
  IF NEW.nominal >= OLD.nominal THEN
    RETURN NEW;
  END IF;

  v_org := COALESCE(NEW.organization_id, OLD.organization_id, public.get_auth_org_id());
  IF v_org IS NULL THEN
    RETURN NEW;
  END IF;

  v_saldo   := public.hitung_saldo_kas_berjalan(v_org);
  v_sesudah := v_saldo - OLD.nominal + NEW.nominal;

  IF v_sesudah < 0 THEN
    RAISE EXCEPTION
      'SALDO_TIDAK_CUKUP: Nominal pemasukan tidak dapat diturunkan, saldo kas akan menjadi Rp %.',
      to_char(v_sesudah, 'FM999,999,999,999');
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_check_saldo_ubah_pemasukan ON public.pemasukan;
CREATE TRIGGER trigger_check_saldo_ubah_pemasukan
BEFORE UPDATE ON public.pemasukan
FOR EACH ROW
EXECUTE FUNCTION public.check_saldo_sebelum_ubah_pemasukan();


-- =========================================================================
-- 5. RPC catat_pengeluaran DIBUAT ULANG DENGAN CEK SALDO
-- =========================================================================
-- Trigger di atas sudah menjadi jaring pengaman terakhir, tetapi pemeriksaan
-- di dalam RPC memberi pesan error yang jauh lebih enak dibaca bendahara
-- dan mencegah transaksi dibuat lalu di-rollback.

CREATE OR REPLACE FUNCTION public.catat_pengeluaran(
  p_no_bukti   text,
  p_tanggal    date,
  p_kategori   text,
  p_nominal    numeric,
  p_keterangan text,
  p_status     text DEFAULT 'Terbayar',
  p_bukti_url  text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org     uuid := public.get_auth_org_id();
  v_periode public.periode_pembukuan%ROWTYPE;
  v_row     public.pengeluaran%ROWTYPE;
  v_saldo   numeric;
  v_tanggal date;
BEGIN
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'AUTH_ORGANIZATION_NOT_FOUND';
  END IF;

  SELECT * INTO v_periode
    FROM public.periode_pembukuan
   WHERE organization_id = v_org AND UPPER(status) = 'AKTIF'
   ORDER BY tanggal_mulai DESC, created_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PERIODE_AKTIF_TIDAK_DITEMUKAN';
  END IF;

  IF COALESCE(p_nominal, 0) <= 0 THEN
    RAISE EXCEPTION 'NOMINAL_INVALID: Nominal pengeluaran harus lebih besar dari nol.';
  END IF;

  v_tanggal := COALESCE(p_tanggal, CURRENT_DATE);

  IF v_tanggal < v_periode.tanggal_mulai THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Tanggal transaksi berada pada periode yang sudah ditutup.';
  END IF;

  IF v_periode.tanggal_akhir IS NOT NULL AND v_tanggal > v_periode.tanggal_akhir THEN
    RAISE EXCEPTION 'TRANSAKSI_DI_LUAR_PERIODE: Tanggal transaksi melewati akhir periode aktif.';
  END IF;

  -- ---- INTI TEMUAN #1: validasi saldo yang sebelumnya hilang ----
  v_saldo := public.hitung_saldo_kas_berjalan(v_org);
  IF (v_saldo - p_nominal) < 0 THEN
    RAISE EXCEPTION
      'SALDO_TIDAK_CUKUP: Nominal pengeluaran (Rp %) melebihi saldo kas tersedia (Rp %).',
      to_char(p_nominal, 'FM999,999,999,999'),
      to_char(COALESCE(v_saldo, 0), 'FM999,999,999,999');
  END IF;

  INSERT INTO public.pengeluaran
    (organization_id, no_bukti, tanggal, kategori, nominal, keterangan, status, bukti_url, created_by)
  VALUES
    (v_org, p_no_bukti, v_tanggal, p_kategori, p_nominal, p_keterangan,
     COALESCE(NULLIF(BTRIM(p_status), ''), 'Terbayar'), p_bukti_url, auth.uid())
  RETURNING * INTO v_row;

  RETURN row_to_json(v_row)::jsonb;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catat_pengeluaran(text,date,text,numeric,text,text,text) TO authenticated;


-- =========================================================================
-- 6. RPC BARU: catat_pemasukan (menggantikan INSERT langsung dari browser)
-- =========================================================================
-- Sebelumnya frontend melakukan `.insert()` polos ke tabel `pemasukan` dan
-- bergantung sepenuhnya pada DEFAULT get_auth_org_id(). Bila default itu
-- hilang di salah satu database, insert gagal dengan NOT NULL violation.
-- RPC ini menyamakan pola dengan pengeluaran & pembayaran siswa.

CREATE OR REPLACE FUNCTION public.catat_pemasukan(
  p_no_bukti   text,
  p_tanggal    date,
  p_sumber     text,
  p_sub        text,
  p_nominal    numeric,
  p_keterangan text,
  p_status     text DEFAULT 'Selesai'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org     uuid := public.get_auth_org_id();
  v_periode public.periode_pembukuan%ROWTYPE;
  v_row     public.pemasukan%ROWTYPE;
  v_tanggal date;
BEGIN
  IF v_org IS NULL THEN
    RAISE EXCEPTION 'AUTH_ORGANIZATION_NOT_FOUND';
  END IF;

  SELECT * INTO v_periode
    FROM public.periode_pembukuan
   WHERE organization_id = v_org AND UPPER(status) = 'AKTIF'
   ORDER BY tanggal_mulai DESC, created_at DESC
   LIMIT 1;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'PERIODE_AKTIF_TIDAK_DITEMUKAN';
  END IF;

  IF COALESCE(p_nominal, 0) <= 0 THEN
    RAISE EXCEPTION 'NOMINAL_INVALID: Nominal pemasukan harus lebih besar dari nol.';
  END IF;

  v_tanggal := COALESCE(p_tanggal, CURRENT_DATE);

  IF v_tanggal < v_periode.tanggal_mulai THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Tanggal transaksi berada pada periode yang sudah ditutup.';
  END IF;

  IF v_periode.tanggal_akhir IS NOT NULL AND v_tanggal > v_periode.tanggal_akhir THEN
    RAISE EXCEPTION 'TRANSAKSI_DI_LUAR_PERIODE: Tanggal transaksi melewati akhir periode aktif.';
  END IF;

  INSERT INTO public.pemasukan
    (organization_id, no_bukti, tanggal, sumber, sub, nominal, keterangan, status, created_by)
  VALUES
    (v_org, p_no_bukti, v_tanggal, p_sumber, p_sub, p_nominal, p_keterangan,
     COALESCE(NULLIF(BTRIM(p_status), ''), 'Selesai'), auth.uid())
  RETURNING * INTO v_row;

  RETURN row_to_json(v_row)::jsonb;
END;
$$;

GRANT EXECUTE ON FUNCTION public.catat_pemasukan(text,date,text,text,numeric,text,text) TO authenticated;


-- =========================================================================
-- 7. PERBAIKAN TRIGGER KUNCI PERIODE (TEMUAN #8) — FILTER ORGANISASI
-- =========================================================================
-- Versi `cutoff_migration.sql` query periode_pembukuan tanpa organization_id.
-- Aman untuk INSERT langsung dari browser (RLS ikut jalan), TETAPI salah
-- ketika dipicu dari dalam RPC SECURITY DEFINER: trigger melihat periode
-- SELURUH sekolah. Versi di bawah memakai organization_id baris itu sendiri.

CREATE OR REPLACE FUNCTION public.cegah_hapus_transaksi_periode_tertutup()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org   uuid;
  v_mulai date;
BEGIN
  v_org := COALESCE(OLD.organization_id, public.get_auth_org_id());
  IF v_org IS NULL THEN
    RETURN OLD;
  END IF;

  SELECT tanggal_mulai INTO v_mulai
    FROM public.periode_pembukuan
   WHERE organization_id = v_org AND UPPER(status) = 'AKTIF'
   ORDER BY tanggal_mulai DESC, created_at DESC
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
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_org   uuid;
  v_mulai date;
BEGIN
  v_org := COALESCE(NEW.organization_id, public.get_auth_org_id());
  IF v_org IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT tanggal_mulai INTO v_mulai
    FROM public.periode_pembukuan
   WHERE organization_id = v_org AND UPPER(status) = 'AKTIF'
   ORDER BY tanggal_mulai DESC, created_at DESC
   LIMIT 1;

  IF v_mulai IS NOT NULL AND NEW.tanggal < v_mulai THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Tanggal transaksi berada pada periode yang sudah ditutup.';
  END IF;

  RETURN NEW;
END;
$$;

-- Fungsi pengunci UPDATE juga dibuat konsisten bila ada di database.
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public' AND p.proname = 'cegah_ubah_transaksi_periode_tertutup'
  ) THEN
    EXECUTE $fn$
      CREATE OR REPLACE FUNCTION public.cegah_ubah_transaksi_periode_tertutup()
      RETURNS TRIGGER
      LANGUAGE plpgsql
      SECURITY DEFINER
      SET search_path = public
      AS $body$
      DECLARE
        v_org   uuid;
        v_mulai date;
      BEGIN
        v_org := COALESCE(NEW.organization_id, OLD.organization_id, public.get_auth_org_id());
        IF v_org IS NULL THEN
          RETURN NEW;
        END IF;

        SELECT tanggal_mulai INTO v_mulai
          FROM public.periode_pembukuan
         WHERE organization_id = v_org AND UPPER(status) = 'AKTIF'
         ORDER BY tanggal_mulai DESC, created_at DESC
         LIMIT 1;

        IF v_mulai IS NOT NULL AND OLD.tanggal < v_mulai THEN
          RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Transaksi periode tertutup tidak dapat diubah.';
        END IF;

        RETURN NEW;
      END;
      $body$;
    $fn$;
  END IF;
END $$;


-- =========================================================================
-- 8. URUTAN TRIGGER
-- =========================================================================
-- PostgreSQL menjalankan trigger BEFORE per baris menurut URUTAN NAMA.
-- `trigger_check_saldo_pengeluaran` < `trigger_kunci_insert_pengeluaran_cutoff`
-- secara alfabet, jadi pesan "saldo tidak cukup" muncul lebih dulu daripada
-- "periode terkunci". Itu urutan yang diinginkan: bendahara lebih sering
-- salah karena saldo daripada karena tanggal.

NOTIFY pgrst, 'reload schema';

COMMIT;


-- =========================================================================
-- VERIFIKASI (jalankan setelah COMMIT, sebagai user yang sudah login
-- lewat aplikasi — bukan di SQL Editor, karena get_auth_org_id() butuh sesi)
-- =========================================================================
--
-- a. Pastikan view hidup kembali:
--      SELECT * FROM public.saldo_kas;
--
-- b. Pastikan fungsi & trigger terpasang:
--      SELECT proname FROM pg_proc
--       WHERE proname IN ('hitung_saldo_kas_berjalan','catat_pengeluaran','catat_pemasukan');
--
--      SELECT tgname, tgrelid::regclass FROM pg_trigger
--       WHERE NOT tgisinternal
--         AND tgrelid IN ('public.pemasukan'::regclass, 'public.pengeluaran'::regclass);
--
-- c. Uji fungsional dari aplikasi (ini yang paling penting):
--      1. Catat pemasukan Rp 1.000.000
--      2. Catat pengeluaran Rp 2.000.000  -> HARUS DITOLAK "SALDO_TIDAK_CUKUP"
--      3. Catat pengeluaran Rp 1.000.000  -> berhasil, saldo jadi 0
--      4. Hapus pemasukan Rp 1.000.000    -> HARUS DITOLAK "SALDO_TIDAK_CUKUP"
--      5. Hapus pengeluaran Rp 1.000.000 dulu, baru pemasukan -> berhasil
-- =========================================================================
