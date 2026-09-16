-- BILLINGFLOW V19 — PURCHASE HARDENING
-- Run after V18. Safe to re-run. Adds payment idempotency and stronger purchase/payment integrity.

ALTER TABLE public.purchase_payments
  ADD COLUMN IF NOT EXISTS idempotency_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS ux_purchase_payments_org_idempotency
  ON public.purchase_payments(organization_id, idempotency_key)
  WHERE idempotency_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_purchases_org_vendor_date
  ON public.purchases(organization_id, vendor_id, purchase_date DESC);

CREATE INDEX IF NOT EXISTS idx_purchases_org_status_due
  ON public.purchases(organization_id, payment_status, due_date);

CREATE OR REPLACE FUNCTION public.record_purchase_payment_atomic(
  p_purchase_id UUID,
  p_amount NUMERIC,
  p_payment_date DATE,
  p_payment_account_id UUID,
  p_reference_number TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_idempotency_key TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_org UUID:=public.get_auth_org_id();
  v_user UUID:=auth.uid();
  v_purchase RECORD;
  v_existing RECORD;
  v_paid NUMERIC;
  v_remaining NUMERIC;
  v_journal UUID:=gen_random_uuid();
  v_journal_no TEXT;
  v_payment UUID:=gen_random_uuid();
  v_ap UUID;
  v_asset UUID;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  IF p_idempotency_key IS NOT NULL THEN
    SELECT pp.id,pp.purchase_id,pp.amount,pp.journal_entry_id,p.paid_amount,p.payment_status,p.total_amount
      INTO v_existing
    FROM public.purchase_payments pp
    JOIN public.purchases p ON p.id=pp.purchase_id
    WHERE pp.organization_id=v_org AND pp.idempotency_key=p_idempotency_key
    LIMIT 1;
    IF v_existing.id IS NOT NULL THEN
      RETURN jsonb_build_object('id',v_existing.id,'purchase_id',v_existing.purchase_id,'amount',v_existing.amount,
        'paid_amount',v_existing.paid_amount,'remaining_amount',round(v_existing.total_amount-v_existing.paid_amount,2),
        'payment_status',v_existing.payment_status,'journal_id',v_existing.journal_entry_id,'already_exists',true);
    END IF;
  END IF;

  IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'Nominal pembayaran harus lebih dari 0'; END IF;
  IF p_payment_date IS NULL THEN RAISE EXCEPTION 'Tanggal pembayaran wajib diisi'; END IF;

  SELECT * INTO v_purchase FROM public.purchases
  WHERE id=p_purchase_id AND organization_id=v_org FOR UPDATE;
  IF v_purchase.id IS NULL THEN RAISE EXCEPTION 'Pembelian tidak ditemukan'; END IF;
  IF v_purchase.status<>'RECEIVED' THEN RAISE EXCEPTION 'Pembelian belum berstatus RECEIVED'; END IF;
  IF v_purchase.due_date IS NOT NULL AND p_payment_date < v_purchase.purchase_date THEN
    RAISE EXCEPTION 'Tanggal pembayaran tidak boleh sebelum tanggal pembelian';
  END IF;

  SELECT id INTO v_ap FROM public.accounts WHERE organization_id=v_org AND code='2-1000' AND is_active;
  IF v_ap IS NULL THEN RAISE EXCEPTION 'Akun Hutang Usaha belum tersedia'; END IF;
  SELECT id INTO v_asset FROM public.accounts WHERE id=p_payment_account_id AND organization_id=v_org AND account_type='ASSET' AND is_active;
  IF v_asset IS NULL THEN RAISE EXCEPTION 'Akun pembayaran tidak valid'; END IF;

  v_paid:=COALESCE(v_purchase.paid_amount,0);
  v_remaining:=round(COALESCE(v_purchase.total_amount,0)-v_paid,2);
  IF v_remaining<=0 THEN RAISE EXCEPTION 'Pembelian sudah lunas'; END IF;
  IF p_amount>v_remaining THEN RAISE EXCEPTION 'Nominal pembayaran melebihi sisa hutang'; END IF;

  v_journal_no:=public.next_accounting_journal_number('JRN-PURPAY',p_payment_date,v_org);
  INSERT INTO public.journal_entries(id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by)
  VALUES(v_journal,v_org,v_journal_no,p_payment_date,'purchase_payment',v_payment,'Pembayaran pembelian '||v_purchase.purchase_number,'POSTED',v_user);
  INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit)
  VALUES(v_journal,v_ap,'Pelunasan hutang '||v_purchase.purchase_number,p_amount,0),
        (v_journal,v_asset,'Pembayaran pembelian '||v_purchase.purchase_number,0,p_amount);
  INSERT INTO public.purchase_payments(id,organization_id,purchase_id,payment_date,amount,payment_account_id,reference_number,notes,journal_entry_id,idempotency_key,created_by)
  VALUES(v_payment,v_org,p_purchase_id,p_payment_date,p_amount,p_payment_account_id,p_reference_number,p_notes,v_journal,p_idempotency_key,v_user);
  v_paid:=round(v_paid+p_amount,2);
  UPDATE public.purchases SET paid_amount=v_paid,
    payment_status=CASE WHEN v_paid>=total_amount THEN 'PAID' ELSE 'PARTIAL' END,
    updated_at=NOW() WHERE id=p_purchase_id;

  RETURN jsonb_build_object('id',v_payment,'purchase_id',p_purchase_id,'amount',p_amount,'paid_amount',v_paid,
    'remaining_amount',round(v_purchase.total_amount-v_paid,2),
    'payment_status',CASE WHEN v_paid>=v_purchase.total_amount THEN 'PAID' ELSE 'PARTIAL' END,
    'journal_id',v_journal,'journal_number',v_journal_no,'already_exists',false);
EXCEPTION WHEN unique_violation THEN
  IF p_idempotency_key IS NOT NULL THEN
    SELECT pp.id,pp.purchase_id,pp.amount,pp.journal_entry_id,p.paid_amount,p.payment_status,p.total_amount INTO v_existing
    FROM public.purchase_payments pp JOIN public.purchases p ON p.id=pp.purchase_id
    WHERE pp.organization_id=v_org AND pp.idempotency_key=p_idempotency_key LIMIT 1;
    IF v_existing.id IS NOT NULL THEN
      RETURN jsonb_build_object('id',v_existing.id,'purchase_id',v_existing.purchase_id,'amount',v_existing.amount,'paid_amount',v_existing.paid_amount,
        'remaining_amount',round(v_existing.total_amount-v_existing.paid_amount,2),'payment_status',v_existing.payment_status,
        'journal_id',v_existing.journal_entry_id,'already_exists',true);
    END IF;
  END IF;
  RAISE;
END; $$;

REVOKE ALL ON FUNCTION public.record_purchase_payment_atomic(UUID,NUMERIC,DATE,UUID,TEXT,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_purchase_payment_atomic(UUID,NUMERIC,DATE,UUID,TEXT,TEXT,TEXT) TO authenticated;

-- Enrich purchase hydration with payment history so the UI never needs a second
-- round trip per purchase and the detail view can reconcile paid_amount.
CREATE OR REPLACE FUNCTION public.fetch_purchases_with_items()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org UUID:=public.get_auth_org_id();
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  RETURN COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'id',p.id,'purchase_number',p.purchase_number,'vendor_id',p.vendor_id,'vendor_name',p.vendor_name,
        'purchase_date',p.purchase_date,'due_date',p.due_date,'status',p.status,'payment_status',p.payment_status,
        'total_amount',p.total_amount,'paid_amount',p.paid_amount,'notes',p.notes,'created_at',p.created_at,'updated_at',p.updated_at,
        'items',COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'id',pi.id,'product_id',pi.product_id,'product_name',pi.product_name,'quantity',pi.quantity,'unit_cost',pi.unit_cost,'line_total',pi.line_total
        ) ORDER BY pi.id) FROM public.purchase_items pi WHERE pi.purchase_id=p.id),'[]'::jsonb),
        'payments',COALESCE((SELECT jsonb_agg(jsonb_build_object(
          'id',pp.id,'payment_date',pp.payment_date,'amount',pp.amount,'payment_account_id',pp.payment_account_id,
          'reference_number',pp.reference_number,'notes',pp.notes,'journal_entry_id',pp.journal_entry_id,'created_at',pp.created_at
        ) ORDER BY pp.payment_date DESC,pp.created_at DESC) FROM public.purchase_payments pp WHERE pp.purchase_id=p.id),'[]'::jsonb)
      ) ORDER BY p.purchase_date DESC,p.created_at DESC
    ) FROM public.purchases p WHERE p.organization_id=v_org
  ),'[]'::jsonb);
END; $$;
REVOKE ALL ON FUNCTION public.fetch_purchases_with_items() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_purchases_with_items() TO authenticated;
