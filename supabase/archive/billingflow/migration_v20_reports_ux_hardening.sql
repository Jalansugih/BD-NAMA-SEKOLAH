-- BillingFlow v20: report aggregation hardening
-- Safe replacement for get_financial_statements(); preserves accounting formulas and tenant isolation.

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
