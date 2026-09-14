-- BILLINGFLOW V27 — PERSISTENCE / RLS HARDENING
-- Jalankan SETELAH migration.sql + v2..v22.
-- Tujuan: memastikan tenant aktif dapat membaca/menulis data aplikasi
-- melalui browser dengan anon key + authenticated session.

CREATE OR REPLACE FUNCTION public.get_auth_org_id()
RETURNS UUID
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT p.organization_id
  FROM public.profiles p
  WHERE p.id = auth.uid()
    AND p.organization_id IS NOT NULL
  LIMIT 1;
$$;

REVOKE ALL ON FUNCTION public.get_auth_org_id() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_auth_org_id() TO authenticated;

-- Core business tables: explicit tenant policies. Re-running is safe.
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_letters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "billingflow customers tenant" ON public.customers;
CREATE POLICY "billingflow customers tenant" ON public.customers
FOR ALL TO authenticated
USING (organization_id = public.get_auth_org_id())
WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "billingflow products tenant" ON public.products;
CREATE POLICY "billingflow products tenant" ON public.products
FOR ALL TO authenticated
USING (organization_id = public.get_auth_org_id())
WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "billingflow invoices tenant" ON public.invoices;
CREATE POLICY "billingflow invoices tenant" ON public.invoices
FOR ALL TO authenticated
USING (organization_id = public.get_auth_org_id())
WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "billingflow invoice items tenant" ON public.invoice_items;
CREATE POLICY "billingflow invoice items tenant" ON public.invoice_items
FOR ALL TO authenticated
USING (EXISTS (
  SELECT 1 FROM public.invoices i
  WHERE i.id = invoice_id AND i.organization_id = public.get_auth_org_id()
))
WITH CHECK (EXISTS (
  SELECT 1 FROM public.invoices i
  WHERE i.id = invoice_id AND i.organization_id = public.get_auth_org_id()
));

DROP POLICY IF EXISTS "billingflow payments tenant" ON public.payments;
CREATE POLICY "billingflow payments tenant" ON public.payments
FOR ALL TO authenticated
USING (organization_id = public.get_auth_org_id())
WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "billingflow billing letters tenant" ON public.billing_letters;
CREATE POLICY "billingflow billing letters tenant" ON public.billing_letters
FOR ALL TO authenticated
USING (organization_id = public.get_auth_org_id())
WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "billingflow documents tenant" ON public.documents;
CREATE POLICY "billingflow documents tenant" ON public.documents
FOR ALL TO authenticated
USING (organization_id = public.get_auth_org_id())
WITH CHECK (organization_id = public.get_auth_org_id());

DROP POLICY IF EXISTS "billingflow bank accounts tenant" ON public.bank_accounts;
CREATE POLICY "billingflow bank accounts tenant" ON public.bank_accounts
FOR ALL TO authenticated
USING (organization_id = public.get_auth_org_id())
WITH CHECK (organization_id = public.get_auth_org_id());

-- Organization itself may only be updated by its current members.
DROP POLICY IF EXISTS "billingflow organization member update" ON public.organizations;
CREATE POLICY "billingflow organization member update" ON public.organizations
FOR UPDATE TO authenticated
USING (id = public.get_auth_org_id())
WITH CHECK (id = public.get_auth_org_id());

-- Diagnostics (jalankan di SQL Editor).
-- SQL Editor biasanya berjalan sebagai postgres, jadi auth.uid() dapat NULL;
-- untuk diagnosis tenant dari browser, lihat profil user yang sedang login
-- melalui query aplikasi / log Supabase.

SELECT id, email, organization_id, role
FROM public.profiles
ORDER BY created_at DESC;

SELECT schemaname, tablename, policyname, cmd
FROM pg_policies
WHERE schemaname='public'
  AND tablename IN ('customers','products','invoices','invoice_items','payments','billing_letters','documents','bank_accounts','organizations')
ORDER BY tablename, policyname;

-- Expected core columns used by the frontend.
SELECT table_name, column_name, data_type
FROM information_schema.columns
WHERE table_schema='public'
  AND table_name IN ('customers','products','invoices','invoice_items','payments','billing_letters','documents','bank_accounts')
  AND column_name IN ('id','organization_id','customer_id','invoice_id','bank_account_id')
ORDER BY table_name, ordinal_position;
