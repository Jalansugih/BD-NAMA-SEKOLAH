-- BILLINGFLOW V18 — ATOMIC PURCHASE -> INVENTORY -> PAYABLE -> JOURNAL
-- Run after V17. Non-destructive and tenant-isolated.

ALTER TABLE public.purchases
  ADD COLUMN IF NOT EXISTS journal_entry_id UUID REFERENCES public.journal_entries(id) ON DELETE RESTRICT,
  ADD COLUMN IF NOT EXISTS received_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.purchase_items
  ADD COLUMN IF NOT EXISTS organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE;

UPDATE public.purchase_items pi
SET organization_id=p.organization_id
FROM public.purchases p
WHERE p.id=pi.purchase_id AND pi.organization_id IS NULL;

CREATE INDEX IF NOT EXISTS idx_purchases_org_date ON public.purchases(organization_id,purchase_date DESC);
CREATE INDEX IF NOT EXISTS idx_purchases_vendor ON public.purchases(organization_id,vendor_id);
CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON public.purchase_items(purchase_id);
CREATE INDEX IF NOT EXISTS idx_purchase_items_product ON public.purchase_items(product_id);

CREATE TABLE IF NOT EXISTS public.purchase_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  purchase_id UUID NOT NULL REFERENCES public.purchases(id) ON DELETE RESTRICT,
  payment_date DATE NOT NULL DEFAULT CURRENT_DATE,
  amount NUMERIC(18,2) NOT NULL CHECK(amount>0),
  payment_account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
  reference_number TEXT,
  notes TEXT,
  journal_entry_id UUID REFERENCES public.journal_entries(id) ON DELETE RESTRICT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_purchase_payments_org_date ON public.purchase_payments(organization_id,payment_date DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_payments_purchase ON public.purchase_payments(purchase_id);

ALTER TABLE public.vendors ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_payments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "vendors tenant read" ON public.vendors;
CREATE POLICY "vendors tenant read" ON public.vendors FOR SELECT USING (organization_id=public.get_auth_org_id());
DROP POLICY IF EXISTS "vendors tenant insert" ON public.vendors;
CREATE POLICY "vendors tenant insert" ON public.vendors FOR INSERT WITH CHECK (organization_id=public.get_auth_org_id());
DROP POLICY IF EXISTS "vendors tenant update" ON public.vendors;
CREATE POLICY "vendors tenant update" ON public.vendors FOR UPDATE USING (organization_id=public.get_auth_org_id()) WITH CHECK (organization_id=public.get_auth_org_id());
DROP POLICY IF EXISTS "purchases tenant read" ON public.purchases;
CREATE POLICY "purchases tenant read" ON public.purchases FOR SELECT USING (organization_id=public.get_auth_org_id());
DROP POLICY IF EXISTS "purchase items tenant read" ON public.purchase_items;
CREATE POLICY "purchase items tenant read" ON public.purchase_items FOR SELECT USING (organization_id=public.get_auth_org_id());
DROP POLICY IF EXISTS "purchase payments tenant read" ON public.purchase_payments;
CREATE POLICY "purchase payments tenant read" ON public.purchase_payments FOR SELECT USING (organization_id=public.get_auth_org_id());

CREATE OR REPLACE FUNCTION public.record_purchase_atomic(
  p_purchase_number TEXT,
  p_vendor_id UUID,
  p_vendor_name TEXT,
  p_purchase_date DATE,
  p_due_date DATE DEFAULT NULL,
  p_notes TEXT DEFAULT NULL,
  p_items JSONB DEFAULT '[]'::jsonb
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_org UUID:=public.get_auth_org_id();
  v_user UUID:=auth.uid();
  v_purchase_id UUID:=gen_random_uuid();
  v_journal UUID:=gen_random_uuid();
  v_journal_no TEXT;
  v_inventory UUID;
  v_ap UUID;
  v_total NUMERIC:=0;
  v_item JSONB;
  v_product RECORD;
  v_qty NUMERIC;
  v_cost NUMERIC;
  v_value NUMERIC;
  v_old_qty NUMERIC;
  v_old_cost NUMERIC;
  v_new_qty NUMERIC;
  v_new_cost NUMERIC;
  v_existing UUID;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  IF COALESCE(trim(p_purchase_number),'')='' THEN RAISE EXCEPTION 'Nomor pembelian wajib diisi'; END IF;
  IF COALESCE(trim(p_vendor_name),'')='' THEN RAISE EXCEPTION 'Vendor wajib diisi'; END IF;
  IF p_purchase_date IS NULL THEN RAISE EXCEPTION 'Tanggal pembelian wajib diisi'; END IF;
  IF jsonb_typeof(p_items)<>'array' OR jsonb_array_length(p_items)=0 THEN RAISE EXCEPTION 'Minimal satu barang pembelian'; END IF;

  SELECT id INTO v_existing FROM public.purchases
  WHERE organization_id=v_org AND purchase_number=p_purchase_number
  FOR UPDATE;
  IF v_existing IS NOT NULL THEN
    RETURN jsonb_build_object(
      'id',v_existing,'purchase_number',p_purchase_number,'already_exists',true,
      'status',(SELECT status FROM public.purchases WHERE id=v_existing),
      'payment_status',(SELECT payment_status FROM public.purchases WHERE id=v_existing),
      'total_amount',(SELECT total_amount FROM public.purchases WHERE id=v_existing),
      'paid_amount',(SELECT paid_amount FROM public.purchases WHERE id=v_existing)
    );
  END IF;

  IF p_vendor_id IS NOT NULL AND NOT EXISTS(
    SELECT 1 FROM public.vendors WHERE id=p_vendor_id AND organization_id=v_org AND is_active
  ) THEN RAISE EXCEPTION 'Vendor tidak valid'; END IF;

  SELECT id INTO v_inventory FROM public.accounts WHERE organization_id=v_org AND code='1-3000' AND is_active;
  SELECT id INTO v_ap FROM public.accounts WHERE organization_id=v_org AND code='2-1000' AND is_active;
  IF v_inventory IS NULL OR v_ap IS NULL THEN RAISE EXCEPTION 'Akun Persediaan atau Hutang Usaha belum tersedia'; END IF;

  INSERT INTO public.purchases(id,organization_id,purchase_number,vendor_id,vendor_name,purchase_date,due_date,status,payment_status,total_amount,paid_amount,notes,created_at,updated_at,received_at,created_by)
  VALUES(v_purchase_id,v_org,p_purchase_number,p_vendor_id,trim(p_vendor_name),p_purchase_date,p_due_date,'RECEIVED','UNPAID',0,0,p_notes,NOW(),NOW(),NOW(),v_user);

  FOR v_item IN SELECT value FROM jsonb_array_elements(p_items) LOOP
    IF NULLIF(v_item->>'product_id','') IS NULL THEN RAISE EXCEPTION 'Produk pada rincian pembelian wajib dipilih'; END IF;
    v_qty:=COALESCE((v_item->>'quantity')::numeric,0);
    v_cost:=COALESCE((v_item->>'unit_cost')::numeric,0);
    IF v_qty<=0 THEN RAISE EXCEPTION 'Qty pembelian harus lebih dari 0'; END IF;
    IF v_cost<0 THEN RAISE EXCEPTION 'Harga pokok tidak boleh negatif'; END IF;

    SELECT * INTO v_product FROM public.products
    WHERE id=(v_item->>'product_id')::uuid AND organization_id=v_org
    FOR UPDATE;
    IF v_product.id IS NULL THEN RAISE EXCEPTION 'Produk tidak ditemukan'; END IF;
    IF NOT COALESCE(v_product.track_inventory,FALSE) THEN RAISE EXCEPTION 'Produk % tidak menggunakan pelacakan persediaan',v_product.name; END IF;

    v_value:=round(v_qty*v_cost,2);
    v_total:=v_total+v_value;
    v_old_qty:=COALESCE(v_product.stock_qty,0);
    v_old_cost:=COALESCE(v_product.cost_price,0);
    v_new_qty:=v_old_qty+v_qty;
    v_new_cost:=CASE WHEN v_old_qty<=0 THEN v_cost ELSE round(((v_old_qty*v_old_cost)+(v_qty*v_cost))/v_new_qty,2) END;

    INSERT INTO public.purchase_items(purchase_id,organization_id,product_id,product_name,quantity,unit_cost,line_total)
    VALUES(v_purchase_id,v_org,v_product.id,v_product.name,v_qty,v_cost,v_value);
    INSERT INTO public.inventory_movements(organization_id,product_id,movement_date,movement_type,quantity,unit_cost,reference_type,reference_id,notes,created_by)
    VALUES(v_org,v_product.id,p_purchase_date,'PURCHASE',v_qty,v_cost,'purchase',v_purchase_id,'Penerimaan pembelian '||p_purchase_number,v_user);
    UPDATE public.products SET stock_qty=v_new_qty,cost_price=v_new_cost,updated_at=NOW() WHERE id=v_product.id;
  END LOOP;

  IF v_total<=0 THEN RAISE EXCEPTION 'Total pembelian harus lebih dari 0'; END IF;
  v_journal_no:=public.next_accounting_journal_number('JRN-PUR',p_purchase_date,v_org);
  INSERT INTO public.journal_entries(id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by)
  VALUES(v_journal,v_org,v_journal_no,p_purchase_date,'purchase',v_purchase_id,'Pembelian barang '||p_purchase_number,'POSTED',v_user);
  INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit)
  VALUES(v_journal,v_inventory,'Persediaan pembelian '||p_purchase_number,round(v_total,2),0),
        (v_journal,v_ap,'Hutang usaha '||p_purchase_number,0,round(v_total,2));
  UPDATE public.purchases SET total_amount=round(v_total,2),journal_entry_id=v_journal WHERE id=v_purchase_id;

  RETURN jsonb_build_object('id',v_purchase_id,'purchase_number',p_purchase_number,'vendor_name',p_vendor_name,'total_amount',round(v_total,2),'payment_status','UNPAID','status','RECEIVED','journal_id',v_journal,'journal_number',v_journal_no,'already_exists',false);
END; $$;
REVOKE ALL ON FUNCTION public.record_purchase_atomic(TEXT,UUID,TEXT,DATE,DATE,TEXT,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_purchase_atomic(TEXT,UUID,TEXT,DATE,DATE,TEXT,JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.record_purchase_payment_atomic(
  p_purchase_id UUID,
  p_amount NUMERIC,
  p_payment_date DATE,
  p_payment_account_id UUID,
  p_reference_number TEXT DEFAULT NULL,
  p_notes TEXT DEFAULT NULL
) RETURNS JSONB
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_org UUID:=public.get_auth_org_id();
  v_user UUID:=auth.uid();
  v_purchase RECORD;
  v_paid NUMERIC;
  v_remaining NUMERIC;
  v_journal UUID:=gen_random_uuid();
  v_journal_no TEXT;
  v_payment UUID:=gen_random_uuid();
  v_ap UUID;
  v_asset UUID;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'Nominal pembayaran harus lebih dari 0'; END IF;
  IF p_payment_date IS NULL THEN RAISE EXCEPTION 'Tanggal pembayaran wajib diisi'; END IF;
  SELECT * INTO v_purchase FROM public.purchases WHERE id=p_purchase_id AND organization_id=v_org FOR UPDATE;
  IF v_purchase.id IS NULL THEN RAISE EXCEPTION 'Pembelian tidak ditemukan'; END IF;
  IF v_purchase.status<>'RECEIVED' THEN RAISE EXCEPTION 'Pembelian belum berstatus RECEIVED'; END IF;
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
  INSERT INTO public.purchase_payments(id,organization_id,purchase_id,payment_date,amount,payment_account_id,reference_number,notes,journal_entry_id,created_by)
  VALUES(v_payment,v_org,p_purchase_id,p_payment_date,p_amount,p_payment_account_id,p_reference_number,p_notes,v_journal,v_user);
  v_paid:=round(v_paid+p_amount,2);
  UPDATE public.purchases SET paid_amount=v_paid,payment_status=CASE WHEN v_paid>=total_amount THEN 'PAID' ELSE 'PARTIAL' END,updated_at=NOW() WHERE id=p_purchase_id;
  RETURN jsonb_build_object('id',v_payment,'purchase_id',p_purchase_id,'amount',p_amount,'paid_amount',v_paid,'remaining_amount',round(v_purchase.total_amount-v_paid,2),'payment_status',CASE WHEN v_paid>=v_purchase.total_amount THEN 'PAID' ELSE 'PARTIAL' END,'journal_id',v_journal,'journal_number',v_journal_no);
END; $$;
REVOKE ALL ON FUNCTION public.record_purchase_payment_atomic(UUID,NUMERIC,DATE,UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_purchase_payment_atomic(UUID,NUMERIC,DATE,UUID,TEXT,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.fetch_purchases_with_items()
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org UUID:=public.get_auth_org_id();
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  RETURN COALESCE((SELECT jsonb_agg(jsonb_build_object('id',p.id,'purchase_number',p.purchase_number,'vendor_id',p.vendor_id,'vendor_name',p.vendor_name,'purchase_date',p.purchase_date,'due_date',p.due_date,'status',p.status,'payment_status',p.payment_status,'total_amount',p.total_amount,'paid_amount',p.paid_amount,'notes',p.notes,'created_at',p.created_at,'updated_at',p.updated_at,'items',COALESCE((SELECT jsonb_agg(jsonb_build_object('id',pi.id,'product_id',pi.product_id,'product_name',pi.product_name,'quantity',pi.quantity,'unit_cost',pi.unit_cost,'line_total',pi.line_total) ORDER BY pi.id) FROM public.purchase_items pi WHERE pi.purchase_id=p.id),'[]'::jsonb)) ORDER BY p.purchase_date DESC,p.created_at DESC) FROM public.purchases p WHERE p.organization_id=v_org),'[]'::jsonb);
END; $$;
REVOKE ALL ON FUNCTION public.fetch_purchases_with_items() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_purchases_with_items() TO authenticated;
