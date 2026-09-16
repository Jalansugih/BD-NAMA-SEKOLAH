-- BillingFlow v8: operational business documents
-- Quotation -> PO -> Sales Order -> Delivery Order -> BAST
-- Run after v7. Safe to re-run.

CREATE TABLE IF NOT EXISTS public.business_documents (
  id UUID PRIMARY KEY,
  organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
  document_type VARCHAR(30) NOT NULL CHECK (document_type IN ('quotation','purchase_order','sales_order','delivery_order','bast')),
  document_number VARCHAR(100) NOT NULL,
  title VARCHAR(255) NOT NULL,
  customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
  customer_name VARCHAR(255),
  date DATE NOT NULL,
  valid_until DATE,
  reference_number VARCHAR(150),
  parent_document_id UUID REFERENCES public.business_documents(id) ON DELETE SET NULL,
  delivery_address TEXT,
  notes TEXT,
  status VARCHAR(30) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','sent','approved','rejected','confirmed','shipped','delivered','completed','cancelled')),
  items JSONB NOT NULL DEFAULT '[]'::jsonb,
  subtotal NUMERIC(18,2) NOT NULL DEFAULT 0,
  tax_amount NUMERIC(18,2) NOT NULL DEFAULT 0,
  grand_total NUMERIC(18,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (organization_id, document_number)
);

CREATE INDEX IF NOT EXISTS idx_business_documents_org_date ON public.business_documents(organization_id, date DESC);
CREATE INDEX IF NOT EXISTS idx_business_documents_org_type ON public.business_documents(organization_id, document_type);
CREATE INDEX IF NOT EXISTS idx_business_documents_parent ON public.business_documents(parent_document_id);
CREATE INDEX IF NOT EXISTS idx_business_documents_customer ON public.business_documents(organization_id, customer_id);

ALTER TABLE public.business_documents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS business_documents_select ON public.business_documents;
DROP POLICY IF EXISTS business_documents_insert ON public.business_documents;
DROP POLICY IF EXISTS business_documents_update ON public.business_documents;
DROP POLICY IF EXISTS business_documents_delete ON public.business_documents;
CREATE POLICY business_documents_select ON public.business_documents FOR SELECT USING (organization_id = public.get_auth_org_id());
CREATE POLICY business_documents_insert ON public.business_documents FOR INSERT WITH CHECK (organization_id = public.get_auth_org_id());
CREATE POLICY business_documents_update ON public.business_documents FOR UPDATE USING (organization_id = public.get_auth_org_id()) WITH CHECK (organization_id = public.get_auth_org_id());
CREATE POLICY business_documents_delete ON public.business_documents FOR DELETE USING (organization_id = public.get_auth_org_id());
