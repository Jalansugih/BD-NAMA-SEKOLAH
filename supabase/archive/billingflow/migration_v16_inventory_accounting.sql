-- BILLINGFLOW V16 — INVENTORY ACCOUNTING / MOVING AVERAGE
-- Run after V15. Safe to re-run. No destructive DROP of business data.

INSERT INTO public.accounts (organization_id,code,name,account_type,normal_balance)
SELECT o.id,'1-3000','Persediaan Barang Dagang','ASSET','DEBIT' FROM public.organizations o
ON CONFLICT (organization_id,code) DO NOTHING;
INSERT INTO public.accounts (organization_id,code,name,account_type,normal_balance)
SELECT o.id,'4-9100','Keuntungan Penyesuaian Persediaan','REVENUE','CREDIT' FROM public.organizations o
ON CONFLICT (organization_id,code) DO NOTHING;
INSERT INTO public.accounts (organization_id,code,name,account_type,normal_balance)
SELECT o.id,'6-1950','Kerugian Penyesuaian Persediaan','EXPENSE','DEBIT' FROM public.organizations o
ON CONFLICT (organization_id,code) DO NOTHING;

CREATE INDEX IF NOT EXISTS idx_inventory_movements_reference
ON public.inventory_movements(organization_id,reference_type,reference_id);

CREATE OR REPLACE FUNCTION public.record_inventory_receipt_atomic(
  p_product_id UUID,p_quantity NUMERIC,p_unit_cost NUMERIC,
  p_movement_type TEXT DEFAULT 'PURCHASE',p_movement_date DATE DEFAULT CURRENT_DATE,
  p_reference_type TEXT DEFAULT NULL,p_reference_id UUID DEFAULT NULL,p_notes TEXT DEFAULT NULL)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_org UUID:=public.get_auth_org_id(); v_product RECORD; v_inventory UUID; v_credit UUID;
  v_gain UUID; v_journal UUID:=gen_random_uuid(); v_journal_no TEXT; v_move UUID;
  v_old_qty NUMERIC; v_old_cost NUMERIC; v_new_qty NUMERIC; v_new_cost NUMERIC; v_value NUMERIC;
  v_type TEXT:=COALESCE(p_movement_type,'PURCHASE');
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  IF p_quantity IS NULL OR p_quantity<=0 THEN RAISE EXCEPTION 'Jumlah stok masuk harus lebih dari 0'; END IF;
  IF p_unit_cost IS NULL OR p_unit_cost<0 THEN RAISE EXCEPTION 'Harga pokok harus >= 0'; END IF;
  IF v_type NOT IN ('OPENING','PURCHASE','RETURN_IN','ADJUSTMENT_IN') THEN RAISE EXCEPTION 'Tipe stok masuk tidak valid'; END IF;
  SELECT * INTO v_product FROM public.products WHERE id=p_product_id AND organization_id=v_org FOR UPDATE;
  IF v_product.id IS NULL THEN RAISE EXCEPTION 'Produk tidak ditemukan'; END IF;
  IF NOT COALESCE(v_product.track_inventory,FALSE) THEN RAISE EXCEPTION 'Produk tidak menggunakan pelacakan persediaan'; END IF;

  v_old_qty:=COALESCE(v_product.stock_qty,0); v_old_cost:=COALESCE(v_product.cost_price,0);
  v_new_qty:=v_old_qty+p_quantity;
  v_new_cost:=CASE WHEN v_old_qty<=0 THEN p_unit_cost ELSE round(((v_old_qty*v_old_cost)+(p_quantity*p_unit_cost))/v_new_qty,2) END;
  v_value:=round(p_quantity*p_unit_cost,2);

  INSERT INTO public.inventory_movements(organization_id,product_id,movement_date,movement_type,quantity,unit_cost,reference_type,reference_id,notes,created_by)
  VALUES(v_org,p_product_id,COALESCE(p_movement_date,CURRENT_DATE),v_type,p_quantity,p_unit_cost,p_reference_type,p_reference_id,p_notes,auth.uid()) RETURNING id INTO v_move;
  UPDATE public.products SET stock_qty=v_new_qty,cost_price=v_new_cost,updated_at=NOW() WHERE id=p_product_id;

  SELECT id INTO v_inventory FROM public.accounts WHERE organization_id=v_org AND code='1-3000';
  IF v_type='PURCHASE' THEN SELECT id INTO v_credit FROM public.accounts WHERE organization_id=v_org AND code='2-1000';
  ELSIF v_type='OPENING' THEN SELECT id INTO v_credit FROM public.accounts WHERE organization_id=v_org AND code='3-1000';
  ELSIF v_type='RETURN_IN' THEN SELECT id INTO v_credit FROM public.accounts WHERE organization_id=v_org AND code='5-1000';
  ELSE SELECT id INTO v_gain FROM public.accounts WHERE organization_id=v_org AND code='4-9100'; v_credit:=v_gain; END IF;

  IF v_value>0 AND v_inventory IS NOT NULL AND v_credit IS NOT NULL THEN
    v_journal_no:=public.next_accounting_journal_number('JRN-STK',COALESCE(p_movement_date,CURRENT_DATE),v_org);
    INSERT INTO public.journal_entries(id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by)
    VALUES(v_journal,v_org,v_journal_no,COALESCE(p_movement_date,CURRENT_DATE),COALESCE(p_reference_type,'inventory'),COALESCE(p_reference_id,v_move),'Stok masuk '||v_product.name,'POSTED',auth.uid());
    INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit) VALUES
      (v_journal,v_inventory,'Persediaan '||v_product.name,v_value,0),
      (v_journal,v_credit,'Lawan transaksi persediaan '||v_product.name,0,v_value);
  END IF;
  RETURN jsonb_build_object('movement_id',v_move,'product_id',p_product_id,'stock_qty',v_new_qty,'cost_price',v_new_cost,'value',v_value);
END; $$;
REVOKE ALL ON FUNCTION public.record_inventory_receipt_atomic(UUID,NUMERIC,NUMERIC,TEXT,DATE,TEXT,UUID,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_inventory_receipt_atomic(UUID,NUMERIC,NUMERIC,TEXT,DATE,TEXT,UUID,TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.post_invoice_inventory(p_invoice_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_invoice RECORD; v_item RECORD; v_product RECORD; v_inventory UUID; v_cogs UUID;
  v_journal UUID:=gen_random_uuid(); v_journal_no TEXT; v_total NUMERIC:=0; v_qty NUMERIC; v_cost NUMERIC;
BEGIN
  SELECT * INTO v_invoice FROM public.invoices WHERE id=p_invoice_id;
  IF v_invoice.id IS NULL THEN RAISE EXCEPTION 'Invoice tidak ditemukan'; END IF;
  IF v_invoice.status IN ('draft','cancelled') THEN RETURN NULL; END IF;
  IF EXISTS(SELECT 1 FROM public.journal_entries WHERE organization_id=v_invoice.organization_id AND reference_type='inventory_sale' AND reference_id=v_invoice.id AND status='POSTED') THEN
    RETURN (SELECT id FROM public.journal_entries WHERE organization_id=v_invoice.organization_id AND reference_type='inventory_sale' AND reference_id=v_invoice.id AND status='POSTED' ORDER BY created_at DESC LIMIT 1);
  END IF;
  SELECT id INTO v_inventory FROM public.accounts WHERE organization_id=v_invoice.organization_id AND code='1-3000';
  SELECT id INTO v_cogs FROM public.accounts WHERE organization_id=v_invoice.organization_id AND code='5-1000';
  IF v_inventory IS NULL OR v_cogs IS NULL THEN RAISE EXCEPTION 'Akun persediaan/HPP belum tersedia'; END IF;

  FOR v_item IN SELECT * FROM public.invoice_items WHERE invoice_id=v_invoice.id AND product_id IS NOT NULL LOOP
    SELECT * INTO v_product FROM public.products WHERE id=v_item.product_id AND organization_id=v_invoice.organization_id FOR UPDATE;
    IF v_product.id IS NULL OR NOT COALESCE(v_product.track_inventory,FALSE) THEN CONTINUE; END IF;
    v_qty:=COALESCE(v_item.quantity,0); IF v_qty<=0 THEN CONTINUE; END IF;
    IF COALESCE(v_product.stock_qty,0)<v_qty THEN RAISE EXCEPTION 'Stok tidak cukup untuk % (tersedia %, diminta %)',v_product.name,COALESCE(v_product.stock_qty,0),v_qty; END IF;
    v_total:=v_total+(v_qty*COALESCE(v_product.cost_price,0));
  END LOOP;
  IF v_total<=0 THEN RETURN NULL; END IF;

  v_journal_no:=public.next_accounting_journal_number('JRN-HPP',v_invoice.issue_date,v_invoice.organization_id);
  INSERT INTO public.journal_entries(id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by)
  VALUES(v_journal,v_invoice.organization_id,v_journal_no,v_invoice.issue_date,'inventory_sale',v_invoice.id,'HPP penjualan '||v_invoice.invoice_number,'POSTED',v_invoice.created_by);
  INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit) VALUES
    (v_journal,v_cogs,'HPP '||v_invoice.invoice_number,round(v_total,2),0),
    (v_journal,v_inventory,'Pengurangan persediaan '||v_invoice.invoice_number,0,round(v_total,2));

  FOR v_item IN SELECT * FROM public.invoice_items WHERE invoice_id=v_invoice.id AND product_id IS NOT NULL LOOP
    SELECT * INTO v_product FROM public.products WHERE id=v_item.product_id AND organization_id=v_invoice.organization_id FOR UPDATE;
    IF v_product.id IS NULL OR NOT COALESCE(v_product.track_inventory,FALSE) OR COALESCE(v_item.quantity,0)<=0 THEN CONTINUE; END IF;
    v_qty:=v_item.quantity; v_cost:=COALESCE(v_product.cost_price,0);
    IF v_product.stock_qty<v_qty THEN RAISE EXCEPTION 'Stok tidak cukup untuk %',v_product.name; END IF;
    INSERT INTO public.inventory_movements(organization_id,product_id,movement_date,movement_type,quantity,unit_cost,reference_type,reference_id,notes,created_by)
    VALUES(v_invoice.organization_id,v_product.id,v_invoice.issue_date,'SALE',-v_qty,v_cost,'invoice',v_invoice.id,'Penjualan melalui invoice '||v_invoice.invoice_number,v_invoice.created_by);
    UPDATE public.products SET stock_qty=stock_qty-v_qty,updated_at=NOW() WHERE id=v_product.id;
  END LOOP;
  RETURN v_journal;
END; $$;
REVOKE ALL ON FUNCTION public.post_invoice_inventory(UUID) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.reverse_invoice_inventory(p_invoice_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_org UUID:=public.get_auth_org_id(); v_old UUID; v_rev UUID:=gen_random_uuid(); v_no TEXT; v_line RECORD; v_move RECORD;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  SELECT id INTO v_old FROM public.journal_entries WHERE organization_id=v_org AND reference_type='inventory_sale' AND reference_id=p_invoice_id AND status='POSTED' ORDER BY created_at DESC LIMIT 1;
  IF v_old IS NULL THEN RETURN NULL; END IF;
  v_no:=public.next_accounting_journal_number('REV-HPP',CURRENT_DATE,v_org);
  INSERT INTO public.journal_entries(id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by)
  VALUES(v_rev,v_org,v_no,CURRENT_DATE,'inventory_sale_reversal',p_invoice_id,'Pembalikan HPP invoice','POSTED',auth.uid());
  FOR v_line IN SELECT * FROM public.journal_lines WHERE journal_entry_id=v_old LOOP
    INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit) VALUES(v_rev,v_line.account_id,'Reversal: '||v_line.description,v_line.credit,v_line.debit);
  END LOOP;
  FOR v_move IN SELECT * FROM public.inventory_movements WHERE organization_id=v_org AND reference_type='invoice' AND reference_id=p_invoice_id AND movement_type='SALE' LOOP
    UPDATE public.products SET stock_qty=stock_qty-v_move.quantity,updated_at=NOW() WHERE id=v_move.product_id AND organization_id=v_org;
    INSERT INTO public.inventory_movements(organization_id,product_id,movement_date,movement_type,quantity,unit_cost,reference_type,reference_id,notes,created_by)
    VALUES(v_org,v_move.product_id,CURRENT_DATE,'RETURN_IN',-v_move.quantity,v_move.unit_cost,'invoice_reversal',p_invoice_id,'Reversal stok invoice',auth.uid());
  END LOOP;
  UPDATE public.journal_entries SET status='REVERSED' WHERE id=v_old;
  RETURN v_rev;
END; $$;
REVOKE ALL ON FUNCTION public.reverse_invoice_inventory(UUID) FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.trg_invoice_inventory()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_existing BOOLEAN; v_changed BOOLEAN:=FALSE;
BEGIN
  SELECT EXISTS(SELECT 1 FROM public.journal_entries WHERE organization_id=NEW.organization_id AND reference_type='inventory_sale' AND reference_id=NEW.id AND status='POSTED') INTO v_existing;
  IF TG_OP='UPDATE' THEN v_changed:=OLD.issue_date IS DISTINCT FROM NEW.issue_date OR OLD.status IS DISTINCT FROM NEW.status; END IF;
  IF v_existing AND (NEW.status='cancelled' OR v_changed) THEN PERFORM public.reverse_invoice_inventory(NEW.id); v_existing:=FALSE; END IF;
  IF NEW.status NOT IN ('draft','cancelled') AND NOT v_existing THEN PERFORM public.post_invoice_inventory(NEW.id); END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_invoices_inventory ON public.invoices;
CREATE TRIGGER trg_invoices_inventory AFTER INSERT OR UPDATE OF issue_date,status ON public.invoices FOR EACH ROW EXECUTE FUNCTION public.trg_invoice_inventory();

CREATE OR REPLACE FUNCTION public.repost_invoice_inventory(p_invoice_id UUID)
RETURNS UUID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_invoice RECORD;
BEGIN
  SELECT * INTO v_invoice FROM public.invoices WHERE id=p_invoice_id AND organization_id=public.get_auth_org_id();
  IF v_invoice.id IS NULL THEN RAISE EXCEPTION 'Invoice tidak ditemukan'; END IF;
  IF v_invoice.status IN ('draft','cancelled') THEN PERFORM public.reverse_invoice_inventory(p_invoice_id); RETURN NULL; END IF;
  PERFORM public.reverse_invoice_inventory(p_invoice_id);
  RETURN public.post_invoice_inventory(p_invoice_id);
END; $$;
REVOKE ALL ON FUNCTION public.repost_invoice_inventory(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.repost_invoice_inventory(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.adjust_product_stock_atomic(
  p_product_id UUID,p_delta NUMERIC,p_movement_type TEXT DEFAULT NULL,p_notes TEXT DEFAULT NULL,p_movement_date DATE DEFAULT CURRENT_DATE)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org UUID:=public.get_auth_org_id(); v_product RECORD; v_type TEXT; v_cost NUMERIC; v_value NUMERIC; v_move UUID; v_inventory UUID; v_gain UUID; v_loss UUID; v_journal UUID:=gen_random_uuid(); v_no TEXT;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  IF p_delta IS NULL OR p_delta=0 THEN RAISE EXCEPTION 'Perubahan stok tidak boleh 0'; END IF;
  SELECT * INTO v_product FROM public.products WHERE id=p_product_id AND organization_id=v_org FOR UPDATE;
  IF v_product.id IS NULL THEN RAISE EXCEPTION 'Produk tidak ditemukan'; END IF;
  IF NOT v_product.track_inventory THEN RAISE EXCEPTION 'Produk ini tidak menggunakan pelacakan persediaan'; END IF;
  IF v_product.stock_qty+p_delta<0 THEN RAISE EXCEPTION 'Stok tidak boleh negatif'; END IF;
  v_type:=COALESCE(p_movement_type,CASE WHEN p_delta>0 THEN 'ADJUSTMENT_IN' ELSE 'ADJUSTMENT_OUT' END);
  IF v_type NOT IN ('ADJUSTMENT_IN','ADJUSTMENT_OUT') THEN RAISE EXCEPTION 'Tipe penyesuaian tidak valid'; END IF;
  v_cost:=COALESCE(v_product.cost_price,0); v_value:=round(abs(p_delta)*v_cost,2);
  INSERT INTO public.inventory_movements(organization_id,product_id,movement_date,movement_type,quantity,unit_cost,notes,created_by)
  VALUES(v_org,p_product_id,p_movement_date,v_type,p_delta,v_cost,p_notes,auth.uid()) RETURNING id INTO v_move;
  UPDATE public.products SET stock_qty=stock_qty+p_delta,updated_at=NOW() WHERE id=p_product_id;
  SELECT id INTO v_inventory FROM public.accounts WHERE organization_id=v_org AND code='1-3000';
  SELECT id INTO v_gain FROM public.accounts WHERE organization_id=v_org AND code='4-9100';
  SELECT id INTO v_loss FROM public.accounts WHERE organization_id=v_org AND code='6-1950';
  IF v_value>0 AND v_inventory IS NOT NULL THEN
    v_no:=public.next_accounting_journal_number('JRN-ADJ',p_movement_date,v_org);
    INSERT INTO public.journal_entries(id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by)
    VALUES(v_journal,v_org,v_no,p_movement_date,'inventory_adjustment',v_move,'Penyesuaian persediaan '||v_product.name,'POSTED',auth.uid());
    IF v_type='ADJUSTMENT_IN' THEN
      INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit) VALUES(v_journal,v_inventory,'Penambahan persediaan '||v_product.name,v_value,0),(v_journal,v_gain,'Keuntungan penyesuaian persediaan',0,v_value);
    ELSE
      INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit) VALUES(v_journal,v_loss,'Kerugian penyesuaian persediaan',v_value,0),(v_journal,v_inventory,'Pengurangan persediaan '||v_product.name,0,v_value);
    END IF;
  END IF;
  RETURN jsonb_build_object('movement_id',v_move,'product_id',p_product_id,'stock_qty',v_product.stock_qty+p_delta,'delta',p_delta,'unit_cost',v_cost,'value',v_value);
END; $$;

CREATE OR REPLACE FUNCTION public.recalculate_inventory_product(p_product_id UUID)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org UUID:=public.get_auth_org_id(); r RECORD; v_qty NUMERIC:=0; v_value NUMERIC:=0; v_cost NUMERIC:=0;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  FOR r IN SELECT quantity,unit_cost FROM public.inventory_movements WHERE organization_id=v_org AND product_id=p_product_id ORDER BY movement_date,created_at,id LOOP
    IF r.quantity>0 THEN v_value:=v_value+(r.quantity*r.unit_cost); v_qty:=v_qty+r.quantity; IF v_qty>0 THEN v_cost:=round(v_value/v_qty,2); END IF;
    ELSE v_value:=GREATEST(0,v_value+(r.quantity*v_cost)); v_qty:=v_qty+r.quantity; END IF;
  END LOOP;
  IF v_qty<0 THEN RAISE EXCEPTION 'Ledger persediaan menghasilkan stok negatif'; END IF;
  UPDATE public.products SET stock_qty=v_qty,cost_price=v_cost,updated_at=NOW() WHERE id=p_product_id AND organization_id=v_org;
  RETURN jsonb_build_object('product_id',p_product_id,'stock_qty',v_qty,'cost_price',v_cost,'inventory_value',round(v_value,2));
END; $$;
REVOKE ALL ON FUNCTION public.recalculate_inventory_product(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.recalculate_inventory_product(UUID) TO authenticated;
