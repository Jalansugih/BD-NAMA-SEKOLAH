-- RAJASCH.ID - PERIODE PEMBUKUAN (ADDITIVE MIGRATION)
-- Jalankan SETELAH supabase/migration.sql.
-- Tidak menghapus atau mengubah tabel transaksi/laporan yang sudah ada.

CREATE TABLE IF NOT EXISTS periode_pembukuan (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  nama_periode VARCHAR(50) NOT NULL,
  tanggal_mulai DATE NOT NULL,
  tanggal_akhir DATE NOT NULL,
  saldo_awal NUMERIC(15,2) NOT NULL DEFAULT 0 CHECK (saldo_awal >= 0),
  saldo_akhir NUMERIC(15,2) CHECK (saldo_akhir >= 0),
  status VARCHAR(10) NOT NULL DEFAULT 'AKTIF' CHECK (status IN ('AKTIF','DITUTUP')),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by UUID,
  closed_at TIMESTAMPTZ,
  closed_by UUID,
  CONSTRAINT periode_tanggal_valid CHECK (tanggal_akhir >= tanggal_mulai)
);

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

-- Audit perubahan periode pembukuan.
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
