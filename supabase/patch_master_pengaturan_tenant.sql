-- RAJAKAS BENDAHARA - PATCH MASTER PENGATURAN (HARDENED MULTI-TENANT)
-- Canonical schema: organization_id + public.get_auth_org_id().
--
-- File lama bernama *_tenant.sql sebelumnya memakai tenant_id/get_my_tenant_id.
-- File ini sengaja dibuat kompatibel dengan migration_v6/v7 dan TIDAK membuat
-- atau mengisi kolom tenant_id. Jalankan setelah migration_v7 bila diperlukan.

ALTER TABLE public.master_kelas
  ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();

ALTER TABLE public.master_kategori
  ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();

ALTER TABLE public.master_sumber_dana
  ALTER COLUMN organization_id SET DEFAULT public.get_auth_org_id();

ALTER TABLE public.master_kelas ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_kategori ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.master_sumber_dana ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Tenant - master_kelas" ON public.master_kelas;
DROP POLICY IF EXISTS "Tenant - master_kategori" ON public.master_kategori;
DROP POLICY IF EXISTS "Tenant - master_sumber_dana" ON public.master_sumber_dana;

CREATE POLICY "Tenant - master_kelas" ON public.master_kelas
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

CREATE POLICY "Tenant - master_kategori" ON public.master_kategori
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());

CREATE POLICY "Tenant - master_sumber_dana" ON public.master_sumber_dana
  FOR ALL USING (organization_id = public.get_auth_org_id())
  WITH CHECK (organization_id = public.get_auth_org_id());
