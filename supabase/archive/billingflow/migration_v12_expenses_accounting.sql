-- BILLINGFLOW V12 — EXPENSE + ACCOUNTING FOUNDATION
-- Run after the existing production migrations (especially V9/V10/V11/V4).
-- No existing table is dropped or altered destructively.

CREATE TABLE IF NOT EXISTS public.accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  code VARCHAR(30) NOT NULL,
  name VARCHAR(150) NOT NULL,
  account_type VARCHAR(20) NOT NULL CHECK (account_type IN ('ASSET','LIABILITY','EQUITY','REVENUE','COGS','EXPENSE')),
  normal_balance VARCHAR(10) NOT NULL CHECK (normal_balance IN ('DEBIT','CREDIT')),
  is_active BOOLEAN NOT NULL DEFAULT TRUE,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (organization_id, code)
);

CREATE TABLE IF NOT EXISTS public.expense_transactions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  expense_number VARCHAR(100) NOT NULL,
  transaction_date DATE NOT NULL,
  vendor_name VARCHAR(255),
  description TEXT NOT NULL,
  due_date DATE,
  notes TEXT,
  status VARCHAR(20) NOT NULL DEFAULT 'POSTED' CHECK (status IN ('DRAFT','POSTED','CANCELLED')),
  payment_status VARCHAR(20) NOT NULL DEFAULT 'PAID' CHECK (payment_status IN ('UNPAID','PARTIAL','PAID')),
  payment_account_id UUID REFERENCES public.accounts(id) ON DELETE RESTRICT,
  subtotal NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (subtotal >= 0),
  tax_amount NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  total_amount NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (total_amount >= 0),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (organization_id, expense_number)
);

CREATE TABLE IF NOT EXISTS public.expense_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  expense_id UUID NOT NULL REFERENCES public.expense_transactions(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
  description TEXT NOT NULL,
  quantity NUMERIC(18,4) NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (unit_price >= 0),
  tax_rate NUMERIC(8,4) NOT NULL DEFAULT 0 CHECK (tax_rate >= 0),
  line_total NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (line_total >= 0),
  tax_amount NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (tax_amount >= 0),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.journal_entries (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  journal_number VARCHAR(100) NOT NULL,
  journal_date DATE NOT NULL,
  reference_type VARCHAR(50) NOT NULL,
  reference_id UUID NOT NULL,
  description TEXT NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'POSTED' CHECK (status IN ('DRAFT','POSTED','REVERSED')),
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (organization_id, journal_number)
);

CREATE TABLE IF NOT EXISTS public.journal_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  journal_entry_id UUID NOT NULL REFERENCES public.journal_entries(id) ON DELETE CASCADE,
  account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
  description TEXT NOT NULL,
  debit NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (debit >= 0),
  credit NUMERIC(18,2) NOT NULL DEFAULT 0 CHECK (credit >= 0),
  CHECK ((debit = 0 AND credit > 0) OR (credit = 0 AND debit > 0))
);

CREATE INDEX IF NOT EXISTS idx_accounts_org ON public.accounts(organization_id);
CREATE INDEX IF NOT EXISTS idx_expenses_org_date ON public.expense_transactions(organization_id, transaction_date DESC);
CREATE INDEX IF NOT EXISTS idx_expense_items_expense ON public.expense_items(expense_id);
CREATE INDEX IF NOT EXISTS idx_journal_entries_org_date ON public.journal_entries(organization_id, journal_date DESC);
CREATE INDEX IF NOT EXISTS idx_journal_entries_reference ON public.journal_entries(reference_type, reference_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_entry ON public.journal_lines(journal_entry_id);
CREATE INDEX IF NOT EXISTS idx_journal_lines_account ON public.journal_lines(account_id);

ALTER TABLE public.accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.expense_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.journal_lines ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "accounts tenant read" ON public.accounts;
CREATE POLICY "accounts tenant read" ON public.accounts FOR SELECT USING (organization_id = public.get_auth_org_id());
DROP POLICY IF EXISTS "expenses tenant read" ON public.expense_transactions;
CREATE POLICY "expenses tenant read" ON public.expense_transactions FOR SELECT USING (organization_id = public.get_auth_org_id());
DROP POLICY IF EXISTS "expense items tenant read" ON public.expense_items;
CREATE POLICY "expense items tenant read" ON public.expense_items FOR SELECT USING (EXISTS (SELECT 1 FROM public.expense_transactions e WHERE e.id=expense_id AND e.organization_id=public.get_auth_org_id()));
DROP POLICY IF EXISTS "journal tenant read" ON public.journal_entries;
CREATE POLICY "journal tenant read" ON public.journal_entries FOR SELECT USING (organization_id = public.get_auth_org_id());
DROP POLICY IF EXISTS "journal lines tenant read" ON public.journal_lines;
CREATE POLICY "journal lines tenant read" ON public.journal_lines FOR SELECT USING (EXISTS (SELECT 1 FROM public.journal_entries j WHERE j.id=journal_entry_id AND j.organization_id=public.get_auth_org_id()));

CREATE OR REPLACE FUNCTION public.ensure_default_accounts()
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org UUID := public.get_auth_org_id();
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  INSERT INTO public.accounts (organization_id,code,name,account_type,normal_balance) VALUES
    (v_org,'1-1000','Kas','ASSET','DEBIT'),
    (v_org,'1-1100','Bank BCA','ASSET','DEBIT'),
    (v_org,'1-1200','Bank Mandiri','ASSET','DEBIT'),
    (v_org,'2-1000','Hutang Usaha','LIABILITY','CREDIT'),
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

CREATE OR REPLACE FUNCTION public.create_expense_atomic(
  p_expense_id UUID,
  p_transaction_date DATE,
  p_vendor_name TEXT,
  p_description TEXT,
  p_due_date DATE,
  p_notes TEXT,
  p_payment_status TEXT,
  p_payment_account_id UUID,
  p_items JSONB
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE
  v_org UUID := public.get_auth_org_id(); v_user UUID := auth.uid(); v_expense UUID := COALESCE(p_expense_id,gen_random_uuid());
  v_num INT; v_expense_no TEXT; v_sub NUMERIC:=0; v_tax NUMERIC:=0; v_total NUMERIC:=0; v_journal UUID:=gen_random_uuid(); v_journal_no TEXT; v_ap UUID;
  item JSONB; v_account UUID; v_qty NUMERIC; v_price NUMERIC; v_rate NUMERIC; v_line NUMERIC; v_item_tax NUMERIC;
  v_debit NUMERIC:=0;
BEGIN
  IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
  IF trim(COALESCE(p_description,''))='' THEN RAISE EXCEPTION 'Deskripsi pengeluaran wajib diisi'; END IF;
  IF jsonb_array_length(COALESCE(p_items,'[]'::jsonb))=0 THEN RAISE EXCEPTION 'Minimal satu rincian biaya diperlukan'; END IF;
  IF p_payment_status NOT IN ('PAID','UNPAID') THEN RAISE EXCEPTION 'Status pembayaran tidak valid'; END IF;
  PERFORM public.ensure_default_accounts();
  SELECT id INTO v_ap FROM public.accounts WHERE organization_id=v_org AND code='2-1000';
  IF p_payment_status='PAID' THEN
    IF p_payment_account_id IS NULL THEN RAISE EXCEPTION 'Akun pembayaran wajib dipilih'; END IF;
    IF NOT EXISTS(SELECT 1 FROM public.accounts WHERE id=p_payment_account_id AND organization_id=v_org AND account_type='ASSET' AND is_active) THEN RAISE EXCEPTION 'Akun pembayaran tidak valid'; END IF;
  END IF;
  -- Posted accounting records are immutable. Editing will be introduced later as a correction/reversal workflow.
  IF p_expense_id IS NOT NULL THEN RAISE EXCEPTION 'Pengeluaran yang sudah dibuat tidak dapat diubah; gunakan pembatalan lalu buat transaksi baru.'; END IF;
  v_num := public.get_next_sequence('expense',0); v_expense_no := 'EXP-'||to_char(p_transaction_date,'YYYY')||'-'||lpad(v_num::text,5,'0');
  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_account := (item->>'account_id')::uuid; v_qty:=GREATEST((item->>'quantity')::numeric,0); v_price:=GREATEST((item->>'unit_price')::numeric,0); v_rate:=GREATEST(COALESCE((item->>'tax_rate')::numeric,0),0); v_line:=round(v_qty*v_price,2); v_item_tax:=round(v_line*v_rate/100,2);
    IF v_qty<=0 OR NOT EXISTS(SELECT 1 FROM public.accounts WHERE id=v_account AND organization_id=v_org AND account_type='EXPENSE' AND is_active) THEN RAISE EXCEPTION 'Rincian akun/nominal tidak valid'; END IF;
    INSERT INTO public.expense_items(expense_id,account_id,description,quantity,unit_price,tax_rate,line_total,tax_amount) VALUES(v_expense,v_account,COALESCE(item->>'description',''),v_qty,v_price,v_rate,v_line,v_item_tax);
    v_sub:=v_sub+v_line; v_tax:=v_tax+v_item_tax;
  END LOOP;
  v_total:=v_sub+v_tax;
  INSERT INTO public.expense_transactions(id,organization_id,expense_number,transaction_date,vendor_name,description,due_date,notes,status,payment_status,payment_account_id,subtotal,tax_amount,total_amount,created_by,updated_at)
  VALUES(v_expense,v_org,v_expense_no,p_transaction_date,p_vendor_name,p_description,p_due_date,p_notes,'POSTED',p_payment_status,p_payment_account_id,v_sub,v_tax,v_total,v_user,NOW())
  ON CONFLICT (id) DO UPDATE SET transaction_date=EXCLUDED.transaction_date,vendor_name=EXCLUDED.vendor_name,description=EXCLUDED.description,due_date=EXCLUDED.due_date,notes=EXCLUDED.notes,payment_status=EXCLUDED.payment_status,payment_account_id=EXCLUDED.payment_account_id,subtotal=EXCLUDED.subtotal,tax_amount=EXCLUDED.tax_amount,total_amount=EXCLUDED.total_amount,updated_at=NOW();
  v_journal_no:='JRN-'||to_char(p_transaction_date,'YYYY')||'-'||lpad(public.get_next_sequence('journal',0)::text,6,'0');
  INSERT INTO public.journal_entries(id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by) VALUES(v_journal,v_org,v_journal_no,p_transaction_date,'expense',v_expense,p_description,'POSTED',v_user);
  FOR item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_account:=(item->>'account_id')::uuid; v_qty:=(item->>'quantity')::numeric; v_price:=(item->>'unit_price')::numeric; v_rate:=COALESCE((item->>'tax_rate')::numeric,0); v_line:=round(v_qty*v_price,2)+round(v_qty*v_price*v_rate/100,2); v_debit:=v_debit+v_line;
    INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit) VALUES(v_journal,v_account,COALESCE(item->>'description',''),v_line,0);
  END LOOP;
  INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit) VALUES(v_journal,CASE WHEN p_payment_status='UNPAID' THEN v_ap ELSE p_payment_account_id END,CASE WHEN p_payment_status='UNPAID' THEN 'Hutang usaha' ELSE 'Pembayaran pengeluaran' END,0,v_total);
  INSERT INTO public.audit_logs(organization_id,user_id,user_name,user_role,action,module,record_id,record_title,details)
  SELECT v_org,v_user,COALESCE(p.name,'Pengguna'),COALESCE(p.role,'finance'),'create','expenses',v_expense::text,v_expense_no,'Mencatat pengeluaran '||v_expense_no||' sebesar Rp '||to_char(v_total,'FM999G999G999G999G990D00') FROM public.profiles p WHERE p.id=v_user;
  RETURN jsonb_build_object('id',v_expense,'expense_number',v_expense_no,'transaction_date',p_transaction_date,'vendor_name',COALESCE(p_vendor_name,''),'description',p_description,'due_date',p_due_date,'notes',COALESCE(p_notes,''),'status','POSTED','payment_status',p_payment_status,'subtotal',v_sub,'tax_amount',v_tax,'total_amount',v_total,'created_by',v_user,'created_at',NOW(),'updated_at',NOW());
END; $$;
REVOKE ALL ON FUNCTION public.create_expense_atomic(UUID,DATE,TEXT,TEXT,DATE,TEXT,TEXT,UUID,JSONB) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_expense_atomic(UUID,DATE,TEXT,TEXT,DATE,TEXT,TEXT,UUID,JSONB) TO authenticated;

CREATE OR REPLACE FUNCTION public.cancel_expense_atomic(p_expense_id UUID)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org UUID:=public.get_auth_org_id(); v_old UUID; v_new UUID:=gen_random_uuid(); v_num TEXT; v_line RECORD;
BEGIN
 SELECT id INTO v_old FROM public.expense_transactions WHERE id=p_expense_id AND organization_id=v_org AND status='POSTED';
 IF v_old IS NULL THEN RAISE EXCEPTION 'Pengeluaran tidak ditemukan atau sudah dibatalkan'; END IF;
 UPDATE public.expense_transactions SET status='CANCELLED',updated_at=NOW() WHERE id=v_old;
 SELECT journal_number INTO v_num FROM public.journal_entries WHERE reference_type='expense' AND reference_id=v_old AND organization_id=v_org AND status='POSTED' LIMIT 1;
 INSERT INTO public.journal_entries(id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by)
 VALUES(v_new,v_org,'REV-'||to_char(CURRENT_DATE,'YYYY')||'-'||lpad(public.get_next_sequence('journal_reversal',0)::text,6,'0'),CURRENT_DATE,'expense_reversal',v_old,'Pembalikan jurnal pengeluaran '||COALESCE(v_num,''),'POSTED',auth.uid());
 FOR v_line IN SELECT jl.* FROM public.journal_lines jl JOIN public.journal_entries je ON je.id=jl.journal_entry_id WHERE je.reference_type='expense' AND je.reference_id=v_old AND je.organization_id=v_org AND je.status='POSTED' LOOP
   INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit) VALUES(v_new,v_line.account_id,'Reversal: '||v_line.description,v_line.credit,v_line.debit);
 END LOOP;
 UPDATE public.journal_entries SET status='REVERSED' WHERE reference_type='expense' AND reference_id=v_old AND organization_id=v_org AND status='POSTED';
END; $$;
REVOKE ALL ON FUNCTION public.cancel_expense_atomic(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_expense_atomic(UUID) TO authenticated;
