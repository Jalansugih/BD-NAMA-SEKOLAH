-- BILLINGFLOW V14 — UNIFIED ACCOUNTING ENGINE
-- Pengeluaran + Faktur + Penerimaan + Pembayaran -> jurnal -> laporan.
-- Safe to re-run. No destructive DROP of business data.
--
-- IMPORTANT:
-- 1. Run V12 and V13 first.
-- 2. This migration makes invoices/payments produce accounting journals.
-- 3. Financial reports must read journal_entries/journal_lines, not UI totals.

-- -------------------------------------------------------------------------
-- 1. Complete the minimum chart of accounts
-- -------------------------------------------------------------------------
ALTER TABLE public.accounts
  ADD COLUMN IF NOT EXISTS bank_account_id UUID REFERENCES public.bank_accounts(id) ON DELETE SET NULL;

CREATE UNIQUE INDEX IF NOT EXISTS uq_accounts_bank_account
  ON public.accounts(bank_account_id)
  WHERE bank_account_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.ensure_default_accounts()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org UUID := public.get_auth_org_id();
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;

  INSERT INTO public.accounts (organization_id,code,name,account_type,normal_balance) VALUES
    (v_org,'1-1000','Kas','ASSET','DEBIT'),
    (v_org,'1-1100','Bank BCA','ASSET','DEBIT'),
    (v_org,'1-1200','Bank Mandiri','ASSET','DEBIT'),
    (v_org,'1-2000','Piutang Usaha','ASSET','DEBIT'),
    (v_org,'2-1000','Hutang Usaha','LIABILITY','CREDIT'),
    (v_org,'2-1100','PPN Keluaran','LIABILITY','CREDIT'),
    (v_org,'3-1000','Modal Disetor','EQUITY','CREDIT'),
    (v_org,'4-1000','Pendapatan Penjualan','REVENUE','CREDIT'),
    (v_org,'4-9000','Pendapatan Lain-lain','REVENUE','CREDIT'),
    (v_org,'5-1000','Harga Pokok Penjualan','COGS','DEBIT'),
    (v_org,'6-1000','Beban Gaji & Tunjangan','EXPENSE','DEBIT'),
    (v_org,'6-1100','Beban Sewa','EXPENSE','DEBIT'),
    (v_org,'6-1200','Beban Listrik & Air','EXPENSE','DEBIT'),
    (v_org,'6-1300','Beban Internet & Telepon','EXPENSE','DEBIT'),
    (v_org,'6-1400','Beban Marketing','EXPENSE','DEBIT'),
    (v_org,'6-1500','Beban Administrasi','EXPENSE','DEBIT'),
    (v_org,'6-1600','Beban Transportasi','EXPENSE','DEBIT'),
    (v_org,'6-1700','Beban Bank','EXPENSE','DEBIT'),
    (v_org,'6-1900','Beban Operasional Lainnya','EXPENSE','DEBIT')
  ON CONFLICT (organization_id,code) DO NOTHING;
END; $$;

REVOKE ALL ON FUNCTION public.ensure_default_accounts() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ensure_default_accounts() TO authenticated;

-- -------------------------------------------------------------------------
-- 2. Create a ledger account for each bank account when needed
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ensure_bank_ledger_account(p_bank_account_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_bank RECORD;
  v_existing UUID;
  v_code TEXT;
  v_suffix INT := 1300;
  v_name TEXT;
BEGIN
  IF p_bank_account_id IS NULL THEN RETURN NULL; END IF;

  SELECT id INTO v_existing
  FROM public.accounts
  WHERE bank_account_id = p_bank_account_id;
  IF v_existing IS NOT NULL THEN RETURN v_existing; END IF;

  SELECT * INTO v_bank FROM public.bank_accounts WHERE id=p_bank_account_id;
  IF v_bank.id IS NULL THEN RAISE EXCEPTION 'Rekening bank tidak ditemukan'; END IF;

  SELECT id INTO v_existing
  FROM public.accounts
  WHERE organization_id=v_bank.organization_id
    AND code IN ('1-1100','1-1200')
    AND bank_account_id IS NULL
    AND lower(name) LIKE '%'||lower(v_bank.bank_name)||'%'
  LIMIT 1;

  IF v_existing IS NOT NULL THEN
    UPDATE public.accounts SET bank_account_id=p_bank_account_id, updated_at=NOW()
    WHERE id=v_existing;
    RETURN v_existing;
  END IF;

  LOOP
    v_code := '1-'||v_suffix::TEXT;
    EXIT WHEN NOT EXISTS (
      SELECT 1 FROM public.accounts WHERE organization_id=v_bank.organization_id AND code=v_code
    );
    v_suffix := v_suffix + 100;
  END LOOP;

  v_name := 'Bank '||v_bank.bank_name||' - '||right(regexp_replace(COALESCE(v_bank.account_number,''),'[^0-9]','','g'),4);

  INSERT INTO public.accounts (
    organization_id, code, name, account_type, normal_balance, is_active, bank_account_id
  ) VALUES (
    v_bank.organization_id, v_code, v_name, 'ASSET', 'DEBIT', TRUE, p_bank_account_id
  ) RETURNING id INTO v_existing;

  RETURN v_existing;
END; $$;

REVOKE ALL ON FUNCTION public.ensure_bank_ledger_account(UUID) FROM PUBLIC;

-- -------------------------------------------------------------------------
-- 3. Generic internal journal sequence helper
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.next_accounting_journal_number(
  p_prefix TEXT, p_date DATE, p_org_id UUID
)
RETURNS TEXT LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_next INT;
BEGIN
  INSERT INTO public.organization_sequences(organization_id,sequence_name,current_value)
  VALUES(p_org_id,'accounting_journal',1)
  ON CONFLICT(organization_id,sequence_name)
  DO UPDATE SET current_value=public.organization_sequences.current_value+1,updated_at=NOW()
  RETURNING current_value INTO v_next;

  RETURN p_prefix||'-'||to_char(p_date,'YYYY')||'-'||lpad(v_next::TEXT,6,'0');
END; $$;
REVOKE ALL ON FUNCTION public.next_accounting_journal_number(TEXT,DATE,UUID) FROM PUBLIC;

-- -------------------------------------------------------------------------
-- 4. Invoice -> Accounts Receivable / Revenue / Output VAT
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.post_invoice_journal(p_invoice_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_invoice RECORD;
  v_journal UUID := gen_random_uuid();
  v_journal_no TEXT;
  v_ar UUID;
  v_revenue UUID;
  v_other_revenue UUID;
  v_vat UUID;
  v_net_sales NUMERIC;
BEGIN
  SELECT * INTO v_invoice FROM public.invoices WHERE id=p_invoice_id;
  IF v_invoice.id IS NULL THEN RAISE EXCEPTION 'Invoice tidak ditemukan'; END IF;
  IF v_invoice.status IN ('draft','cancelled') THEN RETURN NULL; END IF;

  IF EXISTS (
    SELECT 1 FROM public.journal_entries
    WHERE organization_id=v_invoice.organization_id
      AND reference_type='invoice' AND reference_id=v_invoice.id AND status='POSTED'
  ) THEN
    RETURN (SELECT id FROM public.journal_entries WHERE organization_id=v_invoice.organization_id AND reference_type='invoice' AND reference_id=v_invoice.id AND status='POSTED' ORDER BY created_at DESC LIMIT 1);
  END IF;

  SELECT id INTO v_ar FROM public.accounts WHERE organization_id=v_invoice.organization_id AND code='1-2000';
  SELECT id INTO v_revenue FROM public.accounts WHERE organization_id=v_invoice.organization_id AND code='4-1000';
  SELECT id INTO v_other_revenue FROM public.accounts WHERE organization_id=v_invoice.organization_id AND code='4-9000';
  SELECT id INTO v_vat FROM public.accounts WHERE organization_id=v_invoice.organization_id AND code='2-1100';

  v_net_sales := GREATEST(0, COALESCE(v_invoice.subtotal,0)-COALESCE(v_invoice.discount_amount,0));

  v_journal_no := public.next_accounting_journal_number('JRN-INV',v_invoice.issue_date,v_invoice.organization_id);
  INSERT INTO public.journal_entries(
    id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by
  ) VALUES (
    v_journal,v_invoice.organization_id,v_journal_no,v_invoice.issue_date,'invoice',v_invoice.id,
    'Pengakuan invoice '||v_invoice.invoice_number,'POSTED',v_invoice.created_by
  );

  INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit)
  VALUES(v_journal,v_ar,'Piutang '||v_invoice.invoice_number,v_invoice.grand_total,0);

  IF v_net_sales > 0 THEN
    INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit)
    VALUES(v_journal,v_revenue,'Pendapatan penjualan '||v_invoice.invoice_number,0,v_net_sales);
  END IF;

  IF COALESCE(v_invoice.additional_charges,0) > 0 THEN
    INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit)
    VALUES(v_journal,v_other_revenue,'Biaya tambahan '||v_invoice.invoice_number,0,v_invoice.additional_charges);
  END IF;

  IF COALESCE(v_invoice.tax_amount,0) > 0 THEN
    INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit)
    VALUES(v_journal,v_vat,'PPN keluaran '||v_invoice.invoice_number,0,v_invoice.tax_amount);
  END IF;

  RETURN v_journal;
END; $$;
REVOKE ALL ON FUNCTION public.post_invoice_journal(UUID) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.cleanup_orphan_invoice_journal(p_invoice_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  IF EXISTS (SELECT 1 FROM public.invoices WHERE id=p_invoice_id) THEN
    RETURN;
  END IF;
  DELETE FROM public.journal_entries
  WHERE reference_type IN ('invoice','invoice_reversal') AND reference_id=p_invoice_id;
END; $$;
REVOKE ALL ON FUNCTION public.cleanup_orphan_invoice_journal(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cleanup_orphan_invoice_journal(UUID) TO authenticated;


CREATE OR REPLACE FUNCTION public.trg_invoice_accounting()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_existing UUID;
  v_reversal UUID := gen_random_uuid();
  v_journal_no TEXT;
  v_line RECORD;
  v_changed BOOLEAN := FALSE;
BEGIN
  SELECT id INTO v_existing
  FROM public.journal_entries
  WHERE organization_id=NEW.organization_id
    AND reference_type='invoice' AND reference_id=NEW.id AND status='POSTED'
  ORDER BY created_at DESC LIMIT 1;

  IF TG_OP='UPDATE' THEN
    v_changed :=
      OLD.issue_date IS DISTINCT FROM NEW.issue_date OR
      OLD.subtotal IS DISTINCT FROM NEW.subtotal OR
      OLD.discount_amount IS DISTINCT FROM NEW.discount_amount OR
      OLD.tax_amount IS DISTINCT FROM NEW.tax_amount OR
      OLD.additional_charges IS DISTINCT FROM NEW.additional_charges OR
      OLD.grand_total IS DISTINCT FROM NEW.grand_total OR
      OLD.status IS DISTINCT FROM NEW.status;
  END IF;

  IF v_existing IS NOT NULL AND (
      NEW.status IN ('draft','cancelled') OR v_changed
  ) THEN
    v_journal_no := public.next_accounting_journal_number('REV-INV',COALESCE(NEW.issue_date,CURRENT_DATE),NEW.organization_id);
    INSERT INTO public.journal_entries(
      id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by
    ) VALUES (
      v_reversal,NEW.organization_id,v_journal_no,COALESCE(NEW.issue_date,CURRENT_DATE),
      'invoice_reversal',NEW.id,'Pembalikan jurnal invoice '||NEW.invoice_number,'POSTED',auth.uid()
    );

    FOR v_line IN
      SELECT jl.* FROM public.journal_lines jl
      WHERE jl.journal_entry_id=v_existing
    LOOP
      INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit)
      VALUES(v_reversal,v_line.account_id,'Reversal: '||v_line.description,v_line.credit,v_line.debit);
    END LOOP;

    UPDATE public.journal_entries SET status='REVERSED' WHERE id=v_existing;
    v_existing := NULL;
  END IF;

  IF NEW.status NOT IN ('draft','cancelled') AND v_existing IS NULL THEN
    PERFORM public.ensure_default_accounts();
    PERFORM public.post_invoice_journal(NEW.id);
  END IF;

  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_invoices_accounting ON public.invoices;
CREATE TRIGGER trg_invoices_accounting
AFTER INSERT OR UPDATE OF issue_date,subtotal,discount_amount,tax_amount,additional_charges,grand_total,status
ON public.invoices
FOR EACH ROW EXECUTE FUNCTION public.trg_invoice_accounting();

-- -------------------------------------------------------------------------
-- 5. Payments -> Cash/Bank / Accounts Receivable
-- -------------------------------------------------------------------------
ALTER TABLE public.payments
  ADD COLUMN IF NOT EXISTS bank_account_id UUID REFERENCES public.bank_accounts(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_payments_bank_account ON public.payments(bank_account_id);

CREATE OR REPLACE FUNCTION public.post_payment_journal(p_payment_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_payment RECORD;
  v_invoice RECORD;
  v_asset UUID;
  v_ar UUID;
  v_journal UUID := gen_random_uuid();
  v_journal_no TEXT;
BEGIN
  SELECT * INTO v_payment FROM public.payments WHERE id=p_payment_id;
  IF v_payment.id IS NULL THEN RAISE EXCEPTION 'Pembayaran tidak ditemukan'; END IF;

  IF EXISTS (
    SELECT 1 FROM public.journal_entries
    WHERE organization_id=v_payment.organization_id
      AND reference_type='payment' AND reference_id=v_payment.id AND status='POSTED'
  ) THEN
    RETURN (SELECT id FROM public.journal_entries WHERE organization_id=v_payment.organization_id AND reference_type='payment' AND reference_id=v_payment.id AND status='POSTED' LIMIT 1);
  END IF;

  SELECT * INTO v_invoice FROM public.invoices WHERE id=v_payment.invoice_id AND organization_id=v_payment.organization_id;
  IF v_invoice.id IS NULL THEN RAISE EXCEPTION 'Invoice pembayaran tidak ditemukan'; END IF;

  IF v_payment.payment_method='cash' THEN
    SELECT id INTO v_asset FROM public.accounts WHERE organization_id=v_payment.organization_id AND code='1-1000';
  ELSE
    IF v_payment.bank_account_id IS NULL AND v_payment.account_number IS NOT NULL THEN
      SELECT id INTO v_payment.bank_account_id
      FROM public.bank_accounts
      WHERE organization_id=v_payment.organization_id AND account_number=v_payment.account_number
      LIMIT 1;
    END IF;
    IF v_payment.bank_account_id IS NULL THEN
      RAISE EXCEPTION 'Rekening penerimaan belum dipetakan. Pilih rekening bank pada pembayaran.';
    END IF;
    IF NOT EXISTS (
      SELECT 1 FROM public.bank_accounts b
      WHERE b.id=v_payment.bank_account_id AND b.organization_id=v_payment.organization_id
    ) THEN
      RAISE EXCEPTION 'Rekening bank tidak valid untuk organisasi pembayaran';
    END IF;
    v_asset := public.ensure_bank_ledger_account(v_payment.bank_account_id);
  END IF;

  SELECT id INTO v_ar FROM public.accounts WHERE organization_id=v_payment.organization_id AND code='1-2000';

  v_journal_no := public.next_accounting_journal_number('JRN-PAY',v_payment.payment_date,v_payment.organization_id);
  INSERT INTO public.journal_entries(
    id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by
  ) VALUES (
    v_journal,v_payment.organization_id,v_journal_no,v_payment.payment_date,'payment',v_payment.id,
    'Penerimaan '||v_payment.receipt_number||' untuk invoice '||v_invoice.invoice_number,'POSTED',v_payment.created_by
  );

  INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit)
  VALUES(v_journal,v_asset,'Kas/Bank penerimaan '||v_payment.receipt_number,v_payment.amount,0),
        (v_journal,v_ar,'Pelunasan piutang '||v_invoice.invoice_number,0,v_payment.amount);

  RETURN v_journal;
END; $$;
REVOKE ALL ON FUNCTION public.post_payment_journal(UUID) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.trg_payment_accounting()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
BEGIN
  PERFORM public.ensure_default_accounts();
  PERFORM public.post_payment_journal(NEW.id);
  RETURN NEW;
END; $$;

DROP TRIGGER IF EXISTS trg_payments_accounting ON public.payments;
CREATE TRIGGER trg_payments_accounting
AFTER INSERT ON public.payments
FOR EACH ROW EXECUTE FUNCTION public.trg_payment_accounting();

-- Update the atomic payment function so bank_account_id is preserved.
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
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
    v_org_id UUID := public.get_auth_org_id();
    v_user_id UUID := auth.uid();
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
BEGIN
    IF v_org_id IS NULL THEN RAISE EXCEPTION 'Tidak ditemukan organisasi untuk user yang sedang login'; END IF;

    SELECT name, role INTO v_user_name, v_user_role FROM public.profiles WHERE id=v_user_id;
    v_user_name := COALESCE(v_user_name,'Pengguna');
    v_user_role := COALESCE(v_user_role,'staff');

    SELECT * INTO v_invoice FROM public.invoices
    WHERE id=p_invoice_id AND organization_id=v_org_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invoice tidak ditemukan'; END IF;
    IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'Nominal pembayaran harus lebih dari 0'; END IF;
    IF p_amount > v_invoice.outstanding_amount THEN RAISE EXCEPTION 'Nominal pembayaran melebihi sisa tagihan (%)',v_invoice.outstanding_amount; END IF;

    SELECT * INTO v_org FROM public.organizations WHERE id=v_org_id;
    v_pay_seq := public.get_next_sequence('payment',0);
    v_receipt_seq := public.get_next_sequence('receipt',0);
    v_payment_number := 'PAY/'||to_char(p_payment_date,'YYYY')||'/'||to_char(p_payment_date,'MM')||'/'||lpad(v_pay_seq::text,5,'0');
    v_receipt_number := COALESCE(v_org.payment_receipt_format,'KWT/{YEAR}/{MONTH}/{NUMBER}');
    v_receipt_number := replace(v_receipt_number,'{YEAR}',to_char(p_payment_date,'YYYY'));
    v_receipt_number := replace(v_receipt_number,'{MONTH}',to_char(p_payment_date,'MM'));
    v_receipt_number := replace(v_receipt_number,'{NUMBER}',lpad(v_receipt_seq::text,5,'0'));

    IF p_payment_method <> 'cash' AND p_bank_account_id IS NULL THEN
      RAISE EXCEPTION 'Rekening bank wajib dipilih untuk pembayaran non-tunai';
    END IF;
    IF p_bank_account_id IS NOT NULL AND NOT EXISTS (
      SELECT 1 FROM public.bank_accounts b
      WHERE b.id=p_bank_account_id AND b.organization_id=v_org_id
    ) THEN
      RAISE EXCEPTION 'Rekening bank tidak valid untuk organisasi Anda';
    END IF;

    v_destination_bank := COALESCE(
      p_destination_bank,
      (SELECT bank_name FROM public.bank_accounts WHERE id=p_bank_account_id),
      'Kas'
    );

    INSERT INTO public.payments(
      organization_id,payment_number,invoice_id,customer_id,payment_date,amount,payment_method,
      destination_bank,bank_account_id,account_number,reference_number,notes,received_by,receipt_number,created_by
    ) VALUES(
      v_org_id,v_payment_number,v_invoice.id,v_invoice.customer_id,p_payment_date,p_amount,p_payment_method,
      v_destination_bank,p_bank_account_id,p_account_number,p_reference_number,p_notes,
      v_user_name||' ('||upper(v_user_role)||')',v_receipt_number,v_user_id
    ) RETURNING id INTO v_payment_id;

    v_new_paid_amount := v_invoice.paid_amount+p_amount;
    v_new_outstanding := GREATEST(0,v_invoice.grand_total-v_new_paid_amount);
    v_new_status := CASE WHEN v_new_outstanding<=0 THEN 'paid' ELSE 'partially_paid' END;
    v_new_paid_at := CASE WHEN v_new_outstanding<=0 THEN NOW() ELSE v_invoice.paid_at END;

    UPDATE public.invoices SET paid_amount=v_new_paid_amount,outstanding_amount=v_new_outstanding,status=v_new_status,paid_at=v_new_paid_at,updated_at=NOW()
    WHERE id=v_invoice.id;

    INSERT INTO public.documents(
      organization_id,title,document_type,document_number,customer_id,reference_id,amount,date,status
    ) VALUES(
      v_org_id,'Kuitansi Penerimaan Pembayaran - '||v_invoice.customer_id::text,'payment_receipt',
      v_receipt_number,v_invoice.customer_id,v_payment_id,p_amount,p_payment_date,
      CASE WHEN v_new_status='paid' THEN 'Lunas' ELSE 'Dibayar Sebagian' END
    ) RETURNING id INTO v_document_id;

    INSERT INTO public.audit_logs(
      organization_id,user_id,user_name,user_role,action,module,record_id,record_title,details
    ) VALUES(
      v_org_id,v_user_id,v_user_name,v_user_role,'pay','payments',v_payment_id::text,v_payment_number,
      'Mencatat pembayaran Rp'||to_char(p_amount,'FM999,999,999,999')||' untuk '||v_invoice.invoice_number
    );

    RETURN jsonb_build_object(
      'payment_id',v_payment_id,'payment_number',v_payment_number,'receipt_number',v_receipt_number,
      'document_id',v_document_id,'invoice_id',v_invoice.id,'invoice_number',v_invoice.invoice_number,
      'customer_id',v_invoice.customer_id,'paid_amount',v_new_paid_amount,
      'outstanding_amount',v_new_outstanding,'status',v_new_status,'paid_at',v_new_paid_at,
      'destination_bank',v_destination_bank,'received_by',v_user_name||' ('||upper(v_user_role)||')'
    );
END; $$;

REVOKE ALL ON FUNCTION public.record_payment_atomic(UUID,NUMERIC,DATE,VARCHAR,VARCHAR,UUID,VARCHAR,VARCHAR,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_payment_atomic(UUID,NUMERIC,DATE,VARCHAR,VARCHAR,UUID,VARCHAR,VARCHAR,TEXT) TO authenticated;

-- Provision the minimum chart for every existing tenant. This is deliberately
-- independent of auth.uid() because the migration itself runs outside a user session.
DO $$
DECLARE o RECORD;
BEGIN
  FOR o IN SELECT id FROM public.organizations LOOP
    INSERT INTO public.accounts (organization_id,code,name,account_type,normal_balance) VALUES
      (o.id,'1-1000','Kas','ASSET','DEBIT'),
      (o.id,'1-1100','Bank BCA','ASSET','DEBIT'),
      (o.id,'1-1200','Bank Mandiri','ASSET','DEBIT'),
      (o.id,'1-2000','Piutang Usaha','ASSET','DEBIT'),
      (o.id,'2-1000','Hutang Usaha','LIABILITY','CREDIT'),
      (o.id,'2-1100','PPN Keluaran','LIABILITY','CREDIT'),
      (o.id,'3-1000','Modal Disetor','EQUITY','CREDIT'),
      (o.id,'4-1000','Pendapatan Penjualan','REVENUE','CREDIT'),
      (o.id,'4-9000','Pendapatan Lain-lain','REVENUE','CREDIT'),
      (o.id,'5-1000','Harga Pokok Penjualan','COGS','DEBIT'),
      (o.id,'6-1000','Beban Gaji & Tunjangan','EXPENSE','DEBIT'),
      (o.id,'6-1100','Beban Sewa','EXPENSE','DEBIT'),
      (o.id,'6-1200','Beban Listrik & Air','EXPENSE','DEBIT'),
      (o.id,'6-1300','Beban Internet & Telepon','EXPENSE','DEBIT'),
      (o.id,'6-1400','Beban Marketing','EXPENSE','DEBIT'),
      (o.id,'6-1500','Beban Administrasi','EXPENSE','DEBIT'),
      (o.id,'6-1600','Beban Transportasi','EXPENSE','DEBIT'),
      (o.id,'6-1700','Beban Bank','EXPENSE','DEBIT'),
      (o.id,'6-1900','Beban Operasional Lainnya','EXPENSE','DEBIT')
    ON CONFLICT (organization_id,code) DO NOTHING;
  END LOOP;
END $$;

-- -------------------------------------------------------------------------
-- 6. Backfill existing invoices/payments into the ledger.
-- -------------------------------------------------------------------------
DO $$
DECLARE
  r RECORD;
  v_bank_id UUID;
BEGIN
  -- Add a ledger account for each known bank account.
  FOR r IN SELECT id FROM public.bank_accounts LOOP
    BEGIN
      PERFORM public.ensure_bank_ledger_account(r.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Bank account % belum dapat dipetakan: %',r.id,SQLERRM;
    END;
  END LOOP;

  -- Existing invoices.
  FOR r IN
    SELECT id FROM public.invoices WHERE status NOT IN ('draft','cancelled')
  LOOP
    BEGIN
      PERFORM public.post_invoice_journal(r.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Invoice % belum dapat dijurnal: %',r.id,SQLERRM;
    END;
  END LOOP;

  -- Existing payments: infer bank account from account_number when possible.
  FOR r IN
    SELECT p.id,p.organization_id,p.payment_method,p.account_number
    FROM public.payments p
    WHERE NOT EXISTS(
      SELECT 1 FROM public.journal_entries j
      WHERE j.reference_type='payment' AND j.reference_id=p.id AND j.status='POSTED'
    )
  LOOP
    BEGIN
      IF r.payment_method <> 'cash' AND r.account_number IS NOT NULL THEN
        SELECT id INTO v_bank_id FROM public.bank_accounts
        WHERE organization_id=r.organization_id AND account_number=r.account_number
        LIMIT 1;
        IF v_bank_id IS NOT NULL THEN
          UPDATE public.payments SET bank_account_id=v_bank_id WHERE id=r.id;
        END IF;
      END IF;
      PERFORM public.post_payment_journal(r.id);
    EXCEPTION WHEN OTHERS THEN
      RAISE NOTICE 'Payment % belum dapat dijurnal dan perlu pemetaan rekening: %',r.id,SQLERRM;
    END;
  END LOOP;
END $$;

-- -------------------------------------------------------------------------
-- 7. Single source of truth: financial statements read only the posted ledger
-- -------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_financial_statements(
  p_start_date DATE,
  p_end_date DATE
)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_org UUID := public.get_auth_org_id();
  v_start DATE := COALESCE(p_start_date,date_trunc('month',CURRENT_DATE)::date);
  v_end DATE := COALESCE(p_end_date,CURRENT_DATE);
  v_total_revenue NUMERIC := 0;
  v_total_cogs NUMERIC := 0;
  v_total_expenses NUMERIC := 0;
  v_net_profit NUMERIC := 0;
  v_cumulative_profit NUMERIC := 0;
  v_total_assets NUMERIC := 0;
  v_total_liabilities NUMERIC := 0;
  v_total_equity NUMERIC := 0;
  v_opening_cash NUMERIC := 0;
  v_inflows NUMERIC := 0;
  v_outflows NUMERIC := 0;
  v_closing_cash NUMERIC := 0;
  v_receivables NUMERIC := 0;
  v_payables NUMERIC := 0;
  v_debit_total NUMERIC := 0;
  v_credit_total NUMERIC := 0;
  v_unbalanced INT := 0;
  v_posted INT := 0;
  v_unjournalized_invoices INT := 0;
  v_unjournalized_payments INT := 0;
  v_unmapped_bank_payments INT := 0;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  IF v_end < v_start THEN RAISE EXCEPTION 'Periode laporan tidak valid'; END IF;

  PERFORM public.ensure_default_accounts();

  SELECT count(*) INTO v_posted
  FROM public.journal_entries
  WHERE organization_id=v_org AND status='POSTED' AND journal_date<=v_end;

  SELECT COALESCE(sum(x.debit),0),COALESCE(sum(x.credit),0)
  INTO v_debit_total,v_credit_total
  FROM (
    SELECT je.id,sum(jl.debit) debit,sum(jl.credit) credit
    FROM public.journal_entries je
    JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
    WHERE je.organization_id=v_org AND je.status='POSTED' AND je.journal_date<=v_end
    GROUP BY je.id
  ) x;

  SELECT count(*) INTO v_unbalanced
  FROM (
    SELECT je.id
    FROM public.journal_entries je
    JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
    WHERE je.organization_id=v_org AND je.status='POSTED' AND je.journal_date<=v_end
    GROUP BY je.id
    HAVING abs(sum(jl.debit)-sum(jl.credit)) > 0.01
  ) x;

  SELECT
    COALESCE(sum(CASE WHEN a.account_type='REVENUE' THEN jl.credit-jl.debit ELSE 0 END),0),
    COALESCE(sum(CASE WHEN a.account_type='COGS' THEN jl.debit-jl.credit ELSE 0 END),0),
    COALESCE(sum(CASE WHEN a.account_type='EXPENSE' THEN jl.debit-jl.credit ELSE 0 END),0)
  INTO v_total_revenue,v_total_cogs,v_total_expenses
  FROM public.journal_entries je
  JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
  JOIN public.accounts a ON a.id=jl.account_id
  WHERE je.organization_id=v_org AND je.status='POSTED'
    AND je.journal_date BETWEEN v_start AND v_end;

  v_net_profit := v_total_revenue-v_total_cogs-v_total_expenses;

  SELECT COALESCE(sum(CASE
    WHEN a.account_type='REVENUE' THEN jl.credit-jl.debit
    WHEN a.account_type='COGS' THEN jl.debit-jl.credit
    WHEN a.account_type='EXPENSE' THEN jl.debit-jl.credit
    ELSE 0 END),0)
  INTO v_cumulative_profit
  FROM public.journal_entries je
  JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
  JOIN public.accounts a ON a.id=jl.account_id
  WHERE je.organization_id=v_org AND je.status='POSTED' AND je.journal_date<=v_end;

  SELECT COALESCE(sum(CASE WHEN a.normal_balance='DEBIT' THEN jl.debit-jl.credit ELSE jl.credit-jl.debit END),0)
  INTO v_total_assets
  FROM public.journal_entries je JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
  JOIN public.accounts a ON a.id=jl.account_id
  WHERE je.organization_id=v_org AND je.status='POSTED' AND je.journal_date<=v_end AND a.account_type='ASSET';

  SELECT COALESCE(sum(CASE WHEN a.normal_balance='DEBIT' THEN jl.debit-jl.credit ELSE jl.credit-jl.debit END),0)
  INTO v_total_liabilities
  FROM public.journal_entries je JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
  JOIN public.accounts a ON a.id=jl.account_id
  WHERE je.organization_id=v_org AND je.status='POSTED' AND je.journal_date<=v_end AND a.account_type='LIABILITY';

  SELECT COALESCE(sum(CASE WHEN a.normal_balance='DEBIT' THEN jl.debit-jl.credit ELSE jl.credit-jl.debit END),0)
  INTO v_total_equity
  FROM public.journal_entries je JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
  JOIN public.accounts a ON a.id=jl.account_id
  WHERE je.organization_id=v_org AND je.status='POSTED' AND je.journal_date<=v_end AND a.account_type='EQUITY';

  SELECT COALESCE(sum(CASE WHEN (a.code IN ('1-1000','1-1100','1-1200') OR a.bank_account_id IS NOT NULL) THEN jl.debit-jl.credit ELSE 0 END),0)
  INTO v_opening_cash
  FROM public.journal_entries je JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
  JOIN public.accounts a ON a.id=jl.account_id
  WHERE je.organization_id=v_org AND je.status='POSTED' AND je.journal_date < v_start AND a.account_type='ASSET';

  SELECT COALESCE(sum(CASE WHEN (a.code IN ('1-1000','1-1100','1-1200') OR a.bank_account_id IS NOT NULL) THEN jl.debit ELSE 0 END),0),
         COALESCE(sum(CASE WHEN (a.code IN ('1-1000','1-1100','1-1200') OR a.bank_account_id IS NOT NULL) THEN jl.credit ELSE 0 END),0)
  INTO v_inflows,v_outflows
  FROM public.journal_entries je JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
  JOIN public.accounts a ON a.id=jl.account_id
  WHERE je.organization_id=v_org AND je.status='POSTED' AND je.journal_date BETWEEN v_start AND v_end AND a.account_type='ASSET' AND (a.code IN ('1-1000','1-1100','1-1200') OR a.bank_account_id IS NOT NULL);

  v_closing_cash := v_opening_cash+v_inflows-v_outflows;

  SELECT COALESCE(sum(jl.debit-jl.credit),0) INTO v_receivables
  FROM public.journal_entries je JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
  JOIN public.accounts a ON a.id=jl.account_id
  WHERE je.organization_id=v_org AND je.status='POSTED' AND je.journal_date<=v_end AND a.code='1-2000';

  SELECT COALESCE(sum(jl.credit-jl.debit),0) INTO v_payables
  FROM public.journal_entries je JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
  JOIN public.accounts a ON a.id=jl.account_id
  WHERE je.organization_id=v_org AND je.status='POSTED' AND je.journal_date<=v_end AND a.code='2-1000';

  SELECT count(*) INTO v_unjournalized_invoices
  FROM public.invoices i
  WHERE i.organization_id=v_org AND i.status NOT IN ('draft','cancelled')
    AND NOT EXISTS(
      SELECT 1 FROM public.journal_entries j WHERE j.organization_id=v_org AND j.reference_type='invoice' AND j.reference_id=i.id AND j.status='POSTED'
    );

  SELECT count(*) INTO v_unjournalized_payments
  FROM public.payments p
  WHERE p.organization_id=v_org
    AND NOT EXISTS(
      SELECT 1 FROM public.journal_entries j WHERE j.organization_id=v_org AND j.reference_type='payment' AND j.reference_id=p.id AND j.status='POSTED'
    );

  SELECT count(*) INTO v_unmapped_bank_payments
  FROM public.payments p
  WHERE p.organization_id=v_org AND p.payment_method <> 'cash' AND p.bank_account_id IS NULL;

  RETURN jsonb_build_object(
    'period',jsonb_build_object('startDate',v_start,'endDate',v_end),
    'profitLoss',jsonb_build_object(
      'revenue',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'accountType',x.account_type,'amount',x.amount) ORDER BY x.code)
        FROM (SELECT a.code,a.name,a.account_type,round(sum(jl.credit-jl.debit),2) AS amount
              FROM public.accounts a JOIN public.journal_lines jl ON jl.account_id=a.id JOIN public.journal_entries je ON je.id=jl.journal_entry_id
              WHERE a.organization_id=v_org AND a.account_type='REVENUE' AND je.organization_id=v_org AND je.status='POSTED' AND je.journal_date BETWEEN v_start AND v_end
              GROUP BY a.code,a.name,a.account_type) x),'[]'::jsonb),
      'cogs',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'accountType',x.account_type,'amount',x.amount) ORDER BY x.code)
        FROM (SELECT a.code,a.name,a.account_type,round(sum(jl.debit-jl.credit),2) AS amount
              FROM public.accounts a JOIN public.journal_lines jl ON jl.account_id=a.id JOIN public.journal_entries je ON je.id=jl.journal_entry_id
              WHERE a.organization_id=v_org AND a.account_type='COGS' AND je.organization_id=v_org AND je.status='POSTED' AND je.journal_date BETWEEN v_start AND v_end
              GROUP BY a.code,a.name,a.account_type) x),'[]'::jsonb),
      'expenses',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'accountType',x.account_type,'amount',x.amount) ORDER BY x.code)
        FROM (SELECT a.code,a.name,a.account_type,round(sum(jl.debit-jl.credit),2) AS amount
              FROM public.accounts a JOIN public.journal_lines jl ON jl.account_id=a.id JOIN public.journal_entries je ON je.id=jl.journal_entry_id
              WHERE a.organization_id=v_org AND a.account_type='EXPENSE' AND je.organization_id=v_org AND je.status='POSTED' AND je.journal_date BETWEEN v_start AND v_end
              GROUP BY a.code,a.name,a.account_type) x),'[]'::jsonb),
      'totalRevenue',round(v_total_revenue,2),'totalCogs',round(v_total_cogs,2),'totalExpenses',round(v_total_expenses,2),'netProfit',round(v_net_profit,2)
    ),
    'balanceSheet',jsonb_build_object(
      'assets',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'accountType',x.account_type,'amount',x.amount) ORDER BY x.code)
        FROM (SELECT a.code,a.name,a.account_type,round(sum(CASE WHEN a.normal_balance='DEBIT' THEN jl.debit-jl.credit ELSE jl.credit-jl.debit END),2) AS amount
              FROM public.accounts a JOIN public.journal_lines jl ON jl.account_id=a.id JOIN public.journal_entries je ON je.id=jl.journal_entry_id
              WHERE a.organization_id=v_org AND a.account_type='ASSET' AND je.organization_id=v_org AND je.status='POSTED' AND je.journal_date<=v_end
              GROUP BY a.code,a.name,a.account_type,a.normal_balance) x),'[]'::jsonb),
      'liabilities',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'accountType',x.account_type,'amount',x.amount) ORDER BY x.code)
        FROM (SELECT a.code,a.name,a.account_type,round(sum(CASE WHEN a.normal_balance='DEBIT' THEN jl.debit-jl.credit ELSE jl.credit-jl.debit END),2) AS amount
              FROM public.accounts a JOIN public.journal_lines jl ON jl.account_id=a.id JOIN public.journal_entries je ON je.id=jl.journal_entry_id
              WHERE a.organization_id=v_org AND a.account_type='LIABILITY' AND je.organization_id=v_org AND je.status='POSTED' AND je.journal_date<=v_end
              GROUP BY a.code,a.name,a.account_type,a.normal_balance) x),'[]'::jsonb),
      'equity',COALESCE((SELECT jsonb_agg(jsonb_build_object('code',x.code,'name',x.name,'accountType',x.account_type,'amount',x.amount) ORDER BY x.code)
        FROM (SELECT a.code,a.name,a.account_type,round(sum(CASE WHEN a.normal_balance='DEBIT' THEN jl.debit-jl.credit ELSE jl.credit-jl.debit END),2) AS amount
              FROM public.accounts a JOIN public.journal_lines jl ON jl.account_id=a.id JOIN public.journal_entries je ON je.id=jl.journal_entry_id
              WHERE a.organization_id=v_org AND a.account_type='EQUITY' AND je.organization_id=v_org AND je.status='POSTED' AND je.journal_date<=v_end
              GROUP BY a.code,a.name,a.account_type,a.normal_balance) x),'[]'::jsonb)
        || jsonb_build_array(jsonb_build_object('code','3-9999','name','Laba Ditahan / Laba Berjalan','accountType','EQUITY','amount',round(v_cumulative_profit,2))),
      'totalAssets',round(v_total_assets,2),'totalLiabilities',round(v_total_liabilities,2),
      'totalEquity',round(v_total_equity+v_cumulative_profit,2),
      'balanceCheck',round(v_total_assets-v_total_liabilities-v_total_equity-v_cumulative_profit,2)
    ),
    'cashFlow',jsonb_build_object(
      'openingCash',round(v_opening_cash,2),'inflows',round(v_inflows,2),'outflows',round(v_outflows,2),
      'netCashFlow',round(v_inflows-v_outflows,2),'closingCash',round(v_closing_cash,2)
    ),
    'receivables',jsonb_build_object('balance',round(v_receivables,2)),
    'payables',jsonb_build_object('balance',round(v_payables,2)),
    'integrity',jsonb_build_object(
      'postedJournals',v_posted,'unbalancedJournals',v_unbalanced,
      'debitTotal',round(v_debit_total,2),'creditTotal',round(v_credit_total,2),
      'unjournalizedInvoices',v_unjournalized_invoices,
      'unjournalizedPayments',v_unjournalized_payments,
      'unmappedBankPayments',v_unmapped_bank_payments
    )
  );
END; $$;

REVOKE ALL ON FUNCTION public.get_financial_statements(DATE,DATE) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_financial_statements(DATE,DATE) TO authenticated;

COMMENT ON FUNCTION public.get_financial_statements(DATE,DATE)
IS 'Single source of truth for financial statements. Reads only POSTED journal_entries/journal_lines; source document totals are used only for integrity checks.';

-- -------------------------------------------------------------------------
-- 8. Useful ledger view for future reports/audit screens
-- -------------------------------------------------------------------------
CREATE OR REPLACE VIEW public.accounting_ledger AS
SELECT
  je.organization_id,
  je.id AS journal_entry_id,
  je.journal_number,
  je.journal_date,
  je.reference_type,
  je.reference_id,
  je.description AS journal_description,
  je.status AS journal_status,
  a.id AS account_id,
  a.code AS account_code,
  a.name AS account_name,
  a.account_type,
  jl.description AS line_description,
  jl.debit,
  jl.credit
FROM public.journal_entries je
JOIN public.journal_lines jl ON jl.journal_entry_id=je.id
JOIN public.accounts a ON a.id=jl.account_id
WHERE je.status='POSTED';

COMMENT ON VIEW public.accounting_ledger IS 'Canonical posted accounting ledger. Reports should derive from this view/journal tables, not UI caches.';
