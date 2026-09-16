-- BillingFlow V21: production payment-gateway bridge + document-print hardening
-- Run after migration_v20_reports_ux_hardening.sql.

CREATE TABLE IF NOT EXISTS public.payment_gateway_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE RESTRICT,
  provider TEXT NOT NULL DEFAULT 'midtrans',
  order_id TEXT NOT NULL,
  transaction_id TEXT,
  amount NUMERIC(18,2) NOT NULL CHECK (amount > 0),
  currency TEXT NOT NULL DEFAULT 'IDR',
  payment_url TEXT,
  token TEXT,
  status TEXT NOT NULL DEFAULT 'PENDING',
  payment_type TEXT,
  fraud_status TEXT,
  transaction_time TIMESTAMPTZ,
  settlement_time TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  metadata JSONB,
  raw_notification JSONB,
  payment_id UUID REFERENCES public.payments(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CONSTRAINT payment_gateway_order_unique UNIQUE(provider, order_id)
);
CREATE UNIQUE INDEX IF NOT EXISTS payment_gateway_payment_unique ON public.payment_gateway_transactions(payment_id) WHERE payment_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS payment_gateway_org_invoice_idx ON public.payment_gateway_transactions(organization_id, invoice_id, created_at DESC);
CREATE INDEX IF NOT EXISTS payment_gateway_order_idx ON public.payment_gateway_transactions(order_id);

ALTER TABLE public.payment_gateway_transactions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS payment_gateway_select_org ON public.payment_gateway_transactions;
CREATE POLICY payment_gateway_select_org ON public.payment_gateway_transactions FOR SELECT TO authenticated
USING (organization_id = public.get_auth_org_id());
DROP POLICY IF EXISTS payment_gateway_insert_org ON public.payment_gateway_transactions;
CREATE POLICY payment_gateway_insert_org ON public.payment_gateway_transactions FOR INSERT TO authenticated
WITH CHECK (organization_id = public.get_auth_org_id());
-- Updates are intentionally backend/service-role only. Webhooks must not be writable by the browser.

CREATE OR REPLACE FUNCTION public.record_gateway_payment_atomic(p_gateway_transaction_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_tx RECORD; v_invoice RECORD; v_customer RECORD; v_bank RECORD; v_payment UUID; v_result JSONB; v_method VARCHAR := 'bank_transfer';
  v_payment_number TEXT; v_receipt_number TEXT; v_pay_seq INT; v_receipt_seq INT; v_user UUID := NULL;
BEGIN
  SELECT * INTO v_tx FROM public.payment_gateway_transactions WHERE id=p_gateway_transaction_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Transaksi gateway tidak ditemukan'; END IF;
  IF v_tx.status <> 'SETTLEMENT' THEN RAISE EXCEPTION 'Transaksi gateway belum settlement'; END IF;
  IF v_tx.payment_id IS NOT NULL THEN
    SELECT jsonb_build_object('payment_id',p.id,'payment_number',p.payment_number,'receipt_number',p.receipt_number,'invoice_id',p.invoice_id,'amount',p.amount,'already_exists',true)
      INTO v_result FROM public.payments p WHERE p.id=v_tx.payment_id;
    RETURN v_result;
  END IF;
  SELECT * INTO v_invoice FROM public.invoices WHERE id=v_tx.invoice_id AND organization_id=v_tx.organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Invoice transaksi gateway tidak ditemukan'; END IF;
  IF v_tx.amount > v_invoice.outstanding_amount THEN RAISE EXCEPTION 'Nominal settlement melebihi sisa invoice'; END IF;
  SELECT * INTO v_customer FROM public.customers WHERE id=v_invoice.customer_id AND organization_id=v_tx.organization_id;
  SELECT * INTO v_bank FROM public.bank_accounts WHERE id=v_invoice.bank_account_id AND organization_id=v_tx.organization_id;
  IF v_bank.id IS NULL THEN SELECT * INTO v_bank FROM public.bank_accounts WHERE organization_id=v_tx.organization_id AND is_default=true ORDER BY created_at LIMIT 1; END IF;
  IF v_bank.id IS NULL THEN RAISE EXCEPTION 'Belum ada rekening bank default untuk penerimaan payment gateway'; END IF;

  v_pay_seq := public.get_next_sequence('payment',0); v_receipt_seq := public.get_next_sequence('receipt',0);
  v_payment_number := 'PAY/'||to_char(CURRENT_DATE,'YYYY')||'/'||to_char(CURRENT_DATE,'MM')||'/'||lpad(v_pay_seq::text,5,'0');
  v_receipt_number := COALESCE((SELECT payment_receipt_format FROM public.organizations WHERE id=v_tx.organization_id),'KWT/{YEAR}/{MONTH}/{NUMBER}');
  v_receipt_number := replace(replace(replace(v_receipt_number,'{YEAR}',to_char(CURRENT_DATE,'YYYY')),'{MONTH}',to_char(CURRENT_DATE,'MM')),'{NUMBER}',lpad(v_receipt_seq::text,5,'0'));

  INSERT INTO public.payments(organization_id,payment_number,invoice_id,customer_id,payment_date,amount,payment_method,destination_bank,bank_account_id,account_number,reference_number,notes,received_by,receipt_number,created_by)
  VALUES(v_tx.organization_id,v_payment_number,v_invoice.id,v_invoice.customer_id,COALESCE(v_tx.settlement_time::date,CURRENT_DATE),v_tx.amount,v_method,v_bank.bank_name,v_bank.id,v_bank.account_number,'GATEWAY:'||v_tx.order_id,'Midtrans settlement '||v_tx.order_id,'Payment Gateway',v_receipt_number,v_user)
  RETURNING id INTO v_payment;

  UPDATE public.invoices SET paid_amount=paid_amount+v_tx.amount,outstanding_amount=GREATEST(0,grand_total-(paid_amount+v_tx.amount)),status=CASE WHEN GREATEST(0,grand_total-(paid_amount+v_tx.amount))<=0 THEN 'paid' ELSE 'partially_paid' END,paid_at=CASE WHEN GREATEST(0,grand_total-(paid_amount+v_tx.amount))<=0 THEN NOW() ELSE paid_at END,updated_at=NOW() WHERE id=v_invoice.id;
  PERFORM public.post_payment_journal(v_payment);
  UPDATE public.payment_gateway_transactions SET payment_id=v_payment,updated_at=NOW() WHERE id=v_tx.id;
  INSERT INTO public.documents(organization_id,title,document_type,document_number,customer_id,reference_id,amount,date,status)
  VALUES(v_tx.organization_id,'Kuitansi Payment Gateway - '||v_invoice.invoice_number,'payment_receipt',v_receipt_number,v_invoice.customer_id,v_payment,v_tx.amount,COALESCE(v_tx.settlement_time::date,CURRENT_DATE),'Lunas')
  ON CONFLICT DO NOTHING;
  RETURN jsonb_build_object('payment_id',v_payment,'payment_number',v_payment_number,'receipt_number',v_receipt_number,'invoice_id',v_invoice.id,'invoice_number',v_invoice.invoice_number,'amount',v_tx.amount,'status','PAID','already_exists',false);
END; $$;
REVOKE ALL ON FUNCTION public.record_gateway_payment_atomic(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_gateway_payment_atomic(UUID) TO service_role;

COMMENT ON TABLE public.payment_gateway_transactions IS 'Server-side gateway transaction ledger. Browser never receives provider secrets.';
COMMENT ON FUNCTION public.record_gateway_payment_atomic(UUID) IS 'Idempotently converts a verified gateway settlement into a payment, invoice update, accounting journal and receipt document.';
