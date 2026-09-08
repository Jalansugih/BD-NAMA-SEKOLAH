-- RAJAKAS BENDAHARA - PATCH PEMBAYARAN SISWA (HARDENED MULTI-TENANT)
-- Jalankan SETELAH migration_v6_multi_tenant.sql + migration_v7_multi_tenant.sql.
-- Skema canonical: organization_id + public.get_auth_org_id().
--
-- Penting:
-- - Jangan gunakan RPC tenant legacy.
-- - Jangan membaca/menulis kolom tenant legacy.
-- - organization_id untuk siswa_tagihan dan pemasukan diambil/diisi server-side.
-- - Fungsi SECURITY INVOKER membiarkan RLS membatasi data ke organisasi aktif.

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
    v_org_id UUID;
    v_siswa RECORD;
    v_inserted_row RECORD;
BEGIN
    v_org_id := public.get_auth_org_id();

    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'ORGANISASI_TIDAK_DITEMUKAN: User belum memiliki organisasi.';
    END IF;

    IF p_nominal IS NULL OR p_nominal <= 0 THEN
        RAISE EXCEPTION 'NOMINAL_INVALID: Nominal pembayaran harus lebih dari Rp 0';
    END IF;

    SELECT *
      INTO v_siswa
      FROM public.siswa_tagihan
     WHERE id = p_siswa_id
       AND organization_id = v_org_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'SISWA_TIDAK_DITEMUKAN: Data tagihan siswa tidak ditemukan pada organisasi ini';
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
        created_by
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
        auth.uid()
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
