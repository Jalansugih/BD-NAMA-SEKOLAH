-- =========================================================================
-- BILLINGFLOW — MIGRATION V22: Invoice Financial Integrity Guardrails
-- Jalankan ini SETELAH migration_v21_fullstack_payment_reports.sql,
-- di Supabase SQL Editor.
--
-- MASALAH YANG DIPERBAIKI:
-- Perhitungan invoice (quantity x unit_price - discount, lalu pajak &
-- grand total) selama ini HANYA dihitung di browser (React state) dan
-- dikirim apa adanya ke Supabase lewat client anon key. Ada modul
-- `src/lib/actions/invoice-actions.ts` yang niatnya melakukan validasi
-- ulang di "server" (mengambil harga asli dari tabel products supaya
-- tidak bisa dimanipulasi) — tapi modul itu tidak pernah dipanggil dari
-- UI manapun. Alur simpan invoice yang sebenarnya berjalan
-- (StorageService.saveInvoice -> SupabaseService.saveInvoice) langsung
-- meng-upsert nilai yang datang dari client, dan RLS policy yang ada
-- hanya memeriksa isolasi organization_id, bukan kebenaran nilai.
--
-- Akibatnya: request INSERT/UPDATE ke invoice_items atau invoices yang
-- dikirim langsung (mis. lewat DevTools/Network tab, atau bug di
-- frontend) bisa membawa unit_price/amount/grand_total sembarang tanpa
-- ada satupun lapisan yang menahannya.
--
-- SOLUSI:
-- Tiga trigger yang menegakkan rumus di level database, terlepas dari
-- apa yang dikirim client:
--   1. calc_invoice_item_amount()   — BEFORE INSERT/UPDATE invoice_items:
--      menimpa unit_price dengan harga master dari tabel products kalau
--      product_id diisi (mencegah tampering harga), lalu menghitung
--      ulang amount = round(greatest(0, quantity*unit_price - discount)).
--   2. protect_invoice_financials() — BEFORE INSERT/UPDATE invoices:
--      mengabaikan subtotal/discount_amount/tax_amount/grand_total/
--      outstanding_amount yang dikirim client, dan menghitung ulang
--      semuanya dari baris invoice_items yang benar-benar ada di
--      database (rumus sama persis dengan src/lib/invoiceCalc.ts di
--      frontend: pajak per item dengan diskon invoice diprorata).
--   3. trg_sync_invoice_totals()    — AFTER INSERT/UPDATE/DELETE
--      invoice_items: menyentuh baris invoices terkait supaya trigger
--      #2 di atas ikut menghitung ulang setiap kali baris item berubah
--      (bukan cuma saat header invoice yang di-update).
--
-- Ini murni jaring pengaman tambahan (defense in depth) — untuk
-- pemakaian normal lewat aplikasi, angka yang dihasilkan trigger ini
-- akan identik dengan yang sudah dihitung di frontend.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Hitung ulang & validasi setiap baris item invoice
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calc_invoice_item_amount()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_org_id UUID;
    v_product RECORD;
    v_raw_total NUMERIC;
BEGIN
    SELECT organization_id INTO v_org_id FROM public.invoices WHERE id = NEW.invoice_id;

    -- Kalau item terhubung ke produk master, harga & pajak SELALU diambil
    -- dari katalog produk saat ini — mengabaikan unit_price/tax_rate yang
    -- dikirim client untuk baris tersebut. Ini persis niat awal
    -- `calculateInvoiceAmounts()` di invoice-actions.ts, sekarang benar-benar
    -- ditegakkan untuk semua jalur penulisan, bukan cuma yang lewat fungsi
    -- itu (yang ternyata tidak pernah dipanggil).
    IF NEW.product_id IS NOT NULL THEN
        SELECT price, tax_rate INTO v_product
        FROM public.products
        WHERE id = NEW.product_id AND organization_id = v_org_id;

        IF FOUND THEN
            NEW.unit_price := v_product.price;
            IF NEW.tax_rate IS NULL THEN
                NEW.tax_rate := v_product.tax_rate;
            END IF;
        END IF;
    END IF;

    NEW.quantity := GREATEST(0.01, COALESCE(NEW.quantity, 1));
    NEW.unit_price := GREATEST(0, COALESCE(NEW.unit_price, 0));
    NEW.discount := GREATEST(0, COALESCE(NEW.discount, 0));

    v_raw_total := NEW.quantity * NEW.unit_price;
    NEW.discount := LEAST(v_raw_total, NEW.discount); -- diskon tidak boleh melebihi nilai baris
    NEW.amount := ROUND(GREATEST(0, v_raw_total - NEW.discount), 2);

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_invoice_items_calc_amount ON public.invoice_items;
CREATE TRIGGER trg_invoice_items_calc_amount
    BEFORE INSERT OR UPDATE ON public.invoice_items
    FOR EACH ROW EXECUTE FUNCTION public.calc_invoice_item_amount();

-- -------------------------------------------------------------------------
-- 2. Hitung ulang total invoice dari baris invoice_items yang sebenarnya
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.protect_invoice_financials()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_subtotal NUMERIC := 0;
    v_discount_amount NUMERIC := 0;
    v_taxable NUMERIC := 0;
    v_tax_amount NUMERIC := 0;
    v_additional NUMERIC := 0;
    v_paid NUMERIC := 0;
BEGIN
    SELECT COALESCE(SUM(amount), 0) INTO v_subtotal
    FROM public.invoice_items WHERE invoice_id = NEW.id;

    IF COALESCE(NEW.discount_type, 'fixed') = 'percentage' THEN
        v_discount_amount := ROUND(v_subtotal * LEAST(100, GREATEST(0, COALESCE(NEW.discount_value, 0))) / 100, 2);
    ELSE
        v_discount_amount := LEAST(v_subtotal, GREATEST(0, COALESCE(NEW.discount_value, 0)));
    END IF;

    v_taxable := GREATEST(0, v_subtotal - v_discount_amount);

    -- Pajak per item, dengan diskon invoice diprorata sesuai porsi
    -- subtotal masing-masing item (sama seperti calcInvoiceTotals() di
    -- src/lib/invoiceCalc.ts).
    SELECT COALESCE(SUM(
        CASE WHEN v_subtotal > 0 THEN
            GREATEST(0, item.amount - (v_discount_amount * item.amount / v_subtotal)) * COALESCE(item.tax_rate, 0) / 100
        ELSE 0 END
    ), 0) INTO v_tax_amount
    FROM public.invoice_items item WHERE item.invoice_id = NEW.id;

    v_additional := GREATEST(0, COALESCE(NEW.additional_charges, 0));
    v_paid := GREATEST(0, COALESCE(NEW.paid_amount, 0));

    NEW.subtotal := ROUND(v_subtotal, 2);
    NEW.discount_amount := ROUND(v_discount_amount, 2);
    NEW.tax_amount := ROUND(v_tax_amount, 2);
    NEW.grand_total := ROUND(v_taxable + v_tax_amount + v_additional, 2);
    NEW.outstanding_amount := GREATEST(0, ROUND(NEW.grand_total - v_paid, 2));

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_invoices_protect_financials ON public.invoices;
CREATE TRIGGER trg_invoices_protect_financials
    BEFORE INSERT OR UPDATE ON public.invoices
    FOR EACH ROW EXECUTE FUNCTION public.protect_invoice_financials();

-- -------------------------------------------------------------------------
-- 3. Setiap kali baris invoice_items berubah, paksa header invoice
--    dihitung ulang (lewat trigger #2 di atas)
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.trg_sync_invoice_totals()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_invoice_id UUID := COALESCE(NEW.invoice_id, OLD.invoice_id);
BEGIN
    UPDATE public.invoices SET updated_at = now() WHERE id = v_invoice_id;
    RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_invoice_items_sync_totals ON public.invoice_items;
CREATE TRIGGER trg_invoice_items_sync_totals
    AFTER INSERT OR UPDATE OR DELETE ON public.invoice_items
    FOR EACH ROW EXECUTE FUNCTION public.trg_sync_invoice_totals();

-- -------------------------------------------------------------------------
-- Catatan operasional:
-- * Trigger #2 jalan juga saat INSERT header invoice sebelum baris item
--   ditambahkan (urutan yang dipakai app: insert invoices dulu, baru
--   insert invoice_items) — pada saat itu subtotal akan terhitung 0,
--   lalu trigger #3 otomatis memicu perhitungan ulang begitu item masuk.
-- * REVOKE/GRANT tidak diubah di sini: trigger berjalan sebagai pemilik
--   fungsi (SECURITY DEFINER), jadi tetap bisa membaca invoice_items /
--   products lintas RLS tanpa perlu privilese tambahan di sisi client.
-- =========================================================================
