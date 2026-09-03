-- PATCH MASTER PENGATURAN - MULTI TENANT
-- Untuk database yang sudah memakai tenant_id + get_my_tenant_id().
-- Jalankan di Supabase SQL Editor.

-- Pastikan kolom tenant_id ada. Jika sudah ada, perintah ini tidak mengubah data.
ALTER TABLE public.master_kelas
  ADD COLUMN IF NOT EXISTS tenant_id UUID;
ALTER TABLE public.master_kategori
  ADD COLUMN IF NOT EXISTS tenant_id UUID;
ALTER TABLE public.master_sumber_dana
  ADD COLUMN IF NOT EXISTS tenant_id UUID;

-- Isi data lama yang masih NULL ke tenant yang sedang menjadi tenant default.
-- Jika database Anda sudah berisi tenant_id pada semua baris, bagian ini tidak mengubah apa pun.
DO $$
DECLARE
  v_tenant_id UUID;
BEGIN
  SELECT id INTO v_tenant_id
  FROM public.tenants
  ORDER BY created_at
  LIMIT 1;

  IF v_tenant_id IS NOT NULL THEN
    UPDATE public.master_kelas SET tenant_id = v_tenant_id WHERE tenant_id IS NULL;
    UPDATE public.master_kategori SET tenant_id = v_tenant_id WHERE tenant_id IS NULL;
    UPDATE public.master_sumber_dana SET tenant_id = v_tenant_id WHERE tenant_id IS NULL;
  END IF;
END $$;

-- Pastikan INSERT dari frontend wajib membawa tenant yang sesuai.
DROP POLICY IF EXISTS "tenant_insert_master_kelas" ON public.master_kelas;
CREATE POLICY "tenant_insert_master_kelas"
ON public.master_kelas FOR INSERT TO authenticated
WITH CHECK (tenant_id = public.get_my_tenant_id());

DROP POLICY IF EXISTS "tenant_select_master_kelas" ON public.master_kelas;
CREATE POLICY "tenant_select_master_kelas"
ON public.master_kelas FOR SELECT TO authenticated
USING (tenant_id = public.get_my_tenant_id());

DROP POLICY IF EXISTS "tenant_update_master_kelas" ON public.master_kelas;
CREATE POLICY "tenant_update_master_kelas"
ON public.master_kelas FOR UPDATE TO authenticated
USING (tenant_id = public.get_my_tenant_id())
WITH CHECK (tenant_id = public.get_my_tenant_id());

DROP POLICY IF EXISTS "tenant_delete_master_kelas" ON public.master_kelas;
CREATE POLICY "tenant_delete_master_kelas"
ON public.master_kelas FOR DELETE TO authenticated
USING (tenant_id = public.get_my_tenant_id());

DROP POLICY IF EXISTS "tenant_insert_master_kategori" ON public.master_kategori;
CREATE POLICY "tenant_insert_master_kategori"
ON public.master_kategori FOR INSERT TO authenticated
WITH CHECK (tenant_id = public.get_my_tenant_id());

DROP POLICY IF EXISTS "tenant_select_master_kategori" ON public.master_kategori;
CREATE POLICY "tenant_select_master_kategori"
ON public.master_kategori FOR SELECT TO authenticated
USING (tenant_id = public.get_my_tenant_id());

DROP POLICY IF EXISTS "tenant_update_master_kategori" ON public.master_kategori;
CREATE POLICY "tenant_update_master_kategori"
ON public.master_kategori FOR UPDATE TO authenticated
USING (tenant_id = public.get_my_tenant_id())
WITH CHECK (tenant_id = public.get_my_tenant_id());

DROP POLICY IF EXISTS "tenant_delete_master_kategori" ON public.master_kategori;
CREATE POLICY "tenant_delete_master_kategori"
ON public.master_kategori FOR DELETE TO authenticated
USING (tenant_id = public.get_my_tenant_id());

DROP POLICY IF EXISTS "tenant_insert_master_sumber_dana" ON public.master_sumber_dana;
CREATE POLICY "tenant_insert_master_sumber_dana"
ON public.master_sumber_dana FOR INSERT TO authenticated
WITH CHECK (tenant_id = public.get_my_tenant_id());

DROP POLICY IF EXISTS "tenant_select_master_sumber_dana" ON public.master_sumber_dana;
CREATE POLICY "tenant_select_master_sumber_dana"
ON public.master_sumber_dana FOR SELECT TO authenticated
USING (tenant_id = public.get_my_tenant_id());

DROP POLICY IF EXISTS "tenant_update_master_sumber_dana" ON public.master_sumber_dana;
CREATE POLICY "tenant_update_master_sumber_dana"
ON public.master_sumber_dana FOR UPDATE TO authenticated
USING (tenant_id = public.get_my_tenant_id())
WITH CHECK (tenant_id = public.get_my_tenant_id());

DROP POLICY IF EXISTS "tenant_delete_master_sumber_dana" ON public.master_sumber_dana;
CREATE POLICY "tenant_delete_master_sumber_dana"
ON public.master_sumber_dana FOR DELETE TO authenticated
USING (tenant_id = public.get_my_tenant_id());

-- Jika tenant_id memang sudah menjadi kolom wajib di database Anda,
-- aktifkan tiga baris berikut setelah memastikan tidak ada NULL.
-- ALTER TABLE public.master_kelas ALTER COLUMN tenant_id SET NOT NULL;
-- ALTER TABLE public.master_kategori ALTER COLUMN tenant_id SET NOT NULL;
-- ALTER TABLE public.master_sumber_dana ALTER COLUMN tenant_id SET NOT NULL;
