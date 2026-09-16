-- BillingFlow Foundation v7
-- Run this after the existing migrations. Safe to re-run.

-- 1) Organization type drives document identity/templates.
ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS organization_type VARCHAR(30) NOT NULL DEFAULT 'pt';

ALTER TABLE public.organizations
  DROP CONSTRAINT IF EXISTS organizations_organization_type_check;
ALTER TABLE public.organizations
  ADD CONSTRAINT organizations_organization_type_check
  CHECK (organization_type IN ('pt','cv','firma','koperasi','yayasan','ud','perorangan','instansi','other'));

-- 2) Expand the document archive so it can support the full business-document lifecycle.
ALTER TABLE public.documents
  ADD COLUMN IF NOT EXISTS parent_document_id UUID REFERENCES public.documents(id) ON DELETE SET NULL;

ALTER TABLE public.documents
  DROP CONSTRAINT IF EXISTS documents_document_type_check;
ALTER TABLE public.documents
  ADD CONSTRAINT documents_document_type_check
  CHECK (document_type IN (
    'invoice','billing_letter','payment_receipt','purchase_order','quotation',
    'sales_order','delivery_order','bast','credit_note','debit_note','other'
  ));

CREATE INDEX IF NOT EXISTS idx_documents_parent ON public.documents(parent_document_id);
CREATE INDEX IF NOT EXISTS idx_documents_type_date ON public.documents(organization_id, document_type, date DESC);

COMMENT ON COLUMN public.organizations.organization_type IS 'Jenis badan/organisasi untuk identitas dan template dokumen.';
COMMENT ON COLUMN public.documents.parent_document_id IS 'Dokumen sebelumnya dalam rantai transaksi bisnis, misalnya PO -> Surat Jalan -> Invoice.';
