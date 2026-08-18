-- RajaKas: additive migration untuk Tutup Buku (Cut-Off) dan Tahun Ajaran custom.
-- AMAN UNTUK DATA TRANSAKSI: tidak DROP tabel dan tidak DELETE pemasukan/pengeluaran.
-- Jalankan SEKALI di Supabase SQL Editor setelah migration yang sudah ada.

-- 1) Tahun ajaran disimpan di konfigurasi lembaga.
ALTER TABLE konfigurasi_lembaga
  ADD COLUMN IF NOT EXISTS tahun_ajaran VARCHAR(20) NOT NULL DEFAULT '2025/2026';

-- 2) Periode pembukuan: kompatibel dengan tabel yang sudah ada.
CREATE TABLE IF NOT EXISTS periode_pembukuan (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nama_periode VARCHAR(50) NOT NULL,
  tahun_ajaran VARCHAR(20) NOT NULL DEFAULT '2025/2026',
  tanggal_mulai DATE NOT NULL,
  tanggal_akhir DATE,
  saldo_awal NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (saldo_awal >= 0),
  saldo_akhir NUMERIC(15,2) CHECK (saldo_akhir >= 0),
  status VARCHAR(10) NOT NULL DEFAULT 'AKTIF' CHECK (status IN ('AKTIF','DITUTUP')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID,
  closed_at TIMESTAMPTZ,
  closed_by UUID
);

ALTER TABLE periode_pembukuan ADD COLUMN IF NOT EXISTS tahun_ajaran VARCHAR(20);
ALTER TABLE periode_pembukuan ADD COLUMN IF NOT EXISTS tanggal_akhir DATE;
ALTER TABLE periode_pembukuan ADD COLUMN IF NOT EXISTS saldo_awal NUMERIC(15,2) NOT NULL DEFAULT 0;
ALTER TABLE periode_pembukuan ADD COLUMN IF NOT EXISTS saldo_akhir NUMERIC(15,2);
ALTER TABLE periode_pembukuan ADD COLUMN IF NOT EXISTS status VARCHAR(10) NOT NULL DEFAULT 'AKTIF';
ALTER TABLE periode_pembukuan ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW();
ALTER TABLE periode_pembukuan ADD COLUMN IF NOT EXISTS created_by UUID;
ALTER TABLE periode_pembukuan ADD COLUMN IF NOT EXISTS closed_at TIMESTAMPTZ;
ALTER TABLE periode_pembukuan ADD COLUMN IF NOT EXISTS closed_by UUID;

-- Periode aktif memang boleh belum mempunyai tanggal_akhir.
ALTER TABLE periode_pembukuan ALTER COLUMN tanggal_akhir DROP NOT NULL;

-- Sinkronkan tahun ajaran lama yang sudah ada.
UPDATE periode_pembukuan
SET tahun_ajaran = COALESCE(NULLIF(tahun_ajaran, ''), nama_periode, '2025/2026')
WHERE tahun_ajaran IS NULL OR tahun_ajaran = '';

-- Data sumber yang menunjukkan 1900-01-01 diperbaiki hanya untuk tanggal mulai
-- periode aktif, tanpa menyentuh satu pun transaksi.
UPDATE periode_pembukuan
SET tanggal_mulai = make_date(split_part(tahun_ajaran, '/', 1)::INT, 7, 1)
WHERE tanggal_mulai = DATE '1900-01-01'
  AND tahun_ajaran ~ '^[0-9]{4}/[0-9]{4}$';

CREATE INDEX IF NOT EXISTS idx_periode_pembukuan_tanggal
  ON periode_pembukuan (tanggal_mulai DESC, tanggal_akhir DESC);

CREATE UNIQUE INDEX IF NOT EXISTS ux_periode_pembukuan_satu_aktif
  ON periode_pembukuan (status)
  WHERE status = 'AKTIF';

ALTER TABLE periode_pembukuan ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Periode pembukuan - user login" ON periode_pembukuan;
CREATE POLICY "Periode pembukuan - user login"
  ON periode_pembukuan
  FOR ALL
  USING (auth.role() = 'authenticated')
  WITH CHECK (auth.role() = 'authenticated');

GRANT SELECT, INSERT, UPDATE, DELETE ON periode_pembukuan TO authenticated;

-- 3) Fungsi saldo akhir: dihitung dari transaksi di database, bukan dari React.
CREATE OR REPLACE FUNCTION hitung_saldo_akhir_periode(p_periode_id UUID, p_tanggal_cutoff DATE DEFAULT NULL)
RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_periode RECORD;
  v_cutoff DATE;
  v_saldo NUMERIC(15,2);
BEGIN
  IF auth.role() <> 'authenticated' THEN
    RAISE EXCEPTION 'Hanya pengguna login yang dapat menghitung saldo periode.';
  END IF;

  SELECT * INTO v_periode
  FROM periode_pembukuan
  WHERE id = p_periode_id;

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
                WHERE tanggal >= v_periode.tanggal_mulai AND tanggal <= v_cutoff), 0)
    - COALESCE((SELECT SUM(nominal) FROM pengeluaran
                WHERE tanggal >= v_periode.tanggal_mulai AND tanggal <= v_cutoff), 0)
  INTO v_saldo;

  RETURN v_saldo;
END;
$$;

-- 4) Tutup buku atomik:
--    periode lama -> DITUTUP + saldo akhir dihitung,
--    periode baru -> AKTIF + saldo awal = saldo akhir.
CREATE OR REPLACE FUNCTION tutup_buku(p_periode_id UUID, p_tanggal_cutoff DATE)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_periode RECORD;
  v_saldo NUMERIC(15,2);
  v_next_start DATE;
  v_next_year TEXT;
  v_next_id UUID;
  v_next RECORD;
BEGIN
  IF auth.role() <> 'authenticated' THEN
    RAISE EXCEPTION 'Hanya pengguna login yang dapat menutup buku.';
  END IF;

  SELECT * INTO v_periode
  FROM periode_pembukuan
  WHERE id = p_periode_id
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

  v_saldo := hitung_saldo_akhir_periode(p_periode_id, p_tanggal_cutoff);

  UPDATE periode_pembukuan
  SET status = 'DITUTUP',
      tanggal_akhir = p_tanggal_cutoff,
      saldo_akhir = v_saldo,
      closed_at = NOW(),
      closed_by = auth.uid()
  WHERE id = p_periode_id;

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
    (nama_periode, tahun_ajaran, tanggal_mulai, tanggal_akhir, saldo_awal, saldo_akhir, status, created_by)
  VALUES
    (v_next_year, v_next_year, v_next_start, NULL, v_saldo, NULL, 'AKTIF', auth.uid())
  RETURNING * INTO v_next;

  -- Saldo awal konfigurasi tetap menunjukkan saldo awal periode yang sedang aktif.
  UPDATE konfigurasi_lembaga
  SET saldo_awal = v_saldo,
      tahun_ajaran = v_next_year,
      updated_at = NOW(),
      updated_by = auth.uid()
  WHERE id = TRUE;

  RETURN jsonb_build_object(
    'saldo_akhir', v_saldo,
    'periode_berikutnya', row_to_json(v_next)::jsonb
  );
END;
$$;

GRANT EXECUTE ON FUNCTION hitung_saldo_akhir_periode(UUID, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION tutup_buku(UUID, DATE) TO authenticated;

-- 5) Penguncian transaksi lama.
-- Transaksi dengan tanggal sebelum awal periode aktif tidak boleh dihapus.
-- Jika nanti fitur Edit dibuat, koreksi dilakukan setelah periode dibuka kembali.
CREATE OR REPLACE FUNCTION cegah_hapus_transaksi_periode_tertutup()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_mulai DATE;
BEGIN
  SELECT tanggal_mulai INTO v_mulai
  FROM periode_pembukuan
  WHERE status = 'AKTIF'
  ORDER BY tanggal_mulai DESC
  LIMIT 1;

  IF v_mulai IS NOT NULL AND OLD.tanggal < v_mulai THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Transaksi periode yang sudah ditutup tidak dapat dihapus.';
  END IF;

  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trigger_kunci_hapus_pemasukan_cutoff ON pemasukan;
CREATE TRIGGER trigger_kunci_hapus_pemasukan_cutoff
BEFORE DELETE ON pemasukan
FOR EACH ROW EXECUTE FUNCTION cegah_hapus_transaksi_periode_tertutup();

DROP TRIGGER IF EXISTS trigger_kunci_hapus_pengeluaran_cutoff ON pengeluaran;
CREATE TRIGGER trigger_kunci_hapus_pengeluaran_cutoff
BEFORE DELETE ON pengeluaran
FOR EACH ROW EXECUTE FUNCTION cegah_hapus_transaksi_periode_tertutup();

-- Transaksi baru harus berada pada periode aktif.
CREATE OR REPLACE FUNCTION cegah_transaksi_di_luar_periode_aktif()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_mulai DATE;
BEGIN
  SELECT tanggal_mulai INTO v_mulai
  FROM periode_pembukuan
  WHERE status = 'AKTIF'
  ORDER BY tanggal_mulai DESC
  LIMIT 1;

  IF v_mulai IS NOT NULL AND NEW.tanggal < v_mulai THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Tanggal transaksi berada pada periode yang sudah ditutup.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_kunci_insert_pemasukan_cutoff ON pemasukan;
CREATE TRIGGER trigger_kunci_insert_pemasukan_cutoff
BEFORE INSERT ON pemasukan
FOR EACH ROW EXECUTE FUNCTION cegah_transaksi_di_luar_periode_aktif();

DROP TRIGGER IF EXISTS trigger_kunci_insert_pengeluaran_cutoff ON pengeluaran;
CREATE TRIGGER trigger_kunci_insert_pengeluaran_cutoff
BEFORE INSERT ON pengeluaran
FOR EACH ROW EXECUTE FUNCTION cegah_transaksi_di_luar_periode_aktif();

-- UPDATE juga dikunci untuk transaksi histori. Jika periode dibuka kembali,
-- koreksi dapat dilakukan tanpa menghapus histori.
CREATE OR REPLACE FUNCTION cegah_update_transaksi_periode_tertutup()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_mulai DATE;
BEGIN
  SELECT tanggal_mulai INTO v_mulai
  FROM periode_pembukuan
  WHERE status = 'AKTIF'
  ORDER BY tanggal_mulai DESC
  LIMIT 1;

  IF v_mulai IS NOT NULL AND (OLD.tanggal < v_mulai OR NEW.tanggal < v_mulai) THEN
    RAISE EXCEPTION 'TRANSAKSI_PERIODE_TERKUNCI: Transaksi periode yang sudah ditutup tidak dapat diubah.';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trigger_kunci_update_pemasukan_cutoff ON pemasukan;
CREATE TRIGGER trigger_kunci_update_pemasukan_cutoff
BEFORE UPDATE ON pemasukan
FOR EACH ROW EXECUTE FUNCTION cegah_update_transaksi_periode_tertutup();

DROP TRIGGER IF EXISTS trigger_kunci_update_pengeluaran_cutoff ON pengeluaran;
CREATE TRIGGER trigger_kunci_update_pengeluaran_cutoff
BEFORE UPDATE ON pengeluaran
FOR EACH ROW EXECUTE FUNCTION cegah_update_transaksi_periode_tertutup();

-- 6) Buka kembali hanya periode terakhir untuk koreksi.
-- Tidak menghapus transaksi. Periode aktif berikutnya dihapus karena belum
-- mempunyai transaksi periode sendiri; histori transaksi tetap utuh.
CREATE OR REPLACE FUNCTION buka_kembali_periode(p_periode_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_closed RECORD;
  v_active RECORD;
  v_tx_count BIGINT;
BEGIN
  IF auth.role() <> 'authenticated' THEN
    RAISE EXCEPTION 'Hanya pengguna login yang dapat membuka kembali periode.';
  END IF;

  SELECT * INTO v_closed
  FROM periode_pembukuan
  WHERE id = p_periode_id AND status = 'DITUTUP'
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'PERIODE_TERTUTUP_TIDAK_DITEMUKAN';
  END IF;

  SELECT * INTO v_active
  FROM periode_pembukuan
  WHERE status = 'AKTIF'
  ORDER BY tanggal_mulai DESC
  LIMIT 1
  FOR UPDATE;

  IF v_active.id IS NOT NULL THEN
    SELECT COUNT(*) INTO v_tx_count
    FROM (
      SELECT id FROM pemasukan WHERE tanggal >= v_active.tanggal_mulai
      UNION ALL
      SELECT id FROM pengeluaran WHERE tanggal >= v_active.tanggal_mulai
    ) q;

    IF v_tx_count > 0 THEN
      RAISE EXCEPTION 'PERIODE_BERIKUTNYA_SUDAH_MEMILIKI_TRANSAKSI';
    END IF;

    DELETE FROM periode_pembukuan WHERE id = v_active.id;
  END IF;

  UPDATE periode_pembukuan
  SET status = 'AKTIF',
      tanggal_akhir = NULL,
      saldo_akhir = NULL,
      closed_at = NULL,
      closed_by = NULL
  WHERE id = p_periode_id;

  UPDATE konfigurasi_lembaga
  SET saldo_awal = v_closed.saldo_awal,
      tahun_ajaran = v_closed.tahun_ajaran,
      updated_at = NOW(),
      updated_by = auth.uid()
  WHERE id = TRUE;
END;
$$;

GRANT EXECUTE ON FUNCTION buka_kembali_periode(UUID) TO authenticated;

-- 7) Audit perubahan periode.
CREATE OR REPLACE FUNCTION log_audit_change_periode_pembukuan()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO audit_log(tabel_terkait, record_id, aksi, data_sebelum, data_sesudah, user_id)
    VALUES ('periode_pembukuan', NEW.id::text, 'INSERT', NULL, row_to_json(NEW)::jsonb, COALESCE(auth.uid()::text, 'system'));
    RETURN NEW;
  ELSIF TG_OP = 'UPDATE' THEN
    INSERT INTO audit_log(tabel_terkait, record_id, aksi, data_sebelum, data_sesudah, user_id)
    VALUES ('periode_pembukuan', NEW.id::text, 'UPDATE', row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb, COALESCE(auth.uid()::text, 'system'));
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    INSERT INTO audit_log(tabel_terkait, record_id, aksi, data_sebelum, data_sesudah, user_id)
    VALUES ('periode_pembukuan', OLD.id::text, 'DELETE', row_to_json(OLD)::jsonb, NULL, COALESCE(auth.uid()::text, 'system'));
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trigger_audit_periode_pembukuan ON periode_pembukuan;
CREATE TRIGGER trigger_audit_periode_pembukuan
AFTER INSERT OR UPDATE OR DELETE ON periode_pembukuan
FOR EACH ROW EXECUTE FUNCTION log_audit_change_periode_pembukuan();
