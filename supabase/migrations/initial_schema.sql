-- =========================================================================
-- BILLINGFLOW SUPABASE POSTGRESQL INITIAL SCHEMA MIGRATION
-- Tables: organizations, bank_accounts, profiles, customers, products,
--         invoices, invoice_items, payments, billing_letters, documents, audit_logs
-- Supports: UUID v4 primary keys, pgcrypto, automatic profile triggers, and multi-tenant RLS policies
-- =========================================================================

-- 1. Enable Required Cryptographic & UUID Extensions
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. Organizations Table (Tenant Isolation Root)
CREATE TABLE IF NOT EXISTS public.organizations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_type VARCHAR(30) NOT NULL DEFAULT 'pt' CHECK (organization_type IN ('pt','cv','firma','koperasi','yayasan','ud','perorangan','instansi','other')),
    name VARCHAR(255) NOT NULL,
    tagline VARCHAR(255),
    logo_url TEXT,
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(50),
    address TEXT,
    city VARCHAR(100),
    province VARCHAR(100),
    postal_code VARCHAR(20),
    npwp VARCHAR(50),
    website VARCHAR(255),
    signature_name VARCHAR(255),
    signature_role VARCHAR(255),
    signature_image TEXT,
    director_name VARCHAR(255),
    default_tax_rate NUMERIC(5,2) DEFAULT 11.00,
    default_currency VARCHAR(10) DEFAULT 'IDR',
    timezone VARCHAR(50) DEFAULT 'Asia/Jakarta',
    invoice_format VARCHAR(100) DEFAULT 'INV/{YEAR}/{MONTH}/{NUMBER}',
    billing_letter_format VARCHAR(100) DEFAULT 'ST/{YEAR}/{MONTH}/{NUMBER}',
    payment_receipt_format VARCHAR(100) DEFAULT 'KWT/{YEAR}/{MONTH}/{NUMBER}',
    default_payment_terms_days INT DEFAULT 14,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 3. Bank Accounts Table
CREATE TABLE IF NOT EXISTS public.bank_accounts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    bank_name VARCHAR(100) NOT NULL,
    account_number VARCHAR(100) NOT NULL,
    account_holder VARCHAR(255) NOT NULL,
    branch VARCHAR(100),
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. User Profiles Table (Linked with Supabase auth.users)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    organization_id UUID REFERENCES public.organizations(id) ON DELETE CASCADE,
    name VARCHAR(255) NOT NULL,
    email VARCHAR(255) NOT NULL,
    role VARCHAR(50) NOT NULL DEFAULT 'finance' CHECK (role IN ('owner', 'admin', 'finance', 'staff', 'viewer')),
    avatar_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. Customers / Clients Table
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    company_name VARCHAR(255) NOT NULL,
    npwp VARCHAR(50),
    email VARCHAR(255) NOT NULL,
    phone VARCHAR(50) NOT NULL,
    address TEXT NOT NULL,
    city VARCHAR(100),
    province VARCHAR(100),
    postal_code VARCHAR(20),
    pic VARCHAR(255) NOT NULL,
    pic_phone VARCHAR(50),
    notes TEXT,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    total_invoiced NUMERIC(15,2) NOT NULL DEFAULT 0,
    total_paid NUMERIC(15,2) NOT NULL DEFAULT 0,
    total_outstanding NUMERIC(15,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 6. Products & Services Master Table
CREATE TABLE IF NOT EXISTS public.products (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    code VARCHAR(50) NOT NULL,
    name VARCHAR(255) NOT NULL,
    category VARCHAR(100) NOT NULL,
    description TEXT,
    unit VARCHAR(50) NOT NULL DEFAULT 'Unit',
    price NUMERIC(15,2) NOT NULL DEFAULT 0,
    tax_rate NUMERIC(5,2) NOT NULL DEFAULT 11.00,
    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. Invoices Table
CREATE TABLE IF NOT EXISTS public.invoices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    invoice_number VARCHAR(100) NOT NULL,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
    issue_date DATE NOT NULL,
    due_date DATE NOT NULL,
    po_number VARCHAR(100),
    reference_number VARCHAR(100),
    notes TEXT,
    payment_terms VARCHAR(255),
    subtotal NUMERIC(15,2) NOT NULL DEFAULT 0,
    discount_type VARCHAR(20) NOT NULL DEFAULT 'fixed' CHECK (discount_type IN ('percentage', 'fixed')),
    discount_value NUMERIC(15,2) NOT NULL DEFAULT 0,
    discount_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    tax_rate NUMERIC(5,2) NOT NULL DEFAULT 11.00,
    tax_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    additional_charges NUMERIC(15,2) NOT NULL DEFAULT 0,
    grand_total NUMERIC(15,2) NOT NULL DEFAULT 0,
    paid_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    outstanding_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    status VARCHAR(50) NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'sent', 'viewed', 'unpaid', 'partially_paid', 'paid', 'overdue', 'cancelled')),
    bank_account_id UUID REFERENCES public.bank_accounts(id) ON DELETE SET NULL,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    sent_at TIMESTAMPTZ,
    viewed_at TIMESTAMPTZ,
    paid_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. Invoice Line Items Table
CREATE TABLE IF NOT EXISTS public.invoice_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
    product_id UUID REFERENCES public.products(id) ON DELETE SET NULL,
    product_code VARCHAR(50),
    description TEXT NOT NULL,
    quantity NUMERIC(10,2) NOT NULL DEFAULT 1,
    unit VARCHAR(50) NOT NULL DEFAULT 'Unit',
    unit_price NUMERIC(15,2) NOT NULL DEFAULT 0,
    discount NUMERIC(15,2) NOT NULL DEFAULT 0,
    tax_rate NUMERIC(5,2) NOT NULL DEFAULT 11.00,
    amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 9. Payments / Payment Tracking Table
CREATE TABLE IF NOT EXISTS public.payments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    payment_number VARCHAR(100) NOT NULL,
    invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE RESTRICT,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE RESTRICT,
    payment_date DATE NOT NULL,
    amount NUMERIC(15,2) NOT NULL,
    payment_method VARCHAR(50) NOT NULL CHECK (payment_method IN ('bank_transfer', 'cash', 'qris', 'virtual_account', 'giro_cek', 'e_wallet', 'other')),
    destination_bank VARCHAR(255) NOT NULL,
    account_number VARCHAR(100),
    reference_number VARCHAR(100),
    notes TEXT,
    received_by VARCHAR(255),
    receipt_number VARCHAR(100) NOT NULL,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 10. Billing Letters Table (Surat Tagihan & Somasi)
CREATE TABLE IF NOT EXISTS public.billing_letters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    letter_number VARCHAR(100) NOT NULL,
    letter_type VARCHAR(50) NOT NULL CHECK (letter_type IN ('sp1', 'sp2', 'sp3', 'somasi', 'pemberitahuan', 'first_reminder', 'second_warning', 'final_demand')),
    invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    letter_date DATE NOT NULL,
    invoice_due_date DATE NOT NULL,
    overdue_days INT NOT NULL DEFAULT 0,
    total_invoice_amount NUMERIC(15,2) NOT NULL,
    paid_amount NUMERIC(15,2) NOT NULL DEFAULT 0,
    outstanding_amount NUMERIC(15,2) NOT NULL,
    extended_due_date DATE NOT NULL,
    subject VARCHAR(255) NOT NULL,
    body_text TEXT NOT NULL,
    status VARCHAR(50) NOT NULL DEFAULT 'sent',
    sent_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 11. Documents Archive Table
CREATE TABLE IF NOT EXISTS public.documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    document_type VARCHAR(50) NOT NULL CHECK (document_type IN ('invoice', 'billing_letter', 'payment_receipt', 'purchase_order', 'quotation', 'sales_order', 'delivery_order', 'bast', 'credit_note', 'debit_note', 'other')),
    document_number VARCHAR(100) NOT NULL,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    reference_id UUID,
    amount NUMERIC(15,2),
    date DATE NOT NULL,
    status VARCHAR(50),
    file_url TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 12. Audit Logs Table
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    organization_id UUID NOT NULL REFERENCES public.organizations(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    user_name VARCHAR(255) NOT NULL,
    user_role VARCHAR(50) NOT NULL,
    action VARCHAR(50) NOT NULL,
    module VARCHAR(50) NOT NULL,
    record_id VARCHAR(100) NOT NULL,
    record_title VARCHAR(255) NOT NULL,
    details TEXT NOT NULL,
    timestamp TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- =========================================================================
-- 13. AUTOMATIC PROFILE & ORGANIZATION PROVISIONING (Auth Webhook Trigger)
-- =========================================================================

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger AS $$
DECLARE
    org_id UUID;
    org_name TEXT;
    user_role TEXT;
    user_fullname TEXT;
BEGIN
    org_name := COALESCE(new.raw_user_meta_data->>'organization_name', 'Perusahaan Baru');
    user_role := COALESCE(new.raw_user_meta_data->>'role', 'owner');
    user_fullname := COALESCE(new.raw_user_meta_data->>'full_name', new.raw_user_meta_data->>'name', split_part(new.email, '@', 1));
    
    IF new.raw_user_meta_data->>'organization_id' IS NOT NULL AND new.raw_user_meta_data->>'organization_id' ~ '^[0-9a-fA-F-]{36}$' THEN
        org_id := (new.raw_user_meta_data->>'organization_id')::UUID;
    ELSE
        org_id := gen_random_uuid();
    END IF;

    -- Ensure tenant organization exists
    INSERT INTO public.organizations (id, name, email, created_at, updated_at)
    VALUES (org_id, org_name, new.email, NOW(), NOW())
    ON CONFLICT (id) DO NOTHING;

    -- Ensure public user profile exists
    INSERT INTO public.profiles (id, organization_id, name, email, role, created_at, updated_at)
    VALUES (new.id, org_id, user_fullname, new.email, user_role, NOW(), NOW())
    ON CONFLICT (id) DO UPDATE SET
        name = EXCLUDED.name,
        role = EXCLUDED.role,
        organization_id = COALESCE(public.profiles.organization_id, EXCLUDED.organization_id),
        updated_at = NOW();

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- =========================================================================
-- 14. PERFORMANCE INDEXES
-- =========================================================================

CREATE INDEX IF NOT EXISTS idx_profiles_org ON public.profiles(organization_id);
CREATE INDEX IF NOT EXISTS idx_customers_org ON public.customers(organization_id);
CREATE INDEX IF NOT EXISTS idx_products_org ON public.products(organization_id);
CREATE INDEX IF NOT EXISTS idx_invoices_org ON public.invoices(organization_id);
CREATE INDEX IF NOT EXISTS idx_invoices_customer ON public.invoices(customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON public.invoices(status);
CREATE INDEX IF NOT EXISTS idx_invoice_items_invoice ON public.invoice_items(invoice_id);
CREATE INDEX IF NOT EXISTS idx_payments_org ON public.payments(organization_id);
CREATE INDEX IF NOT EXISTS idx_payments_invoice ON public.payments(invoice_id);
CREATE INDEX IF NOT EXISTS idx_billing_letters_org ON public.billing_letters(organization_id);
CREATE INDEX IF NOT EXISTS idx_documents_org ON public.documents(organization_id);
CREATE INDEX IF NOT EXISTS idx_documents_parent ON public.documents(parent_document_id);
CREATE INDEX IF NOT EXISTS idx_documents_type_date ON public.documents(organization_id, document_type, date DESC);
CREATE INDEX IF NOT EXISTS idx_audit_logs_org ON public.audit_logs(organization_id);

-- =========================================================================
-- 15. ROW LEVEL SECURITY (RLS) ACTIVATION
-- =========================================================================

ALTER TABLE public.organizations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.products ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.billing_letters ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- =========================================================================
-- 16. MULTI-TENANT ROW LEVEL SECURITY POLICIES
-- =========================================================================

-- Helper function to retrieve authenticated user's organization_id
CREATE OR REPLACE FUNCTION public.get_auth_org_id()
RETURNS UUID AS $$
    SELECT organization_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Profiles Policy: Users can view/update own profile or profiles in the same tenant organization
DROP POLICY IF EXISTS "Profiles multi-tenant policy" ON public.profiles;
CREATE POLICY "Profiles multi-tenant policy" ON public.profiles
    FOR ALL
    USING (id = auth.uid() OR organization_id = public.get_auth_org_id())
    WITH CHECK (id = auth.uid() OR organization_id = public.get_auth_org_id());

-- Organizations Policy: Users can only access their own organization
DROP POLICY IF EXISTS "Organizations multi-tenant policy" ON public.organizations;
CREATE POLICY "Organizations multi-tenant policy" ON public.organizations
    FOR ALL
    USING (id = public.get_auth_org_id())
    WITH CHECK (id = public.get_auth_org_id());

-- Bank Accounts Policy
DROP POLICY IF EXISTS "Bank accounts multi-tenant policy" ON public.bank_accounts;
CREATE POLICY "Bank accounts multi-tenant policy" ON public.bank_accounts
    FOR ALL
    USING (organization_id = public.get_auth_org_id())
    WITH CHECK (organization_id = public.get_auth_org_id());

-- Customers Policy
DROP POLICY IF EXISTS "Customers multi-tenant policy" ON public.customers;
CREATE POLICY "Customers multi-tenant policy" ON public.customers
    FOR ALL
    USING (organization_id = public.get_auth_org_id())
    WITH CHECK (organization_id = public.get_auth_org_id());

-- Products Policy
DROP POLICY IF EXISTS "Products multi-tenant policy" ON public.products;
CREATE POLICY "Products multi-tenant policy" ON public.products
    FOR ALL
    USING (organization_id = public.get_auth_org_id())
    WITH CHECK (organization_id = public.get_auth_org_id());

-- Invoices Policy
DROP POLICY IF EXISTS "Invoices multi-tenant policy" ON public.invoices;
CREATE POLICY "Invoices multi-tenant policy" ON public.invoices
    FOR ALL
    USING (organization_id = public.get_auth_org_id())
    WITH CHECK (organization_id = public.get_auth_org_id());

-- Invoice Items Policy: Cascaded through parent invoice's organization_id
DROP POLICY IF EXISTS "Invoice items multi-tenant policy" ON public.invoice_items;
CREATE POLICY "Invoice items multi-tenant policy" ON public.invoice_items
    FOR ALL
    USING (invoice_id IN (SELECT id FROM public.invoices WHERE organization_id = public.get_auth_org_id()))
    WITH CHECK (invoice_id IN (SELECT id FROM public.invoices WHERE organization_id = public.get_auth_org_id()));

-- Payments Policy
DROP POLICY IF EXISTS "Payments multi-tenant policy" ON public.payments;
CREATE POLICY "Payments multi-tenant policy" ON public.payments
    FOR ALL
    USING (organization_id = public.get_auth_org_id())
    WITH CHECK (organization_id = public.get_auth_org_id());

-- Billing Letters Policy
DROP POLICY IF EXISTS "Billing letters multi-tenant policy" ON public.billing_letters;
CREATE POLICY "Billing letters multi-tenant policy" ON public.billing_letters
    FOR ALL
    USING (organization_id = public.get_auth_org_id())
    WITH CHECK (organization_id = public.get_auth_org_id());

-- Documents Policy
DROP POLICY IF EXISTS "Documents multi-tenant policy" ON public.documents;
CREATE POLICY "Documents multi-tenant policy" ON public.documents
    FOR ALL
    USING (organization_id = public.get_auth_org_id())
    WITH CHECK (organization_id = public.get_auth_org_id());

-- Audit Logs Policy
DROP POLICY IF EXISTS "Audit logs multi-tenant policy" ON public.audit_logs;
CREATE POLICY "Audit logs multi-tenant policy" ON public.audit_logs
    FOR ALL
    USING (organization_id = public.get_auth_org_id())
    WITH CHECK (organization_id = public.get_auth_org_id());
