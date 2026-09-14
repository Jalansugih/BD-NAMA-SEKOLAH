-- BILLINGFLOW V13 — EXPENSE PAYMENT / ACCOUNTS PAYABLE
CREATE TABLE IF NOT EXISTS public.expense_payments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  expense_id UUID NOT NULL REFERENCES public.expense_transactions(id) ON DELETE RESTRICT,
  payment_date DATE NOT NULL,
  amount NUMERIC(18,2) NOT NULL CHECK (amount > 0),
  payment_account_id UUID NOT NULL REFERENCES public.accounts(id) ON DELETE RESTRICT,
  reference_number VARCHAR(100), notes TEXT,
  journal_entry_id UUID REFERENCES public.journal_entries(id) ON DELETE RESTRICT,
  created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_expense_payments_expense ON public.expense_payments(expense_id, payment_date DESC);
ALTER TABLE public.expense_payments ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "expense payments tenant read" ON public.expense_payments;
CREATE POLICY "expense payments tenant read" ON public.expense_payments FOR SELECT USING (organization_id = public.get_auth_org_id());

CREATE OR REPLACE FUNCTION public.record_expense_payment_atomic(
  p_expense_id UUID, p_payment_date DATE, p_amount NUMERIC, p_payment_account_id UUID, p_reference_number TEXT, p_notes TEXT
) RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_org UUID:=public.get_auth_org_id(); v_user UUID:=auth.uid(); v_expense RECORD; v_paid NUMERIC; v_remaining NUMERIC; v_journal UUID:=gen_random_uuid(); v_journal_no TEXT; v_ap UUID; v_payment_id UUID:=gen_random_uuid();
BEGIN
 IF v_org IS NULL THEN RAISE EXCEPTION 'Organisasi tidak ditemukan'; END IF;
 SELECT * INTO v_expense FROM public.expense_transactions WHERE id=p_expense_id AND organization_id=v_org AND status='POSTED' FOR UPDATE;
 IF v_expense.id IS NULL THEN RAISE EXCEPTION 'Pengeluaran tidak ditemukan atau sudah dibatalkan'; END IF;
 IF v_expense.payment_status='PAID' THEN RAISE EXCEPTION 'Pengeluaran sudah lunas'; END IF;
 IF p_amount IS NULL OR p_amount<=0 THEN RAISE EXCEPTION 'Nominal pembayaran harus lebih dari Rp 0'; END IF;
 IF NOT EXISTS(SELECT 1 FROM public.accounts WHERE id=p_payment_account_id AND organization_id=v_org AND account_type='ASSET' AND is_active) THEN RAISE EXCEPTION 'Akun pembayaran tidak valid'; END IF;
 SELECT COALESCE(SUM(amount),0) INTO v_paid FROM public.expense_payments WHERE expense_id=p_expense_id AND organization_id=v_org;
 v_remaining:=v_expense.total_amount-v_paid;
 IF p_amount>v_remaining THEN RAISE EXCEPTION 'Pembayaran melebihi sisa hutang: Rp %', to_char(v_remaining,'FM999G999G999G990D00'); END IF;
 SELECT id INTO v_ap FROM public.accounts WHERE organization_id=v_org AND code='2-1000';
 v_journal_no:='JRN-'||to_char(p_payment_date,'YYYY')||'-'||lpad(public.get_next_sequence('expense_payment_journal',0)::text,6,'0');
 INSERT INTO public.journal_entries(id,organization_id,journal_number,journal_date,reference_type,reference_id,description,status,created_by) VALUES(v_journal,v_org,v_journal_no,p_payment_date,'expense_payment',v_payment_id,'Pembayaran pengeluaran '||v_expense.expense_number,'POSTED',v_user);
 INSERT INTO public.journal_lines(journal_entry_id,account_id,description,debit,credit) VALUES(v_journal,v_ap,'Pelunasan hutang usaha',p_amount,0),(v_journal,p_payment_account_id,'Pembayaran pengeluaran',0,p_amount);
 INSERT INTO public.expense_payments(id,organization_id,expense_id,payment_date,amount,payment_account_id,reference_number,notes,journal_entry_id,created_by) VALUES(v_payment_id,v_org,p_expense_id,p_payment_date,p_amount,p_payment_account_id,p_reference_number,p_notes,v_journal,v_user);
 SELECT COALESCE(SUM(amount),0) INTO v_paid FROM public.expense_payments WHERE expense_id=p_expense_id AND organization_id=v_org;
 UPDATE public.expense_transactions SET payment_status=CASE WHEN v_paid>=total_amount THEN 'PAID' ELSE 'PARTIAL' END, updated_at=NOW() WHERE id=p_expense_id;
 INSERT INTO public.audit_logs(organization_id,user_id,user_name,user_role,action,module,record_id,record_title,details) SELECT v_org,v_user,COALESCE(p.name,'Pengguna'),COALESCE(p.role,'finance'),'create','expenses',p_expense_id::text,v_expense.expense_number,'Pembayaran pengeluaran Rp '||to_char(p_amount,'FM999G999G999G990D00') FROM public.profiles p WHERE p.id=v_user;
 RETURN jsonb_build_object('id',v_payment_id,'expense_id',p_expense_id,'amount',p_amount,'payment_date',p_payment_date,'payment_account_id',p_payment_account_id,'journal_number',v_journal_no,'payment_status',CASE WHEN v_paid>=v_expense.total_amount THEN 'PAID' ELSE 'PARTIAL' END,'paid_amount',v_paid,'remaining_amount',v_expense.total_amount-v_paid);
END; $$;
REVOKE ALL ON FUNCTION public.record_expense_payment_atomic(UUID,DATE,NUMERIC,UUID,TEXT,TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_expense_payment_atomic(UUID,DATE,NUMERIC,UUID,TEXT,TEXT) TO authenticated;
