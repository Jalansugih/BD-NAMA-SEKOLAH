-- =========================================================================
-- BILLINGFLOW — MIGRATION V5: Atomic Multi-Table Payment Recording
-- Jalankan ini SETELAH supabase/migration_v4_atomic_sequences.sql,
-- di Supabase SQL Editor.
--
-- MASALAH YANG DIPERBAIKI:
-- Mencatat satu pembayaran sebenarnya menyentuh 4 tabel berbeda:
--   1. payments        (INSERT baris kuitansi baru)
--   2. invoices        (UPDATE paid_amount/outstanding_amount/status)
--   3. documents        (INSERT arsip dokumen kuitansi)
--   4. audit_logs       (INSERT jejak audit)
-- Sebelumnya keempatnya dieksekusi sebagai request terpisah dari browser
-- (lihat StorageService.recordPayment di storage.ts). Kalau koneksi
-- terputus atau tab ditutup di tengah proses, hasilnya bisa "nyangkut"
-- separuh jalan — misalnya kuitansi #00042 sudah tercatat tapi saldo
-- invoice belum ter-update, atau sebaliknya. Untuk dokumen keuangan, itu
-- kondisi data yang tidak konsisten dan berbahaya.
--
-- SOLUSI:
-- Fungsi `record_payment_atomic()` di bawah ini menjalankan KEEMPAT
-- operasi itu dalam SATU transaksi Postgres (function body plpgsql =
-- atomic block). Kalau ada satu langkah saja yang gagal (mis. validasi
-- nominal melebihi sisa tagihan), Postgres otomatis ROLLBACK semuanya —
-- tidak ada state "separuh jalan" yang mungkin tersimpan. Ini juga
-- sekaligus memakai `get_next_sequence()` dari migration_v4 untuk nomor
-- payment & kuitansi, jadi tidak ada lagi jendela race-condition di
-- antara reservasi nomor dan penulisan baris seperti pada implementasi
-- client-side sebelumnya.
--
-- Organisasi & user diambil dari sesi login (`get_auth_org_id()` /
-- `auth.uid()`), bukan dikirim dari client, supaya user tidak bisa
-- mencatat pembayaran ke invoice milik organisasi lain.
-- =========================================================================

CREATE OR REPLACE FUNCTION public.record_payment_atomic(
    p_invoice_id UUID,
    p_amount NUMERIC,
    p_payment_date DATE,
    p_payment_method VARCHAR,
    p_destination_bank VARCHAR DEFAULT NULL,
    p_bank_account_id UUID DEFAULT NULL,
    p_account_number VARCHAR DEFAULT NULL,
    p_reference_number VARCHAR DEFAULT NULL,
    p_notes TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_org_id UUID;
    v_user_id UUID;
    v_user_name VARCHAR;
    v_user_role VARCHAR;
    v_invoice RECORD;
    v_org RECORD;
    v_pay_seq INT;
    v_receipt_seq INT;
    v_payment_number VARCHAR;
    v_receipt_number VARCHAR;
    v_new_paid_amount NUMERIC;
    v_new_outstanding NUMERIC;
    v_new_status VARCHAR;
    v_new_paid_at TIMESTAMPTZ;
    v_destination_bank VARCHAR;
    v_payment_id UUID;
    v_document_id UUID;
    v_result JSONB;
BEGIN
    v_org_id := public.get_auth_org_id();
    v_user_id := auth.uid();
    IF v_org_id IS NULL THEN
        RAISE EXCEPTION 'Tidak ditemukan organisasi untuk user yang sedang login';
    END IF;

    SELECT name, role INTO v_user_name, v_user_role
    FROM public.profiles WHERE id = v_user_id;
    v_user_name := COALESCE(v_user_name, 'Pengguna');
    v_user_role := COALESCE(v_user_role, 'staff');

    -- Lock the invoice row so two concurrent payments against the same
    -- invoice can never both read the same stale outstanding_amount.
    SELECT * INTO v_invoice
    FROM public.invoices
    WHERE id = p_invoice_id AND organization_id = v_org_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invoice tidak ditemukan';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION 'Nominal pembayaran harus lebih dari 0';
    END IF;

    IF p_amount > v_invoice.outstanding_amount THEN
        RAISE EXCEPTION 'Nominal pembayaran melebihi sisa tagihan (%)', v_invoice.outstanding_amount;
    END IF;

    SELECT * INTO v_org FROM public.organizations WHERE id = v_org_id;

    -- Reserve payment & receipt sequence numbers atomically (same
    -- mechanism as migration_v4, reused here so both live under one
    -- transaction together with everything else).
    v_pay_seq := public.get_next_sequence('payment', 0);
    v_receipt_seq := public.get_next_sequence('receipt', 0);

    v_payment_number := 'PAY/' || to_char(p_payment_date, 'YYYY') || '/' || to_char(p_payment_date, 'MM')
        || '/' || lpad(v_pay_seq::text, 5, '0');

    v_receipt_number := COALESCE(v_org.payment_receipt_format, 'KWT/{YEAR}/{MONTH}/{NUMBER}');
    v_receipt_number := replace(v_receipt_number, '{YEAR}', to_char(p_payment_date, 'YYYY'));
    v_receipt_number := replace(v_receipt_number, '{MONTH}', to_char(p_payment_date, 'MM'));
    v_receipt_number := replace(v_receipt_number, '{NUMBER}', lpad(v_receipt_seq::text, 5, '0'));

    v_destination_bank := COALESCE(
        p_destination_bank,
        (SELECT bank_name FROM public.bank_accounts WHERE id = p_bank_account_id),
        'Bank Transfer'
    );

    -- 1. Insert payment
    INSERT INTO public.payments (
        organization_id, payment_number, invoice_id, customer_id, payment_date,
        amount, payment_method, destination_bank, account_number, reference_number,
        notes, received_by, receipt_number, created_by
    ) VALUES (
        v_org_id, v_payment_number, v_invoice.id, v_invoice.customer_id, p_payment_date,
        p_amount, p_payment_method, v_destination_bank, p_account_number, p_reference_number,
        p_notes, v_user_name || ' (' || upper(v_user_role) || ')', v_receipt_number, v_user_id
    ) RETURNING id INTO v_payment_id;

    -- 2. Update invoice balance & status
    v_new_paid_amount := v_invoice.paid_amount + p_amount;
    v_new_outstanding := GREATEST(0, v_invoice.grand_total - v_new_paid_amount);
    v_new_status := CASE WHEN v_new_outstanding <= 0 THEN 'paid' ELSE 'partially_paid' END;
    v_new_paid_at := CASE WHEN v_new_outstanding <= 0 THEN NOW() ELSE v_invoice.paid_at END;

    UPDATE public.invoices SET
        paid_amount = v_new_paid_amount,
        outstanding_amount = v_new_outstanding,
        status = v_new_status,
        paid_at = v_new_paid_at,
        updated_at = NOW()
    WHERE id = v_invoice.id;

    -- 3. Archive the payment receipt document
    INSERT INTO public.documents (
        organization_id, title, document_type, document_number, customer_id,
        reference_id, amount, date, status
    ) VALUES (
        v_org_id,
        'Kuitansi Penerimaan Pembayaran - ' || v_invoice.customer_id::text,
        'payment_receipt', v_receipt_number, v_invoice.customer_id,
        v_payment_id, p_amount, p_payment_date,
        CASE WHEN v_new_status = 'paid' THEN 'Lunas' ELSE 'Dibayar Sebagian' END
    ) RETURNING id INTO v_document_id;

    -- 4. Audit log
    INSERT INTO public.audit_logs (
        organization_id, user_id, user_name, user_role, action, module,
        record_id, record_title, details
    ) VALUES (
        v_org_id, v_user_id, v_user_name, v_user_role, 'pay', 'payments',
        v_payment_id::text, v_payment_number,
        'Mencatat pembayaran Rp' || to_char(p_amount, 'FM999,999,999,999') || ' untuk ' || v_invoice.invoice_number
    );

    v_result := jsonb_build_object(
        'payment_id', v_payment_id,
        'payment_number', v_payment_number,
        'receipt_number', v_receipt_number,
        'document_id', v_document_id,
        'invoice_id', v_invoice.id,
        'invoice_number', v_invoice.invoice_number,
        'customer_id', v_invoice.customer_id,
        'paid_amount', v_new_paid_amount,
        'outstanding_amount', v_new_outstanding,
        'status', v_new_status,
        'paid_at', v_new_paid_at,
        'destination_bank', v_destination_bank,
        'received_by', v_user_name || ' (' || upper(v_user_role) || ')'
    );

    RETURN v_result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_payment_atomic(
    UUID, NUMERIC, DATE, VARCHAR, VARCHAR, UUID, VARCHAR, VARCHAR, TEXT
) TO authenticated;

-- =========================================================================
-- CATATAN:
-- Fase ini menyambungkan flow Payments -> StorageService.recordPayment()
-- ke RPC atomic ini (lihat storage.ts). Saat Supabase terkonfigurasi &
-- terhubung, seluruh operasi payment+invoice+document+audit_log terjadi
-- di satu transaksi database; localStorage di browser hanya dipakai
-- sebagai cache tampilan setelah RPC berhasil (nilainya diambil dari
-- hasil RETURN RPC, bukan dihitung ulang di client). Kalau Supabase
-- tidak terkonfigurasi (mode lokal/demo tanpa backend), aplikasi tetap
-- fallback ke logic lokal lama supaya tetap bisa dipakai offline - hanya
-- saja tanpa jaminan atomicity itu (memang tidak relevan tanpa server).
--
-- Rekonsiliasi bank (reconcileTransaction / autoReconcileAllMatched)
-- masih memanggil StorageService.recordPayment() yang sama, jadi otomatis
-- ikut menikmati atomicity ini untuk bagian "catat pembayaran"-nya - tapi
-- update status transaksi bank itu sendiri (public.bank_transactions)
-- masih di luar transaksi ini dan BELUM dibuat atomic (sengaja di-skip
-- untuk fase ini, lihat catatan "Bank Reconciliation" di backlog).
-- =========================================================================
