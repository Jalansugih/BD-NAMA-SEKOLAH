-- =========================================================================
-- BILLINGFLOW — MIGRATION V2: RLS untuk Customers, Invoices, Payments
-- Jalankan ini SETELAH supabase/migration.sql, di Supabase SQL Editor.
--
-- Kenapa perlu ini:
-- migration.sql cuma bikin SATU "Sample RLS Policy" (untuk tabel customers),
-- padahal RLS sudah di-ENABLE di semua tabel. Di Postgres, RLS enabled tanpa
-- policy = akses DITOLAK SEMUA secara default. Jadi invoices, payments,
-- organizations, dan profiles sebenarnya terkunci total sebelum migrasi ini.
-- =========================================================================

-- -------------------------------------------------------------------------
-- 1. Perbaiki CHECK constraint role di profiles (kurang 'viewer')
-- -------------------------------------------------------------------------
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_role_check;
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('owner', 'admin', 'finance', 'staff', 'viewer'));

-- -------------------------------------------------------------------------
-- 2. PROFILES — user harus bisa baca & bikin baris dirinya sendiri.
--    Tanpa ini, tidak ada RLS lain (yang mengecek "SELECT organization_id
--    FROM profiles WHERE id = auth.uid()") yang bisa jalan sama sekali.
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can view own profile" ON public.profiles;
CREATE POLICY "Users can view own profile"
ON public.profiles FOR SELECT
USING (id = auth.uid());

DROP POLICY IF EXISTS "Users can create own profile" ON public.profiles;
CREATE POLICY "Users can create own profile"
ON public.profiles FOR INSERT
WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "Users can update own profile" ON public.profiles;
CREATE POLICY "Users can update own profile"
ON public.profiles FOR UPDATE
USING (id = auth.uid());

-- -------------------------------------------------------------------------
-- 3. ORGANIZATIONS — anggota bisa baca/update org-nya sendiri; user login
--    manapun boleh INSERT (bootstrap org baru saat sign up pertama kali).
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can view own organization" ON public.organizations;
CREATE POLICY "Members can view own organization"
ON public.organizations FOR SELECT
USING (
    id IN (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
);

DROP POLICY IF EXISTS "Members can update own organization" ON public.organizations;
CREATE POLICY "Members can update own organization"
ON public.organizations FOR UPDATE
USING (
    id IN (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
);

DROP POLICY IF EXISTS "Authenticated users can create an organization" ON public.organizations;
CREATE POLICY "Authenticated users can create an organization"
ON public.organizations FOR INSERT
TO authenticated
WITH CHECK (true);

-- -------------------------------------------------------------------------
-- 4. BANK_ACCOUNTS — dibaca saat load Organization (dipakai invoice default)
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can access own bank accounts" ON public.bank_accounts;
CREATE POLICY "Members can access own bank accounts"
ON public.bank_accounts FOR ALL
USING (
    organization_id IN (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
);

-- -------------------------------------------------------------------------
-- 5. CUSTOMERS — ganti policy "Sample" jadi definitif (nama lebih jelas)
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "Users can only access data from their own organization" ON public.customers;
DROP POLICY IF EXISTS "Members can access own customers" ON public.customers;
CREATE POLICY "Members can access own customers"
ON public.customers FOR ALL
USING (
    organization_id IN (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
);

-- -------------------------------------------------------------------------
-- 6. INVOICES
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can access own invoices" ON public.invoices;
CREATE POLICY "Members can access own invoices"
ON public.invoices FOR ALL
USING (
    organization_id IN (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
);

-- -------------------------------------------------------------------------
-- 7. INVOICE_ITEMS — tidak punya organization_id sendiri, jadi cek lewat
--    invoice induknya.
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can access own invoice items" ON public.invoice_items;
CREATE POLICY "Members can access own invoice items"
ON public.invoice_items FOR ALL
USING (
    invoice_id IN (
        SELECT id FROM public.invoices
        WHERE organization_id IN (
            SELECT organization_id FROM public.profiles WHERE id = auth.uid()
        )
    )
);

-- -------------------------------------------------------------------------
-- 8. PAYMENTS
-- -------------------------------------------------------------------------
DROP POLICY IF EXISTS "Members can access own payments" ON public.payments;
CREATE POLICY "Members can access own payments"
ON public.payments FOR ALL
USING (
    organization_id IN (SELECT organization_id FROM public.profiles WHERE id = auth.uid())
);

-- =========================================================================
-- Belum tercakup di sini (sengaja, menyusul di batch berikutnya):
-- products, billing_letters, documents, audit_logs, bank feed / reconciliation
-- tables. Tabel-tabel itu masih RLS-enabled tanpa policy = tertutup total
-- sampai batch berikutnya dikerjakan.
-- =========================================================================
