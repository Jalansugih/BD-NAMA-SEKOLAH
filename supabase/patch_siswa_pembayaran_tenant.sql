-- ============================================================================
-- RAJAKAS BENDAHARA - PATCH SISWA/TAGIHAN + PEMBAYARAN MULTI-TENANT
-- Jalankan SETELAH struktur tenant_id + RLS multi-tenant sudah aktif.
--
-- Memperbaiki:
-- 1. Tambah Tagihan Siswa: insert tenant_id dari user login.
-- 2. Pembayaran Siswa: RPC catat_pembayaran_siswa() tenant-aware dan
--    mengisi tenant_id pada pemasukan.
-- ============================================================================

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
    v_tenant_id UUID;
    v_siswa RECORD;
    v_inserted_row RECORD;
BEGIN
    v_tenant_id := public.get_my_tenant_id();

    IF v_tenant_id IS NULL THEN
        RAISE EXCEPTION 'TENANT_TIDAK_DITEMUKAN: User belum memiliki tenant.';
    END IF;

    IF p_nominal IS NULL OR p_nominal <= 0 THEN
        RAISE EXCEPTION 'NOMINAL_INVALID: Nominal pembayaran harus lebih dari Rp 0';
    END IF;

    SELECT *
      INTO v_siswa
      FROM public.siswa_tagihan
     WHERE id = p_siswa_id
       AND tenant_id = v_tenant_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SISWA_TIDAK_DITEMUKAN: Data tagihan siswa tidak ditemukan pada tenant ini';
    END IF;

    INSERT INTO public.pemasukan (
        no_bukti,
        tanggal,
        sumber,
        sub,
        nominal,
        keterangan,
        status,
        siswa_id,
        created_by,
        tenant_id
    )
    VALUES (
        p_no_bukti,
        p_tanggal,
        'Pembayaran',
        v_siswa.jenis,
        p_nominal,
        'Pembayaran ' || v_siswa.jenis || ' a.n ' ||
          v_siswa.nama || ' (' || v_siswa.kelas || ')',
        COALESCE(NULLIF(p_status, ''), 'Selesai'),
        p_siswa_id,
        auth.uid(),
        v_tenant_id
    )
    RETURNING * INTO v_inserted_row;

    RETURN row_to_json(v_inserted_row)::jsonb;
END;
$$;

REVOKE ALL ON FUNCTION public.catat_pembayaran_siswa(
    UUID, TEXT, DATE, TEXT, NUMERIC
) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.catat_pembayaran_siswa(
    UUID, TEXT, DATE, TEXT, NUMERIC
) TO authenticated;
