-- =========================================================================
-- BILLINGFLOW — MIGRATION V4: Atomic Sequence Counters
-- Jalankan ini SETELAH supabase/migration.sql (dan migration_v2 jika sudah
-- pernah dijalankan), di Supabase SQL Editor.
--
-- MASALAH YANG DIPERBAIKI:
-- Nomor invoice/kuitansi/surat tagihan/kode pelanggan/kode produk selama ini
-- di-generate murni dari counter di localStorage browser
-- (`sequences.invoice + 1`, dst), lalu langsung dipakai. Kalau dua user
-- (atau satu user di dua tab/device) membuat invoice pada saat yang hampir
-- bersamaan, counter lokal masing-masing browser bisa sama-sama membaca
-- nilai lama sebelum sempat sinkron → DUA invoice dengan nomor yang SAMA
-- persis bisa lolos. Untuk dokumen keuangan/pajak, ini masalah serius.
--
-- SOLUSI:
-- Fungsi Postgres `get_next_sequence()` di bawah ini melakukan increment
-- counter dalam SATU statement atomic (`INSERT ... ON CONFLICT DO UPDATE
-- ... RETURNING`). Postgres otomatis mengunci baris yang sedang diupdate,
-- jadi kalaupun dua request datang bersamaan dari device berbeda, Postgres
-- akan memprosesnya berurutan (bukan race condition) - device kedua PASTI
-- mendapat nomor berikutnya, bukan nomor yang sama dengan device pertama.
--
-- Fungsi ini juga menerima `p_minimum_value` (counter lokal saat ini di
-- browser pemanggil) supaya:
--   1. Saat pertama kali dipakai (baris counter belum ada di cloud), nomor
--      yang dihasilkan tidak mulai dari 1 lagi kalau organisasi itu sudah
--      punya invoice #001-#050 secara lokal - counter cloud langsung
--      "disamakan" ke titik terakhir yang diketahui klien.
--   2. Organisasi_id diambil dari sesi login (`get_auth_org_id()`), BUKAN
--      dikirim dari client - jadi satu organisasi tidak bisa memanipulasi
--      atau melihat counter organisasi lain.
-- =========================================================================

CREATE TABLE IF NOT EXISTS public.organization_sequences (
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    sequence_name VARCHAR(50) NOT NULL,
    current_value INT NOT NULL DEFAULT 0,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (organization_id, sequence_name)
);

ALTER TABLE public.organization_sequences ENABLE ROW LEVEL SECURITY;

-- Read-only visibility for the owning org (writes only ever happen through
-- the SECURITY DEFINER function below, never via direct table access).
DROP POLICY IF EXISTS "Organization sequences read policy" ON public.organization_sequences;
CREATE POLICY "Organization sequences read policy" ON public.organization_sequences
    FOR SELECT
    USING (organization_id = public.get_auth_org_id());

CREATE OR REPLACE FUNCTION public.get_next_sequence(
    p_sequence_name VARCHAR,
    p_minimum_value INT DEFAULT 0
)
RETURNS INT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_org_id UUID;
    v_next_value INT;
BEGIN
    v_org_id := public.get_auth_org_id();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'Tidak ditemukan organisasi untuk user yang sedang login';
    END IF;

    INSERT INTO public.organization_sequences (organization_id, sequence_name, current_value)
    VALUES (v_org_id, p_sequence_name, GREATEST(p_minimum_value, 0) + 1)
    ON CONFLICT (organization_id, sequence_name)
    DO UPDATE SET
        current_value = GREATEST(public.organization_sequences.current_value, p_minimum_value) + 1,
        updated_at = NOW()
    RETURNING current_value INTO v_next_value;

    RETURN v_next_value;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_next_sequence(VARCHAR, INT) TO authenticated;

-- =========================================================================
-- CATATAN:
-- Fase ini baru menyambungkan penomoran INVOICE ke mekanisme atomic di
-- atas (lihat StorageService.saveInvoice di storage.ts). Penomoran
-- Payment/Kuitansi, Surat Tagihan, kode Customer, dan kode Product masih
-- pakai counter localStorage lama - fungsi `get_next_sequence()` ini sudah
-- generik dan siap dipakai untuk semuanya, tinggal panggil dengan
-- `p_sequence_name` berbeda ('payment', 'receipt', 'billingLetter',
-- 'customer', 'product') di titik-titik pembuatan nomor masing-masing.
-- =========================================================================
