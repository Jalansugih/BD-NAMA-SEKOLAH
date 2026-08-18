-- =====================================================================
-- RAJASCH.ID MODUL BENDAHARA - DATABASE MIGRATION SCRIPT (V2)
-- Jalankan script ini di SQL Editor Supabase Project Anda
--
-- PERINGATAN: script ini DROP + CREATE ULANG seluruh tabel modul bendahara
-- supaya skema konsisten dengan Panduan Perbaikan (ID dibuat server/UUID,
-- konfigurasi lembaga & saldo awal pindah ke database, dst). Jika project
-- Supabase Anda sudah berisi data produksi sungguhan, BACKUP dulu (Table
-- Editor -> Export CSV per tabel) sebelum menjalankan script ini.
-- =====================================================================

-- 0. BERSIHKAN OBJEK LAMA (aman dijalankan meski belum pernah ada)
DROP TABLE IF EXISTS pemasukan CASCADE;
DROP TABLE IF EXISTS pengeluaran CASCADE;
DROP TABLE IF EXISTS siswa_tagihan CASCADE;
DROP TABLE IF EXISTS master_sumber_dana CASCADE;
DROP TABLE IF EXISTS master_kategori CASCADE;
DROP TABLE IF EXISTS master_kelas CASCADE;
DROP TABLE IF EXISTS konfigurasi_lembaga CASCADE;
DROP TABLE IF EXISTS audit_log CASCADE;
DROP VIEW IF EXISTS saldo_kas;
DROP FUNCTION IF EXISTS check_saldo_sebelum_pengeluaran();
DROP FUNCTION IF EXISTS log_audit_change();
DROP FUNCTION IF EXISTS catat_pengeluaran(text, date, text, numeric, text, text, text);
DROP FUNCTION IF EXISTS catat_pengeluaran(text, date, text, numeric, text, text);
DROP FUNCTION IF EXISTS catat_pembayaran_siswa(text, text, date, text, numeric);

-- 1. KONFIGURASI LEMBAGA (SINGLETON) + SALDO KAS AWAL
-- Satu baris tetap (id selalu TRUE) menyimpan identitas lembaga & saldo awal.
-- Menjawab poin 1 & 2 panduan: tidak ada lagi default Rp100 juta hardcode,
-- dan identitas lembaga tidak lagi hanya di React State.
CREATE TABLE konfigurasi_lembaga (
    id BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id = TRUE),
    nama_lembaga VARCHAR(150) NOT NULL DEFAULT '',
    jenis_lembaga VARCHAR(30) NOT NULL DEFAULT 'SD',
    logo_url TEXT,
    saldo_awal NUMERIC(15,2) NOT NULL DEFAULT 0,
    npsn VARCHAR(30),
    alamat TEXT,
    kontak VARCHAR(50),
    website VARCHAR(150),
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    updated_by UUID
);
INSERT INTO konfigurasi_lembaga (id) VALUES (TRUE);

-- 2. TABEL AUDIT LOG
CREATE TABLE audit_log (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    tabel_terkait VARCHAR(50) NOT NULL,
    record_id TEXT NOT NULL,
    aksi VARCHAR(10) NOT NULL CHECK (aksi IN ('INSERT', 'UPDATE', 'DELETE')),
    data_sebelum JSONB,
    data_sesudah JSONB,
    user_id TEXT DEFAULT 'system',
    waktu TIMESTAMPTZ DEFAULT NOW()
);

-- 3. TABEL MASTER DATA (kelas, sumber dana, kategori pengeluaran)
-- Sebelumnya master_kelas TIDAK PERNAH punya tabel sama sekali (murni
-- React State) -- ini memperbaiki poin 8 panduan.
CREATE TABLE master_kelas (
    nama VARCHAR(100) PRIMARY KEY,
    urutan INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE master_sumber_dana (
    id VARCHAR(50) PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    subs TEXT[] DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE master_kategori (
    nama VARCHAR(100) PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. TABEL SISWA TAGIHAN (id dibuat SERVER via UUID, bukan array frontend)
CREATE TABLE siswa_tagihan (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    nama VARCHAR(100) NOT NULL,
    kelas VARCHAR(50) NOT NULL,
    jenis VARCHAR(100) NOT NULL,
    target NUMERIC(15,2) NOT NULL DEFAULT 0,
    catatan TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID
);

-- 5. TABEL PEMASUKAN (id dibuat SERVER via UUID)
CREATE TABLE pemasukan (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    no_bukti VARCHAR(50) NOT NULL,
    tanggal DATE NOT NULL,
    sumber VARCHAR(50) NOT NULL,
    sub VARCHAR(100) NOT NULL,
    nominal NUMERIC(15,2) NOT NULL CHECK (nominal > 0),
    keterangan TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'Selesai',
    siswa_id UUID REFERENCES siswa_tagihan(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID
);

-- 6. TABEL PENGELUARAN (id dibuat SERVER via UUID)
CREATE TABLE pengeluaran (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    no_bukti VARCHAR(50) NOT NULL,
    tanggal DATE NOT NULL,
    kategori VARCHAR(100) NOT NULL,
    nominal NUMERIC(15,2) NOT NULL CHECK (nominal > 0),
    keterangan TEXT NOT NULL,
    status VARCHAR(20) DEFAULT 'Terbayar',
    bukti_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    created_by UUID
);

-- 7. VIEW SALDO KAS BERJALAN (SALDO AWAL DIAMBIL DARI konfigurasi_lembaga,
-- BUKAN ANGKA HARDCODE Rp 100.000.000 SEPERTI SEBELUMNYA)
CREATE OR REPLACE VIEW saldo_kas AS
SELECT
    (SELECT saldo_awal FROM konfigurasi_lembaga WHERE id = TRUE)
    + COALESCE((SELECT SUM(nominal) FROM pemasukan), 0)
    - COALESCE((SELECT SUM(nominal) FROM pengeluaran), 0) AS total_saldo_kas;

-- 8. TRIGGER FUNCTION VALIDASI SALDO SEBELUM PENGELUARAN (SERVER-SIDE CONSTRAINT)
CREATE OR REPLACE FUNCTION check_saldo_sebelum_pengeluaran()
RETURNS TRIGGER AS $$
DECLARE
    v_saldo_saat_ini NUMERIC(15,2);
    v_saldo_setelah_pengeluaran NUMERIC(15,2);
BEGIN
    IF (TG_OP = 'INSERT') THEN
        SELECT total_saldo_kas INTO v_saldo_saat_ini FROM saldo_kas;
        v_saldo_setelah_pengeluaran := v_saldo_saat_ini - NEW.nominal;
    ELSIF (TG_OP = 'UPDATE') THEN
        SELECT total_saldo_kas INTO v_saldo_saat_ini FROM saldo_kas;
        v_saldo_setelah_pengeluaran := v_saldo_saat_ini + OLD.nominal - NEW.nominal;
    END IF;

    IF v_saldo_setelah_pengeluaran < 0 THEN
        RAISE EXCEPTION 'SALDO_TIDAK_CUKUP: Nominal pengeluaran (Rp %) melebihi total saldo kas tersedia (Rp %)! Transaksi dibatalkan oleh database Server.',
            to_char(NEW.nominal, 'FM999,999,999,999'),
            to_char(COALESCE(v_saldo_saat_ini, 0), 'FM999,999,999,999');
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_saldo_pengeluaran
BEFORE INSERT OR UPDATE ON pengeluaran
FOR EACH ROW
EXECUTE FUNCTION check_saldo_sebelum_pengeluaran();

-- 9. TRIGGER FUNCTION AUDIT LOG (user_id diambil dari auth.uid() SUNGGUHAN,
-- bukan setting session yang tidak pernah di-set aplikasi seperti sebelumnya)
CREATE OR REPLACE FUNCTION log_audit_change()
RETURNS TRIGGER AS $$
DECLARE
    v_user TEXT;
BEGIN
    v_user := COALESCE(auth.uid()::text, 'system');

    IF (TG_OP = 'INSERT') THEN
        INSERT INTO audit_log (tabel_terkait, record_id, aksi, data_sebelum, data_sesudah, user_id)
        VALUES (TG_TABLE_NAME, NEW.id::text, 'INSERT', NULL, row_to_json(NEW)::jsonb, v_user);
        RETURN NEW;
    ELSIF (TG_OP = 'UPDATE') THEN
        INSERT INTO audit_log (tabel_terkait, record_id, aksi, data_sebelum, data_sesudah, user_id)
        VALUES (TG_TABLE_NAME, NEW.id::text, 'UPDATE', row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb, v_user);
        RETURN NEW;
    ELSIF (TG_OP = 'DELETE') THEN
        INSERT INTO audit_log (tabel_terkait, record_id, aksi, data_sebelum, data_sesudah, user_id)
        VALUES (TG_TABLE_NAME, OLD.id::text, 'DELETE', row_to_json(OLD)::jsonb, NULL, v_user);
        RETURN OLD;
    END IF;
    RETURN NULL;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_audit_pemasukan
AFTER INSERT OR UPDATE OR DELETE ON pemasukan
FOR EACH ROW EXECUTE FUNCTION log_audit_change();

CREATE TRIGGER trigger_audit_pengeluaran
AFTER INSERT OR UPDATE OR DELETE ON pengeluaran
FOR EACH ROW EXECUTE FUNCTION log_audit_change();

CREATE TRIGGER trigger_audit_siswa_tagihan
AFTER INSERT OR UPDATE OR DELETE ON siswa_tagihan
FOR EACH ROW EXECUTE FUNCTION log_audit_change();

CREATE OR REPLACE FUNCTION log_audit_change_konfigurasi()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO audit_log (tabel_terkait, record_id, aksi, data_sebelum, data_sesudah, user_id)
    VALUES ('konfigurasi_lembaga', 'singleton', 'UPDATE', row_to_json(OLD)::jsonb, row_to_json(NEW)::jsonb, COALESCE(auth.uid()::text, 'system'));
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_audit_konfigurasi
AFTER UPDATE ON konfigurasi_lembaga
FOR EACH ROW EXECUTE FUNCTION log_audit_change_konfigurasi();

-- 10. RPC: catat_pengeluaran() -- ID SELALU DIBUAT SERVER (parameter p_id
-- DIHAPUS, tidak lagi menerima ID kiriman frontend seperti sebelumnya).
CREATE OR REPLACE FUNCTION catat_pengeluaran(
    p_no_bukti TEXT,
    p_tanggal DATE,
    p_kategori TEXT,
    p_nominal NUMERIC,
    p_keterangan TEXT,
    p_status TEXT DEFAULT 'Terbayar',
    p_bukti_url TEXT DEFAULT NULL
)
RETURNS JSONB AS $$
DECLARE
    v_inserted_row RECORD;
BEGIN
    IF p_nominal <= 0 THEN
        RAISE EXCEPTION 'NOMINAL_INVALID: Nominal pengeluaran harus lebih dari Rp 0';
    END IF;

    INSERT INTO pengeluaran (no_bukti, tanggal, kategori, nominal, keterangan, status, bukti_url, created_by)
    VALUES (p_no_bukti, p_tanggal, p_kategori, p_nominal, p_keterangan, p_status, p_bukti_url, auth.uid())
    RETURNING * INTO v_inserted_row;

    RETURN row_to_json(v_inserted_row)::jsonb;
END;
$$ LANGUAGE plpgsql;

-- 11. RPC: catat_pembayaran_siswa() -- menjawab poin 6 panduan: pembayaran
-- siswa WAJIB masuk Supabase (bukan hanya setState React seperti sebelumnya).
-- Membungkus validasi siswa + insert pemasukan dalam satu transaksi atomic.
CREATE OR REPLACE FUNCTION catat_pembayaran_siswa(
    p_siswa_id UUID,
    p_no_bukti TEXT,
    p_tanggal DATE,
    p_status TEXT,
    p_nominal NUMERIC
)
RETURNS JSONB AS $$
DECLARE
    v_siswa RECORD;
    v_inserted_row RECORD;
BEGIN
    SELECT * INTO v_siswa FROM siswa_tagihan WHERE id = p_siswa_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'SISWA_TIDAK_DITEMUKAN: Data tagihan siswa tidak ditemukan';
    END IF;

    IF p_nominal <= 0 THEN
        RAISE EXCEPTION 'NOMINAL_INVALID: Nominal pembayaran harus lebih dari Rp 0';
    END IF;

    INSERT INTO pemasukan (no_bukti, tanggal, sumber, sub, nominal, keterangan, status, siswa_id, created_by)
    VALUES (
        p_no_bukti,
        p_tanggal,
        'Pembayaran',
        v_siswa.jenis,
        p_nominal,
        'Pembayaran ' || v_siswa.jenis || ' a.n ' || v_siswa.nama || ' (' || v_siswa.kelas || ')',
        COALESCE(p_status, 'Selesai'),
        p_siswa_id,
        auth.uid()
    )
    RETURNING * INTO v_inserted_row;

    RETURN row_to_json(v_inserted_row)::jsonb;
END;
$$ LANGUAGE plpgsql;

-- 12. GRANT DASAR (level tabel) UNTUK ROLE anon & authenticated.
-- RLS di bawah tetap membatasi baris mana yang boleh diakses.
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON
    audit_log, master_sumber_dana, master_kategori, master_kelas,
    siswa_tagihan, pemasukan, pengeluaran, konfigurasi_lembaga
    TO anon, authenticated;

-- 13. AKTIFKAN ROW LEVEL SECURITY -- HANYA PENGGUNA LOGIN (authenticated)
-- YANG BOLEH MENGAKSES DATA. Pengguna anon (belum login) tidak bisa apa-apa.
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_sumber_dana ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_kategori ENABLE ROW LEVEL SECURITY;
ALTER TABLE master_kelas ENABLE ROW LEVEL SECURITY;
ALTER TABLE siswa_tagihan ENABLE ROW LEVEL SECURITY;
ALTER TABLE pemasukan ENABLE ROW LEVEL SECURITY;
ALTER TABLE pengeluaran ENABLE ROW LEVEL SECURITY;
ALTER TABLE konfigurasi_lembaga ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Hanya user login - audit_log" ON audit_log
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Hanya user login - master_sumber_dana" ON master_sumber_dana
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Hanya user login - master_kategori" ON master_kategori
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Hanya user login - master_kelas" ON master_kelas
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Hanya user login - siswa_tagihan" ON siswa_tagihan
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Hanya user login - pemasukan" ON pemasukan
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Hanya user login - pengeluaran" ON pengeluaran
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');
CREATE POLICY "Hanya user login - konfigurasi_lembaga" ON konfigurasi_lembaga
  FOR ALL USING (auth.role() = 'authenticated') WITH CHECK (auth.role() = 'authenticated');

-- 14. RPC catat_pengeluaran() & catat_pembayaran_siswa() berjalan SECURITY
-- INVOKER (default) sehingga tetap tunduk pada RLS di atas -- hanya boleh
-- dieksekusi oleh role 'authenticated', bukan 'anon'.
REVOKE ALL ON FUNCTION catat_pengeluaran(text, date, text, numeric, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catat_pengeluaran(text, date, text, numeric, text, text, text) TO authenticated;
REVOKE ALL ON FUNCTION catat_pembayaran_siswa(uuid, text, date, text, numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION catat_pembayaran_siswa(uuid, text, date, text, numeric) TO authenticated;

-- 15. SUPABASE STORAGE: bucket untuk logo lembaga (menjawab poin 10 panduan
-- -- logo produksi disimpan sebagai file di Storage, bukan Base64 di React
-- State). Jalankan bagian ini SETELAH bucket 'logos' dibuat manual di menu
-- Storage (Supabase Dashboard -> Storage -> New Bucket -> nama "logos",
-- tandai Public bucket agar logo bisa ditampilkan di laporan PDF).
DROP POLICY IF EXISTS "Logo - baca publik" ON storage.objects;
DROP POLICY IF EXISTS "Logo - upload user login" ON storage.objects;
DROP POLICY IF EXISTS "Logo - update user login" ON storage.objects;

CREATE POLICY "Logo - baca publik" ON storage.objects
  FOR SELECT USING (bucket_id = 'logos');
CREATE POLICY "Logo - upload user login" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'logos' AND auth.role() = 'authenticated');
CREATE POLICY "Logo - update user login" ON storage.objects
  FOR UPDATE USING (bucket_id = 'logos' AND auth.role() = 'authenticated');

-- 16. SUPABASE STORAGE: bucket untuk nota/kwitansi bukti pengeluaran.
-- Jalankan bagian ini SETELAH bucket 'bukti-pengeluaran' dibuat manual di
-- menu Storage (Supabase Dashboard -> Storage -> New Bucket -> nama
-- "bukti-pengeluaran", tandai Public bucket agar foto nota bisa ditampilkan
-- di laporan/detail transaksi).
DROP POLICY IF EXISTS "Bukti Pengeluaran - baca publik" ON storage.objects;
DROP POLICY IF EXISTS "Bukti Pengeluaran - upload user login" ON storage.objects;
DROP POLICY IF EXISTS "Bukti Pengeluaran - update user login" ON storage.objects;

CREATE POLICY "Bukti Pengeluaran - baca publik" ON storage.objects
  FOR SELECT USING (bucket_id = 'bukti-pengeluaran');
CREATE POLICY "Bukti Pengeluaran - upload user login" ON storage.objects
  FOR INSERT WITH CHECK (bucket_id = 'bukti-pengeluaran' AND auth.role() = 'authenticated');
CREATE POLICY "Bukti Pengeluaran - update user login" ON storage.objects
  FOR UPDATE USING (bucket_id = 'bukti-pengeluaran' AND auth.role() = 'authenticated');

-- SELESAI. SILAKAN TEKAN "RUN" DI SUPABASE SQL EDITOR!
-- Setelah ini jalan:
-- 1) Buat bucket Storage "logos" DAN "bukti-pengeluaran" (keduanya Public)
--    lewat Dashboard jika belum ada.
-- 2) Buat akun bendahara di Authentication > Users > Add User.
-- 3) Isi profil lembaga & saldo kas awal lewat menu Pengaturan di aplikasi
--    (sekarang tersimpan ke tabel konfigurasi_lembaga, bukan hardcode lagi).
--
-- CATATAN MULTI-LEMBAGA (P3, belum diimplementasikan di script ini):
-- Skema di atas masih single-tenant (satu Supabase project = satu lembaga).
-- Untuk mendukung banyak sekolah dalam satu project, langkah lanjutannya:
-- tambahkan kolom lembaga_id UUID di setiap tabel transaksi/master/audit,
-- ubah konfigurasi_lembaga dari singleton menjadi satu baris per lembaga,
-- dan ganti seluruh policy RLS di atas dari "auth.role() = 'authenticated'"
-- menjadi "lembaga_id = (SELECT lembaga_id FROM user_lembaga WHERE user_id = auth.uid())"
-- agar User A tidak bisa melihat data Lembaga B.
--
-- CATATAN UPGRADE TANPA RESET DATA: jika project Anda sudah berisi data
-- pengeluaran produksi dan TIDAK ingin menjalankan ulang seluruh script di
-- atas (yang men-DROP tabel), cukup jalankan blok berikut saja untuk
-- menambahkan dukungan "Upload Nota / Kwitansi":
--
--   ALTER TABLE pengeluaran ADD COLUMN IF NOT EXISTS bukti_url TEXT;
--
--   CREATE OR REPLACE FUNCTION catat_pengeluaran(
--       p_no_bukti TEXT, p_tanggal DATE, p_kategori TEXT, p_nominal NUMERIC,
--       p_keterangan TEXT, p_status TEXT DEFAULT 'Terbayar',
--       p_bukti_url TEXT DEFAULT NULL
--   ) RETURNS JSONB AS $$
--   DECLARE v_inserted_row RECORD;
--   BEGIN
--       IF p_nominal <= 0 THEN
--           RAISE EXCEPTION 'NOMINAL_INVALID: Nominal pengeluaran harus lebih dari Rp 0';
--       END IF;
--       INSERT INTO pengeluaran (no_bukti, tanggal, kategori, nominal, keterangan, status, bukti_url, created_by)
--       VALUES (p_no_bukti, p_tanggal, p_kategori, p_nominal, p_keterangan, p_status, p_bukti_url, auth.uid())
--       RETURNING * INTO v_inserted_row;
--       RETURN row_to_json(v_inserted_row)::jsonb;
--   END; $$ LANGUAGE plpgsql;
--
--   (lalu buat bucket Storage "bukti-pengeluaran" (Public) dan jalankan
--   blok policy "Bukti Pengeluaran - ..." di atas.)
